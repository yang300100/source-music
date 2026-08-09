import { ThemeColors } from '../../theme/ThemeColors'
import { MotionTokens } from '../../theme/MotionTokens'

/**
 * 搜索输入栏组件
 *
 * 输入框 + 搜索按钮，输入变化与提交通过回调通知外部。
 */
@Component
export struct SearchBar {
  @StorageLink('themeIsDark') isDark: boolean = true
  /** 外部关键词（用于回填搜索历史点击） */
  @Prop keyword: string = ''
  /** 输入变化回调 */
  onKeywordChange: (value: string) => void = (value: string) => {}
  /** 提交搜索回调 */
  onSearch: () => void = () => {}
  @State inputFocused: boolean = false
  @State searchPressed: boolean = false

  private get primaryText(): ResourceColor { return ThemeColors.primaryText(this.isDark) }
  private get secondaryText(): ResourceColor { return ThemeColors.secondaryText(this.isDark) }
  private get inputBg(): ResourceColor { return ThemeColors.inputBg(this.isDark) }
  private get accentColor(): ResourceColor { return ThemeColors.accentColor() }

  build() {
    Row({ space: 8 }) {
      TextInput({ placeholder: '搜索歌曲、歌手...', text: this.keyword })
        .layoutWeight(1)
        .fontSize(15)
        .fontColor(this.primaryText)
        .placeholderColor(this.secondaryText)
        .backgroundColor(this.inputBg)
        .backdropBlur(20)
        .borderRadius(12)
        .border({ width: this.inputFocused ? 1.5 : 0.5,
          color: this.inputFocused ? this.accentColor : ThemeColors.borderFaint(this.isDark) })
        .scale({ x: this.inputFocused ? 1.01 : 1, y: this.inputFocused ? 1.01 : 1 })
        .shadow(this.inputFocused ? { radius: 12, color: '#30b388ff', offsetX: 0, offsetY: 2 } :
          { radius: 0, color: '#00000000', offsetX: 0, offsetY: 0 })
        .animation({ duration: MotionTokens.NORMAL, curve: Curve.FastOutSlowIn })
        .caretColor('#b388ff')
        .onFocus(() => { this.inputFocused = true })
        .onBlur(() => { this.inputFocused = false })
        .onChange((value: string) => { this.onKeywordChange(value) })
        .onSubmit(() => { this.onSearch() })

      Text('搜索')
        .fontSize(14)
        .fontColor(this.isDark ? '#e8d9ff' : '#0e0c18')
        .backgroundColor(this.accentColor)
        .padding({ left: 16, right: 16, top: 8, bottom: 8 })
        .borderRadius(12)
        .scale({ x: this.searchPressed ? MotionTokens.PRESSED_SCALE : 1,
          y: this.searchPressed ? MotionTokens.PRESSED_SCALE : 1 })
        .opacity(this.searchPressed ? 0.82 : 1)
        .animation({ duration: MotionTokens.FAST, curve: Curve.EaseOut })
        .onTouch((event: TouchEvent) => {
          this.searchPressed = event.type === TouchType.Down
        })
        .onClick(() => { this.onSearch() })
    }
    .padding({ left: 16, right: 16, top: 12, bottom: 12 })
  }
}
