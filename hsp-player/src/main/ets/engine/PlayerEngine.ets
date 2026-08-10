import { media } from '@kit.MediaKit'
import { fileIo } from '@kit.CoreFileKit'
import {
  MusicItem,
  MusicQuality,
  PlayerStatus,
  PlayMode,
  SourceType,
  LyricLine,
  LogUtils,
  StorageUtils,
  PlayCacheUtils
} from 'common'
import { SourceManager } from 'hsp_source'
import { PlayQueue } from '../queue/PlayQueue'
import { MediaSession } from './MediaSession'
import audioEqBridgeUntyped from 'libaudio_eq_bridge.so'

interface AudioEqBridgeApi {
  isSupported(): boolean
  initialize(): boolean
  release(): void
  setEnabled(enabled: boolean): boolean
  setGains(gains: number[]): boolean
  getGains(): number[]
  setPreset(presetName: string): boolean
  playerStart(url: string, positionMs: number, autoPlay: boolean): boolean
  playerStop(): void
  playerPause(): boolean
  playerResume(): boolean
  playerSeek(positionMs: number): boolean
  playerGetState(): number
  playerGetPosition(): number
  playerGetDuration(): number
  playerGetLastError(): string
}

const audioEqBridgeNative: AudioEqBridgeApi = audioEqBridgeUntyped as AudioEqBridgeApi

const NATIVE_STATE_IDLE = 0
const NATIVE_STATE_LOADING = 1
const NATIVE_STATE_PLAYING = 2
const NATIVE_STATE_PAUSED = 3
const NATIVE_STATE_COMPLETED = 4
const NATIVE_STATE_ERROR = 5

/**
 * 播放器引擎核心
 *
 * 封装 AVPlayer，管理完整的播放生命周期：
 * 空闲 → 获取URL → 缓冲中 → 播放中 ⇄ 暂停
 * 播放出错 → 自动换源重试
 *
 * 集成媒体会话（AVSession）：通知栏/锁屏/播控中心展示与遥控
 */
export class PlayerEngine {
  status: PlayerStatus = PlayerStatus.IDLE
  currentSong: MusicItem | null = null
  currentProgress: number = 0
  duration: number = 0
  queue: PlayQueue = new PlayQueue()
  lyrics: LyricLine[] = []
  mediaSession: MediaSession = new MediaSession()

  private avPlayer: media.AVPlayer | null = null
  private progressTimer: number | null = null
  private currentAvState: string = 'idle'
  private timeUpdateCount: number = 0
  private playGeneration: number = 0
  /** 播放/换源状态文本（对齐参考 onToggleSource：UI 可显示"正在换源解析..."） */
  statusText: string = ''
  /** 当前歌曲的失败重试次数（最多2次，参考社区音源） */
  private retryNum: number = 0
  /** 错误后跳下一首的定时器（防止重复触发） */
  private errorSkipTimer: number | null = null
  /** 加载超时定时器（25秒，参考社区音源） */
  private loadingTimer: number | null = null
  /** 是否已预加载下一首URL */
  private preloadedNext: boolean = false
  /** 定时关闭倒计时定时器 */
  private sleepTimer: number | null = null
  /** 定时关闭剩余秒数（0 = 未启用） */
  sleepRemainSeconds: number = 0
  /** 播放失败提示回调（UI 层注册，用于 Toast） */
  onPlayError: (message: string) => void = (message: string) => {}
  /** 保存播放进度（开启时每 10 秒持久化当前位置） */
  savePlayProgress: boolean = false
  /** 自动清理已播放列表（开启时播放完成自动移除该曲） */
  autoCleanPlayed: boolean = false
  /** 默认音质（128k / 320k / flac） */
  defaultQuality: MusicQuality = MusicQuality.HIGH
  /** 真正作用于 PCM 的十段均衡器设置 */
  eqSupported: boolean = false
  eqEnabled: boolean = false
  eqPreset: string = 'default'
  eqGains: number[] = [0, 0, 0, 0, 0, 0, 0, 0, 0, 0]
  private usingNativeEq: boolean = false
  private nativeCompletionHandled: boolean = false
  private nativeErrorHandled: boolean = false
  private forceAvFallbackOnce: boolean = false
  private activePlayUrl: string = ''
  private pendingStartPositionMs: number = 0
  private pendingAutoPlay: boolean = true
  private lastProgressSave: number = 0
  private static instance: PlayerEngine | null = null

  static getInstance(): PlayerEngine {
    if (!PlayerEngine.instance) {
      PlayerEngine.instance = new PlayerEngine()
    }
    return PlayerEngine.instance
  }

  /** 初始化 AVPlayer 和媒体会话 */
  async init(context?: Context): Promise<void> {
    try {
      this.avPlayer = await media.createAVPlayer()
      this.setupCallbacks()
      LogUtils.info('AVPlayer 初始化完成')
      await this.loadEqSettings()

      // 创建媒体会话（需要 Context）
      if (context) {
        await this.mediaSession.createSession(context)
        this.bindMediaSessionCommands()
      }
    } catch (err) {
      LogUtils.error('AVPlayer 初始化失败', JSON.stringify(err))
    }
  }

  /** 绑定媒体会话播控命令到播放器 */
  private bindMediaSessionCommands(): void {
    this.mediaSession.onPlayCommand = () => {
      this.togglePlay()
    }
    this.mediaSession.onPauseCommand = () => {
      this.togglePlay()
    }
    this.mediaSession.onTogglePlayCommand = () => {
      this.togglePlay()
    }
    this.mediaSession.onNextCommand = () => {
      this.next()
    }
    this.mediaSession.onPreviousCommand = () => {
      this.previous()
    }
    this.mediaSession.onSeekCommand = (time: number) => {
      this.seekTo(time)
    }
  }

