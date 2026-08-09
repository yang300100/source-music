import { MusicItem, LocalPlaylist, SourceType, PlayerStatus, SourceInstance, LogUtils } from 'common'
import { PlaylistManager } from 'hsp_playlist'
import { PlayerEngine } from 'hsp_player'
import { SourceManager } from 'hsp_source'
import { PlaylistNameDialog } from './PlaylistNameDialog'
import { SourcePickerDialog } from './common/SourcePickerDialog'
import { PlaylistPickerDialog } from './common/PlaylistPickerDialog'
import { DialogPosUtils } from '../utils/DialogPosUtils'

@Component
export struct MusicItemView {
  @StorageLink('themeIsDark') isDark: boolean = true
  @Prop song: MusicItem
  @Prop showSource: boolean = true
  @Prop queueSongs: MusicItem[] = []
  @Prop showAddButton: boolean = false
  private sourcePickerController: CustomDialogController | null = null
  private playlistPickerController: CustomDialogController | null = null
  private nameDialog: CustomDialogController | null = null

  private get primaryText(): ResourceColor { return this.isDark ? '#e8e0f8' : '#1a1525' }
  private get secondaryText(): ResourceColor { return this.isDark ? '#7a6f98' : '#6b6088' }
  private get dimText(): ResourceColor { return this.isDark ? '#a090c0' : '#7a6f98' }
  private get cardBg(): ResourceColor { return this.isDark ? '#30181525' : '#90ffffff' }
  private get placeholderBg(): ResourceColor { return this.isDark ? '#60181525' : '#60e0d8ea' }

  build() {
    Row({ space: 12 }) {
      if (this.song.imgUrl) {
        Image(this.song.imgUrl)
          .width(44).height(44).borderRadius(10)
          .objectFit(ImageFit.Cover).alt($r('app.media.startIcon'))
          .interpolation(ImageInterpolation.Low)
      } else {
        Stack() {
          Image($r('app.media.startIcon'))
            .width(44).height(44).borderRadius(10)
            .objectFit(ImageFit.Cover).opacity(0.2)
        }
        .width(44).height(44).borderRadius(10)
        .backgroundColor(this.placeholderBg)
      }

      Column({ space: 2 }) {
        Text(this.song.name)
          .fontSize(15).fontColor(this.primaryText).maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
        Text(`${this.song.singer} · ${this.song.albumName}`)
          .fontSize(12).fontColor(this.secondaryText).maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
      }
      .layoutWeight(1)

      if (this.showSource) {
        Text(this.getSourceLabel(this.song.source))
          .fontSize(11).fontColor('#b388ff')
          .padding({ left: 8, right: 8, top: 3, bottom: 3 })
          .backgroundColor('#20b388ff')
          .borderRadius(6)
          .onClick((event: ClickEvent) => { this.openSourcePicker(event) })
      }

      if (this.showAddButton) {
        Text('+')
          .fontSize(18).fontColor('#b388ff')
          .width(28).height(28).textAlign(TextAlign.Center)
          .borderRadius(14).backgroundColor('#20b388ff')
          .onClick((event: ClickEvent) => { this.addToPlaylist(event) })
      }

      Text(this.formatDuration(this.song.interval))
        .fontSize(12).fontColor(this.dimText)
    }
    .width('100%')
    .padding({ left: 16, right: 16, top: 10, bottom: 10 })
    .backgroundColor(this.cardBg)
    .borderRadius(12)
    .onClick(() => {
      const player = PlayerEngine.getInstance()
      if (this.queueSongs && this.queueSongs.length > 0) {
        let index = -1
        for (let i = 0; i < this.queueSongs.length; i++) {
          if (this.queueSongs[i].songmid === this.song.songmid && this.queueSongs[i].source === this.song.source) {
            index = i
            break
          }
        }
        player.queue.replaceList(this.queueSongs, index >= 0 ? index : 0)
      } else {
        player.queue.replaceList([this.song])
      }
      // 只在重复点击同一首歌（正在加载中）时忽略；点击其他歌曲应允许切换
      if (player.status === PlayerStatus.LOADING || player.status === PlayerStatus.BUFFERING) {
        const cur = player.currentSong
        if (cur && cur.songmid === this.song.songmid && cur.source === this.song.source) {
          LogUtils.info('[MusicItemView] 同一首歌加载中，忽略重复点击')
          return
        }
        LogUtils.info('[MusicItemView] 点击不同歌曲，允许切换播放')
      }
      player.play(this.song)
    })
  }

