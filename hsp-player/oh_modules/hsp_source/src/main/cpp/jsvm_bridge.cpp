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
 * 重要：JSVM（V8 内核）要求所有 JSVM_Value 操作必须在 HandleScope 内，
 * 否则触发 "Cannot create a handle without a HandleScope" 致命错误。
 */
#include "napi/native_api.h"
#include "ark_runtime/jsvm.h"

#include <map>
#include <string>
#include <vector>
#include <mutex>
#include <memory>

// ============ 基础工具 ============

/** 获取 JSVM 全局对象的指定属性（调用前必须已 OpenHandleScope） */
static JSVM_Value GetGlobalProperty(JSVM_Env env, const char *name) {
    JSVM_Value global = nullptr;
    JSVM_Value key = nullptr;
    JSVM_Value value = nullptr;
    if (OH_JSVM_GetGlobal(env, &global) != JSVM_OK) return nullptr;
    if (OH_JSVM_CreateStringUtf8(env, name, 0, &key) != JSVM_OK) return nullptr;
    if (OH_JSVM_GetProperty(env, global, key, &value) != JSVM_OK) return nullptr;
    return value;
}

/** 在 JSVM 中执行 JSON.stringify 将值转为 C++ 字符串（调用前必须已 OpenHandleScope） */
static std::string ValueToJson(JSVM_Env env, JSVM_Value value) {
    if (value == nullptr) return "";
    // 特殊类型直接处理，避免对 undefined/null 调用 stringify 再取字符串（可能崩溃）
    JSVM_ValueType type = JSVM_UNDEFINED;
    if (OH_JSVM_Typeof(env, value, &type) != JSVM_OK) return "";
    if (type == JSVM_UNDEFINED) return "undefined";
    if (type == JSVM_NULL) return "null";
    // 非对象/字符串的值先转字符串（数组在 JSVM 中也是 OBJECT 类型）
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
    // stringify 结果必须是字符串才能安全取内容
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

/** 在 JSVM 中执行 JSON.parse 将字符串转为值（调用前必须已 OpenHandleScope） */
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
        // 清除可能挂起的异常，避免影响后续调用
        JSVM_Value ex = nullptr;
        OH_JSVM_GetAndClearLastException(env, &ex);
        return nullptr;
    }
    return result;
}

/** 判断值是否为函数（调用前必须已 OpenHandleScope） */
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

/** 挂起的 JS 回调（request 异步桥接用） */
struct PendingCall {
    JSVM_Ref callbackRef = nullptr;
    std::string requestId;
};

static std::map<int, VmInstance> g_vms;
static std::map<int, PendingCall> g_pendingCalls;
static int g_nextHandle = 1;
static std::mutex g_mutex;

// ArkTS 侧回调函数（request 事件通知），在 createVM 时注册
static napi_ref g_nativeRequestCallback = nullptr;
static napi_env g_napiEnv = nullptr;

// ============ JSVM 原生函数（注入脚本） ============

