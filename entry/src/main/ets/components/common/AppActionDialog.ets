import { ThemeColors } from '../../theme/ThemeColors'

/** 自定义操作弹窗中的一个选项 */
export interface AppDialogAction {
  id: string
  label: string
  danger?: boolean
}

/**
 * 应用统一操作弹窗
 *
 * Yuki 把应用内需要用户选择或确认的操作都收口到这张毛玻璃卡片中，
 * 系统文件选择器等受系统权限管理的界面不在此处替换。
 */
@CustomDialog
export struct AppActionDialog {
  @StorageLink('themeIsDark') isDark: boolean = true
  controller: CustomDialogController
  title: string = ''
  message: string = ''
  actions: AppDialogAction[] = []
  onAction: (actionId: string, event: ClickEvent) => void = (actionId: string, event: ClickEvent) => {}

  private get primaryText(): ResourceColor { return ThemeColors.primaryText(this.isDark) }
  private get secondaryText(): ResourceColor { return ThemeColors.secondaryText(this.isDark) }
  private get dialogBg(): ResourceColor { return ThemeColors.dialogBg(this.isDark) }
  private get borderFaint(): ResourceColor { return ThemeColors.dialogBorderFaint(this.isDark) }
  private get rowBg(): ResourceColor { return this.isDark ? '#40181525' : '#b0ffffff' }

  build() {
    Column({ space: 8 }) {
      Row({ space: 10 }) {
        Column({ space: 5 }) {
          Text(this.title)
            .fontSize(17)
            .fontWeight(FontWeight.Bold)
            .fontColor(this.primaryText)

          if (this.message.length > 0) {
            Text(this.message)
              .fontSize(12)
              .fontColor(this.secondaryText)
              .maxLines(4)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
          }
        }
        .alignItems(HorizontalAlign.Start)
        .layoutWeight(1)

        Text('×')
          .fontSize(20)
          .fontColor(this.secondaryText)
          .width(32)
          .height(32)
          .textAlign(TextAlign.Center)
          .onClick(() => { this.controller?.close() })
      }
      .width('100%')
      .padding({ left: 12, right: 4, top: 8, bottom: 6 })

      ForEach(this.actions, (action: AppDialogAction) => {
        this.ActionRow(action)
      }, (action: AppDialogAction) => action.id)
    }
    .width(320)
    .padding({ left: 8, right: 8, top: 8, bottom: 16 })
    .backgroundColor(this.dialogBg)
    .linearGradient({
      angle: 180,
      colors: [['#22ffffff', 0.0], ['#00000000', 0.4], ['#00000000', 0.75], ['#16d8a8ff', 1.0]]
    })
    .backgroundEffect({
      radius: 32,
      saturation: 1.35,
      brightness: 1.0,
      adaptiveColor: AdaptiveColor.AVERAGE
    })
    .borderRadius({ topLeft: 28, topRight: 28, bottomLeft: 20, bottomRight: 20 })
    .border({ width: 0.5, color: this.borderFaint })
    .shadow({ radius: 30, color: '#50d8a8ff', offsetX: 0, offsetY: 4 })
  }

  @Builder
  ActionRow(action: AppDialogAction) {
    Row() {
      Text(action.label)
        .fontSize(15)
        .fontColor(action.danger ? '#e86090' : this.primaryText)
    }
    .width('100%')
    .padding({ left: 16, right: 16, top: 13, bottom: 13 })
    .backgroundColor(this.rowBg)
    .borderRadius(14)
    .onClick((event: ClickEvent) => {
      this.controller?.close()
      this.onAction(action.id, event)
    })
  }
}
