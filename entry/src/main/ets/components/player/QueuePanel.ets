import { MusicItem, PlayerStatus } from 'common'
import { ThemeColors } from '../../theme/ThemeColors'
import { MotionTokens } from '../../theme/MotionTokens'

/**
 * 播放列表面板组件（NowPlaying 播放列表栏）
 *
 * 展示播放队列，支持清空、删除单曲、点击切歌。
 * 开启排序模式后每项显示 ↑↓ 按钮，点击移动一位。
 * 长按弹出歌曲操作菜单。
 */
@Component
export struct QueuePanel {
  @StorageLink('themeIsDark') isDark: boolean = true
  /** 播放队列 */
  @Prop queueSongs: MusicItem[] = []
  /** 当前播放索引 */
  @Prop queueIndex: number = -1
  /** 播放器状态（用于显示正在播放标记） */
  @Prop status: PlayerStatus = PlayerStatus.IDLE
  /** 排序模式 */
  @State sortMode: boolean = false
  /** 清空队列 */
  onClear: () => void = () => {}
  /** 删除指定索引歌曲 */
  onRemoveAt: (index: number) => void = (index: number) => {}
  /** 点击播放指定索引歌曲 */
  onPlayAt: (index: number) => void = (index: number) => {}
  /** 移动歌曲（from → to） */
  onMoveItem: (from: number, to: number) => void = (from: number, to: number) => {}
  /** 长按歌曲回调（传递歌曲和手势事件） */
  onLongPressSong: ((song: MusicItem, index: number, event: GestureEvent) => void) | null = null

  private get primaryText(): ResourceColor { return ThemeColors.primaryText(this.isDark) }
  private get secondaryText(): ResourceColor { return ThemeColors.secondaryText(this.isDark) }
  private get accentColor(): ResourceColor { return ThemeColors.accentColor() }

  build() {
    Column() {
      Row() {
        Text('播放列表')
          .fontSize(16).fontWeight(FontWeight.Bold).fontColor(this.primaryText)
        Blank()
        Text(this.sortMode ? '完成' : '排序')
          .fontSize(12).fontColor(this.sortMode ? '#0e0c18' : this.accentColor)
          .backgroundColor(this.sortMode ? this.accentColor : Color.Transparent)
          .padding({ left: 10, right: 10, top: 4, bottom: 4 })
          .borderRadius(10)
          .scale({ x: this.sortMode ? 1.04 : 1, y: this.sortMode ? 1.04 : 1 })
          .animation({ duration: MotionTokens.NORMAL, curve: Curve.FastOutSlowIn })
          .onClick(() => { this.sortMode = !this.sortMode })
        Image($r('app.media.ic_clear')).width(14).height(14).fillColor(this.accentColor)
          .margin({ left: 10 })
          .onClick(() => { this.onClear() })
      }
      .width('100%')
      .padding({ left: 16, right: 16, top: 16, bottom: 8 })

      if (this.queueSongs.length === 0) {
        Column() {
          Text('队列为空').fontSize(14).fontColor(this.secondaryText)
        }
        .width('100%').height('100%').justifyContent(FlexAlign.Center)
        .transition(TransitionEffect.OPACITY.animation({ duration: MotionTokens.NORMAL, curve: Curve.EaseOut })
          .combine(TransitionEffect.scale({ x: 0.94, y: 0.94 })
            .animation({ duration: MotionTokens.NORMAL, curve: Curve.FastOutSlowIn })))
      } else {
        List({ space: 2 }) {
          ForEach(this.queueSongs, (song: MusicItem, index: number) => {
            ListItem() {
              Row({ space: 10 }) {
                if (song.imgUrl) {
                  Image(song.imgUrl)
                    .width(40).height(40).borderRadius(8)
                    .objectFit(ImageFit.Cover).alt($r('app.media.startIcon'))
                } else {
                  Image($r('app.media.startIcon'))
                    .width(40).height(40).borderRadius(8)
                    .objectFit(ImageFit.Cover).opacity(0.2)
                }
                Column({ space: 2 }) {
                  Text(song.name)
                    .fontSize(13)
                    .fontColor(index === this.queueIndex ? this.accentColor : this.primaryText)
                    .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
                  Text(song.singer)
                    .fontSize(11).fontColor(this.secondaryText)
                    .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
                }
                .layoutWeight(1)

                if (this.sortMode) {
                  Row({ space: 8 }) {
                    Text('↑')
                      .fontSize(14).fontColor(index > 0 ? this.accentColor : this.secondaryText)
                      .onClick(() => {
                        if (index > 0) { this.onMoveItem(index, index - 1) }
                      })
                    Text('↓')
                      .fontSize(14).fontColor(index < this.queueSongs.length - 1 ? this.accentColor : this.secondaryText)
                      .onClick(() => {
                        if (index < this.queueSongs.length - 1) { this.onMoveItem(index, index + 1) }
                      })
                  }
                } else if (index === this.queueIndex && this.status === PlayerStatus.PLAYING) {
                  Text('♪')
                    .fontSize(14).fontColor(this.accentColor)
                } else {
                  Image($r('app.media.ic_delete')).width(14).height(14).fillColor(this.secondaryText)
                    .onClick(() => { this.onRemoveAt(index) })
                }
              }
              .width('100%')
              .padding({ left: 12, right: 12, top: 8, bottom: 8 })
              .borderRadius(10)
              .backgroundColor(index === this.queueIndex ? (this.isDark ? '#15b388ff' : '#10b388ff') : Color.Transparent)
              .scale({ x: index === this.queueIndex ? 1.01 : 1, y: index === this.queueIndex ? 1.01 : 1 })
              .animation({ duration: MotionTokens.NORMAL, curve: Curve.FastOutSlowIn })
              .onClick(() => {
                if (!this.sortMode) { this.onPlayAt(index) }
              })
              .gesture(LongPressGesture({ repeat: false }).onAction((event: GestureEvent) => {
                if (!this.sortMode && this.onLongPressSong) {
                  this.onLongPressSong(song, index, event)
                }
              }))
            }
            .transition(TransitionEffect.OPACITY.animation({ duration: MotionTokens.LIST,
              delay: MotionTokens.staggerDelay(index), curve: Curve.EaseOut })
              .combine(TransitionEffect.translate({ x: 10, y: 0 })
                .animation({ duration: MotionTokens.LIST, delay: MotionTokens.staggerDelay(index),
                  curve: Curve.FastOutSlowIn })))
          }, (song: MusicItem) => `${song.source}_${song.songmid}`)
        }
        .width('100%').layoutWeight(1)
        .scrollBar(BarState.Off)
        .padding({ left: 4, right: 4 })
      }
    }
  }
}
