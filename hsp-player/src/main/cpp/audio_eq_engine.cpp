#include "audio_eq_engine.h"

#include <algorithm>
#include <chrono>
#include <cstring>
#include <string>

namespace {
constexpr int32_t MIN_GAIN_DB = -12;
constexpr int32_t MAX_GAIN_DB = 12;

bool IsSuccess(OH_AudioSuite_Result result)
{
    return result == AUDIOSUITE_SUCCESS;
}

OH_AudioFormat CreateAudioFormat(int32_t sampleRate, int32_t channelCount, int64_t channelLayout)
{
    OH_AudioFormat format{};
    format.samplingRate = static_cast<OH_Audio_SampleRate>(sampleRate);
    format.channelLayout = static_cast<OH_AudioChannelLayout>(channelLayout);
    format.channelCount = channelCount;
    format.sampleFormat = AUDIO_SAMPLE_S16LE;
    format.encodingType = AUDIO_ENCODING_TYPE_RAW;
    return format;
}
}

AudioEqEngine &AudioEqEngine::GetInstance()
{
    static AudioEqEngine instance;
    return instance;
}

AudioEqEngine::~AudioEqEngine()
{
    Release();
}

bool AudioEqEngine::IsSupported() const
{
    bool supported = false;
    const OH_AudioSuite_Result result =
        OH_AudioSuiteEngine_IsNodeTypeSupported(EFFECT_NODE_TYPE_EQUALIZER, &supported);
    return IsSuccess(result) && supported;
}

bool AudioEqEngine::Initialize()
{
    std::lock_guard<std::mutex> lock(controlMutex_);
    return InitializeUnlocked();
}

bool AudioEqEngine::InitializeUnlocked()
{
    if (initialized_) {
        return true;
    }
    if (!IsSupported()) {
        return false;
    }
    if (!IsSuccess(OH_AudioSuiteEngine_Create(&engine_)) || engine_ == nullptr) {
        ReleaseUnlocked();
        return false;
    }
    if (!IsSuccess(OH_AudioSuiteEngine_CreatePipeline(
            engine_, &pipeline_, AUDIOSUITE_PIPELINE_REALTIME_MODE)) || pipeline_ == nullptr) {
        ReleaseUnlocked();
        return false;
    }
    if (!CreateNodes()) {
        ReleaseUnlocked();
        return false;
    }
    initialized_ = true;
    OH_EqualizerFrequencyBandGains params{};
    std::copy(gains_.begin(), gains_.end(), std::begin(params.gains));
    if (!IsSuccess(OH_AudioSuiteEngine_SetEqualizerFrequencyBandGains(eqNode_, params)) ||
        !IsSuccess(OH_AudioSuiteEngine_BypassEffectNode(eqNode_, !enabled_))) {
        ReleaseUnlocked();
        return false;
    }
    return true;
}

bool AudioEqEngine::PrepareForPlayback(int32_t sampleRate, int32_t channelCount, int64_t channelLayout)
{
    if (sampleRate <= 0 || channelCount <= 0) {
        return false;
    }
    std::lock_guard<std::mutex> lock(controlMutex_);
    const bool needsRebuild = !initialized_ || inputSampleRate_ != sampleRate ||
        inputChannelCount_ != channelCount || inputChannelLayout_ != channelLayout;
    if (!needsRebuild) {
        std::lock_guard<std::mutex> pcmLock(pcmMutex_);
        pcmBuffer_.clear();
        pcmReadOffset_ = 0;
        inputFinished_ = false;
        return true;
    }
    ReleaseUnlocked();
    inputSampleRate_ = sampleRate;
    inputChannelCount_ = channelCount;
    inputChannelLayout_ = channelLayout;
    return InitializeUnlocked();
}

bool AudioEqEngine::CreateNodes()
{
    OH_AudioNodeBuilder *builder = nullptr;
    if (!IsSuccess(OH_AudioSuiteNodeBuilder_Create(&builder)) || builder == nullptr) {
        return false;
    }

    bool success = true;
    OH_AudioFormat inputFormat = CreateAudioFormat(inputSampleRate_, inputChannelCount_, inputChannelLayout_);
    OH_AudioFormat outputFormat = CreateAudioFormat(48000, 2, CH_LAYOUT_STEREO);

    success = success && IsSuccess(OH_AudioSuiteNodeBuilder_SetNodeType(builder, INPUT_NODE_TYPE_DEFAULT));
    success = success && IsSuccess(OH_AudioSuiteNodeBuilder_SetFormat(builder, inputFormat));
    success = success && IsSuccess(OH_AudioSuiteNodeBuilder_SetRequestDataCallback(
        builder, RequestInputData, this));
    success = success && IsSuccess(OH_AudioSuiteEngine_CreateNode(pipeline_, builder, &inputNode_));

    success = success && IsSuccess(OH_AudioSuiteNodeBuilder_Reset(builder));
    success = success && IsSuccess(OH_AudioSuiteNodeBuilder_SetNodeType(builder, EFFECT_NODE_TYPE_EQUALIZER));
    success = success && IsSuccess(OH_AudioSuiteEngine_CreateNode(pipeline_, builder, &eqNode_));
    success = success && IsSuccess(OH_AudioSuiteEngine_SetEqualizerFrequencyBandGains(
        eqNode_, OH_EQUALIZER_PARAM_DEFAULT));
    success = success && IsSuccess(OH_AudioSuiteEngine_BypassEffectNode(eqNode_, true));

    success = success && IsSuccess(OH_AudioSuiteNodeBuilder_Reset(builder));
    success = success && IsSuccess(OH_AudioSuiteNodeBuilder_SetNodeType(builder, OUTPUT_NODE_TYPE_DEFAULT));
    success = success && IsSuccess(OH_AudioSuiteNodeBuilder_SetFormat(builder, outputFormat));
    success = success && IsSuccess(OH_AudioSuiteEngine_CreateNode(pipeline_, builder, &outputNode_));

    OH_AudioSuiteNodeBuilder_Destroy(builder);
    if (!success) {
        return false;
    }
    return IsSuccess(OH_AudioSuiteEngine_ConnectNodes(inputNode_, eqNode_)) &&
           IsSuccess(OH_AudioSuiteEngine_ConnectNodes(eqNode_, outputNode_));
}

