#include "native_eq_player.h"

#include <algorithm>
#include <chrono>
#include <cstring>
#include <vector>

#include <multimedia/player_framework/native_avbuffer.h>
#include <multimedia/player_framework/native_avcodec_audiocodec.h>
#include <multimedia/player_framework/native_avcodec_base.h>
#include <multimedia/player_framework/native_avdemuxer.h>
#include <multimedia/player_framework/native_averrors.h>
#include <multimedia/player_framework/native_avformat.h>
#include <multimedia/player_framework/native_avsource.h>

#include "audio_eq_engine.h"

namespace {
constexpr int32_t OUTPUT_SAMPLE_RATE = 48000;
constexpr int32_t OUTPUT_CHANNEL_COUNT = 2;
constexpr int32_t BYTES_PER_SAMPLE = 2;
constexpr int32_t CALLBACK_DURATION_MS = 20;
constexpr int64_t CODEC_TIMEOUT_US = 20000;

bool IsAudioSuccess(OH_AudioStream_Result result)
{
    return result == AUDIOSTREAM_SUCCESS;
}
}

NativeEqPlayer &NativeEqPlayer::GetInstance()
{
    static NativeEqPlayer instance;
    return instance;
}

NativeEqPlayer::~NativeEqPlayer()
{
    Stop();
}

bool NativeEqPlayer::Start(const std::string &url, int64_t positionMs, bool autoPlay)
{
    if (url.empty()) {
        SetError("播放地址为空");
        return false;
    }
    Stop();
    {
        std::lock_guard<std::mutex> lock(mutex_);
        url_ = url;
        lastError_.clear();
        autoPlay_ = autoPlay;
    }
    startPositionMs_.store(std::max<int64_t>(0, positionMs));
    durationMs_.store(0);
    renderErrorCode_.store(0);
    renderFinished_.store(false);
    stopRequested_.store(false);
    state_.store(NativePlayerState::LOADING);
    const uint64_t currentGeneration = generation_.fetch_add(1) + 1;
    decodeThread_ = std::thread(&NativeEqPlayer::DecodeLoop, this, currentGeneration);
    return true;
}

void NativeEqPlayer::Stop()
{
    stopRequested_.store(true);
    generation_.fetch_add(1);
    AudioEqEngine::GetInstance().StopPipeline();
    if (decodeThread_.joinable() && decodeThread_.get_id() != std::this_thread::get_id()) {
        decodeThread_.join();
    }
    ReleaseRenderer();
    AudioEqEngine::GetInstance().ResetPcm();
    state_.store(NativePlayerState::IDLE);
}

bool NativeEqPlayer::Pause()
{
    std::lock_guard<std::mutex> lock(mutex_);
    if (renderer_ == nullptr || state_.load() != NativePlayerState::PLAYING) {
        return false;
    }
    if (!IsAudioSuccess(OH_AudioRenderer_Pause(renderer_))) {
        return false;
    }
    state_.store(NativePlayerState::PAUSED);
    return true;
}

bool NativeEqPlayer::Resume()
{
    std::lock_guard<std::mutex> lock(mutex_);
    if (renderer_ == nullptr || state_.load() != NativePlayerState::PAUSED) {
        return false;
    }
    if (!IsAudioSuccess(OH_AudioRenderer_Start(renderer_))) {
        return false;
    }
    state_.store(NativePlayerState::PLAYING);
    return true;
}

bool NativeEqPlayer::Seek(int64_t positionMs)
{
    std::string currentUrl;
    bool shouldAutoPlay = true;
    {
        std::lock_guard<std::mutex> lock(mutex_);
        currentUrl = url_;
        shouldAutoPlay = state_.load() != NativePlayerState::PAUSED;
    }
    return !currentUrl.empty() && Start(currentUrl, positionMs, shouldAutoPlay);
}

NativePlayerState NativeEqPlayer::GetState() const
{
    return state_.load();
}

