import { LogUtils, StorageUtils } from 'common'

/**
 * 全屏背景层组件
 *
 * 优先使用用户导入的自定义背景图（沙箱文件），
 * 否则根据主题模式（AppStorage themeMode）选择内置深/浅背景图。
 */
@Component
export struct AppBackground {
  @StorageLink('themeMode') @Watch('onThemeChange') themeMode: string = 'dark'
  @StorageLink('customBgUpdated') @Watch('onCustomBgUpdated') customBgUpdated: number = 0
  /** 背景图资源路径 */
  @State bgSrc: string = 'resource://RAWFILE/bg_black_1.png'
  /** 自定义背景路径（file:// 或绝对路径，空则用内置） */
  private customBgPath: string = ''
  private bgIndex: number = 0

  aboutToAppear(): void {
    this.bgIndex = Math.random() < 0.5 ? 0 : 1
    // 读取自定义背景
    StorageUtils.getString('custom_bg_path', '').then((path: string) => {
      this.customBgPath = path
      this.updateBgSrc()
    }).catch(() => {
      this.updateBgSrc()
    })
  }

  onThemeChange(): void {
    this.updateBgSrc()
  }

  /** 自定义背景变化（导入/恢复默认）时重新读取并刷新 */
  onCustomBgUpdated(): void {
    StorageUtils.getString('custom_bg_path', '').then((path: string) => {
      this.customBgPath = path
      this.updateBgSrc()
    }).catch(() => {})
  }

  private updateBgSrc(): void {
    if (this.customBgPath) {
      // 自定义背景优先（file:// 前缀由沙箱路径直接使用）
      this.bgSrc = this.customBgPath.startsWith('file://') ? this.customBgPath : `file://${this.customBgPath}`
      return
    }
    if (this.themeMode !== 'light') {
      this.bgSrc = this.bgIndex % 2 === 0 ? 'resource://RAWFILE/bg_black_1.png' : 'resource://RAWFILE/bg_black_2.png'
    } else {
      this.bgSrc = this.bgIndex % 2 === 0 ? 'resource://RAWFILE/bg_whit4e_1_new.png' : 'resource://RAWFILE/bg_white_2_new.png'
    }
  }

  build() {
    Image(this.bgSrc)
      .width('100%')
      .height('100%')
      .objectFit(ImageFit.Cover)
      .interpolation(ImageInterpolation.Low)
      .expandSafeArea([SafeAreaType.SYSTEM, SafeAreaType.CUTOUT], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
      .onAppear(() => {
        LogUtils.info(`[背景] onAppear 触发, src=${this.bgSrc}`)
      })
      .onComplete(() => {
        LogUtils.info('[背景] onComplete 触发')
      })
      .onError((err: ImageError) => {
        LogUtils.error('[背景] onError 触发 msg=' + JSON.stringify(err))
      })
  }
}