  /** 读取并应用持久化的均衡器设置。 */
  private async loadEqSettings(): Promise<void> {
    try {
      this.eqSupported = audioEqBridgeNative.isSupported()
      this.eqEnabled = (await StorageUtils.getString('eq_enabled', 'false')) === 'true'
      this.eqPreset = await StorageUtils.getString('eq_preset', 'default')
      const savedGains = await StorageUtils.getObject<number[]>('eq_gains', this.eqGains)
      if (savedGains.length === 10) {
        this.eqGains = savedGains.map((value: number) => Math.round(value))
      }
      if (this.eqSupported && this.eqEnabled) {
        const ready = audioEqBridgeNative.initialize()
        if (!ready || !audioEqBridgeNative.setGains(this.eqGains) ||
          !audioEqBridgeNative.setEnabled(true)) {
          this.eqEnabled = false
          await StorageUtils.putString('eq_enabled', 'false')
          LogUtils.warn('[EQ] 已保存的均衡器设置初始化失败，自动关闭')
        }
      }
      LogUtils.info(`[EQ] 支持=${this.eqSupported}, 启用=${this.eqEnabled}, 预设=${this.eqPreset}`)
    } catch (err) {
      this.eqSupported = false
      this.eqEnabled = false
      LogUtils.warn(`[EQ] 设置加载失败: ${JSON.stringify(err)}`)
    }
  }

  /** 开关 EQ；从普通播放器开启时会从当前位置重启到原生效果链。 */
  async setEqEnabled(enabled: boolean): Promise<boolean> {
    if (enabled && !this.eqSupported) return false
    try {
      if (enabled) {
        if (!audioEqBridgeNative.initialize() || !audioEqBridgeNative.setGains(this.eqGains) ||
          !audioEqBridgeNative.setEnabled(true)) return false
      } else if (audioEqBridgeNative.initialize()) {
        audioEqBridgeNative.setEnabled(false)
      }
      const needsSwitch = enabled && !this.usingNativeEq && this.currentSong !== null &&
        (this.status === PlayerStatus.PLAYING || this.status === PlayerStatus.PAUSED)
      this.eqEnabled = enabled
      await StorageUtils.putString('eq_enabled', enabled ? 'true' : 'false')
      if (needsSwitch && this.currentSong) {
        this.pendingStartPositionMs = this.currentProgress
        this.pendingAutoPlay = this.status === PlayerStatus.PLAYING
        await this.play(this.currentSong, true)
      }
      return true
    } catch (err) {
      LogUtils.warn(`[EQ] 开关失败: ${JSON.stringify(err)}`)
      return false
    }
  }

  /** 应用系统预设，并同步实际十段数值。 */
  async setEqPreset(preset: string): Promise<boolean> {
    try {
      if (!audioEqBridgeNative.initialize() || !audioEqBridgeNative.setPreset(preset)) return false
      this.eqPreset = preset
      this.eqGains = audioEqBridgeNative.getGains()
      await StorageUtils.putString('eq_preset', preset)
      await StorageUtils.putObject('eq_gains', this.eqGains)
      return true
    } catch (err) {
      LogUtils.warn(`[EQ] 预设应用失败: ${JSON.stringify(err)}`)
      return false
    }
  }

  /** 实时应用自定义十段增益，范围限制为 -12dB 到 +12dB。 */
  async setEqGains(gains: number[]): Promise<boolean> {
    if (gains.length !== 10) return false
    const normalized = gains.map((value: number) => Math.max(-12, Math.min(12, Math.round(value))))
    try {
      if (!audioEqBridgeNative.initialize() || !audioEqBridgeNative.setGains(normalized)) return false
      this.eqPreset = 'custom'
      this.eqGains = normalized
      await StorageUtils.putString('eq_preset', 'custom')
      await StorageUtils.putObject('eq_gains', normalized)
      return true
    } catch (err) {
      LogUtils.warn(`[EQ] 自定义增益应用失败: ${JSON.stringify(err)}`)
      return false
    }
  }

  /** 设置 AVPlayer 事件回调 */
  private setupCallbacks(): void {
    if (!this.avPlayer) return

    this.avPlayer.on('stateChange', (state: string) => {
      this.currentAvState = state
      const prevStatus = this.status
      LogUtils.info(`[AVPlayer] stateChange: ${state}, 之前status=${prevStatus}, playGen=${this.playGeneration}`)
      switch (state) {
        case 'idle':
          this.status = PlayerStatus.IDLE
          break
        case 'initialized':
          break
        case 'prepared':
          if (this.status === PlayerStatus.BUFFERING || this.status === PlayerStatus.LOADING) {
            LogUtils.info(`[AVPlayer] prepared时status=${this.status}，保持不变`)
          } else {
            LogUtils.info(`[AVPlayer] prepared时status=${this.status}(非BUFFERING)，保持不变`)
          }
          this.startProgressTimer()
          break
        case 'playing':
          this.status = PlayerStatus.PLAYING
          this.startProgressTimer()
          break
        case 'paused':
          this.status = PlayerStatus.PAUSED
          break
        case 'completed':
          this.handleCompletion()
          break
        case 'error':
          this.status = PlayerStatus.ERROR
          LogUtils.error('AVPlayer 播放出错')
          // 用户手动暂停或空闲时出现的 stateChange error 不触发自动重试播放
          if (prevStatus === PlayerStatus.PAUSED || prevStatus === PlayerStatus.IDLE) {
            LogUtils.info(`[AVPlayer] stateChange error 但用户已暂停/空闲(prevStatus=${prevStatus})，跳过自动重试`)
          } else {
            this.handleAvError()
          }
          break
      }
      LogUtils.info(`[AVPlayer] stateChange后: status=${this.status}`)
    })

    this.avPlayer.on('durationUpdate', (duration: number) => {
      LogUtils.info(`[播放] 时长更新: ${duration}`)
      this.duration = duration
    })

    this.avPlayer.on('timeUpdate', (time: number) => {
      this.currentProgress = time
      this.timeUpdateCount++
      // 前 10 次 + 之后每 10 次打一次日志
      if (this.timeUpdateCount <= 10 || this.timeUpdateCount % 10 === 0) {
        LogUtils.info(`[进度] timeUpdate #${this.timeUpdateCount}: ${time}ms (${(time / 1000).toFixed(1)}s), status=${this.status}, avState=${this.currentAvState}`)
      }
      // 预加载下一首：距结尾<10秒且未预加载过（参考社区音源 preloadNextMusic）
      if (!this.preloadedNext && this.duration > 0 && this.duration - time < 10000) {
        this.preloadedNext = true
        this.preloadNextSong()
      }
    })

    this.avPlayer.on('error', (err: Error) => {
      LogUtils.error('AVPlayer 错误', JSON.stringify(err))
      const prevStatus = this.status
      this.status = PlayerStatus.ERROR
      this.stopLoadingTimer()
      // 用户手动暂停或空闲时出错：不需要自动重试播放，静默忽略即可
      if (prevStatus === PlayerStatus.PAUSED || prevStatus === PlayerStatus.IDLE) {
        LogUtils.info(`[播放] AVPlayer 错误但用户已暂停/空闲(status=${prevStatus})，跳过自动重试`)
        return
      }
      // 播放器解码失败：刷新URL重试（最多2次），仍失败则5秒后跳下一首（参考社区音源）
      if (this.currentSong && this.retryNum < 2 && this.errorSkipTimer === null) {
        this.retryNum++
        LogUtils.info(`[播放] 解码错误，刷新URL重试 ${this.retryNum}/2: ${this.currentSong.name} - ${this.currentSong.singer}`)
        const song = this.currentSong
        SourceManager.getInstance().clearPlayUrlCache(song.songmid, song.source)
        this.play(song, true)
      } else {
        LogUtils.info('[播放] 重试次数已用完或已在跳转中，5秒后跳下一首')
        this.scheduleErrorSkip()
      }
    })
  }