int64_t NativeEqPlayer::GetPositionMs() const
{
    std::lock_guard<std::mutex> lock(mutex_);
    int64_t frames = 0;
    if (renderer_ != nullptr && IsAudioSuccess(OH_AudioRenderer_GetFramesWritten(renderer_, &frames))) {
        const int64_t position = startPositionMs_.load() + frames * 1000 / OUTPUT_SAMPLE_RATE;
        const int64_t duration = durationMs_.load();
        return duration > 0 ? std::min(position, duration) : position;
    }
    return startPositionMs_.load();
}

int64_t NativeEqPlayer::GetDurationMs() const
{
    return durationMs_.load();
}

std::string NativeEqPlayer::GetLastError() const
{
    std::lock_guard<std::mutex> lock(mutex_);
    if (lastError_.empty() && renderErrorCode_.load() != 0) {
        return "均衡器渲染失败，系统错误码=" + std::to_string(renderErrorCode_.load());
    }
    return lastError_;
}

void NativeEqPlayer::SetError(const std::string &message)
{
    {
        std::lock_guard<std::mutex> lock(mutex_);
        lastError_ = message;
    }
    state_.store(NativePlayerState::ERROR);
    AudioEqEngine::GetInstance().MarkInputFinished();
}

bool NativeEqPlayer::CreateRenderer()
{
    std::lock_guard<std::mutex> lock(mutex_);
    if (!IsAudioSuccess(OH_AudioStreamBuilder_Create(&rendererBuilder_, AUDIOSTREAM_TYPE_RENDERER)) ||
        rendererBuilder_ == nullptr) {
        return false;
    }
    const int32_t frameSize = CALLBACK_DURATION_MS * OUTPUT_SAMPLE_RATE * OUTPUT_CHANNEL_COUNT *
        BYTES_PER_SAMPLE / 1000;
    bool success = true;
    success = success && IsAudioSuccess(OH_AudioStreamBuilder_SetSamplingRate(rendererBuilder_, OUTPUT_SAMPLE_RATE));
    success = success && IsAudioSuccess(OH_AudioStreamBuilder_SetChannelCount(rendererBuilder_, OUTPUT_CHANNEL_COUNT));
    success = success && IsAudioSuccess(OH_AudioStreamBuilder_SetChannelLayout(rendererBuilder_, CH_LAYOUT_STEREO));
    success = success && IsAudioSuccess(OH_AudioStreamBuilder_SetSampleFormat(
        rendererBuilder_, AUDIOSTREAM_SAMPLE_S16LE));
    success = success && IsAudioSuccess(OH_AudioStreamBuilder_SetEncodingType(
        rendererBuilder_, AUDIOSTREAM_ENCODING_TYPE_RAW));
    success = success && IsAudioSuccess(OH_AudioStreamBuilder_SetRendererInfo(
        rendererBuilder_, AUDIOSTREAM_USAGE_MUSIC));
    success = success && IsAudioSuccess(OH_AudioStreamBuilder_SetFrameSizeInCallback(rendererBuilder_, frameSize));
    success = success && IsAudioSuccess(OH_AudioStreamBuilder_SetRendererWriteDataCallback(
        rendererBuilder_, OnWriteData, this));
    success = success && IsAudioSuccess(OH_AudioStreamBuilder_GenerateRenderer(rendererBuilder_, &renderer_));
    return success && renderer_ != nullptr;
}

void NativeEqPlayer::ReleaseRenderer()
{
    std::lock_guard<std::mutex> lock(mutex_);
    if (renderer_ != nullptr) {
        OH_AudioRenderer_Stop(renderer_);
        OH_AudioRenderer_Release(renderer_);
        renderer_ = nullptr;
    }
    if (rendererBuilder_ != nullptr) {
        OH_AudioStreamBuilder_Destroy(rendererBuilder_);
        rendererBuilder_ = nullptr;
    }
}

