/* QuickJS NAPI 模块入口。 */
#include "napi/native_api.h"

extern "C" {
napi_value NapiQuickCreateVM(napi_env env, napi_callback_info info);
napi_value NapiQuickDestroyVM(napi_env env, napi_callback_info info);
napi_value NapiQuickEvalScript(napi_env env, napi_callback_info info);
napi_value NapiQuickCallGlobalFunction(napi_env env, napi_callback_info info);
napi_value NapiQuickSetNativeResult(napi_env env, napi_callback_info info);
}

EXTERN_C_START

static napi_value Init(napi_env env, napi_value exports)
{
    napi_property_descriptor descriptors[] = {
        {"createVM", nullptr, NapiQuickCreateVM, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"destroyVM", nullptr, NapiQuickDestroyVM, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"evalScript", nullptr, NapiQuickEvalScript, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"callGlobalFunction", nullptr, NapiQuickCallGlobalFunction, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"setNativeResult", nullptr, NapiQuickSetNativeResult, nullptr, nullptr, nullptr, napi_default, nullptr},
    };
    napi_define_properties(env, exports, sizeof(descriptors) / sizeof(descriptors[0]), descriptors);
    return exports;
}

EXTERN_C_END

static napi_module quickJsModule = {
    .nm_version = 1,
    .nm_flags = 0,
    .nm_filename = nullptr,
    .nm_register_func = Init,
    .nm_modname = "quickjs_bridge",
    .nm_priv = nullptr,
    .reserved = {0},
};

extern "C" __attribute__((constructor)) void RegisterQuickJsBridgeModule()
{
    napi_module_register(&quickJsModule);
}
