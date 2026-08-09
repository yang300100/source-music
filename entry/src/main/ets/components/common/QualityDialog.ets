import { ThemeColors } from '../../theme/ThemeColors'

/**
 * 默认音质选择弹窗（自定义毛玻璃底部卡片）
 */
@CustomDialog
export struct QualityDialog {
  @StorageLink('themeIsDark') isDark: boolean = true
  controller: CustomDialogController
  /** 当前音质（'128k' / '320k' / 'flac'） */
  currentQuality: string = '320k'
  /** 选择音质回调 */
  onSelect: (quality: string) => void = (quality: string) => {}

  private get primaryText(): ResourceColor { return ThemeColors.primaryText(this.isDark) }
  private get secondaryText(): ResourceColor { return ThemeColors.secondaryText(this.isDark) }
  private get accentColor(): ResourceColor { return ThemeColors.accentColor() }
  private get dialogBg(): ResourceColor { return this.isDark ? '#701e1a30' : '#88ffffff' }
  private get borderFaint(): ResourceColor { return ThemeColors.dialogBorderFaint(this.isDark) }
  private get rowBg(): ResourceColor { return this.isDark ? '#30181525' : '#90ffffff' }

  build() {
    Column({ space: 4 }) {
      Row({ space: 10 }) {
        Column({ space: 2 }) {
          Text('默认音质')
            .fontSize(16).fontWeight(FontWeight.Bold).fontColor(this.primaryText)
          Text('影响播放与搜索的音质选择')
            .fontSize(12).fontColor(this.secondaryText)
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

      this.QualityRow('流畅（128k）', '128k')
      this.QualityRow('标准（320k）', '320k')
      this.QualityRow('无损（flac）', 'flac')
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
  QualityRow(label: string, quality: string) {
    Row() {
      Text(label)
        .fontSize(15).fontColor(this.primaryText)
      Blank()
      Text(quality === this.currentQuality ? '✓' : '')
        .fontSize(14).fontColor(this.accentColor)
    }
    .width('100%')
    .padding({ left: 16, right: 16, top: 13, bottom: 13 })
    .backgroundColor(this.rowBg)
    .borderRadius(14)
    .onClick(() => {
      this.onSelect(quality)
      this.controller?.close()
    })
  }
}
