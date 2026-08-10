import { PlaylistManager } from 'hsp_playlist'
import { PlayerEngine } from 'hsp_player'
import { SourceManager } from 'hsp_source'
import { LocalPlaylist, MusicItem, SourceType, MusicQuality, DownloadUtils } from 'common'
import { PlaylistNameDialog } from '../components/PlaylistNameDialog'
import { MusicItemView } from '../components/MusicItemView'
import { PlaylistSidebar } from '../components/playlist/PlaylistSidebar'
import { PlaylistHeader } from '../components/playlist/PlaylistHeader'
import { SongActionMenu } from '../components/common/SongActionMenu'
import { SongPositionDialog } from '../components/playlist/SongPositionDialog'
import { PlaylistPickerDialog } from '../components/common/PlaylistPickerDialog'
import { SourcePickerDialog } from '../components/common/SourcePickerDialog'
import { AppActionDialog, AppDialogAction } from '../components/common/AppActionDialog'
import { DialogPosition, DialogPosUtils } from '../utils/DialogPosUtils'
import { ThemeColors } from '../theme/ThemeColors'
import { pasteboard } from '@kit.BasicServicesKit'
import { systemShare } from '@kit.ShareKit'
import { uniformTypeDescriptor } from '@kit.ArkData'
import { common } from '@kit.AbilityKit'
import { picker, fileIo } from '@kit.CoreFileKit'
import { util } from '@kit.ArkTS'
import { MotionTokens } from '../theme/MotionTokens'

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
  /** 导航到搜索页面回调 */
  onNavigateSearch: (keyword: string) => void = (keyword: string) => {}
  private playlistMgr: PlaylistManager = PlaylistManager.getInstance()
  private refreshTimer: number = -1
  private nameDialog: CustomDialogController | null = null
  /** 重命名对话框（成员保持引用，避免局部 controller 被 GC） */
  private renameDialog: CustomDialogController | null = null
  private actionDialogController: CustomDialogController | null = null
  private songActionController: CustomDialogController | null = null
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
      // 对比 updatedAt 和 name 等元数据变化（之前仅比较数量和歌曲数，漏掉重命名）
      let changed = latest.length !== this.playlists.length
      if (!changed) {
        for (let i = 0; i < latest.length; i++) {
          if (latest[i].updatedAt !== this.playlists[i].updatedAt ||
              latest[i].name !== this.playlists[i].name ||
              latest[i].songs.length !== this.playlists[i].songs.length) {
            changed = true
            break
          }
        }
      }
      if (changed) {
        this.playlists = latest
      }
      if (this.selectedPlaylistId) {
        const updated = this.playlistMgr.getById(this.selectedPlaylistId)
        // 用新对象引用触发 @State 变更（原地修改同名属性不会触发 ArkUI 刷新）
        if (updated) {
          this.playlist = {
            id: updated.id,
            name: updated.name,
            description: updated.description,
            songs: updated.songs,
            createdAt: updated.createdAt,
            updatedAt: updated.updatedAt
          }
        } else {
          this.playlist = null
        }
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
            const updated = this.playlistMgr.getById(pl.id)
            // 用新对象引用确保 ArkUI @State 立即刷新（原地修改同名属性不触发）
            if (updated) {
              this.playlist = {
                id: updated.id,
                name: updated.name,
                description: updated.description,
                songs: updated.songs,
                createdAt: updated.createdAt,
                updatedAt: updated.updatedAt
              }
            } else {
              this.playlist = null
            }
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

  /** 长按歌曲：弹出操作菜单 */
  private showSongActionMenu(song: MusicItem, index: number, event: GestureEvent): void {
    const pl = this.playlist
    if (!pl) return
    const pos = DialogPosUtils.fit(DialogPosUtils.fromGesture(event), 300, 500)
    // 存储当前长按上下文，供回调使用
    const contextIndex = index
    const contextSong = song
    this.songActionController = new CustomDialogController({
      builder: SongActionMenu({
        song: song,
        isFavorited: false,
        actions: ['playlist', 'nextPlay', 'favorite', 'download', 'share',
          'sourceSwitch', 'searchSinger', 'searchSong', 'copyName',
          'setPosition', 'remove'],
        onAction: (action: string, clickEvent: ClickEvent) => {
          this.handleSongAction(action, clickEvent, contextSong, contextIndex)
        }
      }),
      autoCancel: true,
      alignment: DialogAlignment.TopStart,
      offset: { dx: pos.x, dy: pos.y },
      customStyle: true
    })
    this.songActionController.open()
  }

  /** 处理歌曲操作菜单回调 */
  private handleSongAction(action: string, event: ClickEvent, song: MusicItem, index: number): void {
    const pl = this.playlist
    const toast = this.getUIContext().getPromptAction()
    if (action === 'playlist') {
      this.showSongPlaylistPicker(song, event)
    } else if (action === 'nextPlay') {
      PlayerEngine.getInstance().queue.insertAt(song, PlayerEngine.getInstance().queue.currentIndex + 1)
      toast.showToast({ message: '已设为下一首播放', duration: 1200 })
    } else if (action === 'favorite') {
      PlaylistManager.getInstance().toggleFavorite(song).then((fav: boolean) => {
        toast.showToast({ message: fav ? '已收藏' : '已取消收藏', duration: 1200 })
        this.playlists = this.playlistMgr.getAll()
      })
    } else if (action === 'download') {
      this.downloadSongFromPlaylist(song)
    } else if (action === 'share') {
      this.shareSongFromPlaylist(song)
    } else if (action === 'sourceSwitch') {
      this.switchSongSourceInPlaylist(song, event)
    } else if (action === 'searchSinger') {
      this.onNavigateSearch(song.singer)
    } else if (action === 'searchSong') {
      this.onNavigateSearch(song.name)
    } else if (action === 'copyName') {
      try {
        const data = pasteboard.createData(pasteboard.MIMETYPE_TEXT_PLAIN, `${song.name} - ${song.singer}`)
        pasteboard.getSystemPasteboard().setData(data)
        toast.showToast({ message: '已复制歌曲名', duration: 1200 })
      } catch (err) {
        toast.showToast({ message: '复制失败', duration: 1200 })
      }
    } else if (action === 'setPosition') {
      this.showSongPositionDialog(song, index, event)
    } else if (action === 'remove' && pl) {
      PlaylistManager.getInstance().removeSongs(pl.id, [index]).then(() => {
        this.playlist = PlaylistManager.getInstance().getById(pl.id) ?? null
        this.playlists = this.playlistMgr.getAll()
        toast.showToast({ message: '已从歌单移除', duration: 1200 })
      })
    }
  }

  /** 序号输入对话框 */
  private showSongPositionDialog(song: MusicItem, index: number, event: ClickEvent): void {
    const pl = this.playlist
    if (!pl) return
    this.dialogPosition = DialogPosUtils.fromClickForDialog(event, 300, 280)
    const ctrl = new CustomDialogController({
      builder: SongPositionDialog({
        songName: song.name,
        currentPosition: index + 1,
        totalSongs: pl.songs.length,
        onConfirm: (targetIndex: number) => {
          PlaylistManager.getInstance().moveSong(pl.id, index, targetIndex).then(() => {
            this.playlist = PlaylistManager.getInstance().getById(pl.id) ?? null
            this.playlists = this.playlistMgr.getAll()
          })
        }
      }),
      autoCancel: true,
      alignment: DialogAlignment.TopStart,
      offset: { dx: this.dialogPosition.x, dy: this.dialogPosition.y },
      customStyle: true
    })
    ctrl.open()
  }

  /** 添加到歌单选择器 */
  private showSongPlaylistPicker(song: MusicItem, event: ClickEvent): void {
    const playlists = this.playlistMgr.getAll()
    const height = Math.min(500, 120 + (playlists.length + 1) * 52)
    const pos = DialogPosUtils.fromClickForDialog(event, 300, height)
    const ctrl = new CustomDialogController({
      builder: PlaylistPickerDialog({
        song: song,
        playlists: playlists,
        onPick: (id: string, pickEvent: ClickEvent) => {
          if (id === 'new') {
            setTimeout(() => { this.showCreateDialog(pickEvent) }, 200)
            return
          }
          const target = playlists.find((item: LocalPlaylist) => item.id === id)
          PlaylistManager.getInstance().addSongs(id, [song]).then((ok: boolean) => {
            this.getUIContext().getPromptAction().showToast({
              message: ok ? `已添加到「${target?.name ?? '歌单'}」` : '添加失败',
              duration: 1200
            })
          })
        }
      }),
      autoCancel: true,
      alignment: DialogAlignment.TopStart,
      offset: { dx: pos.x, dy: pos.y },
      customStyle: true
    })
    ctrl.open()
  }

  /** 歌曲换源选择器 */
  private async switchSongSourceInPlaylist(song: MusicItem, event: ClickEvent): Promise<void> {
    const toast = this.getUIContext().getPromptAction()
    const sources = await SourceManager.getInstance().getSearchSources()
    const searchSources = sources.filter((s) => s.info.id !== 'local_source' && s.info.id !== 'demo')
    if (searchSources.length <= 1) {
      toast.showToast({ message: '暂无可切换的搜索源', duration: 1500 })
      return
    }
    const pos = DialogPosUtils.fromClickForDialog(event, 320, 440)
    const ctrl = new CustomDialogController({
      builder: SourcePickerDialog({
        songName: song.name,
        searchSources: searchSources,
        currentSourceId: song.source,
        onPick: (sourceId: string) => {
          this.performSourceSwitch(song, sourceId)
        }
      }),
      autoCancel: true,
      alignment: DialogAlignment.TopStart,
      offset: { dx: pos.x, dy: pos.y },
      customStyle: true
    })
    ctrl.open()
  }

  private async performSourceSwitch(song: MusicItem, sourceId: string): Promise<void> {
    if (sourceId === song.source) {
      this.getUIContext().getPromptAction().showToast({ message: '已是当前音源', duration: 1500 })
      return
    }
    this.getUIContext().getPromptAction().showToast({ message: '正在切换音源...', duration: 1500 })
    const target = await SourceManager.getInstance().searchSameSongInSource(song, sourceId, '')
    if (!target) {
      this.getUIContext().getPromptAction().showToast({ message: '未找到可播放版本', duration: 1500 })
      return
    }
    PlaylistManager.getInstance().updateSongSource(song, target)
    this.playlists = this.playlistMgr.getAll()
    const pl = this.playlist
    if (pl) {
      this.playlist = PlaylistManager.getInstance().getById(pl.id) ?? null
    }
    this.getUIContext().getPromptAction().showToast({ message: '已切换音源', duration: 1500 })
  }

  /** 下载歌曲 */
  private async downloadSongFromPlaylist(song: MusicItem): Promise<void> {
    const toast = this.getUIContext().getPromptAction()
    toast.showToast({ message: '获取下载地址...', duration: 1500 })
    try {
      const info = await SourceManager.getInstance().getMusicInfoWithFallback(
        song.songmid, song.source, MusicQuality.HIGH, song)
      if (!info) { toast.showToast({ message: '获取下载地址失败', duration: 1500 }); return }
      const qualityKey = Object.keys(info.types)[0]
      const url = info.types[qualityKey]?.url ?? ''
      if (!url) { toast.showToast({ message: '暂无可用下载地址', duration: 1500 }); return }
      toast.showToast({ message: '开始下载...', duration: 1500 })
      const filePath = await DownloadUtils.downloadToLocal(song, url)
      if (filePath) { toast.showToast({ message: '下载完成', duration: 2000 }) }
      else { toast.showToast({ message: '下载失败', duration: 2000 }) }
    } catch (err) { toast.showToast({ message: '下载失败', duration: 2000 }) }
  }

  /** 分享歌曲 */
  private shareSongFromPlaylist(song: MusicItem): void {
    try {
      const data = new systemShare.SharedData({
        utd: uniformTypeDescriptor.UniformDataType.PLAIN_TEXT,
        content: `${song.name} - ${song.singer}`,
        title: '分享歌曲',
        description: `推荐一首歌：${song.name} - ${song.singer}`
      })
      const ctrl = new systemShare.ShareController(data)
      const hostCtx = this.getUIContext().getHostContext()
      if (hostCtx) {
        ctrl.show(hostCtx as common.UIAbilityContext, {
          selectionMode: systemShare.SelectionMode.SINGLE,
          previewMode: systemShare.SharePreviewMode.DEFAULT
        })
      }
    } catch (err) {
      this.getUIContext().getPromptAction().showToast({ message: '分享失败', duration: 1500 })
    }
  }

  /** 导入本地音频文件到歌单 */
  private async importLocalToPlaylist(playlistId: string, event: ClickEvent): Promise<void> {
    void event
    const pl = this.playlistMgr.getById(playlistId)
    if (!pl) return
    try {
      const documentPicker = new picker.DocumentViewPicker()
      const uris = await documentPicker.select({
        maxSelectNumber: 50,
        defaultFilePathUri: ''
      })
      if (!uris || uris.length === 0) return
      const songs: MusicItem[] = []
      for (let i = 0; i < uris.length; i++) {
        const uri = uris[i]
        const name = uri.substring(uri.lastIndexOf('/') + 1)
        const cleanName = decodeURIComponent(name).replace(/\.(mp3|flac|wav|ogg|aac|m4a|wma)$/i, '')
        songs.push({
          songmid: `local_${uri}`,
          name: cleanName,
          singer: '本地文件',
          albumName: '',
          interval: 0,
          imgUrl: '',
          lyricUrl: '',
          source: SourceType.LOCAL,
          types: { '320k': { url: uri, size: 0, br: 320 } }
        })
      }
      await PlaylistManager.getInstance().addSongs(playlistId, songs)
      this.playlists = this.playlistMgr.getAll()
      this.playlist = this.playlistMgr.getById(playlistId) ?? null
      this.getUIContext().getPromptAction().showToast({ message: `已导入 ${songs.length} 首本地歌曲`, duration: 1500 })
    } catch (err) {
      this.getUIContext().getPromptAction().showToast({ message: '导入取消或失败', duration: 1500 })
    }
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
                  Row({ space: 4 }) {
                    Text(`${index + 1}`)
                      .fontSize(11).fontColor(this.secondaryText)
                      .width(18).textAlign(TextAlign.Center)
                    MusicItemView({ song: song, queueSongs: this.playlist!.songs, showCover: false })
                      .layoutWeight(1)
                  }
                  .width('100%')
                }
                .swipeAction({ end: { builder: () => { this.DeleteSongBuilder(index) } } })
                .gesture(LongPressGesture({ repeat: false }).onAction((event: GestureEvent) => {
                  this.showSongActionMenu(song, index, event)
                }))
                .transition(TransitionEffect.OPACITY.animation({ duration: MotionTokens.LIST,
                  delay: MotionTokens.staggerDelay(index), curve: Curve.EaseOut })
                  .combine(TransitionEffect.translate({ x: 0, y: 10 })
                    .animation({ duration: MotionTokens.LIST, delay: MotionTokens.staggerDelay(index),
                      curve: Curve.FastOutSlowIn })))
              }, (song: MusicItem) => `${song.source}_${song.songmid}`)
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
            onMove: (id: string, direction: number) => { this.movePlaylist(id, direction) },
            onImportLocal: (id: string, event: ClickEvent) => { this.importLocalToPlaylist(id, event) }
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
                  Row({ space: 4 }) {
                    Text(`${index + 1}`)
                      .fontSize(11).fontColor(this.secondaryText)
                      .width(18).textAlign(TextAlign.Center)
                    MusicItemView({ song: song, queueSongs: this.playlist!.songs, showCover: false })
                      .layoutWeight(1)
                  }
                  .width('100%')
                }
                .swipeAction({ end: { builder: () => { this.DeleteSongBuilder(index) } } })
                .gesture(LongPressGesture({ repeat: false }).onAction((event: GestureEvent) => {
                  this.showSongActionMenu(song, index, event)
                }))
                .transition(TransitionEffect.OPACITY.animation({ duration: MotionTokens.LIST,
                  delay: MotionTokens.staggerDelay(index), curve: Curve.EaseOut })
                  .combine(TransitionEffect.translate({ x: 0, y: 10 })
                    .animation({ duration: MotionTokens.LIST, delay: MotionTokens.staggerDelay(index),
                      curve: Curve.FastOutSlowIn })))
              }, (song: MusicItem) => `${song.source}_${song.songmid}`)
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
            onMove: (id: string, direction: number) => { this.movePlaylist(id, direction) },
            onImportLocal: (id: string, event: ClickEvent) => { this.importLocalToPlaylist(id, event) }
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
    const archiveJson = PlaylistManager.getInstance().exportArchive(this.selectedPlaylistId)
    if (!archiveJson) {
      this.showInfoDialog('导出失败', '歌单不存在或为空')
      return
    }
    try {
      const documentPicker = new picker.DocumentViewPicker()
      const saveResult = await documentPicker.save({ newFileNames: [`${this.playlist?.name ?? '歌单'}.json`] })
      const saveUri = saveResult && saveResult.length > 0 ? saveResult[0] : ''
      if (saveUri) {
        const file = fileIo.openSync(saveUri, fileIo.OpenMode.READ_WRITE | fileIo.OpenMode.CREATE)
        // 歌单归档为纯 JSON 文本。
        const encoder = new util.TextEncoder()
        const buffer = encoder.encodeInto(archiveJson)
        fileIo.writeSync(file.fd, buffer)
        fileIo.closeSync(file)
        this.showToast('歌单已导出为 JSON 文件')
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
