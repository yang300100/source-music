import { MusicItem, PlayerStatus, PlayMode, LyricLine } from 'common'

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
