import { PlayerEngine } from 'hsp_player'
import { PlaylistManager } from 'hsp_playlist'
import { SourceManager } from 'hsp_source'
import { systemShare } from '@kit.ShareKit'
import { uniformTypeDescriptor as utd } from '@kit.ArkData'
import { common } from '@kit.AbilityKit'
import {
  PlayerStatus,
  PlayMode,
  LyricLine,
  MusicItem,
  LocalPlaylist,
  MusicQuality,
  DownloadUtils
} from 'common'
import { LyricView } from '../LyricView'
import { PlayerSection } from './PlayerSection'
import { PlayerControls } from './PlayerControls'
import { SongActionMenu } from '../common/SongActionMenu'
import { PlaylistPickerDialog } from '../common/PlaylistPickerDialog'
import { DialogPosUtils } from '../../utils/DialogPosUtils'
import { ThemeColors } from '../../theme/ThemeColors'

/**
 * 播放面板组件（主区域右侧）
 *
 * 组合歌曲信息区（PlayerSection）与歌词区（LyricView），
 * 自持 500ms 轮询 PlayerEngine 同步播放状态。
 */
@Component
export struct NowPlayingPanel {
  @StorageLink('themeIsDark') isDark: boolean = true
  @State currentSongName: string = '未在播放'
  @State currentSinger: string = '选择一首歌曲开始播放吧~'
  @State status: PlayerStatus = PlayerStatus.IDLE
  @State currentProgress: number = 0
  @State duration: number = 0
  @State lyrics: LyricLine[] = []
  @State mode: PlayMode = PlayMode.SEQUENCE
  @State coverUrl: string = ''
  @State coverLoadFailed: boolean = false
  @State isSeeking: boolean = false
  @State isFavorited: boolean = false
  @StorageLink('lyricShowTranslation') lyricShowTranslation: boolean = true
  @StorageLink('lyricFontSize') lyricFontSize: number = 14
  @State isDownloading: boolean = false
  /** 纵向滑动切歌偏移（跟手）：歌曲区内容上划、控制区反向位移 */
  @State swipeOffset: number = 0
  /** 滑动/动画进行中：临时关闭毛玻璃模糊与阴影以提升流畅度 */
  @State isSwiping: boolean = false
  private player: PlayerEngine = PlayerEngine.getInstance()
  private syncTimer: number = -1
  private lastSongKey: string = ''
  private dragStartY: number = 0
  private actionMenuController: CustomDialogController = new CustomDialogController({
    builder: SongActionMenu({
      song: null,
      isFavorited: false,
      onAction: (action: string, event: ClickEvent) => { this.handleSongAction(action, event) }
    }),
    autoCancel: true,
    alignment: DialogAlignment.Center,
    customStyle: true
  })
  /** 添加歌单弹窗（成员保持引用） */
  private pickerController: CustomDialogController | null = null

  private get accentColor(): ResourceColor { return ThemeColors.accentColor() }
  private get glassBg(): ResourceColor { return ThemeColors.glassBg(this.isDark) }
  private get borderFaint(): ResourceColor { return ThemeColors.borderFaint(this.isDark) }

  aboutToAppear(): void {
    this.syncTimer = setInterval(() => {
      this.refreshSongInfo()
    }, 500)
  }

  aboutToDisappear(): void {
    if (this.syncTimer >= 0) { clearInterval(this.syncTimer); this.syncTimer = -1 }
  }

  /** 从播放器拉取歌曲信息刷新面板状态 */
  private refreshSongInfo(): void {
    const song = this.player.currentSong
    this.currentSongName = song?.name ?? '未在播放'
    this.currentSinger = song?.singer ?? '选择一首歌曲开始播放吧~'
    this.status = this.player.status
    if (!this.isSeeking) {
      const p = this.player.currentProgress
      this.currentProgress = isNaN(p) ? 0 : p
    }
    const d = this.player.duration
    this.duration = isNaN(d) ? 0 : d
    this.lyrics = this.player.lyrics
    this.mode = this.player.queue.mode
    this.coverUrl = song?.imgUrl ?? ''
    this.coverLoadFailed = false
    // 歌曲变化时刷新收藏状态与光感取色（避免每次轮询都查）
    const key = song ? `${song.source}_${song.songmid}` : ''
    if (key !== this.lastSongKey) {
      this.lastSongKey = key
      this.syncFavoriteState(song)
    }
  }