  /** 播放指定歌曲（isRefresh=true 时跳过缓存，用于失败重试） */
  async play(song: MusicItem, isRefresh: boolean = false): Promise<void> {
    if (!this.avPlayer) {
      LogUtils.error('AVPlayer 未初始化')
      return
    }

    if (!isRefresh) {
      // 新歌开始播放：重置重试计数和预加载标志
      this.retryNum = 0
      this.preloadedNext = false
      this.pendingStartPositionMs = 0
      this.pendingAutoPlay = true
    }
    // 取消挂起的跳下一首定时器
    if (this.errorSkipTimer !== null) {
      clearTimeout(this.errorSkipTimer)
      this.errorSkipTimer = null
    }

    this.playGeneration++
    const myGen = this.playGeneration

    // 立即暂停旧歌（新歌 URL 解析期间旧歌不再继续响；不判断avState，任何状态都尝试）
    if (!isRefresh) {
      if (this.usingNativeEq) {
        audioEqBridgeNative.playerStop()
        this.usingNativeEq = false
      }
      try {
        await this.avPlayer.pause()
        LogUtils.info('[播放] 已暂停旧歌，等待新歌URL')
      } catch (pauseErr) {
        LogUtils.warn('[播放] 暂停旧歌异常(可能无旧歌在播)', JSON.stringify(pauseErr))
      }
    }

    this.status = PlayerStatus.LOADING
    this.currentSong = song
    this.lyrics = []
    this.currentProgress = 0
    this.timeUpdateCount = 0
    LogUtils.info(`[播放] 开始(gen=${myGen}, refresh=${isRefresh}): ${song.name} - ${song.singer} (source=${song.source}), imgUrl="${song.imgUrl ? song.imgUrl.substring(0, 60) : '(空)'}"`)

    // 加载超时定时器：25秒内未开始播放则刷新URL重试，二次超时跳下一首
    this.startLoadingTimer()

    try {
      const sourceMgr = SourceManager.getInstance()
      // 音质降级链（社区音源 逻辑）：高音质获取失败自动降级到低音质
      const qualities = this.buildQualityChain(this.defaultQuality)
      let musicInfo: MusicItem | null = null
      for (let qi = 0; qi < qualities.length; qi++) {
        if (myGen !== this.playGeneration) {
          LogUtils.info(`[播放] gen=${myGen} 音质降级中已过期，跳过`)
          return
        }
        LogUtils.info(`[播放] 请求播放 URL(songmid=${song.songmid}, 音质=${qualities[qi]}, ${qi + 1}/${qualities.length})`)
        musicInfo = await sourceMgr.getMusicInfoWithFallback(
          song.songmid, song.source, qualities[qi], song, isRefresh,
          (text: string) => {
            this.statusText = text
            LogUtils.info(`[播放] 换源状态: ${text}`)
          })
        if (musicInfo) break
      }
      if (myGen !== this.playGeneration) {
        LogUtils.info(`[播放] gen=${myGen} 已过期(当前=${this.playGeneration})，跳过`)
        return
      }
      if (!musicInfo) {
        // 对齐参考 getMusicPlayUrl(isRetryed)：整体失败后延迟重试一次
        // （服务临时不可用如 onrender 冷启动 30-60s，延迟后可能恢复）
        LogUtils.warn('[播放] 首次获取失败，3秒后整体重试一次')
        await new Promise<void>((resolve) => setTimeout(resolve, 3000))
        if (myGen !== this.playGeneration) {
          LogUtils.info(`[播放] gen=${myGen} 重试前已过期，跳过`)
          return
        }
        for (let qi = 0; qi < qualities.length; qi++) {
          if (myGen !== this.playGeneration) {
            LogUtils.info(`[播放] gen=${myGen} 重试音质降级中已过期，跳过`)
            return
          }
          LogUtils.info(`[播放] 重试请求播放 URL(songmid=${song.songmid}, 音质=${qualities[qi]}, ${qi + 1}/${qualities.length})`)
          musicInfo = await sourceMgr.getMusicInfoWithFallback(song.songmid, song.source, qualities[qi], song, isRefresh)
          if (musicInfo) break
        }
      }
      if (myGen !== this.playGeneration) {
        LogUtils.info(`[播放] gen=${myGen} 已过期(当前=${this.playGeneration})，跳过`)
        return
      }
      if (!musicInfo) {
        LogUtils.error('无法获取播放地址，3秒后跳下一首')
        this.status = PlayerStatus.ERROR
        this.resetAvPlayer()
        this.stopLoadingTimer()
        if (this.onPlayError) {
          this.onPlayError('未找到可播放的音频，自动切换下一首')
        }
        this.scheduleErrorSkip()
        return
      }
      LogUtils.info(`[播放] 获取到 URL 信息, types=${JSON.stringify(Object.keys(musicInfo.types))}`)

      const qualityKey = Object.keys(musicInfo.types)[0]
      const playUrl = musicInfo.types[qualityKey]?.url
      if (!playUrl) {
        LogUtils.error('无可用的播放 URL，3秒后跳下一首')
        this.status = PlayerStatus.ERROR
        this.resetAvPlayer()
        this.stopLoadingTimer()
        if (this.onPlayError) {
          this.onPlayError('未找到可播放的音频，自动切换下一首')
        }
        this.scheduleErrorSkip()
        return
      }
      LogUtils.info(`[播放] URL: ${playUrl.substring(0, 150)}`)
      this.activePlayUrl = playUrl

      const playInfoImgUrl = musicInfo.imgUrl ?? ''
      if (playInfoImgUrl && playInfoImgUrl.length > 0) {
        this.currentSong!.imgUrl = playInfoImgUrl
      }

      const playbackStarted = await this.startResolvedPlayback(playUrl, myGen)
      if (!playbackStarted) {
        this.status = PlayerStatus.ERROR
        this.stopLoadingTimer()
        if (this.onPlayError) this.onPlayError('播放器启动失败，自动切换下一首')
        this.scheduleErrorSkip()
        return
      }

      // 恢复上次播放进度（开启时且非刷新重试）
      if (this.savePlayProgress && !isRefresh) {
        this.restorePlayProgress(song, myGen)
      }

      this.fetchLyrics(song, myGen)

      // 后台缓存播放过的音频（不阻塞播放；已缓存则刷新时间）
      if (playUrl) {
        PlayCacheUtils.cacheSong(song, playUrl).catch(() => {})
      }

      this.mediaSession.updateMetadata(song)
      this.mediaSession.updatePlaybackState(PlayerStatus.PLAYING, 0, this.duration)
      this.mediaSession.activate()

      LogUtils.info(`开始播放: ${song.name} - ${song.singer}`)

      const lastSong: Record<string, string | number> = {
        'songmid': song.songmid,
        'source': String(song.source),
        'name': song.name,
        'singer': song.singer,
        'albumName': song.albumName,
        'interval': song.interval,
        'imgUrl': song.imgUrl
      }
      LogUtils.info(`[自动播放] 保存上次播放: ${song.name} - ${song.singer}, hasImg=${!!song.imgUrl}`)
      StorageUtils.putObject('last_played_song', lastSong)

      // 记录播放历史（最多 50 首，按 songmid+source 去重，最新在前）
      this.recordPlayHistory(song)
      // 持久化播放队列（重启后恢复）
      this.saveQueueState()
    } catch (err) {
      if (myGen !== this.playGeneration) {
        LogUtils.info(`[播放] gen=${myGen} 出错但已过期，忽略`)
        return
      }
      LogUtils.error('播放失败', JSON.stringify(err))
      this.stopLoadingTimer()
      this.status = PlayerStatus.ERROR
      this.resetAvPlayer()
      this.scheduleErrorSkip()
    }
  }