/** JS 侧调用 __lx_request__(requestId, url, optionsJson, callback) */
static JSVM_Value JsRequestCallback(JSVM_Env env, JSVM_CallbackInfo info) {
    JSVM_HandleScope scope = nullptr;
    OH_JSVM_OpenHandleScope(env, &scope);

    size_t argc = 4;
    JSVM_Value argv[4] = { nullptr };
    OH_JSVM_GetCbInfo(env, info, &argc, argv, nullptr, nullptr);
    if (argc >= 4) {
        // 提取参数（转为 std::string，脱离 scope 生命周期）
        std::string requestId = ValueToJson(env, argv[0]);
        if (requestId.size() >= 2 && requestId.front() == '"') {
            requestId = requestId.substr(1, requestId.size() - 2);
        }
        std::string url = ValueToJson(env, argv[1]);
        if (url.size() >= 2 && url.front() == '"') {
            url = url.substr(1, url.size() - 2);
        }
        std::string optionsJson = ValueToJson(env, argv[2]);

        // 保存 JS 回调引用（ref 是持久的，不受 scope 影响）
        JSVM_Value cbFn = argv[3];
        if (IsFunction(env, cbFn)) {
            JSVM_Ref cbRef = nullptr;
            if (OH_JSVM_CreateReference(env, cbFn, 1, &cbRef) == JSVM_OK) {
                int handle = 0;
                {
                    std::lock_guard<std::mutex> lock(g_mutex);
                    // 找到当前 env 对应的 handle
                    for (auto &it : g_vms) {
                        if (it.second.env == env && it.second.alive) {
                            handle = it.first;
                            break;
                        }
                    }
                    if (handle > 0) {
                        PendingCall pc;
                        pc.callbackRef = cbRef;
                        pc.requestId = requestId;
                        g_pendingCalls[handle] = pc;
                    }
                }
                // 通知 ArkTS 发起网络请求
                if (handle > 0 && g_napiEnv != nullptr && g_nativeRequestCallback != nullptr) {
                    napi_value fn = nullptr;
                    napi_get_reference_value(g_napiEnv, g_nativeRequestCallback, &fn);
                    if (fn != nullptr) {
                        napi_value argvNapi[3];
                        napi_create_string_utf8(g_napiEnv, requestId.c_str(), requestId.length(), &argvNapi[0]);
                        napi_create_string_utf8(g_napiEnv, url.c_str(), url.length(), &argvNapi[1]);
                        napi_create_string_utf8(g_napiEnv, optionsJson.c_str(), optionsJson.length(), &argvNapi[2]);
                        napi_value global = nullptr;
                        napi_get_global(g_napiEnv, &global);
                        napi_value result = nullptr;
                        napi_call_function(g_napiEnv, global, fn, 3, argvNapi, &result);
                    }
                }
            }
        }
    }

    OH_JSVM_CloseHandleScope(env, scope);
    return nullptr; // undefined
}

/** JS 侧调用 __lx_log__(level, message) */
static JSVM_Value JsLogCallback(JSVM_Env env, JSVM_CallbackInfo info) {
    JSVM_HandleScope scope = nullptr;
    OH_JSVM_OpenHandleScope(env, &scope);

    size_t argc = 2;
    JSVM_Value argv[2] = { nullptr };
    OH_JSVM_GetCbInfo(env, info, &argc, argv, nullptr, nullptr);
    if (argc >= 2) {
        std::string level = ValueToJson(env, argv[0]);
        std::string msg = ValueToJson(env, argv[1]);
        // 暂不处理，后续可桥接 hilog
        (void)level;
        (void)msg;
    }

    OH_JSVM_CloseHandleScope(env, scope);
    return nullptr;
}

/** 初始化 JSVM 原生函数并挂到全局对象（调用前必须已 OpenHandleScope） */
static void InitNativeFunctions(JSVM_Env env) {
    JSVM_Value global = nullptr;
    if (OH_JSVM_GetGlobal(env, &global) != JSVM_OK) return;

    JSVM_CallbackStruct reqCb = { JsRequestCallback, nullptr };
    JSVM_Value reqFn = nullptr;
    if (OH_JSVM_CreateFunction(env, "__lx_request__", strlen("__lx_request__"), &reqCb, &reqFn) == JSVM_OK) {
        OH_JSVM_SetNamedProperty(env, global, "__lx_request__", reqFn);
    }
    JSVM_CallbackStruct logCb = { JsLogCallback, nullptr };
    JSVM_Value logFn = nullptr;
    if (OH_JSVM_CreateFunction(env, "__lx_log__", strlen("__lx_log__"), &logCb, &logFn) == JSVM_OK) {
        OH_JSVM_SetNamedProperty(env, global, "__lx_log__", logFn);
    }
}

// ============ NAPI 导出接口 ============

