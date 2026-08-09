import { ThemeColors } from '../../theme/ThemeColors'

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
        .caretColor('#b388ff')
        .onChange((value: string) => { this.onKeywordChange(value) })
        .onSubmit(() => { this.onSearch() })

      Text('搜索')
        .fontSize(14)
        .fontColor(this.isDark ? '#e8d9ff' : '#0e0c18')
        .backgroundColor(this.accentColor)
        .padding({ left: 16, right: 16, top: 8, bottom: 8 })
        .borderRadius(12)
        .onClick(() => { this.onSearch() })
    }
    .padding({ left: 16, right: 16, top: 12, bottom: 12 })
  }
}