  /** 播放中途出错：清除 URL 缓存并标记主源失败（跳过原源），刷新重试一次，再失败跳下一首 */
  private handleAvError(): void {
    if (this.retryNum < 1 && this.currentSong) {
      this.retryNum++
      const song = this.currentSong
      LogUtils.info(`[播放] 播放出错(${this.retryNum})，清除 URL 缓存并标记主源失败，刷新重试`)
      SourceManager.getInstance().clearPlayUrlCache(song.songmid, song.source)
      SourceManager.getInstance().markPrimaryFailed(song.songmid, song.source)
      this.play(song, true)
    } else {
      LogUtils.info('[播放] 刷新重试仍失败，跳下一首')
      this.scheduleErrorSkip()
    }
  }

  /** 播放队列中当前歌曲 */
  async playCurrent(): Promise<void> {
    const song = this.queue.getCurrentSong()
    if (song) {
      await this.play(song)
    }
  }

  /** 音质降级链（社区音源 逻辑）：从用户设置音质降级到最低音质 */
  private buildQualityChain(preferred: MusicQuality): MusicQuality[] {
    const order: MusicQuality[] = [
      MusicQuality.HIRES, MusicQuality.LOSSLESS, MusicQuality.HIGH, MusicQuality.LOW
    ]
    const start = order.indexOf(preferred)
    const chain: MusicQuality[] = []
    for (let i = start; i < order.length; i++) {
      chain.push(order[i])
    }
    if (chain.length === 0) chain.push(MusicQuality.LOW)
    return chain
  }