  private syncFavoriteState(song: MusicItem | null): void {
    if (!song) {
      this.isFavorited = false
      return
    }
    PlaylistManager.getInstance().isFavorited(song).then((fav: boolean) => {
      this.isFavorited = fav
    }).catch(() => {
      this.isFavorited = false
    })
  }

  /**
   * 纵向滑动切歌：上滑下一首、下滑上一首。
   * 动画：内容区上划滑出 → 切歌（偏移瞬间翻转到对侧，内容在屏幕外）→ 新内容滑入归位，
   * 控制区始终反向位移（相对内容整体下移）。
   */
  private handleVerticalSwipe(): void {
    // swipeOffset > 0 = 下滑（上一首），< 0 = 上滑（下一首）
    if (this.swipeOffset > 90) {
      animateTo({ duration: 180, curve: Curve.EaseOut }, () => {
        this.swipeOffset = 260
      })
      setTimeout(() => {
        this.swipeOffset = -260
        this.player.previous()
        this.refreshSongInfo()
        animateTo({ duration: 320, curve: Curve.FastOutSlowIn }, () => {
          this.swipeOffset = 0
        })
        setTimeout(() => { this.isSwiping = false }, 340)
      }, 180)
    } else if (this.swipeOffset < -90) {
      animateTo({ duration: 180, curve: Curve.EaseOut }, () => {
        this.swipeOffset = -260
      })
      setTimeout(() => {
        this.swipeOffset = 260
        this.player.next()
        this.refreshSongInfo()
        animateTo({ duration: 320, curve: Curve.FastOutSlowIn }, () => {
          this.swipeOffset = 0
        })
        setTimeout(() => { this.isSwiping = false }, 340)
      }, 180)
    } else {
      // 回弹
      animateTo({ duration: 250, curve: Curve.Friction }, () => {
        this.swipeOffset = 0
      })
      setTimeout(() => { this.isSwiping = false }, 260)
    }
  }

  private async toggleFavorite(): Promise<void> {
    const song = this.player.currentSong
    if (!song) return
    try {
      const fav = await PlaylistManager.getInstance().toggleFavorite(song)
      this.isFavorited = fav
      this.getUIContext().getPromptAction().showToast({
        message: fav ? '已收藏' : '已取消收藏',
        duration: 1200
      })
    } catch (err) {
      this.getUIContext().getPromptAction().showToast({ message: '收藏失败', duration: 1200 })
    }
  }

  private async downloadSong(): Promise<void> {
    const song = this.player.currentSong
    if (!song || this.isDownloading) return
    this.isDownloading = true
    const toast = this.getUIContext().getPromptAction()
    toast.showToast({ message: '获取下载地址...', duration: 1500 })
    try {
      const sourceMgr = SourceManager.getInstance()
      const info = await sourceMgr.getMusicInfoWithFallback(song.songmid, song.source, MusicQuality.HIGH, song)
      if (!info) {
        toast.showToast({ message: '获取下载地址失败', duration: 1500 })
        this.isDownloading = false
        return
      }
      const qualityKey = Object.keys(info.types)[0]
      const playUrl = info.types[qualityKey]?.url ?? ''
      if (!playUrl) {
        toast.showToast({ message: '暂无可用下载地址', duration: 1500 })
        this.isDownloading = false
        return
      }
      toast.showToast({ message: '开始下载...', duration: 1500 })
      const filePath = await DownloadUtils.downloadToLocal(song, playUrl)
      this.isDownloading = false
      if (filePath) {
        toast.showToast({ message: '下载完成', duration: 2000 })
      } else {
        toast.showToast({ message: '下载失败，请重试', duration: 2000 })
      }
    } catch (err) {
      this.isDownloading = false
      toast.showToast({ message: '下载失败，请重试', duration: 2000 })
    }
  }

