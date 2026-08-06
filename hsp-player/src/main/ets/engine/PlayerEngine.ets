import { media } from '@kit.MediaKit'
import { fileIo } from '@kit.CoreFileKit'
import {
  MusicItem,
  MusicQuality,
  PlayerStatus,
  PlayMode,
  SourceType,
  LyricLine,
  LogUtils
} from 'common'
import { SourceManager } from 'hsp_source'
import { PlayQueue } from '../queue/PlayQueue'
import { MediaSession } from './MediaSession'

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

  /** 设置 AVPlayer 事件回调 */
  private setupCallbacks(): void {
    if (!this.avPlayer) return

    this.avPlayer.on('stateChange', (state: string) => {
      LogUtils.info(`[播放] 状态变化: ${state}`)
      switch (state) {
        case 'idle':
        case 'initialized':
          this.status = PlayerStatus.IDLE
          break
        case 'prepared':
          this.status = PlayerStatus.PLAYING
          this.startProgressTimer()
          break
        case 'playing':
          this.status = PlayerStatus.PLAYING
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
          break
      }
    })

    this.avPlayer.on('durationUpdate', (duration: number) => {
      LogUtils.info(`[播放] 时长更新: ${duration}`)
      this.duration = duration
    })

    this.avPlayer.on('timeUpdate', (time: number) => {
      this.currentProgress = time
    })

    this.avPlayer.on('error', (err: Error) => {
      LogUtils.error('AVPlayer 错误', JSON.stringify(err))
      this.status = PlayerStatus.ERROR
    })
  }

  /** 播放指定歌曲 */
  async play(song: MusicItem): Promise<void> {
    if (!this.avPlayer) {
      LogUtils.error('AVPlayer 未初始化')
      return
    }

    this.status = PlayerStatus.LOADING
    this.currentSong = song
    LogUtils.info(`[播放] 开始: ${song.name} - ${song.singer} (source=${song.source})`)

    try {
      // 从音源获取播放 URL（支持换源回退）
      const sourceMgr = SourceManager.getInstance()
      LogUtils.info(`[播放] 请求播放 URL: songmid=${song.songmid}`)
      const musicInfo = await sourceMgr.getMusicInfoWithFallback(song.songmid, song.source, MusicQuality.HIGH, song)
      if (!musicInfo) {
        LogUtils.error('无法获取播放地址')
        this.status = PlayerStatus.ERROR
        return
      }
      LogUtils.info(`[播放] 获取到 URL 信息, types=${JSON.stringify(Object.keys(musicInfo.types))}`)

      // 选最高可用音质
      const qualityKey = Object.keys(musicInfo.types)[0]
      const playUrl = musicInfo.types[qualityKey]?.url
      if (!playUrl) {
        LogUtils.error('无可用的播放 URL')
        this.status = PlayerStatus.ERROR
        return
      }
      LogUtils.info(`[播放] URL: ${playUrl.substring(0, 150)}`)

      // 重置播放器
      LogUtils.info('[播放] 开始 reset')
      await this.avPlayer.reset()
      LogUtils.info('[播放] reset 完成')

      // 判断是本地文件还是网络流
      if (playUrl.startsWith('file://')) {
        const filePath = playUrl.replace('file://', '')
        const fdFile = fileIo.openSync(filePath, fileIo.OpenMode.READ_ONLY)
        const stat = fileIo.statSync(filePath)
        const fdDesc: media.AVFileDescriptor = {
          fd: fdFile.fd,
          offset: 0,
          length: stat.size
        }
        this.avPlayer.fdSrc = fdDesc
      } else {
        LogUtils.info('[播放] 设置 URL 数据源')
        this.avPlayer.url = playUrl
      }

      this.status = PlayerStatus.BUFFERING
      LogUtils.info('[播放] 开始 prepare')
      await this.avPlayer.prepare()
      LogUtils.info('[播放] prepare 完成')
      await this.avPlayer.play()
      LogUtils.info('[播放] play() 调用完成')

      // 异步获取歌词
      this.fetchLyrics(song)

      // 更新媒体会话（通知栏/锁屏展示）
      this.mediaSession.updateMetadata(song)
      this.mediaSession.updatePlaybackState(PlayerStatus.PLAYING, 0, this.duration)
      this.mediaSession.activate()

      LogUtils.info(`开始播放: ${song.name} - ${song.singer}`)
    } catch (err) {
      LogUtils.error('播放失败', JSON.stringify(err))
      this.status = PlayerStatus.ERROR
    }
  }

  /** 播放队列中当前歌曲 */
  async playCurrent(): Promise<void> {
    const song = this.queue.getCurrentSong()
    if (song) {
      await this.play(song)
    }
  }

  /** 暂停/继续切换 */
  async togglePlay(): Promise<void> {
    if (!this.avPlayer) return
    if (this.status === PlayerStatus.PLAYING) {
      await this.avPlayer.pause()
      this.mediaSession.updatePlaybackState(PlayerStatus.PAUSED, this.currentProgress, this.duration)
    } else if (this.status === PlayerStatus.PAUSED) {
      await this.avPlayer.play()
      this.mediaSession.updatePlaybackState(PlayerStatus.PLAYING, this.currentProgress, this.duration)
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
    await this.avPlayer.seek(timeMs)
  }

  /** 设置播放模式 */
  setPlayMode(mode: PlayMode): void {
    this.queue.mode = mode
  }

  /** 播放完成处理 */
  private async handleCompletion(): Promise<void> {
    LogUtils.info('歌曲播放完毕')
    this.stopProgressTimer()
    await this.next()
  }

  /** 异步获取歌词 */
  private async fetchLyrics(song: MusicItem): Promise<void> {
    try {
      const sourceMgr = SourceManager.getInstance()
      const source = sourceMgr.getSourceById(String(song.source))
      if (source) {
        this.lyrics = await source.getLyric(song.songmid, song)
      }
    } catch (err) {
      LogUtils.warn('歌词获取失败', JSON.stringify(err))
      this.lyrics = []
    }
  }

  /** 启动进度更新定时器 */
  private startProgressTimer(): void {
    this.stopProgressTimer()
    this.progressTimer = setInterval(() => {
      if (this.status === PlayerStatus.PLAYING) {
        this.currentProgress += 1000
        // 每 5 秒同步一次播放位置到媒体会话
        if (this.currentProgress % 5000 === 0) {
          this.mediaSession.updatePlaybackState(PlayerStatus.PLAYING, this.currentProgress, this.duration)
        }
      }
    }, 1000)
  }

  /** 停止进度更新定时器 */
  private stopProgressTimer(): void {
    if (this.progressTimer !== null) {
      clearInterval(this.progressTimer)
      this.progressTimer = null
    }
  }

  /** 释放资源 */
  async release(): Promise<void> {
    this.stopProgressTimer()
    await this.mediaSession.destroy()
    if (this.avPlayer) {
      await this.avPlayer.release()
      this.avPlayer = null
    }
  }
}
