import { PlaylistManager } from 'hsp_playlist'
import { PlayerEngine } from 'hsp_player'
import { LocalPlaylist, MusicItem } from 'common'
import { PlaylistNameDialog } from '../components/PlaylistNameDialog'
import { MusicItemView } from '../components/MusicItemView'
import { PlaylistSidebar } from '../components/playlist/PlaylistSidebar'
import { PlaylistHeader } from '../components/playlist/PlaylistHeader'
import { AppActionDialog, AppDialogAction } from '../components/common/AppActionDialog'
import { DialogPosition, DialogPosUtils } from '../utils/DialogPosUtils'
import { picker, fileIo } from '@kit.CoreFileKit'
import { util } from '@kit.ArkTS'

@Component
export struct PlaylistListContent {
  @StorageLink('themeIsDark') isDark: boolean = true
  @State playlists: LocalPlaylist[] = []
  @State selectedPlaylistId: string = ''
  @State playlist: LocalPlaylist | null = null
  /** 选中状态变化回调（通知外部调整面板宽度） */
  onSelectionChange: (hasSelection: boolean) => void = (hasSelection: boolean) => {}
  /** 面板方向：'left'（侧栏在左）或 'right'（侧栏在右，详情向左展开） */
  @Prop panelSide: string = 'left'
  /** 竖屏模式：进入时默认打开第一个歌单 */
  @Prop portrait: boolean = false
  private playlistMgr: PlaylistManager = PlaylistManager.getInstance()
  private refreshTimer: number = -1
  private nameDialog: CustomDialogController | null = null
  /** 重命名对话框（成员保持引用，避免局部 controller 被 GC） */
  private renameDialog: CustomDialogController | null = null
  private actionDialogController: CustomDialogController | null = null
  private dialogPosition: DialogPosition = new DialogPosition()

  aboutToAppear(): void {
    this.playlists = this.playlistMgr.getAll()
    // 竖屏模式：默认打开第一个歌单
    if (this.portrait && this.playlists.length > 0) {
      this.selectPlaylist(this.playlists[0].id)
    } else {
      this.onSelectionChange(false)
    }
    // 面板可见期间轮询刷新（收藏/播放等操作后计数自动更新）
    this.refreshTimer = setInterval(() => {
      const latest = this.playlistMgr.getAll()
      if (latest.length !== this.playlists.length) {
        this.playlists = latest
      } else {
        for (let i = 0; i < latest.length; i++) {
          if (latest[i].songs.length !== this.playlists[i].songs.length) {
            this.playlists = latest
            break
          }
        }
      }
      if (this.selectedPlaylistId) {
        this.playlist = this.playlistMgr.getById(this.selectedPlaylistId) ?? null
      }
    }, 3000)
  }

  aboutToDisappear(): void {
    if (this.refreshTimer >= 0) {
      clearInterval(this.refreshTimer)
      this.refreshTimer = -1
    }
  }

  private get primaryText(): ResourceColor { return this.isDark ? '#e8e0f8' : '#1a1525' }
  private get secondaryText(): ResourceColor { return this.isDark ? '#7a6f98' : '#6b6088' }
  private get cardBg(): ResourceColor { return this.isDark ? '#50181525' : '#c0ffffff' }

  private selectPlaylist(id: string): void {
    this.selectedPlaylistId = id
    this.playlist = this.playlistMgr.getById(id) ?? null
    this.onSelectionChange(this.playlist !== null)
  }

  /** 长按菜单：重命名（先选中该歌单） */
  private showCreateDialog(event: ClickEvent): void {
    this.dialogPosition = DialogPosUtils.fromClickForDialog(event, 300, 220)
    this.nameDialog = new CustomDialogController({
      builder: PlaylistNameDialog({
        placeholder: '请输入歌单名称',
        onConfirm: (name: string) => {
          this.playlistMgr.create(name, '').then(() => { this.playlists = this.playlistMgr.getAll() })
        }
      }),
      autoCancel: true,
      alignment: DialogAlignment.TopStart,
      offset: { dx: this.dialogPosition.x, dy: this.dialogPosition.y },
      customStyle: true
    })
    this.nameDialog.open()
  }

