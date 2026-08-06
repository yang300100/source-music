/*
 * JSVM 桥接核心实现
 *
 * 封装鸿蒙系统 JSVM-API（libjsvm.so），为 ArkTS 侧提供：
 * - 创建/销毁 JS 虚拟机（VM + Env）
 * - 执行 JS 脚本
 * - 调用全局函数
 * - 注入原生函数（request 网络请求桥接等）
 * - 异步回调（JS request → ArkTS 网络 → 恢复 JS 回调）
 *
 * 线程模型：所有 JSVM 操作在创建 VM 的线程（ArkTS 主线程）执行，
 * JSVM-API 非线程安全，同一 Env 必须单线程访问。
 *
 * 重要（V8 内核约束）：
 * 1. 所有 JSVM_Value 操作必须在 HandleScope 内
 * 2. 还必须打开 EnvScope（上下文作用域）和 VMScope（VM 作用域）
 * 3. 作用域按 VMScope → EnvScope → HandleScope 顺序打开，逆序关闭
 * 缺失任一作用域都会导致 "Cannot create a handle without a HandleScope" 或
 * CompileScript/RunScript 段错误。
 */
#include "napi/native_api.h"
#include "ark_runtime/jsvm.h"

#include <map>
#include <string>
#include <vector>
#include <mutex>
#include <memory>

// ============ 作用域管理 ============

/** 统一管理 VMScope / EnvScope / HandleScope 三层作用域 */
struct VmScopes {
    JSVM_VM vm = nullptr;
    JSVM_Env env = nullptr;
    JSVM_VMScope vmScope = nullptr;
    JSVM_EnvScope envScope = nullptr;
    JSVM_HandleScope handleScope = nullptr;
    bool opened = false;

    bool open(JSVM_VM vm, JSVM_Env env) {
        this->vm = vm;
        this->env = env;
        if (OH_JSVM_OpenVMScope(vm, &vmScope) != JSVM_OK) return false;
        if (OH_JSVM_OpenEnvScope(env, &envScope) != JSVM_OK) {
            OH_JSVM_CloseVMScope(vm, vmScope);
            return false;
        }
        if (OH_JSVM_OpenHandleScope(env, &handleScope) != JSVM_OK) {
            OH_JSVM_CloseEnvScope(env, envScope);
            OH_JSVM_CloseVMScope(vm, vmScope);
            return false;
        }
        opened = true;
        return true;
    }

    void close() {
        if (!opened) return;
        OH_JSVM_CloseHandleScope(env, handleScope);
        OH_JSVM_CloseEnvScope(env, envScope);
        OH_JSVM_CloseVMScope(vm, vmScope);
        opened = false;
    }
};

// ============ 基础工具（必须在 VmScopes 内调用） ============

/** 获取 JSVM 全局对象的指定属性 */
static JSVM_Value GetGlobalProperty(JSVM_Env env, const char *name) {
    JSVM_Value global = nullptr;
    JSVM_Value key = nullptr;
    JSVM_Value value = nullptr;
    if (OH_JSVM_GetGlobal(env, &global) != JSVM_OK) return nullptr;
    // 注意：length 必须传字符串长度或 JSVM_AUTO_LENGTH，传 0 会创建空字符串 key！
    if (OH_JSVM_CreateStringUtf8(env, name, strlen(name), &key) != JSVM_OK) return nullptr;
    if (OH_JSVM_GetProperty(env, global, key, &value) != JSVM_OK) return nullptr;
    return value;
}

