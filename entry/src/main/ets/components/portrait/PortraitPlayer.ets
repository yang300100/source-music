import { PlayerEngine } from 'hsp_player'
import { PlaylistManager } from 'hsp_playlist'
import { SourceManager } from 'hsp_source'
import { PlayerStatus, PlayMode, LyricLine, MusicItem, MusicQuality, DownloadUtils } from 'common'
import { ThemeColors } from '../../theme/ThemeColors'
import { PlayerSection } from '../player/PlayerSection'
import { PlayerControls } from '../player/PlayerControls'

/**
 * 竖屏播放页（毛玻璃卡片）
 *
 * 复用横屏的信息区与控制区组件，竖排展示：
 * 封面/歌名/歌手 + 操作行/渐变进度条/控制按钮/模式。
 */
@Component
export struct PortraitPlayer {
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
  @State isDownloading: boolean = false
  private player: PlayerEngine = PlayerEngine.getInstance()
  private syncTimer: number = -1
  private lastSongKey: string = ''

  private get glassBg(): ResourceColor { return ThemeColors.glassBg(this.isDark) }
  private get borderFaint(): ResourceColor { return ThemeColors.borderFaint(this.isDark) }
  private get dimLyricColor(): ResourceColor { return this.isDark ? '#4a4260' : '#9088a0' }
  private get noLyricColor(): ResourceColor { return this.isDark ? '#7a6f98' : '#6b6088' }

  /** 当前播放到的歌词索引（-1 表示无歌词/未开始） */
  private currentLyricIndex(): number {
    let idx = -1
    for (let i = this.lyrics.length - 1; i >= 0; i--) {
      if (this.currentProgress >= this.lyrics[i].time) {
        idx = i
        break
      }
    }
    return idx
  }

  aboutToAppear(): void {
    this.syncTimer = setInterval(() => { this.refreshSongInfo() }, 500)
  }

  aboutToDisappear(): void {
    if (this.syncTimer >= 0) {
      clearInterval(this.syncTimer)
      this.syncTimer = -1
    }
  }

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

  private async toggleFavorite(): Promise<void> {
    const song = this.player.currentSong
    if (!song) return
    try {
      const fav = await PlaylistManager.getInstance().toggleFavorite(song)
      this.isFavorited = fav
      this.getUIContext().getPromptAction().showToast({ message: fav ? '已收藏' : '已取消收藏', duration: 1200 })
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

  build() {
    Stack() {
      Column() {
        PlayerSection({
          coverUrl: this.coverUrl,
          coverLoadFailed: this.coverLoadFailed,
          songName: this.currentSongName,
          singer: this.currentSinger,
          onCoverError: () => { this.coverLoadFailed = true }
        })

        // 中间区域：显示当前歌词摘要（7 行，纯展示）
        Column({ space: 10 }) {
          if (this.lyrics.length > 0) {
            ForEach([-3, -2, -1, 0, 1, 2, 3], (offset: number) => {
              if (this.currentLyricIndex() + offset >= 0 && this.currentLyricIndex() + offset < this.lyrics.length) {
                Text(this.lyrics[this.currentLyricIndex() + offset].text)
                  .fontSize(offset === 0 ? 15 : 13)
                  .fontWeight(offset === 0 ? FontWeight.Bold : FontWeight.Normal)
                  .fontColor(offset === 0 ? '#b388ff' : this.dimLyricColor)
                  .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
              }
            }, (offset: number) => `${offset}`)
          } else {
            Text('纯音乐，请欣赏')
              .fontSize(14).fontColor(this.noLyricColor)
          }
        }
        .layoutWeight(1)
        .justifyContent(FlexAlign.Center)
        .width('100%')
        .padding({ left: 24, right: 24 })

        PlayerControls({
          currentProgress: this.currentProgress,
          duration: this.duration,
          status: this.status,
          mode: this.mode,
          isSeeking: this.isSeeking,
          isFavorited: this.isFavorited,
          isDownloading: this.isDownloading,
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
          onMore: () => {
            this.getUIContext().getPromptAction().showToast({ message: '更多操作请横屏使用', duration: 1200 })
          }
        })
      }
      .width('92%')
      .height('94%')
      .backgroundColor(this.glassBg)
      .backdropBlur(40)
      .borderRadius(24)
      .border({ width: 0.5, color: this.borderFaint })
      .shadow({ radius: 30, color: '#a0b388ff', offsetX: 0, offsetY: 4 })
      .shadow({ radius: 60, color: '#60b388ff', offsetX: 0, offsetY: 0 })
      .clip(true)
    }
    .width('100%')
    .height('100%')
  }
}