  /** 暂停/继续切换 */
  async togglePlay(): Promise<void> {
    if (!this.avPlayer) return
    if (this.usingNativeEq) {
      if (this.status === PlayerStatus.PLAYING) {
        if (audioEqBridgeNative.playerPause()) {
          this.status = PlayerStatus.PAUSED
          this.mediaSession.updatePlaybackState(PlayerStatus.PAUSED, this.currentProgress, this.duration)
        }
      } else if (this.status === PlayerStatus.PAUSED) {
        if (audioEqBridgeNative.playerResume()) {
          this.status = PlayerStatus.PLAYING
          this.mediaSession.updatePlaybackState(PlayerStatus.PLAYING, this.currentProgress, this.duration)
        }
      } else if (this.status === PlayerStatus.LOADING || this.status === PlayerStatus.BUFFERING) {
        this.playGeneration++
        audioEqBridgeNative.playerStop()
        this.usingNativeEq = false
        this.stopLoadingTimer()
        this.stopProgressTimer()
        this.status = PlayerStatus.IDLE
      }
      return
    }
    LogUtils.info(`[togglePlay] status=${this.status}, avState=${this.currentAvState}, playGen=${this.playGeneration}`)
    if (this.status === PlayerStatus.PLAYING) {
      LogUtils.info('[togglePlay] → 暂停')
      try {
        await this.avPlayer.pause()
        LogUtils.info('[togglePlay] pause() 完成')
      } catch (err) {
        LogUtils.warn('[togglePlay] pause() 异常', JSON.stringify(err))
      }
      this.mediaSession.updatePlaybackState(PlayerStatus.PAUSED, this.currentProgress, this.duration)
    } else if (this.status === PlayerStatus.PAUSED) {
      LogUtils.info('[togglePlay] → 恢复播放')
      try {
        await this.avPlayer.play()
        LogUtils.info('[togglePlay] play() 完成')
      } catch (err) {
        LogUtils.warn('[togglePlay] play() 异常', JSON.stringify(err))
      }
      this.mediaSession.updatePlaybackState(PlayerStatus.PLAYING, this.currentProgress, this.duration)
    } else if (this.status === PlayerStatus.LOADING || this.status === PlayerStatus.BUFFERING) {
      // 加载/缓冲中：暂停键取消当前加载并彻底停止 avPlayer（任何状态都可用）
      LogUtils.info(`[togglePlay] status=${this.status} → 取消加载并停止`)
      this.playGeneration++
      this.stopLoadingTimer()
      this.stopProgressTimer()
      await this.resetAvPlayer()
      this.status = PlayerStatus.IDLE
      this.mediaSession.updatePlaybackState(PlayerStatus.IDLE, 0, this.duration)
    } else if (this.status === PlayerStatus.ERROR || this.status === PlayerStatus.IDLE) {
      LogUtils.info(`[togglePlay] status=${this.status} → 尝试重播`)
      if (this.currentSong) {
        this.play(this.currentSong)
      }
    }
  }

  /** 下一首 */
  async next(): Promise<void> {
    const song = this.queue.next()
    if (song) {
      await this.play(song)
    } else {
      LogUtils.info('队列播完')
      this.status = PlayerStatus.IDLE
    }
  }

  /** 上一首 */
  async previous(): Promise<void> {
    const song = this.queue.previous()
    if (song) {
      await this.play(song)
    }
  }

  /** 跳转到指定进度（毫秒） */
  async seekTo(timeMs: number): Promise<void> {
    if (!this.avPlayer) return
    if (this.usingNativeEq) {
      if (audioEqBridgeNative.playerSeek(timeMs)) {
        this.currentProgress = timeMs
        this.status = PlayerStatus.BUFFERING
        this.nativeCompletionHandled = false
        this.nativeErrorHandled = false
      } else {
        LogUtils.warn(`[EQ] 原生播放器 seek 失败: ${timeMs}ms`)
      }
      return
    }
    try {
      // 记录 seek 前状态，seek 后恢复播放
      const wasPlaying = this.status === PlayerStatus.PLAYING
      LogUtils.info(`[seek] 开始 seek → ${timeMs}ms, seek前 status=${this.status}, avState=${this.currentAvState}, wasPlaying=${wasPlaying}`)
      await this.avPlayer.seek(timeMs)
      LogUtils.info(`[seek] seek 完成, 此时 status=${this.status}, avState=${this.currentAvState}`)
      this.currentProgress = timeMs
      // seek 后 AVPlayer 通常停在 paused，需手动恢复
      // 不依赖 this.status 判断——event 回调时序不确定，可能已误设为 PLAYING
      if (wasPlaying) {
        LogUtils.info(`[seek] wasPlaying=true, 尝试恢复播放...`)
        try {
          await this.avPlayer.play()
          LogUtils.info(`[seek] play() 调用完成, status=${this.status}, avState=${this.currentAvState}`)
        } catch (playErr) {
          // 已在播放中时会抛异常，忽略即可
          LogUtils.warn('[seek] play() 抛异常（可能已在播）', JSON.stringify(playErr))
        }
        // 更新媒体会话
        this.mediaSession.updatePlaybackState(PlayerStatus.PLAYING, this.currentProgress, this.duration)
      } else {
        LogUtils.info(`[seek] wasPlaying=false, 不恢复播放`)
      }
    } catch (err) {
      LogUtils.error('seek 失败', JSON.stringify(err))
    }
  }

  /** 设置播放模式 */
  setPlayMode(mode: PlayMode): void {
    const enteringShuffle = mode === PlayMode.SHUFFLE && this.queue.mode !== PlayMode.SHUFFLE
    this.queue.mode = mode
    if (enteringShuffle) {
      this.queue.shuffleForPlayback()
    }
    this.saveQueueState()
  }

