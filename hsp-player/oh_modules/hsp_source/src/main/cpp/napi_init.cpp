/*
 * NAPI 模块入口
 *
 * 注册 jsvm_bridge 模块，导出以下接口给 ArkTS 侧调用：
 * - createVM(onRequestCallback) → handle
 * - destroyVM(handle)
 * - evalScript(handle, script) → resultJson
 * - callGlobalFunction(handle, fnName, argsJson) → resultJson
 * - setNativeResult(handle, requestId, errorJson, responseJson)
 */
#include "napi/native_api.h"

// 外部实现（jsvm_bridge.cpp），统一使用 C 链接避免名称修饰
extern "C" {
napi_value NapiCreateVM(napi_env env, napi_callback_info info);
napi_value NapiDestroyVM(napi_env env, napi_callback_info info);
napi_value NapiEvalScript(napi_env env, napi_callback_info info);
napi_value NapiCallGlobalFunction(napi_env env, napi_callback_info info);
napi_value NapiSetNativeResult(napi_env env, napi_callback_info info);
}

EXTERN_C_START

static napi_value Init(napi_env env, napi_value exports) {
    napi_property_descriptor desc[] = {
        {"createVM", nullptr, NapiCreateVM, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"destroyVM", nullptr, NapiDestroyVM, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"evalScript", nullptr, NapiEvalScript, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"callGlobalFunction", nullptr, NapiCallGlobalFunction, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"setNativeResult", nullptr, NapiSetNativeResult, nullptr, nullptr, nullptr, napi_default, nullptr},
    };
    napi_define_properties(env, exports, sizeof(desc) / sizeof(desc[0]), desc);
    return exports;
}

EXTERN_C_END

// NAPI 模块注册（模块名需与库名 jsvm_bridge 一致）
static napi_module demoModule = {
    .nm_version = 1,
    .nm_flags = 0,
    .nm_filename = nullptr,
    .nm_register_func = Init,
    .nm_modname = "jsvm_bridge",
    .nm_priv = ((void *)0),
    .reserved = { 0 },
};

extern "C" __attribute__((constructor)) void RegisterJsvmBridgeModule(void) {
    napi_module_register(&demoModule);
}
