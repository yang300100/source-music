#ifndef SOURCE_MUSIC_NATIVE_EQ_PLAYER_H
#define SOURCE_MUSIC_NATIVE_EQ_PLAYER_H

#include <atomic>
#include <cstdint>
#include <mutex>
#include <string>
#include <thread>

#include <ohaudio/native_audiorenderer.h>
#include <ohaudio/native_audiostreambuilder.h>

enum class NativePlayerState : int32_t {
    IDLE = 0,
    LOADING = 1,
    PLAYING = 2,
    PAUSED = 3,
    COMPLETED = 4,
    ERROR = 5,
};

/** 使用 AVSource/AVDemuxer/AudioCodec 解码，并经 OHAudioSuite 输出的原生播放器。 */
class NativeEqPlayer final {
public:
    static NativeEqPlayer &GetInstance();
    ~NativeEqPlayer();

    bool Start(const std::string &url, int64_t positionMs = 0, bool autoPlay = true);
    void Stop();
    bool Pause();
    bool Resume();
    bool Seek(int64_t positionMs);

    NativePlayerState GetState() const;
    int64_t GetPositionMs() const;
    int64_t GetDurationMs() const;
    std::string GetLastError() const;

private:
    NativeEqPlayer() = default;
    NativeEqPlayer(const NativeEqPlayer &) = delete;
    NativeEqPlayer &operator=(const NativeEqPlayer &) = delete;

    void DecodeLoop(uint64_t generation);
    bool CreateRenderer();
    void ReleaseRenderer();
    void SetError(const std::string &message);
    static OH_AudioData_Callback_Result OnWriteData(
        OH_AudioRenderer *renderer, void *userData, void *audioData, int32_t audioDataSize);

    mutable std::mutex mutex_;
    std::thread decodeThread_;
    std::atomic<bool> stopRequested_{false};
    std::atomic<uint64_t> generation_{0};
    std::atomic<NativePlayerState> state_{NativePlayerState::IDLE};
    std::atomic<int64_t> durationMs_{0};
    std::atomic<int64_t> startPositionMs_{0};
    std::atomic<int32_t> renderErrorCode_{0};
    std::atomic<bool> renderFinished_{false};
    std::string url_;
    std::string lastError_;
    bool autoPlay_ = true;
    OH_AudioStreamBuilder *rendererBuilder_ = nullptr;
    OH_AudioRenderer *renderer_ = nullptr;
};

#endif