  private renamePlaylist(id: string, event: ClickEvent): void {
    this.selectPlaylist(id)
    const pl = this.playlist
    if (!pl) return
    this.dialogPosition = DialogPosUtils.fromClickForDialog(event, 300, 220)
    // 成员变量保持引用，避免局部 controller 被 GC 后对话框内 this.controller 失效
    this.renameDialog = new CustomDialogController({
      builder: PlaylistNameDialog({
        title: '重命名歌单',
        confirmText: '保存',
        placeholder: pl.name,
        defaultValue: pl.name,
        onConfirm: (name: string) => {
          PlaylistManager.getInstance().update(pl.id, name).then(() => {
            this.playlists = this.playlistMgr.getAll()
            this.playlist = this.playlistMgr.getById(pl.id) ?? null
          })
        }
      }),
      autoCancel: true,
      alignment: DialogAlignment.TopStart,
      offset: { dx: this.dialogPosition.x, dy: this.dialogPosition.y },
      customStyle: true
    })
    this.renameDialog.open()
  }

  /** 长按菜单：删除（先选中该歌单） */
  private deletePlaylist(id: string, event: ClickEvent): void {
    this.selectPlaylist(id)
    const actions: AppDialogAction[] = [{ id: 'delete', label: '确认删除', danger: true }]
    this.showActionDialog('删除歌单', `确定删除歌单「${this.playlist?.name}」吗？`, actions,
      (actionId: string, actionEvent: ClickEvent) => {
      void actionEvent
      if (actionId !== 'delete') return
      this.playlistMgr.delete(id).then(() => {
        this.playlists = this.playlistMgr.getAll()
        this.selectedPlaylistId = ''
        this.playlist = null
        this.onSelectionChange(false)
      })
    }, event)
  }

  /** 长按菜单：移动排序（direction: -1 上移 / 1 下移） */
  private movePlaylist(id: string, direction: number): void {
    this.playlistMgr.movePlaylist(id, direction).then(() => {
      this.playlists = this.playlistMgr.getAll()
    })
  }

  build() {
    if (this.panelSide === 'right') {
      // 右侧面板：未选中时侧栏占满整个面板；选中后侧栏贴右缘固定 160，详情在左展开
      Stack({ alignContent: Alignment.End }) {
        if (this.playlist) {
          Column() {
            PlaylistHeader({
              playlist: this.playlist,
              onExport: (event: ClickEvent) => { this.exportPlaylist(event) },
              onPlayAll: () => {
                const target = this.playlist
                if (!target) return
                PlayerEngine.getInstance().queue.replaceList(target.songs)
                PlayerEngine.getInstance().playCurrent()
              }
            })

            List({ space: 4 }) {
              ForEach(this.playlist.songs, (song: MusicItem, index: number) => {
                ListItem() {
                  MusicItemView({ song: song, queueSongs: this.playlist!.songs })
                }
                .swipeAction({ end: { builder: () => { this.DeleteSongBuilder(index) } } })
              })
            }
            .width('100%').layoutWeight(1)
            .padding({ left: 12, right: 12 })
          }
          .width('100%')
          .height('100%')
          .padding({ right: 160 })
          .transition(TransitionEffect.OPACITY.animation({ duration: 350, curve: Curve.FastOutSlowIn })
            .combine(TransitionEffect.translate({ x: 20, y: 0 }).animation({ duration: 350, curve: Curve.FastOutSlowIn })))
        }

        Column() {
          PlaylistSidebar({
            playlists: this.playlists,
            selectedId: this.selectedPlaylistId,
            borderOnLeft: true,
            hasDetail: this.playlist !== null,
            onCreate: (event: ClickEvent) => { this.showCreateDialog(event) },
            onSelect: (id: string) => { this.selectPlaylist(id) },
            onRename: (id: string, event: ClickEvent) => { this.renamePlaylist(id, event) },
            onDelete: (id: string, event: ClickEvent) => { this.deletePlaylist(id, event) },
            onMove: (id: string, direction: number) => { this.movePlaylist(id, direction) }
          })
        }
        .width(160)
        .height('100%')
      }
      .width('100%').height('100%')
      .clip(true)
    } else {
      // 左侧面板：未选中时侧栏占满面板；选中后侧栏贴左缘固定 160，详情在右展开
      // 注意层级：详情区（width 100%）在下层，侧栏在上层，避免详情拦截侧栏点击
      Stack({ alignContent: Alignment.Start }) {
        if (this.playlist) {
          Column() {
            PlaylistHeader({
              playlist: this.playlist,
              onExport: (event: ClickEvent) => { this.exportPlaylist(event) },
              onPlayAll: () => {
                const target = this.playlist
                if (!target) return
                PlayerEngine.getInstance().queue.replaceList(target.songs)
                PlayerEngine.getInstance().playCurrent()
              }
            })

            List({ space: 4 }) {
              ForEach(this.playlist.songs, (song: MusicItem, index: number) => {
                ListItem() {
                  MusicItemView({ song: song, queueSongs: this.playlist!.songs })
                }
                .swipeAction({ end: { builder: () => { this.DeleteSongBuilder(index) } } })
              })
            }
            .width('100%').layoutWeight(1)
            .padding({ left: 12, right: 12 })
          }
          .width('100%')
          .height('100%')
          .padding({ left: 160 })
          .transition(TransitionEffect.OPACITY.animation({ duration: 350, curve: Curve.FastOutSlowIn })
            .combine(TransitionEffect.translate({ x: -20, y: 0 }).animation({ duration: 350, curve: Curve.FastOutSlowIn })))
        }

        Column() {
          PlaylistSidebar({
            playlists: this.playlists,
            selectedId: this.selectedPlaylistId,
            borderOnLeft: false,
            hasDetail: this.playlist !== null,
            onCreate: (event: ClickEvent) => { this.showCreateDialog(event) },
            onSelect: (id: string) => { this.selectPlaylist(id) },
            onRename: (id: string, event: ClickEvent) => { this.renamePlaylist(id, event) },
            onDelete: (id: string, event: ClickEvent) => { this.deletePlaylist(id, event) },
            onMove: (id: string, direction: number) => { this.movePlaylist(id, direction) }
          })
        }
        .width(160)
        .height('100%')
      }
      .width('100%').height('100%')
      .clip(true)
    }
  }

