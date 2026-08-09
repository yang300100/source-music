import { ThemeColors } from '../../theme/ThemeColors'
import { MotionTokens } from '../../theme/MotionTokens'

export interface EqPresetOption {
  id: string
  label: string
  gains: number[]
}

const EQ_FREQUENCIES: string[] = ['31', '62', '125', '250', '500', '1k', '2k', '4k', '8k', '16k']
const EQ_PRESETS: EqPresetOption[] = [
  { id: 'default', label: '默认', gains: [0, 0, 0, 0, 0, 0, 0, 0, 0, 0] },
  { id: 'ballad', label: '民谣', gains: [3, 5, 2, -4, 1, 2, -3, 1, 4, 5] },
  { id: 'chinese', label: '中国风', gains: [0, 0, 2, 0, 0, 4, 4, 2, 2, 5] },
  { id: 'classical', label: '古典', gains: [2, 3, 2, 1, 0, 0, -5, -5, -5, -6] },
  { id: 'dance', label: '舞曲', gains: [4, 3, 2, -3, 0, 0, 5, 4, 2, 0] },
  { id: 'jazz', label: '爵士', gains: [2, 0, 2, 3, 6, 5, -1, 3, 4, 4] },
  { id: 'pop', label: '流行', gains: [5, 2, 1, -1, -5, -5, -2, 1, 2, 4] },
  { id: 'rb', label: 'R&B', gains: [1, 4, 5, 3, -2, -2, 2, 3, 5, 5] },
  { id: 'rock', label: '摇滚', gains: [6, 4, 4, 2, 0, 1, 3, 3, 5, 4] }
]

/** 应用统一样式的十段均衡器弹窗，拖动时实时改变声音。 */
@CustomDialog
export struct EqDialog {
  @StorageLink('themeIsDark') isDark: boolean = true
  controller: CustomDialogController
  eqEnabled: boolean = false
  supported: boolean = false
  preset: string = 'default'
  gains: number[] = [0, 0, 0, 0, 0, 0, 0, 0, 0, 0]
  onEnabledChange: (enabled: boolean) => void = (enabled: boolean) => {}
  onPresetChange: (preset: string) => void = (preset: string) => {}
  onGainsChange: (gains: number[]) => void = (gains: number[]) => {}
  @State localEnabled: boolean = false
  @State localPreset: string = 'default'
  @State localGains: number[] = [0, 0, 0, 0, 0, 0, 0, 0, 0, 0]
  @State entered: boolean = false

  aboutToAppear(): void {
    this.localEnabled = this.eqEnabled
    this.localPreset = this.preset
    this.localGains = this.gains.length === 10 ? [...this.gains] : [0, 0, 0, 0, 0, 0, 0, 0, 0, 0]
    setTimeout(() => { this.entered = true }, 20)
  }

  private get primaryText(): ResourceColor { return ThemeColors.primaryText(this.isDark) }
  private get secondaryText(): ResourceColor { return ThemeColors.secondaryText(this.isDark) }
  private get dialogBg(): ResourceColor { return ThemeColors.dialogBg(this.isDark) }
  private get eqBorderColor(): ResourceColor { return ThemeColors.dialogBorderFaint(this.isDark) }

