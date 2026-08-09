/*
 * QuickJS 音源沙箱桥
 *
 * 每个音源创建独立 JSRuntime + JSContext，并设置内存、栈和执行时限。
 * 网络请求仍由脚本侧队列交给 ArkTS 处理，Native 层只负责安全执行 JavaScript。
 */
#include "napi/native_api.h"
#include "quickjs/quickjs.h"
#include "CryptoArchitectureKit/crypto_architecture_kit.h"

#include <algorithm>
#include <atomic>
#include <chrono>
#include <cstdint>
#include <cstring>
#include <map>
#include <memory>
#include <mutex>
#include <string>
#include <vector>

namespace {

constexpr size_t QUICKJS_MEMORY_LIMIT = 64 * 1024 * 1024;
constexpr size_t QUICKJS_STACK_LIMIT = 2 * 1024 * 1024;
constexpr int64_t QUICKJS_EXECUTION_TIMEOUT_MS = 8000;

struct QuickVmInstance {
    JSRuntime *runtime = nullptr;
    JSContext *context = nullptr;
    std::atomic<int64_t> deadlineNs {0};
};

std::map<int32_t, std::unique_ptr<QuickVmInstance>> g_instances;
std::mutex g_instancesMutex;
int32_t g_nextHandle = 1;

const char BASE64_CHARS[] =
    "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";

int Base64Value(char value)
{
    if (value >= 'A' && value <= 'Z') return value - 'A';
    if (value >= 'a' && value <= 'z') return value - 'a' + 26;
    if (value >= '0' && value <= '9') return value - '0' + 52;
    if (value == '+') return 62;
    if (value == '/') return 63;
    return -1;
}

bool DecodeBase64(const std::string &input, std::vector<uint8_t> &output)
{
    output.clear();
    int accumulator = 0;
    int bits = -8;
    for (char value : input) {
        if (value == '=') break;
        const int decoded = Base64Value(value);
        if (decoded < 0) {
            if (value == ' ' || value == '\r' || value == '\n' || value == '\t') continue;
            return false;
        }
        accumulator = (accumulator << 6) | decoded;
        bits += 6;
        if (bits >= 0) {
            output.push_back(static_cast<uint8_t>((accumulator >> bits) & 0xff));
            bits -= 8;
        }
    }
    return true;
}

std::string EncodeBase64(const uint8_t *data, size_t length)
{
    std::string output;
    output.reserve(((length + 2) / 3) * 4);
    for (size_t index = 0; index < length; index += 3) {
        const uint32_t first = data[index];
        const uint32_t second = index + 1 < length ? data[index + 1] : 0;
        const uint32_t third = index + 2 < length ? data[index + 2] : 0;
        const uint32_t group = (first << 16) | (second << 8) | third;
        output.push_back(BASE64_CHARS[(group >> 18) & 0x3f]);
        output.push_back(BASE64_CHARS[(group >> 12) & 0x3f]);
        output.push_back(index + 1 < length ? BASE64_CHARS[(group >> 6) & 0x3f] : '=');
        output.push_back(index + 2 < length ? BASE64_CHARS[group & 0x3f] : '=');
    }
    return output;
}

bool ReadDerElement(
    const std::vector<uint8_t> &data,
    size_t &position,
    uint8_t expectedTag,
    size_t &contentStart,
    size_t &contentLength)
{
    if (position + 2 > data.size() || data[position++] != expectedTag) return false;
    uint8_t lengthByte = data[position++];
    if ((lengthByte & 0x80) == 0) {
        contentLength = lengthByte;
    } else {
        const size_t byteCount = lengthByte & 0x7f;
        if (byteCount == 0 || byteCount > sizeof(size_t) || position + byteCount > data.size()) return false;
        contentLength = 0;
        for (size_t index = 0; index < byteCount; index++) {
            contentLength = (contentLength << 8) | data[position++];
        }
    }
    contentStart = position;
    if (contentStart + contentLength > data.size()) return false;
    return true;
}

size_t GetRsaModulusBytes(const std::vector<uint8_t> &der)
{
    size_t position = 0;
    size_t outerStart = 0;
    size_t outerLength = 0;
    if (!ReadDerElement(der, position, 0x30, outerStart, outerLength)) return 0;
    position = outerStart;

    // X.509 SubjectPublicKeyInfo 先包含算法序列，再包含公钥 BIT STRING。
    if (position < der.size() && der[position] == 0x30) {
        size_t algorithmStart = 0;
        size_t algorithmLength = 0;
        if (!ReadDerElement(der, position, 0x30, algorithmStart, algorithmLength)) return 0;
        position = algorithmStart + algorithmLength;
        size_t bitStringStart = 0;
        size_t bitStringLength = 0;
        if (!ReadDerElement(der, position, 0x03, bitStringStart, bitStringLength) || bitStringLength < 2) return 0;
        position = bitStringStart + 1; // 跳过 unused-bits 字节。
        size_t keyStart = 0;
        size_t keyLength = 0;
        if (!ReadDerElement(der, position, 0x30, keyStart, keyLength)) return 0;
        position = keyStart;
    }

    size_t modulusStart = 0;
    size_t modulusLength = 0;
    if (!ReadDerElement(der, position, 0x02, modulusStart, modulusLength) || modulusLength == 0) return 0;
    if (der[modulusStart] == 0 && modulusLength > 1) {
        modulusStart++;
        modulusLength--;
    }
    return modulusLength;
}

bool EncryptAes(
    const std::vector<uint8_t> &input,
    const std::vector<uint8_t> &keyData,
    const std::vector<uint8_t> &ivData,
    const std::string &mode,
    std::vector<uint8_t> &output,
    std::string &error)
{
    if (keyData.size() != 16) {
        error = "AES-128 key must be 16 bytes";
        return false;
    }
    const bool isCbc = mode == "aes-128-cbc";
    const bool isEcb = mode == "aes-128-ecb";
    if (!isCbc && !isEcb) {
        error = "unsupported AES mode: " + mode;
        return false;
    }
    if (isCbc && ivData.size() != 16) {
        error = "AES-CBC iv must be 16 bytes";
        return false;
    }

    OH_CryptoSymKeyGenerator *keyGenerator = nullptr;
    OH_CryptoSymKey *key = nullptr;
    OH_CryptoSymCipher *cipher = nullptr;
    OH_CryptoSymCipherParams *params = nullptr;
    Crypto_DataBlob encrypted = {nullptr, 0};
    OH_Crypto_ErrCode code = OH_CryptoSymKeyGenerator_Create("AES128", &keyGenerator);
    if (code == CRYPTO_SUCCESS) {
        Crypto_DataBlob keyBlob = {
            const_cast<uint8_t *>(keyData.data()), keyData.size()
        };
        code = OH_CryptoSymKeyGenerator_Convert(keyGenerator, &keyBlob, &key);
    }
    const char *algorithm = isCbc ? "AES128|CBC|PKCS7" : "AES128|ECB|PKCS7";
    if (code == CRYPTO_SUCCESS) code = OH_CryptoSymCipher_Create(algorithm, &cipher);
    if (code == CRYPTO_SUCCESS && isCbc) {
        code = OH_CryptoSymCipherParams_Create(&params);
        if (code == CRYPTO_SUCCESS) {
            Crypto_DataBlob ivBlob = {
                const_cast<uint8_t *>(ivData.data()), ivData.size()
            };
            code = OH_CryptoSymCipherParams_SetParam(params, CRYPTO_IV_DATABLOB, &ivBlob);
        }
    }
    if (code == CRYPTO_SUCCESS) {
        code = OH_CryptoSymCipher_Init(cipher, CRYPTO_ENCRYPT_MODE, key, params);
    }
    if (code == CRYPTO_SUCCESS) {
        Crypto_DataBlob inputBlob = {
            const_cast<uint8_t *>(input.data()), input.size()
        };
        code = OH_CryptoSymCipher_Final(cipher, &inputBlob, &encrypted);
    }
    if (code == CRYPTO_SUCCESS && encrypted.data != nullptr) {
        output.assign(encrypted.data, encrypted.data + encrypted.len);
    } else {
        error = "AES encryption failed, code=" + std::to_string(static_cast<int>(code));
    }

    if (encrypted.data != nullptr) OH_Crypto_FreeDataBlob(&encrypted);
    if (params != nullptr) OH_CryptoSymCipherParams_Destroy(params);
    if (cipher != nullptr) OH_CryptoSymCipher_Destroy(cipher);
    if (key != nullptr) OH_CryptoSymKey_Destroy(key);
    if (keyGenerator != nullptr) OH_CryptoSymKeyGenerator_Destroy(keyGenerator);
    return code == CRYPTO_SUCCESS;
}

bool EncryptRsaNoPadding(
    const std::vector<uint8_t> &input,
    const std::vector<uint8_t> &publicKeyDer,
    std::vector<uint8_t> &output,
    std::string &error)
{
    const size_t modulusBytes = GetRsaModulusBytes(publicKeyDer);
    if (modulusBytes == 0 || input.size() > modulusBytes) {
        error = "invalid RSA public key or input length";
        return false;
    }
    const std::string keyAlgorithm = "RSA" + std::to_string(modulusBytes * 8);
    std::vector<uint8_t> paddedInput(modulusBytes, 0);
    std::copy(input.begin(), input.end(), paddedInput.end() - input.size());

    OH_CryptoAsymKeyGenerator *keyGenerator = nullptr;
    OH_CryptoKeyPair *keyPair = nullptr;
    OH_CryptoAsymCipher *cipher = nullptr;
    Crypto_DataBlob encrypted = {nullptr, 0};
    OH_Crypto_ErrCode code = OH_CryptoAsymKeyGenerator_Create(keyAlgorithm.c_str(), &keyGenerator);
    if (code == CRYPTO_SUCCESS) {
        Crypto_DataBlob publicKeyBlob = {
            const_cast<uint8_t *>(publicKeyDer.data()), publicKeyDer.size()
        };
        code = OH_CryptoAsymKeyGenerator_Convert(
            keyGenerator, CRYPTO_DER, &publicKeyBlob, nullptr, &keyPair);
    }
    if (code == CRYPTO_SUCCESS) code = OH_CryptoAsymCipher_Create("RSA|NoPadding", &cipher);
    if (code == CRYPTO_SUCCESS) {
        code = OH_CryptoAsymCipher_Init(cipher, CRYPTO_ENCRYPT_MODE, keyPair);
    }
    if (code == CRYPTO_SUCCESS) {
        Crypto_DataBlob inputBlob = {paddedInput.data(), paddedInput.size()};
        code = OH_CryptoAsymCipher_Final(cipher, &inputBlob, &encrypted);
    }
    if (code == CRYPTO_SUCCESS && encrypted.data != nullptr) {
        output.assign(encrypted.data, encrypted.data + encrypted.len);
    } else {
        error = "RSA encryption failed, code=" + std::to_string(static_cast<int>(code));
    }

    if (encrypted.data != nullptr) OH_Crypto_FreeDataBlob(&encrypted);
    if (cipher != nullptr) OH_CryptoAsymCipher_Destroy(cipher);
    if (keyPair != nullptr) OH_CryptoKeyPair_Destroy(keyPair);
    if (keyGenerator != nullptr) OH_CryptoAsymKeyGenerator_Destroy(keyGenerator);
    return code == CRYPTO_SUCCESS;
}

std::string GetJsString(JSContext *context, JSValueConst value)
{
    const char *text = JS_ToCString(context, value);
    if (text == nullptr) return "";
    std::string result(text);
    JS_FreeCString(context, text);
    return result;
}

JSValue JsNativeAesEncrypt(
    JSContext *context,
    JSValueConst,
    int argc,
    JSValueConst *argv)
{
    if (argc < 4) return JS_ThrowTypeError(context, "aesEncrypt requires data, key, iv and mode");
    std::vector<uint8_t> input;
    std::vector<uint8_t> key;
    std::vector<uint8_t> iv;
    if (!DecodeBase64(GetJsString(context, argv[0]), input) ||
        !DecodeBase64(GetJsString(context, argv[1]), key) ||
        !DecodeBase64(GetJsString(context, argv[2]), iv)) {
        return JS_ThrowTypeError(context, "invalid AES base64 input");
    }
    std::vector<uint8_t> encrypted;
    std::string error;
    if (!EncryptAes(input, key, iv, GetJsString(context, argv[3]), encrypted, error)) {
        return JS_ThrowInternalError(context, "%s", error.c_str());
    }
    const std::string encoded = EncodeBase64(encrypted.data(), encrypted.size());
    return JS_NewStringLen(context, encoded.c_str(), encoded.length());
}

JSValue JsNativeRsaEncrypt(
    JSContext *context,
    JSValueConst,
    int argc,
    JSValueConst *argv)
{
    if (argc < 2) return JS_ThrowTypeError(context, "rsaEncrypt requires data and public key");
    std::vector<uint8_t> input;
    std::vector<uint8_t> publicKey;
    if (!DecodeBase64(GetJsString(context, argv[0]), input) ||
        !DecodeBase64(GetJsString(context, argv[1]), publicKey)) {
        return JS_ThrowTypeError(context, "invalid RSA base64 input");
    }
    std::vector<uint8_t> encrypted;
    std::string error;
    if (!EncryptRsaNoPadding(input, publicKey, encrypted, error)) {
        return JS_ThrowInternalError(context, "%s", error.c_str());
    }
    const std::string encoded = EncodeBase64(encrypted.data(), encrypted.size());
    return JS_NewStringLen(context, encoded.c_str(), encoded.length());
}

void InstallSourceNativeFunctions(JSContext *context)
{
    JSValue global = JS_GetGlobalObject(context);
    JS_SetPropertyStr(context, global, "__source_native_aes_encrypt__",
        JS_NewCFunction(context, JsNativeAesEncrypt, "__source_native_aes_encrypt__", 4));
    JS_SetPropertyStr(context, global, "__source_native_rsa_encrypt__",
        JS_NewCFunction(context, JsNativeRsaEncrypt, "__source_native_rsa_encrypt__", 2));
    JS_FreeValue(context, global);
}

int64_t NowNs()
{
    return std::chrono::duration_cast<std::chrono::nanoseconds>(
        std::chrono::steady_clock::now().time_since_epoch()).count();
}

int InterruptHandler(JSRuntime *, void *opaque)
{
    auto *instance = static_cast<QuickVmInstance *>(opaque);
    if (instance == nullptr) return 1;
    const int64_t deadline = instance->deadlineNs.load();
    return deadline > 0 && NowNs() >= deadline ? 1 : 0;
}

QuickVmInstance *GetInstance(int32_t handle)
{
    std::lock_guard<std::mutex> lock(g_instancesMutex);
    const auto it = g_instances.find(handle);
    return it == g_instances.end() ? nullptr : it->second.get();
}

std::string GetNapiString(napi_env env, napi_value value)
{
    size_t length = 0;
    if (napi_get_value_string_utf8(env, value, nullptr, 0, &length) != napi_ok) return "";
    std::string result(length, '\0');
    if (length > 0) {
        napi_get_value_string_utf8(env, value, &result[0], length + 1, &length);
    }
    return result;
}

napi_value CreateNapiString(napi_env env, const std::string &value)
{
    napi_value result = nullptr;
    napi_create_string_utf8(env, value.c_str(), value.length(), &result);
    return result;
}

std::string GetExceptionText(JSContext *context)
{
    JSValue exception = JS_GetException(context);
    std::string message = "unknown script error";
    const char *text = JS_ToCString(context, exception);
    if (text != nullptr) {
        message = text;
        JS_FreeCString(context, text);
    }
    JSValue stack = JS_GetPropertyStr(context, exception, "stack");
    if (!JS_IsUndefined(stack)) {
        const char *stackText = JS_ToCString(context, stack);
        if (stackText != nullptr) {
            message = stackText;
            JS_FreeCString(context, stackText);
        }
    }
    JS_FreeValue(context, stack);
    JS_FreeValue(context, exception);
    return message;
}

std::string ValueToJson(JSContext *context, JSValueConst value)
{
    if (JS_IsUndefined(value)) return "undefined";
    if (JS_IsNull(value)) return "null";
    JSValue json = JS_JSONStringify(context, value, JS_UNDEFINED, JS_UNDEFINED);
    if (JS_IsException(json)) return GetExceptionText(context);
    if (!JS_IsUndefined(json)) {
        const char *text = JS_ToCString(context, json);
        if (text != nullptr) {
            std::string result(text);
            JS_FreeCString(context, text);
            JS_FreeValue(context, json);
            return result;
        }
    }
    JS_FreeValue(context, json);
    const char *text = JS_ToCString(context, value);
    if (text == nullptr) return "";
    std::string result(text);
    JS_FreeCString(context, text);
    return result;
}

bool DrainPendingJobs(QuickVmInstance *instance, std::string &error)
{
    JSContext *jobContext = nullptr;
    for (int i = 0; i < 1024; i++) {
        const int status = JS_ExecutePendingJob(instance->runtime, &jobContext);
        if (status == 0) return true;
        if (status < 0) {
            error = GetExceptionText(jobContext == nullptr ? instance->context : jobContext);
            return false;
        }
    }
    error = "too many pending jobs";
    return false;
}

void BeginExecution(QuickVmInstance *instance)
{
    instance->deadlineNs.store(NowNs() + QUICKJS_EXECUTION_TIMEOUT_MS * 1000 * 1000);
}

void EndExecution(QuickVmInstance *instance)
{
    instance->deadlineNs.store(0);
}

JSValue ParseJsonOrNull(JSContext *context, const std::string &json)
{
    if (json.empty() || json == "null") return JS_NULL;
    return JS_ParseJSON(context, json.c_str(), json.length(), "<native-json>");
}

std::string CallGlobalFunction(
    QuickVmInstance *instance,
    const std::string &functionName,
    const std::string &argsJson)
{
    JSContext *context = instance->context;
    JSValue global = JS_GetGlobalObject(context);
    JSValue function = JS_GetPropertyStr(context, global, functionName.c_str());
    if (!JS_IsFunction(context, function)) {
        JS_FreeValue(context, function);
        JS_FreeValue(context, global);
        return "function not found: " + functionName;
    }

    JSValue argsArray = JS_ParseJSON(context, argsJson.c_str(), argsJson.length(), "<native-args>");
    if (JS_IsException(argsArray) || JS_IsArray(context, argsArray) != 1) {
        if (JS_IsException(argsArray)) JS_FreeValue(context, JS_GetException(context));
        JS_FreeValue(context, argsArray);
        JS_FreeValue(context, function);
        JS_FreeValue(context, global);
        return "call error: invalid args json";
    }

    uint32_t length = 0;
    JSValue lengthValue = JS_GetPropertyStr(context, argsArray, "length");
    JS_ToUint32(context, &length, lengthValue);
    JS_FreeValue(context, lengthValue);
    std::vector<JSValue> values;
    std::vector<JSValueConst> argv;
    values.reserve(length);
    argv.reserve(length);
    for (uint32_t i = 0; i < length; i++) {
        values.push_back(JS_GetPropertyUint32(context, argsArray, i));
    }
    for (const JSValue &value : values) argv.push_back(value);

    BeginExecution(instance);
    JSValue result = JS_Call(context, function, global, argv.size(), argv.data());
    std::string pendingError;
    const bool jobsOk = !JS_IsException(result) && DrainPendingJobs(instance, pendingError);
    EndExecution(instance);

    std::string output;
    if (JS_IsException(result)) {
        output = "call error: " + GetExceptionText(context);
    } else if (!jobsOk) {
        output = "call error: " + pendingError;
    } else {
        output = ValueToJson(context, result);
    }

    JS_FreeValue(context, result);
    for (JSValue &value : values) JS_FreeValue(context, value);
    JS_FreeValue(context, argsArray);
    JS_FreeValue(context, function);
    JS_FreeValue(context, global);
    return output;
}

} // namespace