OH_AudioData_Callback_Result NativeEqPlayer::OnWriteData(
    OH_AudioRenderer *renderer, void *userData, void *audioData, int32_t audioDataSize)
{
    if (renderer == nullptr || userData == nullptr || audioData == nullptr || audioDataSize <= 0) {
        return AUDIO_DATA_CALLBACK_RESULT_INVALID;
    }
    auto *player = static_cast<NativeEqPlayer *>(userData);
    if (player->stopRequested_.load() || player->renderFinished_.load()) {
        std::memset(audioData, 0, static_cast<size_t>(audioDataSize));
        return AUDIO_DATA_CALLBACK_RESULT_VALID;
    }
    OH_AudioSuitePipeline *pipeline = AudioEqEngine::GetInstance().GetPipeline();
    if (pipeline == nullptr) {
        return AUDIO_DATA_CALLBACK_RESULT_INVALID;
    }
    int32_t responseSize = 0;
    bool finished = false;
    const OH_AudioSuite_Result result = OH_AudioSuiteEngine_RenderFrame(
        pipeline, audioData, audioDataSize, &responseSize, &finished);
    if (result != AUDIOSUITE_SUCCESS) {
        // 音频回调线程不能等待播放器互斥锁，否则停止 Renderer 时可能互相等待。
        if (!player->stopRequested_.load()) {
            player->renderErrorCode_.store(static_cast<int32_t>(result));
            player->state_.store(NativePlayerState::ERROR);
        }
        return AUDIO_DATA_CALLBACK_RESULT_INVALID;
    }
    if (responseSize < audioDataSize) {
        std::memset(static_cast<uint8_t *>(audioData) + std::max(0, responseSize), 0,
                    static_cast<size_t>(audioDataSize - std::max(0, responseSize)));
    }
    if (finished) {
        // 系统可能在完成后再次请求数据；先标记完成，后续回调只补静音，不能再次调用 RenderFrame。
        player->renderFinished_.store(true);
        player->state_.store(NativePlayerState::COMPLETED);
    }
    return AUDIO_DATA_CALLBACK_RESULT_VALID;
}