  /** 更多菜单：在点击位置弹出自定义操作菜单 */
  private showMoreMenu(event: ClickEvent): void {
    const song = this.player.currentSong
    if (!song) return
    const pos = DialogPosUtils.fromClickForDialog(event, 300, 390)
    this.actionMenuController = new CustomDialogController({
      builder: SongActionMenu({
        song: song,
        isFavorited: this.isFavorited,
        onAction: (action: string, actionEvent: ClickEvent) => { this.handleSongAction(action, actionEvent) }
      }),
      autoCancel: true,
      alignment: DialogAlignment.TopStart,
      offset: { dx: pos.x, dy: pos.y },
      customStyle: true
    })
    this.actionMenuController.open()
  }

  /** 处理操作菜单回调 */
  private handleSongAction(action: string, event: ClickEvent): void {
    const song = this.player.currentSong
    if (!song) return
    if (action === 'playlist') {
      this.addToPlaylist(song, event)
    } else if (action === 'next') {
      this.player.queue.insertAt(song, this.player.queue.currentIndex + 1)
      this.getUIContext().getPromptAction().showToast({ message: '已设为下一首播放', duration: 1200 })
    } else if (action === 'favorite') {
      this.toggleFavorite()
    } else if (action === 'download') {
      this.downloadSong()
    } else if (action === 'share') {
      this.shareSong(song)
    }
  }

  /** 分享歌曲（拉起系统分享面板，发送歌名+歌手文本） */
  private shareSong(song: MusicItem): void {
    try {
      const data: systemShare.SharedData = new systemShare.SharedData({
        utd: utd.UniformDataType.PLAIN_TEXT,
        content: `${song.name} - ${song.singer}`,
        title: '分享歌曲',
        description: `推荐一首歌：${song.name} - ${song.singer}`
      })
      const controller: systemShare.ShareController = new systemShare.ShareController(data)
      const hostContext = this.getUIContext().getHostContext()
      if (hostContext) {
        const options: systemShare.ShareControllerOptions = {
          selectionMode: systemShare.SelectionMode.SINGLE,
          previewMode: systemShare.SharePreviewMode.DEFAULT
        }
        controller.show(hostContext as common.UIAbilityContext, options).then(() => {}).catch((err: Error) => {
          this.getUIContext().getPromptAction().showToast({ message: '分享面板打开失败', duration: 1200 })
        })
      }
    } catch (err) {
      this.getUIContext().getPromptAction().showToast({ message: '分享失败', duration: 1200 })
    }
  }

  /** 添加到歌单（自定义底部卡片弹窗，成员保持引用避免 controller 被 GC） */
  private addToPlaylist(song: MusicItem, event: ClickEvent): void {
    const playlists = PlaylistManager.getInstance().getAll()
    const height = Math.min(500, 120 + (playlists.length + 1) * 52)
    const pos = DialogPosUtils.fromClickForDialog(event, 300, height)
    this.pickerController = new CustomDialogController({
      builder: PlaylistPickerDialog({
        song: song,
        playlists: playlists,
        onPick: (playlistId: string, pickEvent: ClickEvent) => {
          void pickEvent
          if (playlistId === 'new') {
            PlaylistManager.getInstance().create('新歌单', '').then((newPl: LocalPlaylist) => {
              PlaylistManager.getInstance().addSongs(newPl.id, [song])
              this.getUIContext().getPromptAction().showToast({ message: '已添加到新歌单', duration: 1200 })
            })
          } else {
            const pl = playlists.find(p => p.id === playlistId)
            PlaylistManager.getInstance().addSongs(playlistId, [song])
            this.getUIContext().getPromptAction().showToast({ message: `已添加到「${pl ? pl.name : '歌单'}」`, duration: 1200 })
          }
        }
      }),
      autoCancel: true,
      alignment: DialogAlignment.TopStart,
      offset: { dx: pos.x, dy: pos.y },
      customStyle: true
    })
    this.pickerController.open()
  }

