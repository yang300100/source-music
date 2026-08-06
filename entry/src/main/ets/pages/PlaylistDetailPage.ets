import { LocalPlaylist, MusicItem } from 'common'
import { PlaylistManager } from 'hsp_playlist'
import { PlayerEngine } from 'hsp_player'
import { MusicItemView } from '../components/MusicItemView'
import { router } from '@kit.ArkUI'

/**
 * 歌单详情页面 — 展示歌单内歌曲列表，支持删除和播放全部
 */
@Entry
@Component
struct PlaylistDetailPage {
  @State playlist: LocalPlaylist | null = null
  private playlistId: string = ''

  aboutToAppear(): void {
    const params = router.getParams() as Record<string, Object>
    this.playlistId = (params?.['playlistId'] as string) ?? ''
    if (this.playlistId) {
      this.playlist = PlaylistManager.getInstance().getById(this.playlistId) ?? null
    }
  }

  build() {
    Column() {
      if (!this.playlist) {
        Text('歌单不存在').fontSize(15).fontColor('#6c7086')
      } else {
        Row({ space: 12 }) {
          Column({ space: 4 }) {
            Text(this.playlist!.name).fontSize(18).fontWeight(FontWeight.Bold).fontColor('#cdd6f4')
            Text(`${this.playlist!.songs.length} 首`).fontSize(12).fontColor('#6c7086')
          }
          Blank()
          Text('▶ 播放全部')
            .fontSize(14)
            .fontColor('#a6e3a1')
            .onClick(() => {
              const player = PlayerEngine.getInstance()
              player.queue.replaceList(this.playlist!.songs)
              player.playCurrent()
            })
        }
        .width('100%').padding(16)

        List() {
          ForEach(this.playlist!.songs, (song: MusicItem, index: number) => {
            ListItem() {
              MusicItemView({ song: song })
            }
            .swipeAction({
              end: {
                builder: () => {
                  Button('删除')
                    .fontSize(13)
                    .backgroundColor('#f38ba8')
                    .onClick(() => {
                      PlaylistManager.getInstance().removeSongs(this.playlistId, [index])
                      this.playlist = PlaylistManager.getInstance().getById(this.playlistId) ?? null
                    })
                }
              }
            })
          })
        }
        .width('100%').layoutWeight(1)
      }
    }
    .width('100%').height('100%').backgroundColor('#1e1e2e')
  }
}