int32_t AudioEqEngine::RequestInputData(OH_AudioNode *audioNode, void *userData, void *audioData,
                                        int32_t audioDataSize, bool *finished)
{
    if (audioNode == nullptr || userData == nullptr || audioData == nullptr ||
        audioDataSize <= 0 || finished == nullptr) {
        return -1;
    }
    auto *engine = static_cast<AudioEqEngine *>(userData);
    std::unique_lock<std::mutex> lock(engine->pcmMutex_);
    engine->pcmCondition_.wait_for(lock, std::chrono::milliseconds(40), [engine]() {
        return engine->pcmReadOffset_ < engine->pcmBuffer_.size() || engine->inputFinished_;
    });

    const size_t available = engine->pcmBuffer_.size() - engine->pcmReadOffset_;
    const size_t requested = static_cast<size_t>(audioDataSize);
    const size_t copySize = std::min(available, requested);
    if (copySize > 0) {
        std::memcpy(audioData, engine->pcmBuffer_.data() + engine->pcmReadOffset_, copySize);
        engine->pcmReadOffset_ += copySize;
    }
    if (copySize < requested) {
        std::memset(static_cast<uint8_t *>(audioData) + copySize, 0, requested - copySize);
    }
    if (engine->pcmReadOffset_ > 1024 * 1024 && engine->pcmReadOffset_ * 2 > engine->pcmBuffer_.size()) {
        engine->pcmBuffer_.erase(engine->pcmBuffer_.begin(),
                                 engine->pcmBuffer_.begin() + static_cast<std::ptrdiff_t>(engine->pcmReadOffset_));
        engine->pcmReadOffset_ = 0;
    }
    *finished = engine->inputFinished_ && engine->pcmReadOffset_ >= engine->pcmBuffer_.size();
    lock.unlock();
    engine->pcmCondition_.notify_all();
    // 网络短暂抖动时用静音补齐当前实时帧；输入真正结束后才返回实际剩余量。
    return *finished ? static_cast<int32_t>(copySize) : audioDataSize;
}

bool AudioEqEngine::PushPcm(const uint8_t *data, size_t size)
{
    if (data == nullptr || size == 0) {
        return false;
    }
    std::unique_lock<std::mutex> lock(pcmMutex_);
    pcmCondition_.wait(lock, [this]() {
        const size_t pending = pcmBuffer_.size() - pcmReadOffset_;
        return !pipelineRunning_.load() || pending < 4 * 1024 * 1024;
    });
    if (!pipelineRunning_.load() || inputFinished_) {
        return false;
    }
    pcmBuffer_.insert(pcmBuffer_.end(), data, data + size);
    lock.unlock();
    pcmCondition_.notify_all();
    return true;
}

void AudioEqEngine::ResetPcm()
{
    std::lock_guard<std::mutex> lock(pcmMutex_);
    pcmBuffer_.clear();
    pcmReadOffset_ = 0;
    inputFinished_ = false;
    pcmCondition_.notify_all();
}

void AudioEqEngine::MarkInputFinished()
{
    std::lock_guard<std::mutex> lock(pcmMutex_);
    inputFinished_ = true;
    pcmCondition_.notify_all();
}

bool AudioEqEngine::StartPipeline()
{
    std::lock_guard<std::mutex> lock(controlMutex_);
    if (!initialized_ || pipeline_ == nullptr) {
        return false;
    }
    if (pipelineRunning_.load()) {
        return true;
    }
    {
        std::lock_guard<std::mutex> pcmLock(pcmMutex_);
        inputFinished_ = false;
    }
    if (!IsSuccess(OH_AudioSuiteEngine_StartPipeline(pipeline_))) {
        std::lock_guard<std::mutex> pcmLock(pcmMutex_);
        inputFinished_ = true;
        return false;
    }
    pipelineRunning_.store(true);
    return true;
}