extern "C" {

/** 创建 VM：createVM(onRequestCallback) → handle */
napi_value NapiCreateVM(napi_env env, napi_callback_info info) {
    size_t argc = 1;
    napi_value argv[1] = { nullptr };
    napi_get_cb_info(env, info, &argc, argv, nullptr, nullptr);

    if (argc >= 1 && argv[0] != nullptr) {
        if (g_nativeRequestCallback != nullptr) {
            napi_delete_reference(env, g_nativeRequestCallback);
        }
        napi_create_reference(env, argv[0], 1, &g_nativeRequestCallback);
        g_napiEnv = env;
    }

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

    // 注入原生函数（需在 HandleScope 内）
    {
        JSVM_HandleScope scope = nullptr;
        OH_JSVM_OpenHandleScope(jsEnv, &scope);
        InitNativeFunctions(jsEnv);
        OH_JSVM_CloseHandleScope(jsEnv, scope);
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
            // 清理挂起的回调引用
            auto pcIt = g_pendingCalls.find(handle);
            if (pcIt != g_pendingCalls.end()) {
                OH_JSVM_DeleteReference(it->second.env, pcIt->second.callbackRef);
                g_pendingCalls.erase(pcIt);
            }
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

    VmInstance *inst = nullptr;
    {
        std::lock_guard<std::mutex> lock(g_mutex);
        auto it = g_vms.find(handle);
        if (it != g_vms.end()) inst = &it->second;
    }
    if (inst == nullptr || !inst->alive) {
        napi_value err;
        napi_create_string_utf8(env, "vm not found", NAPI_AUTO_LENGTH, &err);
        napi_throw(env, err);
        return nullptr;
    }

    // 所有 JSVM 操作必须在 HandleScope 内
    std::string resultStr;
    {
        JSVM_HandleScope scope = nullptr;
        OH_JSVM_OpenHandleScope(inst->env, &scope);

        JSVM_Value scriptValue = nullptr;
        JSVM_Script compiledScript = nullptr;
        JSVM_Value result = nullptr;
        JSVM_Status status = JSVM_GENERIC_FAILURE;
        bool cacheRejected = false;
        if (OH_JSVM_CreateStringUtf8(inst->env, script.c_str(), script.length(), &scriptValue) == JSVM_OK &&
            OH_JSVM_CompileScript(inst->env, scriptValue, nullptr, 0, false, &cacheRejected, &compiledScript) == JSVM_OK) {
            status = OH_JSVM_RunScript(inst->env, compiledScript, &result);
        }
        if (status == JSVM_OK && result != nullptr) {
            resultStr = ValueToJson(inst->env, result);
        } else {
            JSVM_Value ex = nullptr;
            OH_JSVM_GetAndClearLastException(inst->env, &ex);
            if (ex != nullptr) {
                resultStr = "script error: " + ValueToJson(inst->env, ex);
            } else {
                resultStr = "script error";
            }
        }
        OH_JSVM_CloseHandleScope(inst->env, scope);
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

    VmInstance *inst = nullptr;
    {
        std::lock_guard<std::mutex> lock(g_mutex);
        auto it = g_vms.find(handle);
        if (it != g_vms.end()) inst = &it->second;
    }
    if (inst == nullptr || !inst->alive) return nullptr;

    std::string resultStr;
    {
        JSVM_HandleScope scope = nullptr;
        OH_JSVM_OpenHandleScope(inst->env, &scope);

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
                        argvList.push_back(item);
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
        OH_JSVM_CloseHandleScope(inst->env, scope);
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

    VmInstance *inst = nullptr;
    PendingCall *pc = nullptr;
    {
        std::lock_guard<std::mutex> lock(g_mutex);
        auto it = g_vms.find(handle);
        if (it != g_vms.end()) inst = &it->second;
        auto pcIt = g_pendingCalls.find(handle);
        if (pcIt != g_pendingCalls.end() && pcIt->second.requestId == requestId) {
            pc = &pcIt->second;
        }
    }
    if (inst == nullptr || pc == nullptr || pc->callbackRef == nullptr) return nullptr;

    {
        JSVM_HandleScope scope = nullptr;
        OH_JSVM_OpenHandleScope(inst->env, &scope);

        JSVM_Value cbFn = nullptr;
        if (OH_JSVM_GetReferenceValue(inst->env, pc->callbackRef, &cbFn) == JSVM_OK && cbFn != nullptr) {
            JSVM_Value argvCall[2];
            if (errorJson == "null" || errorJson.empty()) {
                OH_JSVM_GetNull(inst->env, &argvCall[0]);
            } else {
                argvCall[0] = JsonToValue(inst->env, errorJson);
            }
            if (responseJson.empty()) {
                OH_JSVM_GetNull(inst->env, &argvCall[1]);
            } else {
                argvCall[1] = JsonToValue(inst->env, responseJson);
            }
            JSVM_Value global = nullptr;
            OH_JSVM_GetGlobal(inst->env, &global);
            JSVM_Value result = nullptr;
            OH_JSVM_CallFunction(inst->env, global, cbFn, 2, argvCall, &result);
        }
        OH_JSVM_DeleteReference(inst->env, pc->callbackRef);
        OH_JSVM_CloseHandleScope(inst->env, scope);
    }

    {
        std::lock_guard<std::mutex> lock(g_mutex);
        g_pendingCalls.erase(handle);
    }
    return nullptr;
}

} // extern "C"
