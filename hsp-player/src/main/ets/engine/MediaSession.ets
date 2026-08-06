import { avSession } from '@kit.AVSessionKit'
import { BusinessError } from '@kit.BasicServicesKit'
import { LogUtils, MusicItem, PlayerStatus } from 'common'

/**
 * 媒体会话管理（AVSession Kit）
 *
 * 接入鸿蒙系统播控中心：
 * - 在通知栏/锁屏/播控中心展示歌曲信息（标题、歌手、专辑、封面）
 * - 响应系统下发的播放/暂停/上一首/下一首命令
 * - 展示播放状态（播放中/暂停）和进度
 *
 * 参考官方文档：媒体会话提供方（ArkTS）
 */
export class MediaSession {
  private session: avSession.AVSession | null = null
  private context: Context | null = null

  /**
   * 创建媒体会话（在播放器初始化时调用一次）
   * @param context UIAbilityContext
   */
  async createSession(context: Context): Promise<void> {
    this.context = context
    try {
      this.session = await avSession.createAVSession(context, 'lx_music', 'audio')
      this.setupCommandCallbacks()
      LogUtils.info('媒体会话创建成功')
    } catch (err) {
      const e = err as BusinessError
      LogUtils.error('创建媒体会话失败', `${e.code} ${e.message}`)
    }
  }

  /** 设置系统播控命令监听 */
  private setupCommandCallbacks(): void {
    if (!this.session) return

    this.session.on('play', () => {
      LogUtils.info('收到播控命令: 播放')
      this.onPlayCommand?.()
    })

    this.session.on('pause', () => {
      LogUtils.info('收到播控命令: 暂停')
      this.onPauseCommand?.()
    })

    this.session.on('playNext', () => {
      LogUtils.info('收到播控命令: 下一首')
      this.onNextCommand?.()
    })

    this.session.on('playPrevious', () => {
      LogUtils.info('收到播控命令: 上一首')
      this.onPreviousCommand?.()
    })

    this.session.on('seek', (time: number) => {
      LogUtils.info(`收到播控命令: 跳转 ${time}`)
      this.onSeekCommand?.(time)
    })
  }

  /** 更新媒体元数据（歌曲信息） */
  async updateMetadata(song: MusicItem | null): Promise<void> {
    if (!this.session || !song) return
    try {
      const metadata: avSession.AVMetadata = {
        assetId: song.songmid,
        title: song.name,
        artist: song.singer,
        album: song.albumName,
        duration: song.interval * 1000,
        mediaImage: song.imgUrl || undefined
      }
      await this.session.setAVMetadata(metadata)
    } catch (err) {
      LogUtils.warn('更新媒体元数据失败', JSON.stringify(err))
    }
  }

  /** 更新播放状态 */
  async updatePlaybackState(status: PlayerStatus, position: number = 0, duration: number = 0): Promise<void> {
    if (!this.session) return
    try {
      // AVPlaybackState 状态映射：0=未播放 1=准备中 2=播放中 3=暂停 4=停止
      let playState = 0
      switch (status) {
        case PlayerStatus.PLAYING:
          playState = 2
          break
        case PlayerStatus.PAUSED:
          playState = 3
          break
        case PlayerStatus.BUFFERING:
        case PlayerStatus.LOADING:
          playState = 1
          break
        default:
          playState = 0
      }
      const state: avSession.AVPlaybackState = {
        state: playState,
        position: {
          elapsedTime: position,
          updateTime: Date.now()
        },
        duration: duration
      }
      await this.session.setAVPlaybackState(state)
    } catch (err) {
      LogUtils.warn('更新播放状态失败', JSON.stringify(err))
    }
  }

  /** 激活会话（开始播放时调用） */
  activate(): void {
    try {
      this.session?.activate()
    } catch (err) {
      LogUtils.warn('激活媒体会话失败', JSON.stringify(err))
    }
  }

  /** 释放会话 */
  async destroy(): Promise<void> {
    try {
      await this.session?.destroy()
      this.session = null
    } catch (err) {
      LogUtils.warn('销毁媒体会话失败', JSON.stringify(err))
    }
  }

  // 播控命令回调（由 PlayerEngine 注入）
  onPlayCommand: (() => void) | null = null
  onPauseCommand: (() => void) | null = null
  onNextCommand: (() => void) | null = null
  onPreviousCommand: (() => void) | null = null
  onTogglePlayCommand: (() => void) | null = null
  onSeekCommand: ((time: number) => void) | null = null
}