/** 在 JSVM 中执行 JSON.stringify 将值转为 C++ 字符串 */
static std::string ValueToJson(JSVM_Env env, JSVM_Value value) {
    if (value == nullptr) return "";
    JSVM_ValueType type = JSVM_UNDEFINED;
    if (OH_JSVM_Typeof(env, value, &type) != JSVM_OK) return "";
    if (type == JSVM_UNDEFINED) return "undefined";
    if (type == JSVM_NULL) return "null";
    if (type != JSVM_OBJECT && type != JSVM_STRING) {
        JSVM_Value coerced = nullptr;
        if (OH_JSVM_CoerceToString(env, value, &coerced) == JSVM_OK && coerced != nullptr) {
            value = coerced;
        } else {
            return "";
        }
    }
    JSVM_Value jsonObj = GetGlobalProperty(env, "JSON");
    if (jsonObj == nullptr) return "";
    JSVM_Value stringifyFn = nullptr;
    if (OH_JSVM_GetNamedProperty(env, jsonObj, "stringify", &stringifyFn) != JSVM_OK) return "";
    JSVM_Value argv[1] = { value };
    JSVM_Value result = nullptr;
    if (OH_JSVM_CallFunction(env, jsonObj, stringifyFn, 1, argv, &result) != JSVM_OK) return "";
    if (result == nullptr) return "";
    JSVM_ValueType resultType = JSVM_UNDEFINED;
    if (OH_JSVM_Typeof(env, result, &resultType) != JSVM_OK) return "";
    if (resultType == JSVM_UNDEFINED || resultType == JSVM_NULL) return "";
    if (resultType != JSVM_STRING) {
        JSVM_Value coerced = nullptr;
        if (OH_JSVM_CoerceToString(env, result, &coerced) != JSVM_OK || coerced == nullptr) return "";
        result = coerced;
    }
    size_t len = 0;
    if (OH_JSVM_GetValueStringUtf8(env, result, nullptr, 0, &len) != JSVM_OK) return "";
    std::string str(len, '\0');
    if (len > 0) {
        OH_JSVM_GetValueStringUtf8(env, result, &str[0], len + 1, &len);
    }
    return str;
}

/** 在 JSVM 中执行 JSON.parse 将字符串转为值 */
static JSVM_Value JsonToValue(JSVM_Env env, const std::string &json) {
    if (json.empty()) return nullptr;
    JSVM_Value jsonObj = GetGlobalProperty(env, "JSON");
    if (jsonObj == nullptr) return nullptr;
    JSVM_Value parseFn = nullptr;
    if (OH_JSVM_GetNamedProperty(env, jsonObj, "parse", &parseFn) != JSVM_OK) return nullptr;
    JSVM_Value argStr = nullptr;
    if (OH_JSVM_CreateStringUtf8(env, json.c_str(), json.length(), &argStr) != JSVM_OK) return nullptr;
    JSVM_Value result = nullptr;
    JSVM_Status status = OH_JSVM_CallFunction(env, jsonObj, parseFn, 1, &argStr, &result);
    if (status != JSVM_OK) {
        JSVM_Value ex = nullptr;
        OH_JSVM_GetAndClearLastException(env, &ex);
        return nullptr;
    }
    return result;
}

/** 判断值是否为函数 */
static bool IsFunction(JSVM_Env env, JSVM_Value value) {
    if (value == nullptr) return false;
    JSVM_ValueType type = JSVM_UNDEFINED;
    if (OH_JSVM_Typeof(env, value, &type) != JSVM_OK) return false;
    return type == JSVM_FUNCTION;
}

// ============ VM 实例管理 ============

/** 单个脚本的 VM 实例 */
struct VmInstance {
    JSVM_VM vm = nullptr;
    JSVM_Env env = nullptr;
    bool alive = false;
};

static std::map<int, VmInstance> g_vms;
static int g_nextHandle = 1;
static std::mutex g_mutex;

/** 获取 VM 实例（加锁） */
static VmInstance *GetVmInstance(int handle) {
    std::lock_guard<std::mutex> lock(g_mutex);
    auto it = g_vms.find(handle);
    if (it != g_vms.end() && it->second.alive) {
        return &it->second;
    }
    return nullptr;
}

// ============ NAPI 导出接口 ============

