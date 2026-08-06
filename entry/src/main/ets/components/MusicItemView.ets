import { MusicItem, LocalPlaylist } from 'common'
import { PlaylistManager } from 'hsp_playlist'
import { PlayerEngine } from 'hsp_player'

/**
 * 歌曲列表项组件 — 显示歌曲信息 + 音源标签，点击播放
 * 支持整列表入队（切歌）和添加到歌单
 */
@Component
export struct MusicItemView {
  @Prop song: MusicItem
  @Prop showSource: boolean = true
  // 传入整个播放列表（搜索结果/歌单），点击时整列表入队，支持切歌
  @Prop queueSongs: MusicItem[] = []
  @Prop showAddButton: boolean = false

  build() {
    Row({ space: 12 }) {
      Column({ space: 2 }) {
        Text(this.song.name)
          .fontSize(15)
          .fontColor('#cdd6f4')
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })

        Text(`${this.song.singer} · ${this.song.albumName}`)
          .fontSize(12)
          .fontColor('#6c7086')
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
      }
      .layoutWeight(1)

      if (this.showSource) {
        Text(this.song.source)
          .fontSize(11)
          .fontColor('#89b4fa')
          .padding({ left: 6, right: 6, top: 2, bottom: 2 })
          .backgroundColor('#45475a')
          .borderRadius(4)
      }

      // 添加到歌单按钮（明显的入口）
      if (this.showAddButton) {
        Text('➕')
          .fontSize(18)
          .padding({ left: 8, right: 4 })
          .onClick(() => { this.addToPlaylist() })
      }

      Text(this.formatDuration(this.song.interval))
        .fontSize(12)
        .fontColor('#585b70')
    }
    .width('100%')
    .padding({ left: 16, right: 16, top: 12, bottom: 12 })
    .onClick(() => {
      const player = PlayerEngine.getInstance()
      // 有列表则整列表入队（支持上一首/下一首），否则单曲
      if (this.queueSongs && this.queueSongs.length > 0) {
        const index = this.queueSongs.indexOf(this.song)
        player.queue.replaceList(this.queueSongs, index >= 0 ? index : 0)
      } else {
        player.queue.replaceList([this.song])
      }
      player.play(this.song)
    })
  }

  /** 添加到歌单（弹窗选择） */
  private addToPlaylist(): void {
    const playlists = PlaylistManager.getInstance().getAll()
    if (playlists.length === 0) {
      // 无歌单时自动创建并添加
      PlaylistManager.getInstance().create('我的歌单', '自动创建').then((pl: LocalPlaylist) => {
        PlaylistManager.getInstance().addSongs(pl.id, [this.song])
        this.showToast('已创建歌单并添加')
      })
      return
    }
    // 弹出歌单选择
    AlertDialog.show({
      title: '添加到歌单',
      message: '选择目标歌单',
      autoCancel: true,
      alignment: DialogAlignment.Bottom,
      primaryButton: {
        value: playlists[0].name,
        action: () => {
          PlaylistManager.getInstance().addSongs(playlists[0].id, [this.song])
          this.showToast(`已添加到「${playlists[0].name}」`)
        }
      },
      secondaryButton: {
        value: playlists.length > 1 ? playlists[1].name : '新建歌单',
        action: () => {
          if (playlists.length > 1) {
            PlaylistManager.getInstance().addSongs(playlists[1].id, [this.song])
            this.showToast(`已添加到「${playlists[1].name}」`)
          } else {
            PlaylistManager.getInstance().create('新歌单', '').then((pl: LocalPlaylist) => {
              PlaylistManager.getInstance().addSongs(pl.id, [this.song])
              this.showToast('已创建歌单并添加')
            })
          }
        }
      }
    })
  }

  private showToast(msg: string): void {
    // 轻提示
    AlertDialog.show({ title: '提示', message: msg, autoCancel: true })
  }

  private formatDuration(sec: number): string {
    const m = Math.floor(sec / 60)
    const s = sec % 60
    return `${m}:${s.toString().padStart(2, '0')}`
  }
}