  /** 根据 EQ 开关选择原生效果链或系统 AVPlayer。 */
  private async startResolvedPlayback(playUrl: string, generation: number): Promise<boolean> {
    const shouldUseNative = this.eqEnabled && this.eqSupported && !this.forceAvFallbackOnce
    this.forceAvFallbackOnce = false
    if (shouldUseNative) {
      try {
        const initialized = audioEqBridgeNative.initialize()
        const gainsApplied = initialized && audioEqBridgeNative.setGains(this.eqGains)
        const enabled = gainsApplied && audioEqBridgeNative.setEnabled(true)
        if (enabled) {
          if (this.currentAvState !== 'idle') {
            try { await this.avPlayer?.reset() } catch (err) {
              LogUtils.warn(`[EQ] 切换原生引擎时重置 AVPlayer 失败: ${JSON.stringify(err)}`)
            }
          }
          const position = this.pendingStartPositionMs
          const autoPlay = this.pendingAutoPlay
          this.pendingStartPositionMs = 0
          this.pendingAutoPlay = true
          if (audioEqBridgeNative.playerStart(playUrl, position, autoPlay)) {
            this.usingNativeEq = true
            this.nativeCompletionHandled = false
            this.nativeErrorHandled = false
            this.status = PlayerStatus.BUFFERING
            this.startProgressTimer()
            LogUtils.info(`[EQ] 已切换到原生十段均衡器播放链，起点=${position}ms`)
            return true
          }
        }
      } catch (err) {
        LogUtils.warn(`[EQ] 原生播放链启动异常，回退 AVPlayer: ${JSON.stringify(err)}`)
      }
      audioEqBridgeNative.playerStop()
      this.usingNativeEq = false
      if (this.onPlayError) this.onPlayError('均衡器播放链不可用，已自动使用普通播放')
    }

    LogUtils.info(`[播放] 使用 AVPlayer，开始 reset (当前avState=${this.currentAvState})`)
    if (this.currentAvState !== 'idle') {
      try { await this.avPlayer?.reset() } catch (resetErr) {
        LogUtils.warn('[播放] reset异常，尝试继续', JSON.stringify(resetErr))
      }
    }
    if (generation !== this.playGeneration || !this.avPlayer) return false

    if (playUrl.startsWith('file://')) {
      const filePath = playUrl.replace('file://', '')
      const fdFile = fileIo.openSync(filePath, fileIo.OpenMode.READ_ONLY)
      const stat = fileIo.statSync(filePath)
      const fdDesc: media.AVFileDescriptor = { fd: fdFile.fd, offset: 0, length: stat.size }
      this.avPlayer.fdSrc = fdDesc
    } else {
      this.avPlayer.url = playUrl
      const stateDeadline = Date.now() + 8000
      while (this.currentAvState !== 'initialized' && Date.now() < stateDeadline) {
        await new Promise<void>((resolve) => setTimeout(resolve, 50))
        if (generation !== this.playGeneration) return false
      }
      if (this.currentAvState !== 'initialized') {
        LogUtils.error(`URL 设置超时，状态: ${this.currentAvState}`)
        return false
      }
    }

    this.usingNativeEq = false
    this.status = PlayerStatus.BUFFERING
    await this.avPlayer.prepare()
    if (generation !== this.playGeneration) return false
    // 按需播放：pendingAutoPlay=false 时跳过 play()，消除"先播后停"的音频泄漏窗口
    const shouldAutoPlay = this.pendingAutoPlay
    if (shouldAutoPlay) {
      await this.avPlayer.play()
      if (generation !== this.playGeneration) return false
      if (this.pendingStartPositionMs > 0) {
        await this.avPlayer.seek(this.pendingStartPositionMs)
        this.currentProgress = this.pendingStartPositionMs
      }
    } else {
      this.status = PlayerStatus.PAUSED
      LogUtils.info('[播放] pendingAutoPlay=false，跳过 play() 保持在 prepared 状态')
    }
    this.pendingStartPositionMs = 0
    this.pendingAutoPlay = true
    this.stopLoadingTimer()
    return true
  }

  /** 播放完成处理 */
  private async handleCompletion(): Promise<void> {
    LogUtils.info('歌曲播放完毕')
    this.stopProgressTimer()
    // 自动清理：先记下当前歌曲，next() 后仅当真正切换到其他歌曲时才移除已播歌曲
    // （单曲循环 / 随机命中同一首时 next() 不会前进，不能清理，否则会删掉正在播放的歌）
    const playedIndex = this.queue.currentIndex
    const playedSong = this.queue.getCurrentSong()
    await this.next()
    if (this.autoCleanPlayed && playedIndex >= 0) {
      const nowSong = this.queue.getCurrentSong()
      if (nowSong && playedSong && nowSong.songmid === playedSong.songmid) {
        LogUtils.info('[自动清理] 单曲循环/随机同首，跳过清理')
        return
      }
      const removed = this.queue.removeAt(playedIndex)
      if (removed) {
        LogUtils.info(`[自动清理] 已移除已播歌曲: ${removed.name}`)
      }
    }
  }

  /** 异步获取歌词（带换源） */
  private async fetchLyrics(song: MusicItem, gen: number): Promise<void> {
    try {
      const sourceMgr = SourceManager.getInstance()
      const sourceId = String(song.source)
      LogUtils.info(`[歌词] 尝试获取(gen=${gen}): songmid=${song.songmid}, source=${sourceId}`)
      const startMs = Date.now()
      const result = await sourceMgr.getLyricWithFallback(song.songmid, sourceId, song)
      if (gen !== this.playGeneration) {
        LogUtils.info(`[歌词] gen=${gen}已过期(当前=${this.playGeneration})，丢弃结果`)
        return
      }
      this.lyrics = result
      const elapsed = Date.now() - startMs
      LogUtils.info(`[歌词] 获取完成(gen=${gen}): ${this.lyrics.length} 行, 耗时${elapsed}ms`)
    } catch (err) {
      if (gen !== this.playGeneration) {
        LogUtils.info(`[歌词] gen=${gen}出错但已过期，忽略`)
        return
      }
      LogUtils.warn(`[歌词] 异常: ${JSON.stringify(err)}`)
      this.lyrics = []
    }
  }