  /** 打开"选择搜索源"弹窗（手动换源：列出全部导入音源，社区音源 风格） */
  private openSourcePicker(event: ClickEvent): void {
    const pos = DialogPosUtils.fromClickForDialog(event, 320, 440)
    const mgr = SourceManager.getInstance()
    mgr.getSearchSources().then((sources: SourceInstance[]) => {
      const searchSources = sources.filter((source: SourceInstance) =>
        source.info.id !== 'local_source' && source.info.id !== 'demo')
      if (searchSources.length <= 1) {
        this.showToast('暂无可切换的搜索源')
        return
      }
      this.sourcePickerController = new CustomDialogController({
        builder: SourcePickerDialog({
          songName: this.song.name,
          searchSources: searchSources,
          currentSourceId: this.song.source,
          onPick: (sourceId: string) => {
            this.switchSource(sourceId)
          }
        }),
        autoCancel: true,
        alignment: DialogAlignment.TopStart,
        offset: { dx: pos.x, dy: pos.y },
        customStyle: true
      })
      this.sourcePickerController.open()
    }).catch(() => {
      this.showToast('读取搜索源失败')
    })
  }

  /** 在目标音源搜索同歌并播放（社区音源 风格：单源搜索+解析，失败自动兜底） */
  private async switchSource(sourceId: string): Promise<void> {
    if (sourceId === this.song.source) {
      this.showToast('已是当前音源')
      return
    }
    this.showToast('正在切换音源...')
    const target = await SourceManager.getInstance().searchSameSongInSource(this.song, sourceId, '')
    if (!target) {
      this.showToast('未找到可播放版本')
      return
    }
    // 播放前先持久化：将换源结果写回歌单（下次播放/展示使用新源）
    PlaylistManager.getInstance().updateSongSource(this.song, target).then((changed: boolean) => {
      LogUtils.info(`[换源] 歌单更新: ${changed}`)
    }).catch((err: Error) => {
      LogUtils.warn(`[换源] 歌单更新失败: ${JSON.stringify(err)}`)
    })
    PlayerEngine.getInstance().play(target)
    const sourceLabel = this.getSourceLabel(target.source)
    if (target.source !== sourceId) {
      // 所选音源无可用播放地址，自动兜底到了其他源
      this.showToast(`所选源无可用地址，已改用「${sourceLabel}」播放`)
    } else {
      this.showToast(`已切换为「${sourceLabel}」播放`)
    }
  }

  private addToPlaylist(event: ClickEvent): void {
    const playlists = PlaylistManager.getInstance().getAll()
    const height = Math.min(500, 120 + (playlists.length + 1) * 52)
    const pos = DialogPosUtils.fromClickForDialog(event, 300, height)
    this.playlistPickerController = new CustomDialogController({
      builder: PlaylistPickerDialog({
        song: this.song,
        playlists: playlists,
        onPick: (playlistId: string, pickEvent: ClickEvent) => {
          if (playlistId === 'new') {
            setTimeout(() => { this.openNameDialog(pickEvent) }, 200)
            return
          }
          const playlist = playlists.find((item: LocalPlaylist) => item.id === playlistId)
          PlaylistManager.getInstance().addSongs(playlistId, [this.song]).then((ok: boolean) => {
            this.showToast(ok ? `已添加到「${playlist?.name ?? '歌单'}」` : '添加失败')
          })
        }
      }),
      autoCancel: true,
      alignment: DialogAlignment.TopStart,
      offset: { dx: pos.x, dy: pos.y },
      customStyle: true
    })
    this.playlistPickerController.open()
  }

  private openNameDialog(event: ClickEvent): void {
    const pos = DialogPosUtils.fromClickForDialog(event, 300, 220)
    this.nameDialog = new CustomDialogController({
      builder: PlaylistNameDialog({
        placeholder: '请输入歌单名称',
        onConfirm: (name: string) => {
          PlaylistManager.getInstance().create(name, '').then((pl: LocalPlaylist) => {
            PlaylistManager.getInstance().addSongs(pl.id, [this.song])
            this.showToast(`已创建歌单「${name}」并添加`)
          })
        }
      }),
      autoCancel: true,
      alignment: DialogAlignment.TopStart,
      offset: { dx: pos.x, dy: pos.y },
      customStyle: true
    })
    this.nameDialog.open()
  }

  private showToast(msg: string): void {
    this.getUIContext().getPromptAction().showToast({ message: msg, duration: 1500 })
  }

  private formatDuration(sec: number): string {
    const m = Math.floor(sec / 60)
    const s = sec % 60
    return `${m}:${s.toString().padStart(2, '0')}`
  }

  private getSourceLabel(source: SourceType): string {
    switch (source) {
      case SourceType.KG: return '酷狗'
      case SourceType.WY: return '网易'
      case SourceType.TX: return 'QQ'
      case SourceType.KW: return '酷我'
      case SourceType.MG: return '咪咕'
      case SourceType.LOCAL: return '本地'
      default: return '自定义'
    }
  }
}