void NativeEqPlayer::DecodeLoop(uint64_t currentGeneration)
{
    std::string url;
    bool shouldAutoPlay = true;
    {
        std::lock_guard<std::mutex> lock(mutex_);
        url = url_;
        shouldAutoPlay = autoPlay_;
    }

    std::vector<char> uri(url.begin(), url.end());
    uri.push_back('\0');
    OH_AVSource *source = OH_AVSource_CreateWithURI(uri.data());
    if (source == nullptr) {
        SetError("无法打开音频地址");
        return;
    }
    OH_AVDemuxer *demuxer = OH_AVDemuxer_CreateWithSource(source);
    if (demuxer == nullptr) {
        OH_AVSource_Destroy(source);
        SetError("无法创建音频分离器");
        return;
    }

    OH_AVFormat *sourceFormat = OH_AVSource_GetSourceFormat(source);
    int32_t trackCount = 0;
    int64_t durationUs = 0;
    if (sourceFormat != nullptr) {
        OH_AVFormat_GetIntValue(sourceFormat, OH_MD_KEY_TRACK_COUNT, &trackCount);
        OH_AVFormat_GetLongValue(sourceFormat, OH_MD_KEY_DURATION, &durationUs);
        OH_AVFormat_Destroy(sourceFormat);
    }
    durationMs_.store(std::max<int64_t>(0, durationUs / 1000));

    int32_t audioTrackId = -1;
    OH_AVFormat *trackFormat = nullptr;
    for (int32_t index = 0; index < trackCount; ++index) {
        OH_AVFormat *candidate = OH_AVSource_GetTrackFormat(source, index);
        int32_t trackType = -1;
        if (candidate != nullptr) {
            OH_AVFormat_GetIntValue(candidate, OH_MD_KEY_TRACK_TYPE, &trackType);
        }
        if (candidate != nullptr && trackType == MEDIA_TYPE_AUD) {
            audioTrackId = index;
            trackFormat = candidate;
            break;
        }
        if (candidate != nullptr) {
            OH_AVFormat_Destroy(candidate);
        }
    }
    if (audioTrackId < 0 || trackFormat == nullptr ||
        OH_AVDemuxer_SelectTrackByID(demuxer, audioTrackId) != AV_ERR_OK) {
        if (trackFormat != nullptr) OH_AVFormat_Destroy(trackFormat);
        OH_AVDemuxer_Destroy(demuxer);
        OH_AVSource_Destroy(source);
        SetError("音频中没有可解码的声音轨道");
        return;
    }

    const char *mime = nullptr;
    int32_t sampleRate = OUTPUT_SAMPLE_RATE;
    int32_t channelCount = OUTPUT_CHANNEL_COUNT;
    int64_t channelLayout = CH_LAYOUT_STEREO;
    OH_AVFormat_GetStringValue(trackFormat, OH_MD_KEY_CODEC_MIME, &mime);
    OH_AVFormat_GetIntValue(trackFormat, OH_MD_KEY_AUD_SAMPLE_RATE, &sampleRate);
    OH_AVFormat_GetIntValue(trackFormat, OH_MD_KEY_AUD_CHANNEL_COUNT, &channelCount);
    if (!OH_AVFormat_GetLongValue(trackFormat, OH_MD_KEY_CHANNEL_LAYOUT, &channelLayout)) {
        channelLayout = channelCount == 1 ? CH_LAYOUT_MONO : CH_LAYOUT_STEREO;
    }
    if (mime == nullptr || !AudioEqEngine::GetInstance().PrepareForPlayback(
            sampleRate, channelCount, channelLayout)) {
        OH_AVFormat_Destroy(trackFormat);
        OH_AVDemuxer_Destroy(demuxer);
        OH_AVSource_Destroy(source);
        SetError("均衡器管线初始化失败");
        return;
    }

    OH_AVCodec *decoder = OH_AudioCodec_CreateByMime(mime, false);
    OH_AVFormat_SetIntValue(trackFormat, OH_MD_KEY_AUDIO_SAMPLE_FORMAT, SAMPLE_S16LE);
    OH_AVFormat_SetIntValue(trackFormat, OH_MD_KEY_ENABLE_SYNC_MODE, 1);
    const bool decoderReady = decoder != nullptr &&
        OH_AudioCodec_Configure(decoder, trackFormat) == AV_ERR_OK &&
        OH_AudioCodec_Prepare(decoder) == AV_ERR_OK &&
        OH_AudioCodec_Start(decoder) == AV_ERR_OK;
    OH_AVFormat_Destroy(trackFormat);
    if (!decoderReady) {
        if (decoder != nullptr) OH_AudioCodec_Destroy(decoder);
        OH_AVDemuxer_Destroy(demuxer);
        OH_AVSource_Destroy(source);
        SetError("音频解码器初始化失败");
        return;
    }

    if (startPositionMs_.load() > 0) {
        OH_AVDemuxer_SeekToTime(demuxer, startPositionMs_.load(), SEEK_MODE_CLOSEST_SYNC);
    }
    AudioEqEngine::GetInstance().ResetPcm();
    if (!AudioEqEngine::GetInstance().StartPipeline() || !CreateRenderer()) {
        OH_AudioCodec_Stop(decoder);
        OH_AudioCodec_Destroy(decoder);
        OH_AVDemuxer_Destroy(demuxer);
        OH_AVSource_Destroy(source);
        SetError("音频输出初始化失败");
        return;
    }
    bool rendererStarted = false;
    {
        std::lock_guard<std::mutex> lock(mutex_);
        rendererStarted = renderer_ != nullptr && IsAudioSuccess(OH_AudioRenderer_Start(renderer_));
        if (rendererStarted && !shouldAutoPlay) {
            OH_AudioRenderer_Pause(renderer_);
            state_.store(NativePlayerState::PAUSED);
        } else if (rendererStarted) {
            state_.store(NativePlayerState::PLAYING);
        }
    }
    if (!rendererStarted) {
        SetError("音频输出启动失败");
    }

    bool inputEnded = false;
    bool outputEnded = false;
    while (!stopRequested_.load() && currentGeneration == generation_.load() && !outputEnded &&
           state_.load() != NativePlayerState::ERROR) {
        if (!inputEnded) {
            uint32_t inputIndex = 0;
            const OH_AVErrCode inputResult = OH_AudioCodec_QueryInputBuffer(decoder, &inputIndex, CODEC_TIMEOUT_US);
            if (inputResult == AV_ERR_OK) {
                OH_AVBuffer *inputBuffer = OH_AudioCodec_GetInputBuffer(decoder, inputIndex);
                if (inputBuffer == nullptr ||
                    OH_AVDemuxer_ReadSampleBuffer(demuxer, audioTrackId, inputBuffer) != AV_ERR_OK) {
                    SetError("读取音频数据失败");
                    break;
                }
                OH_AVCodecBufferAttr inputAttr{};
                OH_AVBuffer_GetBufferAttr(inputBuffer, &inputAttr);
                inputEnded = (inputAttr.flags & AVCODEC_BUFFER_FLAGS_EOS) != 0;
                if (OH_AudioCodec_PushInputBuffer(decoder, inputIndex) != AV_ERR_OK) {
                    SetError("提交音频解码数据失败");
                    break;
                }
            } else if (inputResult != AV_ERR_TRY_AGAIN_LATER) {
                SetError("获取解码输入缓冲区失败");
                break;
            }
        }

        while (!stopRequested_.load()) {
            uint32_t outputIndex = 0;
            const OH_AVErrCode outputResult = OH_AudioCodec_QueryOutputBuffer(
                decoder, &outputIndex, inputEnded ? CODEC_TIMEOUT_US : 0);
            if (outputResult == AV_ERR_STREAM_CHANGED) {
                OH_AVFormat *description = OH_AudioCodec_GetOutputDescription(decoder);
                if (description != nullptr) OH_AVFormat_Destroy(description);
                continue;
            }
            if (outputResult == AV_ERR_TRY_AGAIN_LATER) {
                break;
            }
            if (outputResult != AV_ERR_OK) {
                SetError("获取解码输出缓冲区失败");
                outputEnded = true;
                break;
            }
            OH_AVBuffer *outputBuffer = OH_AudioCodec_GetOutputBuffer(decoder, outputIndex);
            OH_AVCodecBufferAttr outputAttr{};
            if (outputBuffer == nullptr || OH_AVBuffer_GetBufferAttr(outputBuffer, &outputAttr) != AV_ERR_OK) {
                SetError("读取解码结果失败");
                outputEnded = true;
            } else {
                uint8_t *address = OH_AVBuffer_GetAddr(outputBuffer);
                if (address != nullptr && outputAttr.size > 0 &&
                    !AudioEqEngine::GetInstance().PushPcm(
                        address + outputAttr.offset, static_cast<size_t>(outputAttr.size))) {
                    outputEnded = true;
                }
                outputEnded = outputEnded || ((outputAttr.flags & AVCODEC_BUFFER_FLAGS_EOS) != 0);
            }
            OH_AudioCodec_FreeOutputBuffer(decoder, outputIndex);
            if (outputEnded) break;
        }
    }

    AudioEqEngine::GetInstance().MarkInputFinished();
    OH_AudioCodec_Stop(decoder);
    OH_AudioCodec_Destroy(decoder);
    OH_AVDemuxer_Destroy(demuxer);
    OH_AVSource_Destroy(source);
}
