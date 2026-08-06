import { PlaylistVM } from '../viewmodel/PlaylistVM'
import { LocalPlaylist } from 'common'
import { PlayerEngine } from 'hsp_player'
import { router } from '@kit.ArkUI'

/**
 * 歌单列表页面 — 展示所有本地歌单，点击进入详情
 */
@Entry
@Component
struct PlaylistListPage {
  @State viewModel: PlaylistVM = new PlaylistVM()

  aboutToAppear(): void {
    this.viewModel.load()
  }

  build() {
    Column() {
      Text('我的歌单')
        .fontSize(18)
        .fontWeight(FontWeight.Bold)
        .fontColor('#cdd6f4')
        .padding({ left: 16, top: 16, bottom: 12 })

      if (this.viewModel.playlists.length === 0) {
        Column({ space: 4 }) {
          Text('还没有歌单').fontSize(14).fontColor('#6c7086')
          Text('去搜索页添加喜欢的歌曲吧~').fontSize(12).fontColor('#585b70')
        }
        .width('100%').height('100%').justifyContent(FlexAlign.Center)
        return
      }

      List() {
        ForEach(this.viewModel.playlists, (pl: LocalPlaylist) => {
          ListItem() {
            Row({ space: 12 }) {
              Column({ space: 4 }) {
                Text(pl.name).fontSize(15).fontColor('#cdd6f4')
                Text(`${pl.songs.length} 首`).fontSize(12).fontColor('#6c7086')
              }
              .layoutWeight(1)

              Text('▶')
                .fontSize(20)
                .fontColor('#a6e3a1')
                .onClick(() => {
                  const player = PlayerEngine.getInstance()
                  player.queue.replaceList(pl.songs)
                  player.playCurrent()
                })
            }
            .width('100%')
            .padding({ left: 16, right: 16, top: 14, bottom: 14 })
            .onClick(() => {
              router.pushUrl({
                url: 'pages/PlaylistDetailPage',
                params: { playlistId: pl.id } as Record<string, Object>
              })
            })
          }
        })
      }
      .width('100%').layoutWeight(1)
    }
    .width('100%').height('100%').backgroundColor('#1e1e2e')
  }
}
