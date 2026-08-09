import { LogUtils } from 'common'
import { ThemeColors } from '../../theme/ThemeColors'

/**
 * 播放器信息区组件（NowPlaying 播放栏）
 *
 * 展示封面大图（加载失败降级为占位图）、歌名、歌手。
 */
@Component
export struct PlayerSection {
  @StorageLink('themeIsDark') isDark: boolean = true
  /** 封面图 URL */
  @Prop coverUrl: string = ''
  /** 封面加载失败标记 */
  @Prop coverLoadFailed: boolean = false
  /** 歌名 */
  @Prop songName: string = ''
  /** 歌手 */
  @Prop singer: string = ''
  /** 滑动切歌动画中：关闭毛玻璃模糊提升流畅度 */
  @Prop isSwiping: boolean = false
  /** 封面加载失败回调 */
  onCoverError: () => void = () => {}

  private get primaryText(): ResourceColor { return ThemeColors.primaryText(this.isDark) }
  private get secondaryText(): ResourceColor { return ThemeColors.secondaryText(this.isDark) }

  build() {
    Column({ space: 8 }) {
      Stack() {
        if (this.coverUrl && !this.coverLoadFailed) {
          Image(this.coverUrl)
            .width(240)
            .height(240)
            .borderRadius(20)
            .objectFit(ImageFit.Cover)
            .onError(() => {
              LogUtils.warn(`[封面UI] 图片加载失败`)
              this.onCoverError()
            })
        } else {
          Image($r('app.media.startIcon'))
            .width(240)
            .height(240)
            .borderRadius(20)
            .objectFit(ImageFit.Cover)
            .opacity(0.25)
        }
      }
      .width(240)
      .height(240)
      .borderRadius(20)
      .backgroundColor(this.isDark ? '#601a1525' : '#60d8d0e8')
      .backdropBlur(this.isSwiping ? 0 : 20)
      .margin({ top: '10%' })

      Text(this.songName)
        .fontSize(22).fontWeight(FontWeight.Bold).fontColor(this.primaryText)
        .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
        .padding({ left: 24, right: 24, top: 16 })

      Text(this.singer)
        .fontSize(14).fontColor(this.secondaryText)
        .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
        .padding({ left: 24, right: 24, bottom: 4 })
    }
  }
}
