import { MusicItem } from 'common'
import { PlayerEngine } from 'hsp_player'

/**
 * 歌曲列表项组件 — 显示歌曲信息 + 音源标签，点击播放
 */
@Component
export struct MusicItemView {
  @Prop song: MusicItem
  @Prop showSource: boolean = true

  build() {
    Row({ space: 12 }) {
      Column({ space: 2 }) {
        Text(this.song.name)
          .fontSize(15)
          .fontColor('#cdd6f4')
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })

        Text(`${this.song.singer} · ${this.song.albumName}`)
          .fontSize(12)
          .fontColor('#6c7086')
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
      }
      .layoutWeight(1)

      if (this.showSource) {
        Text(this.song.source)
          .fontSize(11)
          .fontColor('#89b4fa')
          .padding({ left: 6, right: 6, top: 2, bottom: 2 })
          .backgroundColor('#45475a')
          .borderRadius(4)
      }

      Text(this.formatDuration(this.song.interval))
        .fontSize(12)
        .fontColor('#585b70')
    }
    .width('100%')
    .padding({ left: 16, right: 16, top: 12, bottom: 12 })
    .onClick(() => {
      const player = PlayerEngine.getInstance()
      player.queue.replaceList([this.song])
      player.play(this.song)
    })
  }

  private formatDuration(sec: number): string {
    const m = Math.floor(sec / 60)
    const s = sec % 60
    return `${m}:${s.toString().padStart(2, '0')}`
  }
}
