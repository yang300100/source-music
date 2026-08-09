import { PlayerEngine } from 'hsp_player'
import { LyricLine } from 'common'
import { LyricView } from '../LyricView'

/**
 * 竖屏歌词页（全屏歌词，支持拖动 seek 与中心辉光线标记）
 */
@Component
export struct PortraitLyricPage {
  @StorageLink('lyricShowTranslation') lyricShowTranslation: boolean = true
  @StorageLink('lyricFontSize') lyricFontSize: number = 14
  @State lyrics: LyricLine[] = []
  @State currentProgress: number = 0
  private player: PlayerEngine = PlayerEngine.getInstance()
  private syncTimer: number = -1

  aboutToAppear(): void {
    this.syncTimer = setInterval(() => {
      this.lyrics = this.player.lyrics
      const p = this.player.currentProgress
      this.currentProgress = isNaN(p) ? 0 : p
    }, 500)
  }

  aboutToDisappear(): void {
    if (this.syncTimer >= 0) {
      clearInterval(this.syncTimer)
      this.syncTimer = -1
    }
  }

  build() {
    Stack() {
      Column() {
        LyricView({
          lyrics: this.lyrics,
          currentProgress: this.currentProgress,
          showTranslation: this.lyricShowTranslation,
          fontSize: this.lyricFontSize,
          onSeek: (timeMs: number) => { this.player.seekTo(timeMs) }
        })
      }
      .width('100%')
      .height('100%')
      .padding({ top: 40, bottom: 40 })
    }
    .width('100%')
    .height('100%')
  }
}
