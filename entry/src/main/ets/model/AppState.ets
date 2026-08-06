import { PlayerState } from './PlayerState'
import { PlayerEngine } from 'hsp_player'
import { SourceManager } from 'hsp_source'
import { PlaylistManager } from 'hsp_playlist'
import { LogUtils } from 'common'

/**
 * 全局应用状态容器
 * 在 EntryAbility 中初始化，通过 @Provide/@Consume 贯穿组件树
 */
export class AppState {
  playerState: PlayerState = new PlayerState()

  async init(): Promise<void> {
    LogUtils.info('应用初始化开始...')

    // 初始化各子系统（音源、歌单；播放器已在 EntryAbility 中初始化）
    await SourceManager.getInstance().init()
    await PlaylistManager.getInstance().init()

    // 将 PlayerEngine 状态同步到可观察 PlayerState（每 500ms）
    this.syncPlayerState()

    LogUtils.info('应用初始化完成')
  }

  /** 定时同步播放器状态到可观察对象，驱动 UI 更新 */
  private syncPlayerState(): void {
    const engine = PlayerEngine.getInstance()
    setInterval(() => {
      this.playerState.status = engine.status
      this.playerState.currentSong = engine.currentSong
      this.playerState.currentProgress = engine.currentProgress
      this.playerState.duration = engine.duration
      this.playerState.lyrics = engine.lyrics
      this.playerState.mode = engine.queue.mode
      this.playerState.queueLength = engine.queue.length
      this.playerState.currentIndex = engine.queue.currentIndex
    }, 500)
  }
}