extern "C" {

/** 创建 VM：createVM() → handle */
napi_value NapiCreateVM(napi_env env, napi_callback_info info) {
    // OH_JSVM_Init 只允许调用一次
    static bool s_initialized = false;
    if (!s_initialized) {
        JSVM_InitOptions initOptions = { 0 };
        if (OH_JSVM_Init(&initOptions) != JSVM_OK) {
            napi_value err;
            napi_create_string_utf8(env, "jsvm init failed", NAPI_AUTO_LENGTH, &err);
            napi_throw(env, err);
            return nullptr;
        }
        s_initialized = true;
    }

    JSVM_VM vm = nullptr;
    JSVM_CreateVMOptions vmOptions = { 0 };
    if (OH_JSVM_CreateVM(&vmOptions, &vm) != JSVM_OK) {
        napi_value err;
        napi_create_string_utf8(env, "jsvm create vm failed", NAPI_AUTO_LENGTH, &err);
        napi_throw(env, err);
        return nullptr;
    }

    JSVM_Env jsEnv = nullptr;
    if (OH_JSVM_CreateEnv(vm, 0, nullptr, &jsEnv) != JSVM_OK) {
        OH_JSVM_DestroyVM(vm);
        napi_value err;
        napi_create_string_utf8(env, "jsvm create env failed", NAPI_AUTO_LENGTH, &err);
        napi_throw(env, err);
        return nullptr;
    }

    int handle = 0;
    {
        std::lock_guard<std::mutex> lock(g_mutex);
        handle = g_nextHandle++;
        VmInstance inst;
        inst.vm = vm;
        inst.env = jsEnv;
        inst.alive = true;
        g_vms[handle] = inst;
    }

    napi_value result;
    napi_create_int32(env, handle, &result);
    return result;
}

/** 销毁 VM：destroyVM(handle) */
napi_value NapiDestroyVM(napi_env env, napi_callback_info info) {
    size_t argc = 1;
    napi_value argv[1] = { nullptr };
    napi_get_cb_info(env, info, &argc, argv, nullptr, nullptr);

    int32_t handle = 0;
    napi_get_value_int32(env, argv[0], &handle);

    {
        std::lock_guard<std::mutex> lock(g_mutex);
        auto it = g_vms.find(handle);
        if (it != g_vms.end()) {
            OH_JSVM_DestroyEnv(it->second.env);
            OH_JSVM_DestroyVM(it->second.vm);
            g_vms.erase(it);
        }
    }
    return nullptr;
}

/** 执行脚本：evalScript(handle, script) → string（脚本返回值的 JSON） */
napi_value NapiEvalScript(napi_env env, napi_callback_info info) {
    size_t argc = 2;
    napi_value argv[2] = { nullptr };
    napi_get_cb_info(env, info, &argc, argv, nullptr, nullptr);

    int32_t handle = 0;
    napi_get_value_int32(env, argv[0], &handle);

    size_t scriptLen = 0;
    napi_get_value_string_utf8(env, argv[1], nullptr, 0, &scriptLen);
    std::string script(scriptLen, '\0');
    if (scriptLen > 0) {
        napi_get_value_string_utf8(env, argv[1], &script[0], scriptLen + 1, &scriptLen);
    }

    VmInstance *inst = GetVmInstance(handle);
    if (inst == nullptr) {
        napi_value err;
        napi_create_string_utf8(env, "vm not found", NAPI_AUTO_LENGTH, &err);
        napi_throw(env, err);
        return nullptr;
    }

    std::string resultStr;
    {
        VmScopes scopes;
        if (!scopes.open(inst->vm, inst->env)) {
            resultStr = "scope open failed";
        } else {
            JSVM_Value scriptValue = nullptr;
            JSVM_Script compiledScript = nullptr;
            JSVM_Value result = nullptr;
            JSVM_Status status = JSVM_GENERIC_FAILURE;
            bool cacheRejected = false;
            if (OH_JSVM_CreateStringUtf8(inst->env, script.c_str(), script.length(), &scriptValue) == JSVM_OK &&
                OH_JSVM_CompileScript(inst->env, scriptValue, nullptr, 0, true, &cacheRejected, &compiledScript) == JSVM_OK) {
                status = OH_JSVM_RunScript(inst->env, compiledScript, &result);
            }
            if (status == JSVM_OK && result != nullptr) {
                resultStr = ValueToJson(inst->env, result);
            } else {
                // 提取异常详细信息（先尝试结构化错误信息，再回退到字符串转换）
                std::string errDetail = "";
                const JSVM_ExtendedErrorInfo *errInfo = nullptr;
                if (OH_JSVM_GetLastErrorInfo(inst->env, &errInfo) == JSVM_OK && errInfo != nullptr &&
                    errInfo->errorMessage != nullptr) {
                    errDetail = errInfo->errorMessage;
                }
                JSVM_Value ex = nullptr;
                OH_JSVM_GetAndClearLastException(inst->env, &ex);
                if (ex != nullptr) {
                    JSVM_Value coerced = nullptr;
                    if (OH_JSVM_CoerceToString(inst->env, ex, &coerced) == JSVM_OK && coerced != nullptr) {
                        size_t len = 0;
                        if (OH_JSVM_GetValueStringUtf8(inst->env, coerced, nullptr, 0, &len) == JSVM_OK && len > 0) {
                            std::string exStr(len, '\0');
                            OH_JSVM_GetValueStringUtf8(inst->env, coerced, &exStr[0], len + 1, &len);
                            errDetail = exStr;
                        }
                    }
                }
                if (errDetail.empty()) {
                    errDetail = "unknown script error";
                }
                resultStr = "script error: " + errDetail;
            }
            scopes.close();
        }
    }

    napi_value napiResult;
    napi_create_string_utf8(env, resultStr.c_str(), resultStr.length(), &napiResult);
    return napiResult;
}

/** 调用全局函数：callGlobalFunction(handle, fnName, argsJson) → string */
napi_value NapiCallGlobalFunction(napi_env env, napi_callback_info info) {
    size_t argc = 3;
    napi_value argv[3] = { nullptr };
    napi_get_cb_info(env, info, &argc, argv, nullptr, nullptr);

    int32_t handle = 0;
    napi_get_value_int32(env, argv[0], &handle);

    size_t fnLen = 0;
    napi_get_value_string_utf8(env, argv[1], nullptr, 0, &fnLen);
    std::string fnName(fnLen, '\0');
    if (fnLen > 0) {
        napi_get_value_string_utf8(env, argv[1], &fnName[0], fnLen + 1, &fnLen);
    }

    size_t argsLen = 0;
    napi_get_value_string_utf8(env, argv[2], nullptr, 0, &argsLen);
    std::string argsJson(argsLen, '\0');
    if (argsLen > 0) {
        napi_get_value_string_utf8(env, argv[2], &argsJson[0], argsLen + 1, &argsLen);
    }

    VmInstance *inst = GetVmInstance(handle);
    if (inst == nullptr) return nullptr;

    std::string resultStr;
    {
        VmScopes scopes;
        if (!scopes.open(inst->vm, inst->env)) {
            resultStr = "scope open failed";
        } else {
            JSVM_Value fn = GetGlobalProperty(inst->env, fnName.c_str());
            if (IsFunction(inst->env, fn)) {
                JSVM_Value args = JsonToValue(inst->env, argsJson);
                uint32_t argCount = 0;
                std::vector<JSVM_Value> argvList;
                if (args != nullptr) {
                    JSVM_ValueType type = JSVM_UNDEFINED;
                    OH_JSVM_Typeof(inst->env, args, &type);
                    if (type == JSVM_OBJECT) {
                        OH_JSVM_GetArrayLength(inst->env, args, &argCount);
                        for (uint32_t i = 0; i < argCount; i++) {
                            JSVM_Value item = nullptr;
                            OH_JSVM_GetElement(inst->env, args, i, &item);
                            if (item != nullptr) {
                                argvList.push_back(item);
                            }
                        }
                    }
                }
                JSVM_Value global = nullptr;
                OH_JSVM_GetGlobal(inst->env, &global);
                JSVM_Value result = nullptr;
                JSVM_Status status = OH_JSVM_CallFunction(inst->env, global, fn, argvList.size(), argvList.data(), &result);
                if (status == JSVM_OK && result != nullptr) {
                    resultStr = ValueToJson(inst->env, result);
                } else {
                    JSVM_Value ex = nullptr;
                    OH_JSVM_GetAndClearLastException(inst->env, &ex);
                    if (ex != nullptr) {
                        resultStr = "call error: " + ValueToJson(inst->env, ex);
                    } else {
                        resultStr = "call error";
                    }
                }
            } else {
                resultStr = "function not found: " + fnName;
            }
            scopes.close();
        }
    }

    napi_value napiResult;
    napi_create_string_utf8(env, resultStr.c_str(), resultStr.length(), &napiResult);
    return napiResult;
}

/** 设置原生请求结果：setNativeResult(handle, requestId, errorJson, responseJson) */
napi_value NapiSetNativeResult(napi_env env, napi_callback_info info) {
    size_t argc = 4;
    napi_value argv[4] = { nullptr };
    napi_get_cb_info(env, info, &argc, argv, nullptr, nullptr);

    int32_t handle = 0;
    napi_get_value_int32(env, argv[0], &handle);

    size_t idLen = 0;
    napi_get_value_string_utf8(env, argv[1], nullptr, 0, &idLen);
    std::string requestId(idLen, '\0');
    if (idLen > 0) {
        napi_get_value_string_utf8(env, argv[1], &requestId[0], idLen + 1, &idLen);
    }

    size_t errLen = 0;
    napi_get_value_string_utf8(env, argv[2], nullptr, 0, &errLen);
    std::string errorJson(errLen, '\0');
    if (errLen > 0) {
        napi_get_value_string_utf8(env, argv[2], &errorJson[0], errLen + 1, &errLen);
    }

    size_t respLen = 0;
    napi_get_value_string_utf8(env, argv[3], nullptr, 0, &respLen);
    std::string responseJson(respLen, '\0');
    if (respLen > 0) {
        napi_get_value_string_utf8(env, argv[3], &responseJson[0], respLen + 1, &respLen);
    }

    VmInstance *inst = GetVmInstance(handle);
    if (inst == nullptr) return nullptr;

    {
        VmScopes scopes;
        if (scopes.open(inst->vm, inst->env)) {
            // 调用脚本侧 __lx_resolveRequest__(requestId, errorJson, responseJson)
            JSVM_Value fn = GetGlobalProperty(inst->env, "__lx_resolveRequest__");
            if (IsFunction(inst->env, fn)) {
                JSVM_Value argvCall[3];
                // 参数 0：requestId 字符串
                if (OH_JSVM_CreateStringUtf8(inst->env, requestId.c_str(), requestId.length(), &argvCall[0]) != JSVM_OK) {
                    scopes.close();
                    return nullptr;
                }
                // 参数 1/2：errorJson / responseJson（失败兜底为 null，禁止传 nullptr）
                JSVM_Value errVal = (errorJson == "null" || errorJson.empty())
                    ? nullptr : JsonToValue(inst->env, errorJson);
                if (errVal == nullptr) {
                    OH_JSVM_GetNull(inst->env, &errVal);
                }
                argvCall[1] = errVal;
                JSVM_Value respVal = responseJson.empty()
                    ? nullptr : JsonToValue(inst->env, responseJson);
                if (respVal == nullptr) {
                    OH_JSVM_GetNull(inst->env, &respVal);
                }
                argvCall[2] = respVal;
                JSVM_Value global = nullptr;
                OH_JSVM_GetGlobal(inst->env, &global);
                JSVM_Value result = nullptr;
                OH_JSVM_CallFunction(inst->env, global, fn, 3, argvCall, &result);
            }
            scopes.close();
        }
    }
    return nullptr;
}

} // extern "C"
