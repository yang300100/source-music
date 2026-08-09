import { LocalPlaylist } from 'common'
import { ThemeColors } from '../../theme/ThemeColors'
import { PlaylistActionMenu } from './PlaylistActionMenu'
import { DialogPosUtils } from '../../utils/DialogPosUtils'

/**
 * 歌单侧栏组件（歌单列表）
 *
 * 顶部标题 + 右上角创建按钮；长按歌单项弹出自定义操作菜单（重命名/上移/下移/删除）。
 */
@Component
export struct PlaylistSidebar {
  @StorageLink('themeIsDark') isDark: boolean = true
  /** 歌单列表 */
  @Prop playlists: LocalPlaylist[] = []
  /** 当前选中歌单 id */
  @Prop selectedId: string = ''
  /** 新建歌单 */
  onCreate: () => void = () => {}
  /** 选择歌单 */
  onSelect: (id: string) => void = (id: string) => {}
  /** 重命名歌单（携带 id） */
  onRename: (id: string) => void = (id: string) => {}
  /** 删除歌单（携带 id） */
  onDelete: (id: string) => void = (id: string) => {}
  /** 移动歌单位置（携带 id 与方向：-1 上移 / 1 下移） */
  onMove: (id: string, direction: number) => void = (id: string, direction: number) => {}
  /** 边框位置：true=左侧（右侧面板时），false=右侧（左侧面板时） */
  @Prop borderOnLeft: boolean = false
  /** 是否有详情区展开（展开时显示分隔竖线，未展开时不显示） */
  @Prop hasDetail: boolean = false

  /** 长按操作菜单（成员保持引用，避免 controller 被 GC） */
  private actionMenuController: CustomDialogController | null = null
  /** 被长按的歌单 id */
  private longPressedId: string = ''

  private get primaryText(): ResourceColor { return ThemeColors.primaryText(this.isDark) }
  private get secondaryText(): ResourceColor { return ThemeColors.secondaryText(this.isDark) }
  private get accentColor(): ResourceColor { return ThemeColors.accentColor() }
  private get activeBg(): ResourceColor { return ThemeColors.playlistActiveBg(this.isDark) }
  private get sidebarBg(): ResourceColor { return ThemeColors.sidebarBg(this.isDark) }
  private get borderFaint(): ResourceColor { return ThemeColors.borderFaint(this.isDark) }

  build() {
    Column() {
      Row() {
        Text('歌单')
          .fontSize(16).fontWeight(FontWeight.Bold).fontColor(this.primaryText)
        Blank()
        Text('+')
          .fontSize(20).fontColor(this.accentColor)
          .onClick(() => { this.onCreate() })
      }
      .width('100%')
      .padding({ left: 12, right: 12, top: 16, bottom: 8 })

      List({ space: 2 }) {
        ForEach(this.playlists, (pl: LocalPlaylist) => {
          ListItem() {
            Row() {
              Column({ space: 2 }) {
                Text(pl.name)
                  .fontSize(13)
                  .fontColor(this.selectedId === pl.id ? this.accentColor : this.primaryText)
                  .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
                Text(`${pl.songs.length} 首`)
                  .fontSize(10).fontColor(this.secondaryText)
              }
              .layoutWeight(1)
            }
            .width('100%')
            .padding({ left: 12, right: 12, top: 10, bottom: 10 })
            .borderRadius(8)
            .backgroundColor(this.selectedId === pl.id ? this.activeBg : Color.Transparent)
            .onClick(() => { this.onSelect(pl.id) })
            .gesture(
              LongPressGesture()
                .onAction((event: GestureEvent) => { this.openActionMenu(pl.id, event) })
            )
          }
        })
      }
      .width('100%').layoutWeight(1)
    }
    .width('100%')
    .height('100%')
    .backgroundColor(this.sidebarBg)
    .backdropBlur(20)
    .border(this.hasDetail
      ? (this.borderOnLeft ? { width: { left: 0.5 }, color: this.borderFaint } : { width: { right: 0.5 }, color: this.borderFaint })
      : { width: 0, color: Color.Transparent })
  }

  /** 长按歌单：在长按位置弹出自定义操作菜单 */
  private openActionMenu(playlistId: string, event: GestureEvent): void {
    this.longPressedId = playlistId
    const pl = this.playlists.find(p => p.id === playlistId)
    const pos = DialogPosUtils.fromGesture(event)
    const width = 280
    const maxX = DialogPosUtils.screenWidth() - width - 8
    const dx = pos.x > maxX ? maxX : pos.x
    this.actionMenuController = new CustomDialogController({
      builder: PlaylistActionMenu({
        playlistName: pl?.name ?? '',
        onAction: (action: string) => { this.handleAction(action) }
      }),
      autoCancel: true,
      alignment: DialogAlignment.TopStart,
      offset: { dx: dx, dy: pos.y },
      customStyle: true
    })
    this.actionMenuController.open()
  }

  private handleAction(action: string): void {
    const id = this.longPressedId
    if (action === 'rename') {
      this.onRename(id)
    } else if (action === 'up') {
      this.onMove(id, -1)
    } else if (action === 'down') {
      this.onMove(id, 1)
    } else if (action === 'delete') {
      this.onDelete(id)
    }
  }
}
