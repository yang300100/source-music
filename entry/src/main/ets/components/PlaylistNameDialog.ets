import { ThemeColors } from '../theme/ThemeColors'

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

  private get primaryText(): ResourceColor { return this.isDark ? '#e8e0f8' : '#1a1525' }
  private get secondaryText(): ResourceColor { return this.isDark ? '#7a6f98' : '#6b6088' }
  private get inputBg(): ResourceColor { return this.isDark ? '#80181525' : '#c0e8e0f0' }
  private get dialogBg(): ResourceColor { return ThemeColors.dialogBg(this.isDark) }
  private get borderFaint(): ResourceColor { return ThemeColors.dialogBorderFaint(this.isDark) }

  aboutToAppear(): void {
    this.inputText = this.defaultValue
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
        .caretColor('#b388ff')
        .padding({ left: 12, right: 12, top: 10, bottom: 10 })
        .onChange((value: string) => { this.inputText = value })

      Row({ space: 12 }) {
        Text('取消')
          .fontSize(14).fontColor(this.secondaryText)
          .backgroundColor(this.inputBg).backdropBlur(20)
          .padding({ left: 20, right: 20, top: 8, bottom: 8 }).borderRadius(10)
          .onClick(() => { this.controller?.close() })

        Text(this.confirmText)
          .fontSize(14).fontColor('#0e0c18')
          .backgroundColor('#b388ff')
          .padding({ left: 20, right: 20, top: 8, bottom: 8 }).borderRadius(10)
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
  }
}
