import { LyricLine } from 'common'

@Component
export struct LyricView {
  @StorageLink('themeIsDark') isDark: boolean = true
  @Prop lyrics: LyricLine[] = []
  @Prop currentProgress: number = 0
  /** 是否显示翻译 */
  @Prop showTranslation: boolean = true
  /** 歌词字号（当前行 = 字号 + 6） */
  @Prop fontSize: number = 14
  /** 点击中心虚线确认跳转时回调（目标歌词行时间，用于 seek） */
  onSeek: (timeMs: number) => void = (timeMs: number) => {}
  @State currentIndex: number = 0
  @State isUserScrolling: boolean = false
  /** 中心虚线标记是否显示（拖动后保留，点击虚线确认跳转） */
  @State showTargetLine: boolean = false
  /** 虚线呼吸脉动 */
  @State linePulse: boolean = false
  private scroller: Scroller = new Scroller()
  private syncTimer: number = -1
  /** 用户拖动后记录中央歌词索引（含顶部占位的偏移校正） */
  private userCenterIndex: number = -1
  /** 虚线未确认时的自动隐藏计时器 */
  private lineHideTimer: number = -1
  /** 虚线脉动计时器 */
  private pulseTimer: number = -1

  private get dimLyricColor(): ResourceColor { return this.isDark ? '#4a4260' : '#9088a0' }
  private get transLyricColor(): ResourceColor { return this.isDark ? '#3a3450' : '#a098b0' }
  private get noLyricColor(): ResourceColor { return this.isDark ? '#7a6f98' : '#6b6088' }
  private get accentColor(): ResourceColor { return '#b388ff' }

  build() {
    if (this.lyrics.length === 0) {
      Column() {
        Text('纯音乐，请欣赏')
          .fontSize(16).fontColor(this.noLyricColor)
      }
      .width('100%').height('100%').justifyContent(FlexAlign.Center)
    } else {
      Stack() {
        List({ scroller: this.scroller }) {
          ListItem() { Row().height('40%') }

          ForEach(this.lyrics, (line: LyricLine, index: number) => {
            ListItem() {
              Column({ space: 2 }) {
                Text(line.text)
                  .fontSize(index === this.currentIndex ? this.fontSize + 6 : this.fontSize)
                  .fontWeight(index === this.currentIndex ? FontWeight.Bold : FontWeight.Normal)
                  .fontColor(index === this.currentIndex ? '#b388ff' : this.dimLyricColor)
                  .animation({ duration: 300, curve: Curve.EaseOut })

                if (this.showTranslation && line.transText && index === this.currentIndex) {
                  Text(line.transText)
                    .fontSize(this.fontSize - 1).fontColor(this.transLyricColor)
                }
              }
              .width('100%')
              .padding({ top: 6, bottom: 6 })
            }
          })

          ListItem() { Row().height('40%') }
        }
        .width('100%').height('100%')
        .scrollBar(BarState.Off)
        .onScrollIndex((start: number, end: number, center: number) => {
          // 视口中央索引（index 0 为顶部占位，歌词索引 = center - 1）
          if (this.isUserScrolling || this.showTargetLine) {
            this.userCenterIndex = center - 1
          }
        })
        .onTouch((event: TouchEvent) => {
          if (event.type === TouchType.Down) {
            this.isUserScrolling = true
            this.showTargetLine = true
            this.userCenterIndex = this.currentIndex
            if (this.lineHideTimer >= 0) { clearTimeout(this.lineHideTimer); this.lineHideTimer = -1 }
          } else if (event.type === TouchType.Up || event.type === TouchType.Cancel) {
            this.isUserScrolling = false
            // 松手不直接跳转：保留虚线标记，点击虚线确认
            if (this.lineHideTimer >= 0) { clearTimeout(this.lineHideTimer); this.lineHideTimer = -1 }
            this.lineHideTimer = setTimeout(() => {
              this.lineHideTimer = -1
              this.showTargetLine = false
            }, 3000)
          }
        })

        if (this.showTargetLine) {
          // 单条辉光线：粉紫渐变 + 辉光，出现/消失淡入淡出
          Row() {
            Row()
              .width('85%')
              .height(2)
              .linearGradient({
                angle: 0,
                colors: [['#00b388ff', 0], ['#c99bff', 0.5], ['#00b388ff', 1]]
              })
              .shadow({ radius: 12, color: '#90b388ff', offsetX: 0, offsetY: 0 })
          }
          .width('100%')
          .height(28)
          .justifyContent(FlexAlign.Center)
          .opacity(0.7 + 0.3 * (this.linePulse ? 1 : 0))
          .animation({ duration: 600, curve: Curve.EaseInOut })
          .transition(
            TransitionEffect.OPACITY.animation({ duration: 300, curve: Curve.EaseOut })
              .combine(TransitionEffect.translate({ y: -12 }).animation({ duration: 300, curve: Curve.EaseOut }))
          )
          .onClick(() => { this.confirmTargetLine() })
        }
      }
      .width('100%')
      .height('100%')
    }
  }

  /** 点击虚线：跳转到目标行并隐藏标记 */
  private confirmTargetLine(): void {
    if (this.userCenterIndex < 0 || this.userCenterIndex >= this.lyrics.length) return
    const lyricIndex = this.userCenterIndex
    const targetTime = this.lyrics[lyricIndex].time
    this.showTargetLine = false
    this.currentIndex = lyricIndex
    this.scroller.scrollToIndex(lyricIndex + 1, true, ScrollAlign.CENTER)
    this.onSeek(targetTime)
  }

  aboutToAppear(): void {
    this.pulseTimer = setInterval(() => {
      this.linePulse = !this.linePulse
    }, 600)
    this.syncTimer = setInterval(() => {
      // 用户拖动或虚线标记中暂停自动滚动
      if (this.isUserScrolling || this.showTargetLine) return
      for (let i = this.lyrics.length - 1; i >= 0; i--) {
        if (this.currentProgress >= this.lyrics[i].time) {
          if (this.currentIndex !== i) {
            this.currentIndex = i
            this.scroller.scrollToIndex(i + 1, true, ScrollAlign.CENTER)
          }
          break
        }
      }
    }, 300)
  }

  aboutToDisappear(): void {
    if (this.syncTimer >= 0) { clearInterval(this.syncTimer); this.syncTimer = -1 }
    if (this.lineHideTimer >= 0) { clearTimeout(this.lineHideTimer); this.lineHideTimer = -1 }
    if (this.pulseTimer >= 0) { clearInterval(this.pulseTimer); this.pulseTimer = -1 }
  }
}