extern "C" {

napi_value NapiQuickCreateVM(napi_env env, napi_callback_info)
{
    auto instance = std::make_unique<QuickVmInstance>();
    instance->runtime = JS_NewRuntime();
    if (instance->runtime == nullptr) {
        napi_throw_error(env, nullptr, "quickjs create runtime failed");
        return nullptr;
    }
    JS_SetMemoryLimit(instance->runtime, QUICKJS_MEMORY_LIMIT);
    JS_SetMaxStackSize(instance->runtime, QUICKJS_STACK_LIMIT);
    JS_SetInterruptHandler(instance->runtime, InterruptHandler, instance.get());
    instance->context = JS_NewContext(instance->runtime);
    if (instance->context == nullptr) {
        JS_FreeRuntime(instance->runtime);
        napi_throw_error(env, nullptr, "quickjs create context failed");
        return nullptr;
    }
    InstallSourceNativeFunctions(instance->context);

    int32_t handle = 0;
    {
        std::lock_guard<std::mutex> lock(g_instancesMutex);
        handle = g_nextHandle++;
        g_instances.emplace(handle, std::move(instance));
    }
    napi_value result = nullptr;
    napi_create_int32(env, handle, &result);
    return result;
}

napi_value NapiQuickDestroyVM(napi_env env, napi_callback_info info)
{
    size_t argc = 1;
    napi_value argv[1] = {nullptr};
    napi_get_cb_info(env, info, &argc, argv, nullptr, nullptr);
    int32_t handle = 0;
    napi_get_value_int32(env, argv[0], &handle);

    std::unique_ptr<QuickVmInstance> instance;
    {
        std::lock_guard<std::mutex> lock(g_instancesMutex);
        const auto it = g_instances.find(handle);
        if (it != g_instances.end()) {
            instance = std::move(it->second);
            g_instances.erase(it);
        }
    }
    if (instance != nullptr) {
        JS_FreeContext(instance->context);
        JS_FreeRuntime(instance->runtime);
    }
    return nullptr;
}

napi_value NapiQuickEvalScript(napi_env env, napi_callback_info info)
{
    size_t argc = 2;
    napi_value argv[2] = {nullptr, nullptr};
    napi_get_cb_info(env, info, &argc, argv, nullptr, nullptr);
    int32_t handle = 0;
    napi_get_value_int32(env, argv[0], &handle);
    QuickVmInstance *instance = GetInstance(handle);
    if (instance == nullptr) return CreateNapiString(env, "script error: vm not found");
    const std::string script = GetNapiString(env, argv[1]);

    BeginExecution(instance);
    JSValue result = JS_Eval(instance->context, script.c_str(), script.length(), "<user-api>", JS_EVAL_TYPE_GLOBAL);
    std::string pendingError;
    const bool jobsOk = !JS_IsException(result) && DrainPendingJobs(instance, pendingError);
    EndExecution(instance);

    std::string output;
    if (JS_IsException(result)) {
        output = "script error: " + GetExceptionText(instance->context);
    } else if (!jobsOk) {
        output = "script error: " + pendingError;
    } else {
        output = ValueToJson(instance->context, result);
    }
    JS_FreeValue(instance->context, result);
    return CreateNapiString(env, output);
}

napi_value NapiQuickCallGlobalFunction(napi_env env, napi_callback_info info)
{
    size_t argc = 3;
    napi_value argv[3] = {nullptr, nullptr, nullptr};
    napi_get_cb_info(env, info, &argc, argv, nullptr, nullptr);
    int32_t handle = 0;
    napi_get_value_int32(env, argv[0], &handle);
    QuickVmInstance *instance = GetInstance(handle);
    if (instance == nullptr) return CreateNapiString(env, "call error: vm not found");
    return CreateNapiString(env, CallGlobalFunction(
        instance, GetNapiString(env, argv[1]), GetNapiString(env, argv[2])));
}

napi_value NapiQuickSetNativeResult(napi_env env, napi_callback_info info)
{
    size_t argc = 4;
    napi_value argv[4] = {nullptr, nullptr, nullptr, nullptr};
    napi_get_cb_info(env, info, &argc, argv, nullptr, nullptr);
    int32_t handle = 0;
    napi_get_value_int32(env, argv[0], &handle);
    QuickVmInstance *instance = GetInstance(handle);
    if (instance == nullptr) return nullptr;
    const std::string requestId = GetNapiString(env, argv[1]);
    const std::string errorJson = GetNapiString(env, argv[2]);
    const std::string responseJson = GetNapiString(env, argv[3]);

    JSContext *context = instance->context;
    JSValue global = JS_GetGlobalObject(context);
    JSValue function = JS_GetPropertyStr(context, global, "__source_resolveRequest__");
    if (JS_IsFunction(context, function)) {
        JSValue callArgs[3] = {
            JS_NewStringLen(context, requestId.c_str(), requestId.length()),
            ParseJsonOrNull(context, errorJson),
            ParseJsonOrNull(context, responseJson)
        };
        BeginExecution(instance);
        JSValue result = JS_Call(context, function, global, 3, callArgs);
        std::string ignored;
        if (!JS_IsException(result)) DrainPendingJobs(instance, ignored);
        EndExecution(instance);
        JS_FreeValue(context, result);
        for (JSValue &arg : callArgs) JS_FreeValue(context, arg);
    }
    JS_FreeValue(context, function);
    JS_FreeValue(context, global);
    return nullptr;
}

} // extern "C"
