import { ThemeColors } from '../../theme/ThemeColors'
import { MotionTokens } from '../../theme/MotionTokens'

/**
 * 通用设置行组件
 *
 * 左侧标题（可带副标题），右侧为值文本 / Toggle / 箭头。
 */
@Component
export struct SettingsRow {
  @StorageLink('themeIsDark') isDark: boolean = true
  /** 标题 */
  @Prop title: string = ''
  /** 副标题（可选） */
  @Prop subtitle: string = ''
  /** 右侧值文本（可选） */
  @Prop value: string = ''
  /** 是否显示右侧箭头 */
  @Prop showArrow: boolean = false
  /** 是否显示右侧 Toggle */
  @Prop showToggle: boolean = false
  /** Toggle 状态 */
  @Prop isOn: boolean = false
  /** 点击整行回调（携带点击坐标） */
  onRowClick: (event: ClickEvent) => void = (event: ClickEvent) => {}
  /** Toggle 切换回调 */
  onToggle: (checked: boolean) => void = (checked: boolean) => {}
  @State rowPressed: boolean = false

  private get primaryText(): ResourceColor { return ThemeColors.primaryText(this.isDark) }
  private get secondaryText(): ResourceColor { return ThemeColors.secondaryText(this.isDark) }
  private get cardBg(): ResourceColor { return ThemeColors.cardBg(this.isDark) }
  private get borderFaint(): ResourceColor { return ThemeColors.borderFaint(this.isDark) }

  build() {
    Row() {
      Column({ space: 2 }) {
        Text(this.title).fontSize(15).fontColor(this.primaryText)
        if (this.subtitle.length > 0) {
          Text(this.subtitle).fontSize(12).fontColor(this.secondaryText)
        }
      }
      .alignItems(HorizontalAlign.Start)

      Blank()

      if (this.value.length > 0) {
        Text(this.value).fontSize(13).fontColor(this.secondaryText)
      }
      if (this.showToggle) {
        Toggle({ type: ToggleType.Switch, isOn: this.isOn })
          .selectedColor('#b388ff')
          .scale({ x: this.isOn ? 1.04 : 1, y: this.isOn ? 1.04 : 1 })
          .animation({ duration: MotionTokens.NORMAL, curve: Curve.FastOutSlowIn })
          .onChange((checked: boolean) => { this.onToggle(checked) })
          .margin({ right: 4 })
      }
      if (this.showArrow) {
        Text('›').fontSize(15).fontColor(this.secondaryText).margin({ left: 8 })
      }
    }
    .width('100%').padding({ left: 16, right: 16, top: 14, bottom: 14 })
    .backgroundColor(this.cardBg).backdropBlur(20).borderRadius(12)
    .border({ width: 0.5, color: this.borderFaint })
    .scale({ x: this.rowPressed ? MotionTokens.PRESSED_SCALE : 1,
      y: this.rowPressed ? MotionTokens.PRESSED_SCALE : 1 })
    .opacity(this.rowPressed ? 0.88 : 1)
    .animation({ duration: MotionTokens.FAST, curve: Curve.EaseOut })
    .onTouch((event: TouchEvent) => { this.rowPressed = event.type === TouchType.Down })
    .onClick((event: ClickEvent) => { this.onRowClick(event) })
  }
}
