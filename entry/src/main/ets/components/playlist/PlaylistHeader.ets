import { LocalPlaylist } from 'common'
import { ThemeColors } from '../../theme/ThemeColors'

/**
 * 歌单头部组件（歌单详情栏）
 *
 * 展示歌单名称/歌曲数，提供导出与播放全部入口。
 */
@Component
export struct PlaylistHeader {
  @StorageLink('themeIsDark') isDark: boolean = true
  /** 当前歌单（null 时渲染占位） */
  @Prop playlist: LocalPlaylist | null = null
  /** 导出歌单 */
  onExport: () => void = () => {}
  /** 播放全部 */
  onPlayAll: () => void = () => {}

  private get primaryText(): ResourceColor { return ThemeColors.primaryText(this.isDark) }
  private get secondaryText(): ResourceColor { return ThemeColors.secondaryText(this.isDark) }
  private get accentColor(): ResourceColor { return ThemeColors.accentColor() }
  private get cardBg(): ResourceColor { return ThemeColors.cardBg(this.isDark) }

  build() {
    if (!this.playlist) {
      Column() {
        Image($r('app.media.ic_playlist_placeholder')).width(32).height(32).fillColor(this.secondaryText).opacity(0.4)
        Text('选择一个歌单查看歌曲').fontSize(14).fontColor(this.secondaryText).margin({ top: 8 })
      }
      .width('100%').height('100%').justifyContent(FlexAlign.Center)
    } else {
      Column() {
        Row({ space: 12 }) {
          Column({ space: 4 }) {
            Text(this.playlist.name).fontSize(20).fontWeight(FontWeight.Bold).fontColor(this.primaryText)
            Text(`${this.playlist.songs.length} 首`).fontSize(12).fontColor(this.secondaryText)
          }
          Blank()
          Text('导出').fontSize(13).fontColor(this.accentColor).margin({ right: 12 })
            .onClick(() => { this.onExport() })
          Image($r('app.media.ic_play'))
            .width(30).height(30)
            .fillColor(this.accentColor)
            .onClick(() => { this.onPlayAll() })
        }
        .width('100%').padding(16)
      }
      .backgroundColor(this.cardBg)
      .backdropBlur(20)
      .borderRadius({ topLeft: 0, topRight: 0, bottomLeft: 16, bottomRight: 16 })
      .margin({ left: 12, right: 12, bottom: 8 })
    }
  }
}
