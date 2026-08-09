import { MusicItem } from 'common'
import { MusicItemView } from '../MusicItemView'
import { MotionTokens } from '../../theme/MotionTokens'

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
  onAddToPlaylist: (song: MusicItem, event: ClickEvent) => void = (song: MusicItem, event: ClickEvent) => {}

  build() {
    List() {
      ForEach(this.results, (song: MusicItem, index: number) => {
        ListItem() {
          MusicItemView({ song: song, queueSongs: this.results, showAddButton: true })
        }
        .swipeAction({
          end: { builder: () => { this.AddToPlaylistBuilder(song) } }
        })
        .transition(TransitionEffect.OPACITY.animation({ duration: MotionTokens.LIST,
          delay: MotionTokens.staggerDelay(index), curve: Curve.EaseOut })
          .combine(TransitionEffect.translate({ x: 0, y: 12 })
            .animation({ duration: MotionTokens.LIST, delay: MotionTokens.staggerDelay(index),
              curve: Curve.FastOutSlowIn })))
      }, (song: MusicItem) => `${song.source}_${song.songmid}`)
    }
    .width('100%')
    .height('100%')
    .scrollBar(BarState.Off)
    .edgeEffect(EdgeEffect.Spring)
    .padding({ bottom: 12 })
    .clip(true)
  }

  @Builder
  AddToPlaylistBuilder(song: MusicItem) {
    Text('添加到歌单')
      .fontSize(12)
      .fontColor('#0e0c18')
      .backgroundColor('#b388ff')
      .padding({ left: 16, right: 16, top: 8, bottom: 8 })
      .borderRadius(8)
      .transition(TransitionEffect.OPACITY.animation({ duration: MotionTokens.NORMAL, curve: Curve.EaseOut })
        .combine(TransitionEffect.translate({ x: 12, y: 0 })
          .animation({ duration: MotionTokens.NORMAL, curve: Curve.FastOutSlowIn })))
      .onClick((event: ClickEvent) => { this.onAddToPlaylist(song, event) })
  }
}
