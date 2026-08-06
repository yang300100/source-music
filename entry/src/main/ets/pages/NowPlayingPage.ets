import { PlayerEngine } from 'hsp_player'
import { LyricView } from '../components/LyricView'
import { PlayerStatus, PlayMode } from 'common'

/**
 * 正在播放页面 — 封面 + 歌曲信息 + 播放控制 + 歌词
 */
@Entry
@Component
struct NowPlayingPage {
  @State player: PlayerEngine = PlayerEngine.getInstance()

  build() {
    Column() {
      // 歌曲信息区域
      Column({ space: 8 }) {
        Image($r('app.media.startIcon'))
          .width(200)
          .height(200)
          .borderRadius(12)
          .objectFit(ImageFit.Cover)

        Text(this.player.currentSong?.name ?? '未在播放')
          .fontSize(20)
          .fontWeight(FontWeight.Bold)
          .fontColor('#cdd6f4')

        Text(this.player.currentSong?.singer ?? '选择一首歌曲开始播放吧~')
          .fontSize(15)
          .fontColor('#6c7086')
      }
      .padding({ top: 40, bottom: 16 })

      // 进度条
      Row({ space: 12 }) {
        Text(this.formatTime(this.player.currentProgress))
          .fontSize(12)
          .fontColor('#585b70')
        Slider({
          value: this.player.duration > 0
            ? this.player.currentProgress / this.player.duration
            : 0
        })
          .width('60%')
          .onChange((value: number) => {
            this.player.seekTo(value * this.player.duration)
          })
        Text(this.formatTime(this.player.duration))
          .fontSize(12)
          .fontColor('#585b70')
      }
      .width('100%')
      .padding({ left: 24, right: 24 })
      .justifyContent(FlexAlign.Center)

      // 播放控制
      Row({ space: 24 }) {
        Text('⏮').fontSize(28).onClick(() => this.player.previous())
        Text(this.player.status === PlayerStatus.PLAYING ? '⏸' : '▶️')
          .fontSize(36).onClick(() => this.player.togglePlay())
        Text('⏭').fontSize(28).onClick(() => this.player.next())
      }
      .padding({ top: 12, bottom: 8 })
      .justifyContent(FlexAlign.Center)

      // 播放模式
      Row() {
        Text(this.getModeIcon())
          .fontSize(16)
          .fontColor('#89b4fa')
          .onClick(() => {
            const modes = [PlayMode.SEQUENCE, PlayMode.LOOP_ONE, PlayMode.LOOP_ALL, PlayMode.SHUFFLE]
            const idx = (modes.indexOf(this.player.queue.mode) + 1) % modes.length
            this.player.setPlayMode(modes[idx])
          })
      }
      .width('100%')
      .justifyContent(FlexAlign.Center)
      .padding({ bottom: 8 })

      // 歌词区域
      LyricView({
        lyrics: this.player.lyrics,
        currentProgress: this.player.currentProgress
      })
        .layoutWeight(1)
    }
    .width('100%')
    .height('100%')
    .backgroundColor('#1e1e2e')
  }

  private formatTime(ms: number): string {
    const totalSec = Math.floor(ms / 1000)
    const min = Math.floor(totalSec / 60)
    const sec = totalSec % 60
    return `${min.toString().padStart(2, '0')}:${sec.toString().padStart(2, '0')}`
  }

  private getModeIcon(): string {
    switch (this.player.queue.mode) {
      case PlayMode.LOOP_ONE: return '🔂'
      case PlayMode.LOOP_ALL: return '🔁'
      case PlayMode.SHUFFLE: return '🔀'
      default: return '➡️'
    }
  }
}
