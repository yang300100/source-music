import { ThemeColors } from '../../theme/ThemeColors'
import { MotionTokens } from '../../theme/MotionTokens'

/**
 * 定时关闭选择弹窗（自定义毛玻璃风格）
 *
 * 提供 15/30/45/60 分钟与取消定时选项。
 */
@CustomDialog
export struct SleepTimerDialog {
  @StorageLink('themeIsDark') isDark: boolean = true
  controller: CustomDialogController
  /** 当前剩余文本（'关闭' 或 'N分钟'） */
  currentText: string = '关闭'
  /** 选择分钟数回调（0 = 取消） */
  onSelect: (minutes: number) => void = (minutes: number) => {}
  @State entered: boolean = false

  aboutToAppear(): void {
    setTimeout(() => { this.entered = true }, 20)
  }

  private get primaryText(): ResourceColor { return ThemeColors.primaryText(this.isDark) }
  private get secondaryText(): ResourceColor { return ThemeColors.secondaryText(this.isDark) }
  private get dialogBg(): ResourceColor { return this.isDark ? '#701e1a30' : '#88ffffff' }
  private get borderFaint(): ResourceColor { return ThemeColors.dialogBorderFaint(this.isDark) }
  private get rowBg(): ResourceColor { return this.isDark ? '#30181525' : '#90ffffff' }

  build() {
    Column({ space: 4 }) {
      Row({ space: 10 }) {
        Column({ space: 2 }) {
          Text('定时关闭')
            .fontSize(16).fontWeight(FontWeight.Bold).fontColor(this.primaryText)
          Text(this.currentText === '关闭' ? '当前未启用' : `当前：${this.currentText}`)
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

      this.TimeRow('15 分钟', 15)
      this.TimeRow('30 分钟', 30)
      this.TimeRow('45 分钟', 45)
      this.TimeRow('60 分钟', 60)
      this.TimeRow('取消定时', 0)
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
    .opacity(this.entered ? 1 : 0)
    .scale({ x: this.entered ? 1 : 0.92, y: this.entered ? 1 : 0.92 })
    .translate({ x: 0, y: this.entered ? 0 : 12 })
    .animation({ duration: MotionTokens.PAGE, curve: Curve.FastOutSlowIn })
  }

  @Builder
  TimeRow(label: string, minutes: number) {
    Row() {
      Text(label)
        .fontSize(15).fontColor(this.primaryText)
      Blank()
      Text(minutes > 0 ? '›' : '')
        .fontSize(15).fontColor(this.secondaryText)
    }
    .width('100%')
    .padding({ left: 16, right: 16, top: 13, bottom: 13 })
    .backgroundColor(this.rowBg)
    .borderRadius(14)
    .stateStyles({
      normal: { .opacity(1).scale({ x: 1, y: 1 }) },
      pressed: { .opacity(0.72).scale({ x: MotionTokens.PRESSED_SCALE, y: MotionTokens.PRESSED_SCALE }) }
    })
    .onClick(() => {
      this.onSelect(minutes)
      this.controller?.close()
    })
  }
}
