#ifndef SOURCE_MUSIC_AUDIO_EQ_ENGINE_H
#define SOURCE_MUSIC_AUDIO_EQ_ENGINE_H

#include <array>
#include <atomic>
#include <condition_variable>
#include <cstdint>
#include <mutex>
#include <vector>

#include <ohaudiosuite/native_audio_suite_base.h>
#include <ohaudiosuite/native_audio_suite_engine.h>

/**
 * 十段均衡器原生管线。
 *
 * 管线固定使用 OHAudioSuite 均衡器要求的 48kHz、双声道、S16LE PCM。
 * 当前类只负责效果节点生命周期；解码与渲染播放链会复用此实例。
 */
class AudioEqEngine final {
public:
    static AudioEqEngine &GetInstance();

    bool IsSupported() const;
    bool Initialize();
    bool PrepareForPlayback(int32_t sampleRate, int32_t channelCount, int64_t channelLayout);
    void Release();

    bool SetEnabled(bool enabled);
    bool SetGains(const std::array<int32_t, EQUALIZER_BAND_NUM> &gains);
    bool SetPreset(const char *presetName);
    std::array<int32_t, EQUALIZER_BAND_NUM> GetGains() const;
    bool IsEnabled() const;
    bool IsInitialized() const;

    OH_AudioSuitePipeline *GetPipeline() const;
    bool StartPipeline();
    void StopPipeline();
    bool PushPcm(const uint8_t *data, size_t size);
    void ResetPcm();
    void MarkInputFinished();

private:
    AudioEqEngine() = default;
    ~AudioEqEngine();
    AudioEqEngine(const AudioEqEngine &) = delete;
    AudioEqEngine &operator=(const AudioEqEngine &) = delete;

    static int32_t RequestInputData(OH_AudioNode *audioNode, void *userData, void *audioData,
                                    int32_t audioDataSize, bool *finished);
    bool CreateNodes();
    bool InitializeUnlocked();
    void ReleaseUnlocked();

    // 控制锁只保护管线、节点与参数；绝不能让 PCM 回调等待它。
    mutable std::mutex controlMutex_;
    // PCM 锁只保护解码缓冲，避免系统设置 EQ 参数时与实时回调形成环形等待。
    mutable std::mutex pcmMutex_;
    OH_AudioSuiteEngine *engine_ = nullptr;
    OH_AudioSuitePipeline *pipeline_ = nullptr;
    OH_AudioNode *inputNode_ = nullptr;
    OH_AudioNode *eqNode_ = nullptr;
    OH_AudioNode *outputNode_ = nullptr;
    std::array<int32_t, EQUALIZER_BAND_NUM> gains_{};
    std::vector<uint8_t> pcmBuffer_;
    size_t pcmReadOffset_ = 0;
    std::condition_variable pcmCondition_;
    int32_t inputSampleRate_ = 48000;
    int32_t inputChannelCount_ = 2;
    int64_t inputChannelLayout_ = CH_LAYOUT_STEREO;
    bool inputFinished_ = false;
    std::atomic<bool> pipelineRunning_{false};
    bool enabled_ = false;
    bool initialized_ = false;
};

#endif