  build() {
    Column({ space: 12 }) {
      Row({ space: 10 }) {
        Column({ space: 4 }) {
          Text('十段均衡器').fontSize(18).fontWeight(FontWeight.Bold).fontColor(this.primaryText)
          Text(this.supported ? '31Hz—16kHz · 调节会实时作用于声音' : '当前系统不支持原生均衡器')
            .fontSize(12).fontColor(this.secondaryText)
        }.alignItems(HorizontalAlign.Start).layoutWeight(1)

        Toggle({ type: ToggleType.Switch, isOn: this.localEnabled })
          .enabled(this.supported)
          .selectedColor('#b388ff')
          .onChange((checked: boolean) => {
            this.localEnabled = checked
            this.onEnabledChange(checked)
          })

        Text('×').fontSize(20).fontColor(this.secondaryText).width(32).height(32)
          .textAlign(TextAlign.Center).onClick(() => { this.controller?.close() })
      }.width('100%')

      Flex({ wrap: FlexWrap.Wrap, justifyContent: FlexAlign.Start }) {
        ForEach(EQ_PRESETS, (item: EqPresetOption) => {
          Text(item.label)
            .fontSize(12)
            .fontColor(this.localPreset === item.id ? '#ffffff' : this.primaryText)
            .padding({ left: 10, right: 10, top: 6, bottom: 6 })
            .margin({ right: 6, bottom: 6 })
            .backgroundColor(this.localPreset === item.id ? '#a06ce8' : '#25181525')
            .borderRadius(12)
            .border({ width: 0.5, color: this.localPreset === item.id ? '#e6c8ff' : this.eqBorderColor })
            .stateStyles({
              normal: { .opacity(1).scale({ x: 1, y: 1 }) },
              pressed: { .opacity(0.72).scale({ x: MotionTokens.PRESSED_SCALE, y: MotionTokens.PRESSED_SCALE }) }
            })
            .onClick(() => { this.applyPreset(item) })
        }, (item: EqPresetOption) => item.id)
      }.width('100%')

      Row() {
        ForEach(EQ_FREQUENCIES, (frequency: string, index: number) => {
          Column({ space: 4 }) {
            Text(`${this.localGains[index] > 0 ? '+' : ''}${this.localGains[index]}`)
              .fontSize(10).fontColor(this.localEnabled ? '#d8a8ff' : this.secondaryText)
            Slider({
              value: this.localGains[index], min: -12, max: 12, step: 1,
              style: SliderStyle.InSet, direction: Axis.Vertical, reverse: true
            })
              .height(150)
              .trackThickness(3)
              .selectedColor('#b388ff')
              .blockColor('#f0d8ff')
              .enabled(this.supported && this.localEnabled)
              .onChange((value: number, mode: SliderChangeMode) => {
                // 拖动时只更新界面；松手后再调用原生 EQ，避免高频系统调用阻塞主线程。
                this.updateGain(index, value, mode === SliderChangeMode.End || mode === SliderChangeMode.Click)
              })
            Text(frequency).fontSize(10).fontColor(this.secondaryText)
          }.layoutWeight(1).alignItems(HorizontalAlign.Center)
        }, (frequency: string) => frequency)
      }.width('100%').height(190)

      Row() {
        Text('−12 dB').fontSize(10).fontColor(this.secondaryText)
        Blank()
        Text('0 dB').fontSize(10).fontColor(this.secondaryText)
        Blank()
        Text('+12 dB').fontSize(10).fontColor(this.secondaryText)
      }.width('100%')
    }
    .width('92%')
    .constraintSize({ maxWidth: 540 })
    .padding(18)
    .backgroundColor(this.dialogBg)
    .backgroundEffect({ radius: 32, saturation: 1.35, brightness: 1.0, adaptiveColor: AdaptiveColor.AVERAGE })
    .borderRadius(24)
    .border({ width: 0.8, color: this.eqBorderColor })
    .shadow({ radius: 30, color: '#50d8a8ff', offsetX: 0, offsetY: 4 })
    .opacity(this.entered ? 1 : 0)
    .scale({ x: this.entered ? 1 : 0.94, y: this.entered ? 1 : 0.94 })
    .translate({ x: 0, y: this.entered ? 0 : 12 })
    .animation({ duration: MotionTokens.PAGE, curve: Curve.FastOutSlowIn })
  }

  private applyPreset(item: EqPresetOption): void {
    this.localPreset = item.id
    this.localGains = [...item.gains]
    this.onPresetChange(item.id)
  }

  private updateGain(index: number, value: number, applyToPlayer: boolean): void {
    const next = [...this.localGains]
    next[index] = Math.round(value)
    this.localGains = next
    this.localPreset = 'custom'
    if (applyToPlayer) {
      this.onGainsChange(next)
    }
  }
}
