#include "audio_eq_engine.h"

#include <array>
#include <string>
#include <vector>

#include "napi/native_api.h"
#include "native_eq_player.h"

namespace {
napi_value CreateBoolean(napi_env env, bool value)
{
    napi_value result = nullptr;
    napi_get_boolean(env, value, &result);
    return result;
}

napi_value NapiIsSupported(napi_env env, napi_callback_info info)
{
    return CreateBoolean(env, AudioEqEngine::GetInstance().IsSupported());
}

napi_value NapiInitialize(napi_env env, napi_callback_info info)
{
    return CreateBoolean(env, AudioEqEngine::GetInstance().Initialize());
}

napi_value NapiRelease(napi_env env, napi_callback_info info)
{
    AudioEqEngine::GetInstance().Release();
    napi_value result = nullptr;
    napi_get_undefined(env, &result);
    return result;
}

napi_value NapiSetEnabled(napi_env env, napi_callback_info info)
{
    size_t argc = 1;
    napi_value argv[1] = {nullptr};
    napi_get_cb_info(env, info, &argc, argv, nullptr, nullptr);
    bool enabled = false;
    if (argc != 1 || napi_get_value_bool(env, argv[0], &enabled) != napi_ok) {
        napi_throw_type_error(env, nullptr, "enabled 必须是布尔值");
        return nullptr;
    }
    return CreateBoolean(env, AudioEqEngine::GetInstance().SetEnabled(enabled));
}

napi_value NapiSetGains(napi_env env, napi_callback_info info)
{
    size_t argc = 1;
    napi_value argv[1] = {nullptr};
    napi_get_cb_info(env, info, &argc, argv, nullptr, nullptr);
    bool isArray = false;
    if (argc != 1 || napi_is_array(env, argv[0], &isArray) != napi_ok || !isArray) {
        napi_throw_type_error(env, nullptr, "gains 必须是包含十个整数的数组");
        return nullptr;
    }
    uint32_t length = 0;
    napi_get_array_length(env, argv[0], &length);
    if (length != EQUALIZER_BAND_NUM) {
        napi_throw_range_error(env, nullptr, "gains 必须正好包含十个频段");
        return nullptr;
    }
    std::array<int32_t, EQUALIZER_BAND_NUM> gains{};
    for (uint32_t index = 0; index < length; ++index) {
        napi_value item = nullptr;
        napi_get_element(env, argv[0], index, &item);
        if (napi_get_value_int32(env, item, &gains[index]) != napi_ok) {
            napi_throw_type_error(env, nullptr, "每个频段增益都必须是整数");
            return nullptr;
        }
    }
    return CreateBoolean(env, AudioEqEngine::GetInstance().SetGains(gains));
}

napi_value NapiGetGains(napi_env env, napi_callback_info info)
{
    const auto gains = AudioEqEngine::GetInstance().GetGains();
    napi_value result = nullptr;
    napi_create_array_with_length(env, gains.size(), &result);
    for (uint32_t index = 0; index < gains.size(); ++index) {
        napi_value value = nullptr;
        napi_create_int32(env, gains[index], &value);
        napi_set_element(env, result, index, value);
    }
    return result;
}

napi_value NapiSetPreset(napi_env env, napi_callback_info info)
{
    size_t argc = 1;
    napi_value argv[1] = {nullptr};
    napi_get_cb_info(env, info, &argc, argv, nullptr, nullptr);
    size_t length = 0;
    if (argc != 1 || napi_get_value_string_utf8(env, argv[0], nullptr, 0, &length) != napi_ok) {
        napi_throw_type_error(env, nullptr, "presetName 必须是字符串");
        return nullptr;
    }
    std::vector<char> preset(length + 1, '\0');
    napi_get_value_string_utf8(env, argv[0], preset.data(), preset.size(), &length);
    return CreateBoolean(env, AudioEqEngine::GetInstance().SetPreset(preset.data()));
}

napi_value NapiPlayerStart(napi_env env, napi_callback_info info)
{
    size_t argc = 3;
    napi_value argv[3] = {nullptr, nullptr, nullptr};
    napi_get_cb_info(env, info, &argc, argv, nullptr, nullptr);
    size_t urlLength = 0;
    if (argc < 1 || napi_get_value_string_utf8(env, argv[0], nullptr, 0, &urlLength) != napi_ok) {
        napi_throw_type_error(env, nullptr, "url 必须是字符串");
        return nullptr;
    }
    std::vector<char> url(urlLength + 1, '\0');
    napi_get_value_string_utf8(env, argv[0], url.data(), url.size(), &urlLength);
    int64_t positionMs = 0;
    bool autoPlay = true;
    if (argc >= 2) napi_get_value_int64(env, argv[1], &positionMs);
    if (argc >= 3) napi_get_value_bool(env, argv[2], &autoPlay);
    return CreateBoolean(env, NativeEqPlayer::GetInstance().Start(url.data(), positionMs, autoPlay));
}

napi_value NapiPlayerStop(napi_env env, napi_callback_info info)
{
    NativeEqPlayer::GetInstance().Stop();
    napi_value result = nullptr;
    napi_get_undefined(env, &result);
    return result;
}

napi_value NapiPlayerPause(napi_env env, napi_callback_info info)
{
    return CreateBoolean(env, NativeEqPlayer::GetInstance().Pause());
}

napi_value NapiPlayerResume(napi_env env, napi_callback_info info)
{
    return CreateBoolean(env, NativeEqPlayer::GetInstance().Resume());
}

napi_value NapiPlayerSeek(napi_env env, napi_callback_info info)
{
    size_t argc = 1;
    napi_value argv[1] = {nullptr};
    napi_get_cb_info(env, info, &argc, argv, nullptr, nullptr);
    int64_t positionMs = 0;
    if (argc != 1 || napi_get_value_int64(env, argv[0], &positionMs) != napi_ok) {
        napi_throw_type_error(env, nullptr, "positionMs 必须是整数");
        return nullptr;
    }
    return CreateBoolean(env, NativeEqPlayer::GetInstance().Seek(positionMs));
}

napi_value NapiPlayerGetState(napi_env env, napi_callback_info info)
{
    napi_value result = nullptr;
    napi_create_int32(env, static_cast<int32_t>(NativeEqPlayer::GetInstance().GetState()), &result);
    return result;
}

napi_value NapiPlayerGetPosition(napi_env env, napi_callback_info info)
{
    napi_value result = nullptr;
    napi_create_int64(env, NativeEqPlayer::GetInstance().GetPositionMs(), &result);
    return result;
}

napi_value NapiPlayerGetDuration(napi_env env, napi_callback_info info)
{
    napi_value result = nullptr;
    napi_create_int64(env, NativeEqPlayer::GetInstance().GetDurationMs(), &result);
    return result;
}

napi_value NapiPlayerGetLastError(napi_env env, napi_callback_info info)
{
    const std::string message = NativeEqPlayer::GetInstance().GetLastError();
    napi_value result = nullptr;
    napi_create_string_utf8(env, message.c_str(), message.size(), &result);
    return result;
}
}

