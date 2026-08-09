import { ThemeColors } from '../theme/ThemeColors'
import { MotionTokens } from '../theme/MotionTokens'

@CustomDialog
export struct PlaylistNameDialog {
  @StorageLink('themeIsDark') isDark: boolean = true
  controller: CustomDialogController
  onConfirm: (name: string) => void = () => {}
  title: string = '新建歌单'
  confirmText: string = '创建'
  placeholder: string = '请输入歌单名称'
  defaultValue: string = ''
  fallbackValue: string = '新歌单'
  @State inputText: string = ''
  @State inputFocused: boolean = false
  @State entered: boolean = false

  private get primaryText(): ResourceColor { return this.isDark ? '#e8e0f8' : '#1a1525' }
  private get secondaryText(): ResourceColor { return this.isDark ? '#7a6f98' : '#6b6088' }
  private get inputBg(): ResourceColor { return this.isDark ? '#80181525' : '#c0e8e0f0' }
  private get dialogBg(): ResourceColor { return ThemeColors.dialogBg(this.isDark) }
  private get borderFaint(): ResourceColor { return ThemeColors.dialogBorderFaint(this.isDark) }

  aboutToAppear(): void {
    this.inputText = this.defaultValue
    setTimeout(() => { this.entered = true }, 20)
  }

  build() {
    Column() {
      Text(this.title)
        .fontSize(18).fontWeight(FontWeight.Bold).fontColor(this.primaryText)
        .margin({ bottom: 16 })

      TextInput({ placeholder: this.placeholder, text: this.inputText })
        .width('100%').fontSize(15)
        .fontColor(this.primaryText).placeholderColor(this.secondaryText)
        .backgroundColor(this.inputBg).backdropBlur(20).borderRadius(10)
        .border({ width: this.inputFocused ? 1.5 : 0.5,
          color: this.inputFocused ? '#b388ff' : this.borderFaint })
        .scale({ x: this.inputFocused ? 1.01 : 1, y: this.inputFocused ? 1.01 : 1 })
        .animation({ duration: MotionTokens.NORMAL, curve: Curve.FastOutSlowIn })
        .caretColor('#b388ff')
        .padding({ left: 12, right: 12, top: 10, bottom: 10 })
        .onChange((value: string) => { this.inputText = value })
        .onFocus(() => { this.inputFocused = true })
        .onBlur(() => { this.inputFocused = false })

      Row({ space: 12 }) {
        Text('取消')
          .fontSize(14).fontColor(this.secondaryText)
          .backgroundColor(this.inputBg).backdropBlur(20)
          .padding({ left: 20, right: 20, top: 8, bottom: 8 }).borderRadius(10)
          .stateStyles({
            normal: { .opacity(1).scale({ x: 1, y: 1 }) },
            pressed: { .opacity(0.72).scale({ x: MotionTokens.PRESSED_SCALE, y: MotionTokens.PRESSED_SCALE }) }
          })
          .onClick(() => { this.controller?.close() })

        Text(this.confirmText)
          .fontSize(14).fontColor('#0e0c18')
          .backgroundColor('#b388ff')
          .padding({ left: 20, right: 20, top: 8, bottom: 8 }).borderRadius(10)
          .stateStyles({
            normal: { .opacity(1).scale({ x: 1, y: 1 }) },
            pressed: { .opacity(0.72).scale({ x: MotionTokens.PRESSED_SCALE, y: MotionTokens.PRESSED_SCALE }) }
          })
          .onClick(() => {
            const input = this.inputText.trim()
            const value = input.length > 0 ? input : this.fallbackValue
            if (value.length === 0) return
            this.onConfirm(value)
            this.controller?.close()
          })
      }
      .justifyContent(FlexAlign.End)
      .width('100%').margin({ top: 16 })
    }
    .width(300)
    .padding(20)
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
    .opacity(this.entered ? 1 : 0)
    .scale({ x: this.entered ? 1 : 0.92, y: this.entered ? 1 : 0.92 })
    .translate({ x: 0, y: this.entered ? 0 : 12 })
    .animation({ duration: MotionTokens.PAGE, curve: Curve.FastOutSlowIn })
  }
}
