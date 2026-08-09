import { AppBackground } from '../common/AppBackground'
import { PortraitLandingPage } from './PortraitLandingPage'
import { PortraitPlayer } from './PortraitPlayer'
import { PortraitLyricPage } from './PortraitLyricPage'
import { MotionTokens } from '../../theme/MotionTokens'

/**
 * 竖屏布局容器（Swiper 三页横滑）
 *
 * 页顺序：搜索负一屏（左） | 播放毛玻璃（默认） | 歌词（右）
 * - 播放页左滑 → 歌词页；播放页右滑 → 负一屏
 * - 负一屏底部导航切换子页面，点"播放"跳到播放页
 */
@Component
export struct PortraitPage {
  private swiperController: SwiperController = new SwiperController()

  build() {
    Stack() {
      AppBackground()

      Swiper(this.swiperController) {
        PortraitLandingPage({
          onOpenPlayer: () => { this.swiperController.showNext() }
        })

        PortraitPlayer()

        PortraitLyricPage()
      }
      .index(1)
      .loop(false)
      .indicator(false)
      .duration(MotionTokens.PAGE)
      .curve(Curve.FastOutSlowIn)
      .width('100%')
      .height('100%')
    }
    .width('100%')
    .height('100%')
    .expandSafeArea([SafeAreaType.SYSTEM, SafeAreaType.CUTOUT], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
  }
}
