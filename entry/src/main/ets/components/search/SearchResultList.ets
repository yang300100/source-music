import { MusicItem } from 'common'
import { MusicItemView } from '../MusicItemView'

/**
 * 搜索结果列表组件
 *
 * 渲染歌曲结果列表，滑动手势提供"添加到歌单"入口。
 */
@Component
export struct SearchResultList {
  @StorageLink('themeIsDark') isDark: boolean = true
  /** 搜索结果 */
  @Prop results: MusicItem[] = []
  /** 添加到歌单回调 */
  onAddToPlaylist: (song: MusicItem) => void = (song: MusicItem) => {}

  build() {
    List() {
      ForEach(this.results, (song: MusicItem) => {
        ListItem() {
          MusicItemView({ song: song, queueSongs: this.results, showAddButton: true })
        }
        .swipeAction({
          end: { builder: () => { this.AddToPlaylistBuilder(song) } }
        })
      })
    }
    .width('100%').layoutWeight(1).scrollBar(BarState.Off)
  }

  @Builder
  AddToPlaylistBuilder(song: MusicItem) {
    Text('添加到歌单')
      .fontSize(12)
      .fontColor('#0e0c18')
      .backgroundColor('#b388ff')
      .padding({ left: 16, right: 16, top: 8, bottom: 8 })
      .borderRadius(8)
      .onClick(() => { this.onAddToPlaylist(song) })
  }
}