  /** 启动进度同步定时器（真实进度由 timeUpdate 回调驱动，这里只做媒体会话同步 + 进度保存） */
  private startProgressTimer(): void {
    this.stopProgressTimer()
    this.progressTimer = setInterval(() => {
      if (this.usingNativeEq) {
        const nativeState = audioEqBridgeNative.playerGetState()
        this.currentProgress = audioEqBridgeNative.playerGetPosition()
        const nativeDuration = audioEqBridgeNative.playerGetDuration()
        if (nativeDuration > 0) this.duration = nativeDuration
        if (nativeState === NATIVE_STATE_LOADING) {
          this.status = PlayerStatus.BUFFERING
        } else if (nativeState === NATIVE_STATE_PLAYING) {
          this.status = PlayerStatus.PLAYING
          this.stopLoadingTimer()
        } else if (nativeState === NATIVE_STATE_PAUSED) {
          this.status = PlayerStatus.PAUSED
        } else if (nativeState === NATIVE_STATE_COMPLETED && !this.nativeCompletionHandled) {
          this.nativeCompletionHandled = true
          this.handleCompletion()
          return
        } else if (nativeState === NATIVE_STATE_ERROR && !this.nativeErrorHandled) {
          this.nativeErrorHandled = true
          const message = audioEqBridgeNative.playerGetLastError() || '未知错误'
          LogUtils.warn(`[EQ] 原生播放失败，自动回退 AVPlayer: ${message}`)
          if (this.onPlayError) this.onPlayError('均衡器播放失败，已自动回退普通播放')
          const song = this.currentSong
          this.pendingStartPositionMs = this.currentProgress
          this.pendingAutoPlay = true
          this.forceAvFallbackOnce = true
          this.usingNativeEq = false
          audioEqBridgeNative.playerStop()
          if (song) this.play(song, true)
          return
        }
      }
      if (this.status === PlayerStatus.PLAYING) {
        // 每 5 秒同步一次播放位置到媒体会话（不修改 currentProgress，避免与 timeUpdate 冲突）
        if (this.currentProgress % 5000 < 1000) {
          this.mediaSession.updatePlaybackState(PlayerStatus.PLAYING, this.currentProgress, this.duration)
        }
        // 每 10 秒保存一次播放进度（开启时）
        if (this.savePlayProgress && this.currentSong && Date.now() - this.lastProgressSave > 10000) {
          this.lastProgressSave = Date.now()
          this.saveProgressNow(this.currentSong)
        }
      }
    }, this.usingNativeEq ? 500 : 1000)
  }

  /** 立即保存当前播放进度（按 songmid+source 记录） */
  private saveProgressNow(song: MusicItem): void {
    if (this.duration <= 0 || this.currentProgress < 5000) return
    const key = `${song.source}_${song.songmid}`
    const saved: Record<string, Object> = {
      'progress': this.currentProgress,
      'duration': this.duration,
      'updatedAt': Date.now()
    }
    StorageUtils.getObject<Record<string, Object>>('play_progress', {}).then((map: Record<string, Object>) => {
      map[key] = saved
      StorageUtils.putObject('play_progress', map).catch(() => {})
    }).catch(() => {})
  }

  /** 恢复上次播放进度（仅当进度>5秒且距上次播放<24小时，避免误恢复） */
  private restorePlayProgress(song: MusicItem, gen: number): void {
    const key = `${song.source}_${song.songmid}`
    StorageUtils.getObject<Record<string, Object>>('play_progress', {}).then((map: Record<string, Object>) => {
      const entry = map[key] as Record<string, Object>
      if (!entry) return
      const progress = Number(entry['progress'] ?? 0)
      const updatedAt = Number(entry['updatedAt'] ?? 0)
      const duration = Number(entry['duration'] ?? 0)
      const isFresh = Date.now() - updatedAt < 24 * 3600 * 1000
      const isSignificant = progress > 5000 && duration > 0 && progress < duration - 3000
      if (isFresh && isSignificant) {
        if (gen !== this.playGeneration) return
        LogUtils.info(`[进度] 恢复上次播放位置: ${song.name} ${(progress / 1000).toFixed(1)}s / ${(duration / 1000).toFixed(1)}s`)
        // 延迟 400ms 再 seek，避免与 play() 的状态机竞争导致 seek 被覆盖
        setTimeout(() => {
          if (gen !== this.playGeneration) return
          try {
            if (this.usingNativeEq) {
              audioEqBridgeNative.playerSeek(progress)
            } else {
              this.avPlayer?.seek(progress)
            }
            this.currentProgress = progress
            this.mediaSession.updatePlaybackState(PlayerStatus.PLAYING, progress, this.duration)
            LogUtils.info(`[进度] seek 完成: ${(progress / 1000).toFixed(1)}s`)
          } catch (err) {
            LogUtils.warn(`[进度] seek 异常: ${JSON.stringify(err)}`)
          }
        }, 400)
      }
    }).catch(() => {})
  }

  /** 清除指定歌曲的播放进度记录 */
  clearPlayProgress(song: MusicItem): void {
    const key = `${song.source}_${song.songmid}`
    StorageUtils.getObject<Record<string, Object>>('play_progress', {}).then((map: Record<string, Object>) => {
      if (map[key]) {
        const remaining: Record<string, Object> = {}
        for (const k of Object.keys(map)) {
          if (k !== key) {
            remaining[k] = map[k]
          }
        }
        StorageUtils.putObject('play_progress', remaining).catch(() => {})
      }
    }).catch(() => {})
  }

  /** 停止进度更新定时器 */
  private stopProgressTimer(): void {
    if (this.progressTimer !== null) {
      clearInterval(this.progressTimer)
      this.progressTimer = null
    }
  }

  /** 启动加载超时定时器（25秒，参考社区音源） */
  private startLoadingTimer(): void {
    this.stopLoadingTimer()
    this.loadingTimer = setTimeout(() => {
      this.loadingTimer = null
      if (this.status !== PlayerStatus.LOADING && this.status !== PlayerStatus.BUFFERING) {
        return // 已开始播放或已结束
      }
      if (this.currentSong && this.retryNum < 2) {
        this.retryNum++
        LogUtils.info(`[播放] 加载超时(25s)，刷新URL重试 ${this.retryNum}/2: ${this.currentSong.name}`)
        const song = this.currentSong
        SourceManager.getInstance().clearPlayUrlCache(song.songmid, song.source)
        this.play(song, true)
      } else {
        LogUtils.info('[播放] 加载超时且重试次数已用完，跳下一首')
        this.status = PlayerStatus.ERROR
        this.resetAvPlayer()
        this.scheduleErrorSkip()
      }
    }, 25000)
  }

  /** 停止加载超时定时器 */
  private stopLoadingTimer(): void {
    if (this.loadingTimer !== null) {
      clearTimeout(this.loadingTimer)
      this.loadingTimer = null
    }
  }