  @Builder
  DeleteSongBuilder(index: number) {
    Text('删除')
      .fontSize(13).fontColor('#0e0c18')
      .backgroundColor('#e86090')
      .padding({ left: 16, right: 16, top: 8, bottom: 8 })
      .borderRadius(8)
      .onClick(() => {
        PlaylistManager.getInstance().removeSongs(this.selectedPlaylistId, [index]).then(() => {
          this.playlist = PlaylistManager.getInstance().getById(this.selectedPlaylistId) ?? null
          this.playlists = this.playlistMgr.getAll()
        })
      })
  }

  private async exportPlaylist(event: ClickEvent): Promise<void> {
    this.dialogPosition = DialogPosUtils.fromClickForDialog(event, 320, 180)
    const lxmc = PlaylistManager.getInstance().exportToLxmc(this.selectedPlaylistId)
    if (!lxmc) {
      this.showInfoDialog('导出失败', '歌单不存在或为空')
      return
    }
    try {
      const documentPicker = new picker.DocumentViewPicker()
      const saveResult = await documentPicker.save({ newFileNames: [`${this.playlist?.name ?? '歌单'}.lxmc`] })
      const saveUri = saveResult && saveResult.length > 0 ? saveResult[0] : ''
      if (saveUri) {
        const file = fileIo.openSync(saveUri, fileIo.OpenMode.READ_WRITE | fileIo.OpenMode.CREATE)
        // .lxmc 为纯 JSON 文本
        const encoder = new util.TextEncoder()
        const buffer = encoder.encodeInto(lxmc)
        fileIo.writeSync(file.fd, buffer)
        fileIo.closeSync(file)
        this.showToast('歌单已导出为 .lxmc 文件')
      }
    } catch (err) {
      this.showInfoDialog('导出失败', JSON.stringify(err))
    }
  }

  private showToast(msg: string): void {
    this.getUIContext().getPromptAction().showToast({ message: msg, duration: 1500 })
  }

  private showActionDialog(
    title: string,
    message: string,
    actions: AppDialogAction[],
    onAction: (actionId: string, event: ClickEvent) => void,
    event?: ClickEvent
  ): void {
    if (event) {
      this.dialogPosition = DialogPosUtils.fromClickForDialog(event, 320, 100 + actions.length * 52)
    }
    this.actionDialogController = new CustomDialogController({
      builder: AppActionDialog({
        title: title,
        message: message,
        actions: actions,
        onAction: onAction
      }),
      autoCancel: true,
      alignment: DialogAlignment.TopStart,
      offset: { dx: this.dialogPosition.x, dy: this.dialogPosition.y },
      customStyle: true
    })
    this.actionDialogController.open()
  }

  private showInfoDialog(title: string, message: string): void {
    const actions: AppDialogAction[] = [{ id: 'ok', label: '知道了' }]
    this.showActionDialog(title, message, actions, (actionId: string, event: ClickEvent) => {
      void actionId
      void event
    })
  }
}