EXTERN_C_START
static napi_value Init(napi_env env, napi_value exports)
{
    napi_property_descriptor descriptors[] = {
        {"isSupported", nullptr, NapiIsSupported, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"initialize", nullptr, NapiInitialize, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"release", nullptr, NapiRelease, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"setEnabled", nullptr, NapiSetEnabled, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"setGains", nullptr, NapiSetGains, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"getGains", nullptr, NapiGetGains, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"setPreset", nullptr, NapiSetPreset, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"playerStart", nullptr, NapiPlayerStart, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"playerStop", nullptr, NapiPlayerStop, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"playerPause", nullptr, NapiPlayerPause, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"playerResume", nullptr, NapiPlayerResume, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"playerSeek", nullptr, NapiPlayerSeek, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"playerGetState", nullptr, NapiPlayerGetState, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"playerGetPosition", nullptr, NapiPlayerGetPosition, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"playerGetDuration", nullptr, NapiPlayerGetDuration, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"playerGetLastError", nullptr, NapiPlayerGetLastError, nullptr, nullptr, nullptr, napi_default, nullptr},
    };
    napi_define_properties(env, exports, sizeof(descriptors) / sizeof(descriptors[0]), descriptors);
    return exports;
}
EXTERN_C_END

static napi_module audioEqModule = {
    .nm_version = 1,
    .nm_flags = 0,
    .nm_filename = nullptr,
    .nm_register_func = Init,
    .nm_modname = "audio_eq_bridge",
    .nm_priv = nullptr,
    .reserved = {0},
};

extern "C" __attribute__((constructor)) void RegisterAudioEqBridgeModule()
{
    napi_module_register(&audioEqModule);
}