  /** 调度跳下一首（3秒后，防止重复触发） */
  private scheduleErrorSkip(): void {
    if (this.errorSkipTimer !== null) return
    this.errorSkipTimer = setTimeout(() => {
      this.errorSkipTimer = null
      // 注意：resetAvPlayer 已把 status 置为 IDLE，这里不能依赖 status===ERROR 判断
      LogUtils.info('[播放] 播放失败，自动跳下一首')
      this.next()
    }, 3000)
  }

  /** 预加载下一首URL到缓存（不播放，参考社区音源 preloadNextMusic） */
  private async preloadNextSong(): Promise<void> {
    const nextSong = this.queue.peekNext()
    if (!nextSong || !nextSong.name) {
      LogUtils.info('[预加载] 无下一首，跳过')
      return
    }
    LogUtils.info(`[预加载] 预加载下一首: ${nextSong.name} - ${nextSong.singer} (source=${nextSong.source})`)
    try {
      const sourceMgr = SourceManager.getInstance()
      await sourceMgr.getMusicInfoWithFallback(nextSong.songmid, nextSong.source, this.defaultQuality, nextSong)
      LogUtils.info(`[预加载] 下一首URL缓存完成: ${nextSong.name}`)
    } catch (err) {
      LogUtils.warn(`[预加载] 失败: ${JSON.stringify(err)}`)
    }
  }

  /** 记录播放历史（最多 50 首，songmid+source 去重，最新在前） */
  private recordPlayHistory(song: MusicItem): void {
    StorageUtils.getObject<MusicItem[]>('play_history', []).then((history: MusicItem[]) => {
      const key = `${song.source}_${song.songmid}`
      const filtered = history.filter(h => `${h.source}_${h.songmid}` !== key)
      filtered.unshift(song)
      const trimmed = filtered.slice(0, 50)
      StorageUtils.putObject('play_history', trimmed).catch(() => {})
      LogUtils.info(`[历史] 记录播放: ${song.name} - ${song.singer}, 共 ${trimmed.length} 条`)
    }).catch(() => {})
  }

  /** 获取播放历史（最新在前） */
  async getPlayHistory(): Promise<MusicItem[]> {
    return await StorageUtils.getObject<MusicItem[]>('play_history', [])
  }

  /** 持久化播放队列（歌曲列表 + 当前索引 + 播放模式），重启后恢复 */
  saveQueueState(): void {
    const state: Record<string, Object> = {
      'songs': this.queue.list,
      'index': this.queue.currentIndex,
      'mode': String(this.queue.mode)
    }
    StorageUtils.putObject('play_queue_state', state).catch(() => {})
  }

  /** 恢复播放队列（应用启动时调用），返回是否恢复成功 */
  async restoreQueueState(): Promise<boolean> {
    try {
      const state = await StorageUtils.getObject<Record<string, Object>>('play_queue_state', {})
      const songs = state['songs'] as MusicItem[]
      if (!songs || songs.length === 0) return false
      const index = Number(state['index'] ?? 0)
      const modeStr = state['mode'] as string
      // 恢复队列与播放模式
      this.queue.list = [...songs]
      this.queue.currentIndex = index >= 0 && index < songs.length ? index : 0
      if (modeStr === 'loopOne') {
        this.queue.mode = PlayMode.LOOP_ONE
      } else if (modeStr === 'loopAll') {
        this.queue.mode = PlayMode.LOOP_ALL
      } else if (modeStr === 'shuffle') {
        this.queue.mode = PlayMode.SHUFFLE
      } else {
        this.queue.mode = PlayMode.SEQUENCE
      }
      LogUtils.info(`[队列] 恢复播放队列: ${songs.length} 首, 当前第 ${this.queue.currentIndex + 1} 首`)
      return true
    } catch (err) {
      LogUtils.warn(`[队列] 恢复失败: ${JSON.stringify(err)}`)
      return false
    }
  }

  /** 设置定时关闭（分钟），到点自动暂停播放；minutes<=0 表示取消 */
  setSleepTimer(minutes: number): void {
    this.cancelSleepTimer()
    if (minutes <= 0) {
      LogUtils.info('[定时关闭] 已取消')
      return
    }
    this.sleepRemainSeconds = minutes * 60
    this.sleepTimer = setInterval(() => {
      this.sleepRemainSeconds--
      if (this.sleepRemainSeconds <= 0) {
        this.cancelSleepTimer()
        LogUtils.info('[定时关闭] 时间到，暂停播放')
        if (this.status === PlayerStatus.PLAYING) {
          this.togglePlay()
        }
      }
    }, 1000)
    LogUtils.info(`[定时关闭] 已设置 ${minutes} 分钟`)
  }

  /** 取消定时关闭 */
  cancelSleepTimer(): void {
    if (this.sleepTimer !== null) {
      clearInterval(this.sleepTimer)
      this.sleepTimer = null
    }
    this.sleepRemainSeconds = 0
  }

  /** 安全重置 AVPlayer（失败时也设为 IDLE） */
  private async resetAvPlayer(): Promise<void> {
    if (this.usingNativeEq) {
      audioEqBridgeNative.playerStop()
      this.usingNativeEq = false
    }
    if (!this.avPlayer) return
    try {
      if (this.currentAvState !== 'idle') {
        await this.avPlayer.reset()
        LogUtils.info('[resetAvPlayer] reset 完成')
      }
    } catch (err) {
      LogUtils.warn('[resetAvPlayer] reset 异常', JSON.stringify(err))
      this.currentAvState = 'idle'
    }
    this.status = PlayerStatus.IDLE
  }

  /** 释放资源 */
  async release(): Promise<void> {
    this.stopProgressTimer()
    this.stopLoadingTimer()
    this.cancelSleepTimer()
    if (this.errorSkipTimer !== null) {
      clearTimeout(this.errorSkipTimer)
      this.errorSkipTimer = null
    }
    audioEqBridgeNative.playerStop()
    audioEqBridgeNative.release()
    this.usingNativeEq = false
    await this.mediaSession.destroy()
    if (this.avPlayer) {
      await this.avPlayer.release()
      this.avPlayer = null
    }
  }
}
