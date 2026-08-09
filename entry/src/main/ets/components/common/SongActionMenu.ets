import { MusicItem } from 'common'
import { ThemeColors } from '../../theme/ThemeColors'

/**
 * 歌曲操作菜单（自定义毛玻璃弹窗）
 *
 * 提供：添加到歌单 / 下一首播放 / 收藏 / 下载 等操作。
 * 通过 onAction 回调通知外部。
 */
@CustomDialog
export struct SongActionMenu {
  @StorageLink('themeIsDark') isDark: boolean = true
  controller: CustomDialogController
  /** 当前歌曲 */
  song: MusicItem | null = null
  /** 是否已收藏 */
  isFavorited: boolean = false
  /** 操作回调：'playlist' | 'next' | 'favorite' | 'download' */
  onAction: (action: string, event: ClickEvent) => void = (action: string, event: ClickEvent) => {}

  private get primaryText(): ResourceColor { return ThemeColors.primaryText(this.isDark) }
  private get secondaryText(): ResourceColor { return ThemeColors.secondaryText(this.isDark) }
  private get dialogBg(): ResourceColor { return this.isDark ? '#701e1a30' : '#88ffffff' }
  private get borderFaint(): ResourceColor { return ThemeColors.dialogBorderFaint(this.isDark) }
  private get rowBg(): ResourceColor { return this.isDark ? '#30181525' : '#90ffffff' }

  build() {
    Column({ space: 4 }) {
      Row({ space: 10 }) {
        Column({ space: 2 }) {
          Text(this.song ? this.song.name : '未知歌曲')
            .fontSize(16).fontWeight(FontWeight.Bold).fontColor(this.primaryText)
            .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
          Text(this.song ? this.song.singer : '')
            .fontSize(12).fontColor(this.secondaryText)
            .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
        }
        .alignItems(HorizontalAlign.Start)
        .layoutWeight(1)

        Text('✕')
          .fontSize(16).fontColor(this.secondaryText)
          .padding(6)
          .onClick(() => { this.controller?.close() })
      }
      .width('100%')
      .padding({ left: 20, right: 12, top: 20, bottom: 8 })

      this.ActionRow('添加到歌单', (event: ClickEvent) => {
        this.onAction('playlist', event)
        this.controller?.close()
      })
      this.ActionRow('下一首播放', (event: ClickEvent) => {
        this.onAction('next', event)
        this.controller?.close()
      })
      this.ActionRow(this.isFavorited ? '取消收藏' : '收藏', (event: ClickEvent) => {
        this.onAction('favorite', event)
        this.controller?.close()
      })
      this.ActionRow('下载到本地', (event: ClickEvent) => {
        this.onAction('download', event)
        this.controller?.close()
      })
      this.ActionRow('分享歌曲', (event: ClickEvent) => {
        this.onAction('share', event)
        this.controller?.close()
      })
    }
    .width(300)
    .padding({ left: 8, right: 8, bottom: 16 })
    .backgroundColor(this.dialogBg)
    .linearGradient({
      angle: 180,
      colors: [['#22ffffff', 0.0], ['#00000000', 0.4], ['#00000000', 0.75], ['#10b388ff', 1.0]]
    })
    .backgroundEffect({
      radius: 32,
      saturation: 1.35,
      brightness: 1.0,
      adaptiveColor: AdaptiveColor.AVERAGE
    })
    .borderRadius({ topLeft: 28, topRight: 28, bottomLeft: 20, bottomRight: 20 })
    .border({ width: 0.5, color: this.borderFaint })
    .shadow({ radius: 30, color: '#60b388ff', offsetX: 0, offsetY: 4 })
  }

  @Builder
  ActionRow(label: string, action: (event: ClickEvent) => void) {
    Row() {
      Text(label)
        .fontSize(15).fontColor(this.primaryText)
      Blank()
      Text('›')
        .fontSize(15).fontColor(this.secondaryText)
    }
    .width('100%')
    .padding({ left: 16, right: 16, top: 13, bottom: 13 })
    .backgroundColor(this.rowBg)
    .borderRadius(14)
    .onClick((event: ClickEvent) => { action(event) })
  }
}
