import { SourceInstance } from 'common'
import { ThemeColors } from '../../theme/ThemeColors'
import { MotionTokens } from '../../theme/MotionTokens'

/**
 * 选择音源弹窗（歌曲手动换源，社区音源 风格）
 *
 * 列出全部启用音源单选，底部"确定换源"回调 onPick(sourceId)。
 */
@CustomDialog
export struct SourcePickerDialog {
  /** 歌曲名（标题展示） */
  songName: string = ''
  /** 可选音源列表（全部启用音源） */
  searchSources: SourceInstance[] = []
  /** 当前音源 ID（用于默认选中） */
  currentSourceId: string = ''
  /** 确认回调：音源 ID */
  onPick: (sourceId: string) => void = (sourceId: string) => {}

  @StorageLink('themeIsDark') isDark: boolean = true
  private controller: CustomDialogController
  /** 选中的音源 ID */
  @State selectedSearchId: string = ''
  @State entered: boolean = false

  private get primaryText(): ResourceColor { return ThemeColors.primaryText(this.isDark) }
  private get secondaryText(): ResourceColor { return ThemeColors.secondaryText(this.isDark) }
  private get accentColor(): ResourceColor { return ThemeColors.accentColor() }
  private get dialogBg(): ResourceColor { return ThemeColors.dialogBg(this.isDark) }
  private get borderFaint(): ResourceColor { return ThemeColors.dialogBorderFaint(this.isDark) }

  aboutToAppear(): void {
    setTimeout(() => { this.entered = true }, 20)
    // 默认选中当前源（如果在搜索源组），否则选第一个
    let found = false
    for (const s of this.searchSources) {
      if (s.info.id === this.currentSourceId) {
        this.selectedSearchId = s.info.id
        found = true
        break
      }
    }
    if (!found && this.searchSources.length > 0) {
      this.selectedSearchId = this.searchSources[0].info.id
    }
  }

  build() {
    Column() {
      Text('选择搜索源')
        .fontSize(16).fontWeight(FontWeight.Bold).fontColor(this.primaryText)
        .width('100%').textAlign(TextAlign.Start)
        .padding({ left: 20, top: 18, bottom: 4 })

      Text(this.songName)
        .fontSize(12).fontColor(this.secondaryText)
        .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
        .width('100%').textAlign(TextAlign.Start)
        .padding({ left: 20, bottom: 8 })

      Scroll() {
        Column({ space: 4 }) {
          if (this.searchSources.length > 0) {
            ForEach(this.searchSources, (source: SourceInstance) => {
              this.SourceRow(source)
            }, (source: SourceInstance) => `s_${source.info.id}`)
          } else {
            Text('暂无可用音源，请在设置→音源管理中导入')
              .fontSize(12).fontColor(this.secondaryText)
              .width('100%').textAlign(TextAlign.Start)
              .padding({ left: 16, top: 6, bottom: 6 })
          }
        }
        .width('100%')
      }
      .width('100%')
      .layoutWeight(1)
      .scrollBar(BarState.Off)

      Row({ space: 12 }) {
        Blank()

        Text('确定换源')
          .fontSize(14).fontWeight(FontWeight.Bold)
          .fontColor('#0e0c18')
          .backgroundColor(this.accentColor)
          .padding({ left: 20, right: 20, top: 8, bottom: 8 })
          .borderRadius(12)
          .onClick(() => {
            this.onPick(this.selectedSearchId)
            this.controller?.close()
          })
      }
      .width('100%')
      .padding({ left: 16, right: 16, top: 10, bottom: 14 })
    }
    .width(320)
    .height(380)
    .backgroundColor(this.dialogBg)
    .backdropBlur(30)
    .borderRadius(20)
    .border({ width: 0.5, color: this.borderFaint })
    .shadow({ radius: 24, color: '#60b388ff', offsetX: 0, offsetY: 4 })
    .opacity(this.entered ? 1 : 0)
    .scale({ x: this.entered ? 1 : 0.92, y: this.entered ? 1 : 0.92 })
    .translate({ x: 0, y: this.entered ? 0 : 12 })
    .animation({ duration: MotionTokens.PAGE, curve: Curve.FastOutSlowIn })
  }

  @Builder
  SourceRow(source: SourceInstance) {
    Row() {
      Column({ space: 2 }) {
        Text(source.info.name)
          .fontSize(14)
          .fontColor(this.selectedSearchId === source.info.id ? this.accentColor : this.primaryText)
        if (source.info.description) {
          Text(source.info.description)
            .fontSize(10).fontColor(this.secondaryText)
            .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
        }
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)

      if (this.selectedSearchId === source.info.id) {
        Text('✓')
          .fontSize(13).fontColor(this.accentColor)
      }
    }
    .width('100%')
    .padding({ left: 16, right: 16, top: 10, bottom: 10 })
    .borderRadius(10)
    .backgroundColor(this.selectedSearchId === source.info.id ? '#20b388ff' : Color.Transparent)
    .scale({ x: this.selectedSearchId === source.info.id ? 1.02 : 1,
      y: this.selectedSearchId === source.info.id ? 1.02 : 1 })
    .animation({ duration: MotionTokens.NORMAL, curve: Curve.FastOutSlowIn })
    .onClick(() => {
      this.selectedSearchId = source.info.id
    })
  }
}
