import { LyricLine } from 'common'

/**
 * 滚动歌词组件 — 根据播放进度高亮当前行，支持原文+译文
 */
@Component
export struct LyricView {
  @Prop lyrics: LyricLine[] = []
  @Prop currentProgress: number = 0
  @State currentIndex: number = 0

  build() {
    if (this.lyrics.length === 0) {
      Column() {
        Text('纯音乐，请欣赏')
          .fontSize(16)
          .fontColor('#6c7086')
      }
      .width('100%')
      .height('100%')
      .justifyContent(FlexAlign.Center)
    } else {
      List() {
        ForEach(this.lyrics, (line: LyricLine, index: number) => {
          ListItem() {
            Column({ space: 2 }) {
              Text(line.text)
                .fontSize(index === this.currentIndex ? 18 : 14)
                .fontWeight(index === this.currentIndex ? FontWeight.Bold : FontWeight.Normal)
                .fontColor(index === this.currentIndex ? '#a6e3a1' : '#6c7086')
                .animation({ duration: 300, curve: Curve.EaseOut })

              if (line.transText && index === this.currentIndex) {
                Text(line.transText)
                  .fontSize(13)
                  .fontColor('#585b70')
              }
            }
            .width('100%')
            .padding({ top: 6, bottom: 6 })
          }
        })
      }
      .width('100%')
      .height('100%')
      .scrollBar(BarState.Off)
    }
  }

  aboutToAppear(): void {
    setInterval(() => {
      for (let i = this.lyrics.length - 1; i >= 0; i--) {
        if (this.currentProgress >= this.lyrics[i].time) {
          this.currentIndex = i
          break
        }
      }
    }, 300)
  }
}
