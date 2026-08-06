import { MusicItem, PlayerStatus, PlayMode, LyricLine } from 'common'

/**
 * 播放器可观察状态
 * @Observed 配合 @ObjectLink 在组件树中传递播放状态变化
 */
export class PlayerState {
  status: PlayerStatus = PlayerStatus.IDLE
  currentSong: MusicItem | null = null
  currentProgress: number = 0
  duration: number = 0
  lyrics: LyricLine[] = []
  mode: PlayMode = PlayMode.SEQUENCE
  queueLength: number = 0
  currentIndex: number = -1
}
