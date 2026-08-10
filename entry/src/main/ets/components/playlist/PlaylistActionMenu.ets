import { ThemeColors } from '../../theme/ThemeColors'
import { MotionTokens } from '../../theme/MotionTokens'

/**
 * 歌单操作菜单（自定义毛玻璃弹窗，长按歌单弹出）
 *
 * 提供：重命名 / 上移 / 下移 / 删除。
 * 通过 onAction 回调通知外部。
 */
@CustomDialog
export struct PlaylistActionMenu {
  @StorageLink('themeIsDark') isDark: boolean = true
  controller: CustomDialogController
  /** 歌单名 */
  playlistName: string = ''
  /** 操作回调：'rename' | 'up' | 'down' | 'delete' | 'importLocal' */
  onAction: (action: string, event: ClickEvent) => void = (action: string, event: ClickEvent) => {}
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
          Text(this.playlistName)
            .fontSize(16).fontWeight(FontWeight.Bold).fontColor(this.primaryText)
            .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
          Text('歌单操作')
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

      this.ActionRow('重命名', (event: ClickEvent) => {
        this.onAction('rename', event)
        this.controller?.close()
      })
      this.ActionRow('上移', (event: ClickEvent) => {
        this.onAction('up', event)
        this.controller?.close()
      })
      this.ActionRow('下移', (event: ClickEvent) => {
        this.onAction('down', event)
        this.controller?.close()
      })
      this.ActionRow('导入本地歌曲', (event: ClickEvent) => {
        this.onAction('importLocal', event)
        this.controller?.close()
      })
      this.ActionRow('删除歌单', (event: ClickEvent) => {
        this.onAction('delete', event)
        this.controller?.close()
      })
    }
    .width(280)
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
  ActionRow(label: string, action: (event: ClickEvent) => void) {
    Row() {
      Text(label)
        .fontSize(15).fontColor(this.primaryText)
      Blank()
      Text('›')
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
    .onClick((event: ClickEvent) => { action(event) })
  }
}
