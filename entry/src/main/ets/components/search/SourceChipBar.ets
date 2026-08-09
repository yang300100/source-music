import { ThemeColors } from '../../theme/ThemeColors'

/** 搜索源选项 */
export interface SearchSourceOption {
  id: string
  name: string
}

/**
 * 搜索源选择栏组件
 *
 * "全部" + 各搜索源 chips，点击切换当前源。
 */
@Component
export struct SourceChipBar {
  @StorageLink('themeIsDark') isDark: boolean = true
  /** 搜索源选项列表（不含"全部"） */
  @Prop options: SearchSourceOption[] = []
  /** 当前激活的源 id（'' = 全部） */
  @Prop activeSourceId: string = ''
  /** 切换源回调 */
  onSourceChange: (sourceId: string) => void = (sourceId: string) => {}

  private get secondaryText(): ResourceColor { return ThemeColors.secondaryText(this.isDark) }
  private get chipBg(): ResourceColor { return ThemeColors.chipBg(this.isDark) }
  private get accentColor(): ResourceColor { return ThemeColors.accentColor() }

  build() {
    Scroll() {
      Row({ space: 8 }) {
        this.SourceChip('', '全部')
        ForEach(this.options, (source: SearchSourceOption) => {
          this.SourceChip(source.id, source.name)
        })
      }
      .padding({ left: 16, right: 16, bottom: 8 })
    }
    .scrollable(ScrollDirection.Horizontal)
    .scrollBar(BarState.Off)
    .edgeEffect(EdgeEffect.Spring)
    .width('100%')
  }

  @Builder
  SourceChip(sourceId: string, name: string) {
    Text(name)
      .fontSize(13)
      .fontColor(this.activeSourceId === sourceId ? '#0e0c18' : (this.isDark ? '#dcccf0' : '#5a5078'))
      .backgroundColor(this.activeSourceId === sourceId ? this.accentColor : this.chipBg)
      .backdropBlur(this.activeSourceId === sourceId ? 0 : 20)
      .padding({ left: 14, right: 14, top: 5, bottom: 5 })
      .borderRadius(14)
      .onClick(() => {
        this.onSourceChange(sourceId)
      })
  }
}
