import { PlayerEngine } from 'hsp_player'
import { MusicItem } from 'common'
import { ThemeColors } from '../../theme/ThemeColors'
import { SearchContent } from '../../pages/SearchPage'
import { PlaylistListContent } from '../../pages/PlaylistListPage'
import { SettingsContent } from '../../pages/SettingsPage'
import { DownloadPanel } from '../download/DownloadPanel'

/**
 * 竖屏负一屏（搜索页为主，含底部导航）
 *
 * 底部导航实现横屏悬浮球中的导航操作：搜索/歌单/下载/设置切换子页，播放跳到播放页。
 */
@Component
export struct PortraitLandingPage {
  @StorageLink('themeIsDark') isDark: boolean = true
  @State subPanel: string = 'search'
  /** 切换到播放页（Swiper 下一页） */
  onOpenPlayer: () => void = () => {}
  private player: PlayerEngine = PlayerEngine.getInstance()

  private get primaryText(): ResourceColor { return ThemeColors.primaryText(this.isDark) }
  private get secondaryText(): ResourceColor { return ThemeColors.secondaryText(this.isDark) }
  private get accentColor(): ResourceColor { return ThemeColors.accentColor() }

  build() {
    Column() {
      Column() {
        if (this.subPanel === 'search') {
          SearchContent()
        } else if (this.subPanel === 'playlist') {
          PlaylistListContent({ panelSide: 'left', portrait: true })
        } else if (this.subPanel === 'downloads') {
          DownloadPanel({
            onPlay: (song: MusicItem) => { this.player.play(song) }
          })
        } else {
          SettingsContent()
        }
      }
      .width('100%')
      .layoutWeight(1)

      // 底部导航（替代悬浮球导航）
      Row() {
        this.TabBtn($r('app.media.ic_search'), '搜索', 'search')
        this.TabBtn($r('app.media.ic_nav_playlist'), '歌单', 'playlist')
        this.TabBtn($r('app.media.ic_download'), '下载', 'downloads')

        Column({ space: 2 }) {
          Image($r('app.media.ic_play'))
            .width(22).height(22).fillColor(this.accentColor)
          Text('播放')
            .fontSize(10).fontColor(this.accentColor)
        }
        .layoutWeight(1)
        .onClick(() => { this.onOpenPlayer() })

        this.TabBtn($r('app.media.ic_more'), '设置', 'settings')
      }
      .width('100%')
      .padding({ top: 8, bottom: 14 })
      .backgroundColor(this.isDark ? '#cc141218' : '#e8ffffff')
      .backdropBlur(30)
      .border({ width: { top: 0.5 }, color: '#d8a8ff' })
    }
    .width('100%')
    .height('100%')
  }

  @Builder
  TabBtn(icon: Resource, label: string, panel: string) {
    Column({ space: 2 }) {
      Image(icon)
        .width(22).height(22)
        .fillColor(this.subPanel === panel ? this.accentColor : this.secondaryText)
      Text(label)
        .fontSize(10)
        .fontColor(this.subPanel === panel ? this.accentColor : this.secondaryText)
    }
    .layoutWeight(1)
    .onClick(() => { this.subPanel = panel })
  }
}