  build() {
    Row({ space: 8 }) {
      Column({ space: 0 }) {
        PlayerSection({
          coverUrl: this.coverUrl,
          coverLoadFailed: this.coverLoadFailed,
          songName: this.currentSongName,
          singer: this.currentSinger,
          isSwiping: this.isSwiping,
          onCoverError: () => { this.coverLoadFailed = true }
        })
        .translate({ x: 0, y: this.swipeOffset })

        PlayerControls({
          currentProgress: this.currentProgress,
          duration: this.duration,
          status: this.status,
          mode: this.mode,
          isSeeking: this.isSeeking,
          isFavorited: this.isFavorited,
          isDownloading: this.isDownloading,
          isSwiping: this.isSwiping,
          onSeekStart: (seekMs: number) => {
            this.currentProgress = isNaN(seekMs) ? 0 : seekMs
            this.isSeeking = true
          },
          onSeekEnd: (seekMs: number) => {
            this.player.seekTo(isNaN(seekMs) ? 0 : seekMs)
            this.isSeeking = false
          },
          onPrev: () => { this.player.previous() },
          onToggle: () => { this.player.togglePlay() },
          onNext: () => { this.player.next() },
          onModeChange: () => {
            const modes = [PlayMode.LOOP_ALL, PlayMode.LOOP_ONE, PlayMode.SHUFFLE, PlayMode.SEQUENCE]
            this.player.setPlayMode(modes[(modes.indexOf(this.mode) + 1) % modes.length])
          },
          onToggleFavorite: () => { this.toggleFavorite() },
          onDownload: () => { this.downloadSong() },
          onMore: (event: ClickEvent) => { this.showMoreMenu(event) }
        })
        .translate({ x: 0, y: this.swipeOffset })
        .margin({ top: '30%' })
      }
      .width('44%')
      .height('96%')
      .margin({ left: 4 })
      .backgroundColor(this.glassBg)
      .backdropBlur(this.isSwiping ? 0 : 40)
      .borderRadius(20)
      .border({ width: 0.5, color: this.borderFaint })
      .shadow(this.isSwiping
        ? { radius: 0, color: Color.Transparent, offsetX: 0, offsetY: 0 }
        : { radius: 30, color: '#a0b388ff', offsetX: 0, offsetY: 4 })
      .shadow(this.isSwiping
        ? { radius: 0, color: Color.Transparent, offsetX: 0, offsetY: 0 }
        : { radius: 60, color: '#60b388ff', offsetX: 0, offsetY: 0 })
      .clip(true)
      .gesture(
        PanGesture({ direction: PanDirection.Vertical })
          .onActionStart(() => {
            this.dragStartY = this.swipeOffset
            this.isSwiping = true
          })
          .onActionUpdate((event: GestureEvent) => {
            // 跟手纵滑
            this.swipeOffset = this.dragStartY + event.offsetY
          })
          .onActionEnd(() => {
            this.handleVerticalSwipe()
          })
          .onActionCancel(() => {
            animateTo({ duration: 250, curve: Curve.Friction }, () => {
              this.swipeOffset = 0
            })
          })
      )

      Column() {
        LyricView({
          lyrics: this.lyrics,
          currentProgress: this.currentProgress,
          showTranslation: this.lyricShowTranslation,
          fontSize: this.lyricFontSize,
          onSeek: (timeMs: number) => { this.player.seekTo(timeMs) }
        })
      }
      .layoutWeight(1)
      .height('96%')
      .justifyContent(FlexAlign.Center)
      .margin({ right: 4 })
    }
    .width('100%')
    .height('100%')
  }
}