void AudioEqEngine::StopPipeline()
{
    std::lock_guard<std::mutex> lock(controlMutex_);
    const bool shouldStop = pipeline_ != nullptr && pipelineRunning_.exchange(false);
    {
        std::lock_guard<std::mutex> pcmLock(pcmMutex_);
        inputFinished_ = true;
        pcmCondition_.notify_all();
    }
    // 实时回调只使用 pcmMutex_，因此这里持有控制锁不会再造成环形等待。
    if (shouldStop) {
        OH_AudioSuiteEngine_StopPipeline(pipeline_);
    }
}

bool AudioEqEngine::SetEnabled(bool enabled)
{
    std::lock_guard<std::mutex> lock(controlMutex_);
    if (!initialized_ || eqNode_ == nullptr) {
        return false;
    }
    if (!IsSuccess(OH_AudioSuiteEngine_BypassEffectNode(eqNode_, !enabled))) {
        return false;
    }
    enabled_ = enabled;
    return true;
}

bool AudioEqEngine::SetGains(const std::array<int32_t, EQUALIZER_BAND_NUM> &gains)
{
    std::lock_guard<std::mutex> lock(controlMutex_);
    if (!initialized_ || eqNode_ == nullptr) {
        return false;
    }
    OH_EqualizerFrequencyBandGains params{};
    for (size_t index = 0; index < gains.size(); ++index) {
        params.gains[index] = std::clamp(gains[index], MIN_GAIN_DB, MAX_GAIN_DB);
    }
    if (!IsSuccess(OH_AudioSuiteEngine_SetEqualizerFrequencyBandGains(eqNode_, params))) {
        return false;
    }
    std::copy(std::begin(params.gains), std::end(params.gains), gains_.begin());
    return true;
}

bool AudioEqEngine::SetPreset(const char *presetName)
{
    if (presetName == nullptr) {
        return false;
    }
    const std::string name(presetName);
    const OH_EqualizerFrequencyBandGains *preset = &OH_EQUALIZER_PARAM_DEFAULT;
    if (name == "ballad") {
        preset = &OH_EQUALIZER_PARAM_BALLADS;
    } else if (name == "chinese") {
        preset = &OH_EQUALIZER_PARAM_CHINESE_STYLE;
    } else if (name == "classical") {
        preset = &OH_EQUALIZER_PARAM_CLASSICAL;
    } else if (name == "dance") {
        preset = &OH_EQUALIZER_PARAM_DANCE_MUSIC;
    } else if (name == "jazz") {
        preset = &OH_EQUALIZER_PARAM_JAZZ;
    } else if (name == "pop") {
        preset = &OH_EQUALIZER_PARAM_POP;
    } else if (name == "rb") {
        preset = &OH_EQUALIZER_PARAM_RB;
    } else if (name == "rock") {
        preset = &OH_EQUALIZER_PARAM_ROCK;
    } else if (name != "default") {
        return false;
    }

    std::array<int32_t, EQUALIZER_BAND_NUM> values{};
    std::copy(std::begin(preset->gains), std::end(preset->gains), values.begin());
    return SetGains(values);
}

std::array<int32_t, EQUALIZER_BAND_NUM> AudioEqEngine::GetGains() const
{
    std::lock_guard<std::mutex> lock(controlMutex_);
    return gains_;
}

bool AudioEqEngine::IsEnabled() const
{
    std::lock_guard<std::mutex> lock(controlMutex_);
    return enabled_;
}

bool AudioEqEngine::IsInitialized() const
{
    std::lock_guard<std::mutex> lock(controlMutex_);
    return initialized_;
}

OH_AudioSuitePipeline *AudioEqEngine::GetPipeline() const
{
    std::lock_guard<std::mutex> lock(controlMutex_);
    return pipeline_;
}

void AudioEqEngine::Release()
{
    StopPipeline();
    std::lock_guard<std::mutex> lock(controlMutex_);
    ReleaseUnlocked();
}

void AudioEqEngine::ReleaseUnlocked()
{
    // 调用方必须先通过 StopPipeline 停止系统管线。
    pipelineRunning_.store(false);
    if (inputNode_ != nullptr) {
        OH_AudioSuiteEngine_DestroyNode(inputNode_);
        inputNode_ = nullptr;
    }
    if (eqNode_ != nullptr) {
        OH_AudioSuiteEngine_DestroyNode(eqNode_);
        eqNode_ = nullptr;
    }
    if (outputNode_ != nullptr) {
        OH_AudioSuiteEngine_DestroyNode(outputNode_);
        outputNode_ = nullptr;
    }
    if (pipeline_ != nullptr) {
        OH_AudioSuiteEngine_DestroyPipeline(pipeline_);
        pipeline_ = nullptr;
    }
    if (engine_ != nullptr) {
        OH_AudioSuiteEngine_Destroy(engine_);
        engine_ = nullptr;
    }
    initialized_ = false;
    {
        std::lock_guard<std::mutex> pcmLock(pcmMutex_);
        inputFinished_ = true;
        pcmBuffer_.clear();
        pcmReadOffset_ = 0;
        pcmCondition_.notify_all();
    }
}
