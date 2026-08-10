import { display } from '@kit.ArkUI'
import { ThemeColors } from '../../theme/ThemeColors'
import { MotionTokens } from '../../theme/MotionTokens'

/** 导航胶囊选项 */
export interface NavTab {
  icon: Resource
  label: string
  pageName: string
}

/**
 * 悬浮导航菜单组件
 *
 * 仅菜单形态（无独立小球）：横滑手势展开时出现在屏幕侧边，反向滑动/拖拽贴边收起。
 * 支持展开/收起与自由拖拽，点击选项回调 onSelect(pageName)。
 * 拖拽带屏幕边界限位（防止菜单丢失）。
 */
@Component
export struct NavCapsule {
  @StorageLink('themeIsDark') isDark: boolean = true
  /** 导航选项列表（由 Index 传入） */
  @Prop tabs: NavTab[] = []
  /** 当前激活的页面名（高亮显示） */
  @Prop activePage: string = ''
  /** 点击导航选项回调 */
  onSelect: (pageName: string) => void = (pageName: string) => {}
  /** 悬浮导航自身是否显示；与侧边页面是否展开完全独立 */
  @Link capsuleVisible: boolean
  /** 展开时回调（携带胶囊所在侧：true=左半屏，false=右半屏） */
  onExpand: (isLeft: boolean) => void = (isLeft: boolean) => {}
  /** 展开状态下拖拽跨越中线时回调（面板方向跟随切换） */
  onSideChange: (isLeft: boolean) => void = (isLeft: boolean) => {}
  /** 外部手势锚定侧边：'left'/'right'（锚定到屏幕边缘垂直居中），''=自由拖拽 */
  @Prop @Watch('onDockSideChange') dockSide: string = ''
  @State capsuleOffsetX: number = 12
  @State capsuleOffsetY: number = 60
  private dragStartX: number = 0
  private dragStartY: number = 0
  /** 本次手势的原始横向位移，用它判断是否确实向屏幕外侧滑动 */
  private dragOffsetX: number = 0
  private lastIsLeftHalf: boolean = true
  /** 展开态胶囊宽度 */
  private readonly capsuleWidth: number = 72

  /**
   * 胶囊实际高度：每个入口 56vp、入口间距 6vp、上下内边距共 20vp。
   * 外层始终保留这个尺寸，避免隐藏退场时容器塌缩到 0 导致绝对定位内容瞬间跳位。
   */
  private get capsuleHeight(): number {
    return this.tabs.length * 56 + Math.max(0, this.tabs.length - 1) * 6 + 20
  }

  private get secondaryText(): ResourceColor { return ThemeColors.secondaryText(this.isDark) }
  private get accentColor(): ResourceColor { return ThemeColors.accentColor() }
  private get capsuleBg(): ResourceColor { return ThemeColors.capsuleBg(this.isDark) }

  /**
   * 外部手势锚定：'left'/'right' 时定位到屏幕对应侧边缘垂直居中并展开菜单；
   * '' 表示保持当前位置，不改变悬浮导航的可见状态。
   */
  private onDockSideChange(): void {
    if (this.dockSide === '') return
    animateTo({ duration: 250, curve: Curve.EaseOut }, () => {
      const screenW = NavCapsule.getScreenWidth()
      const screenH = NavCapsule.getScreenHeight()
      const size = 72
      this.capsuleOffsetY = (screenH - size) / 2
      this.capsuleOffsetX = this.dockSide === 'right' ? screenW - size - 4 : 4
    })
  }

  build() {
    Stack() {
      Column({ space: 6 }) {
        ForEach(this.tabs, (tab: NavTab) => {
          Column() {
            Image(tab.icon)
              .width(26)
              .height(26)
              .fillColor(this.activePage === tab.pageName ? '#ffffff' : this.secondaryText)
          }
          .width(56)
          .height(56)
          .borderRadius(16)
          .justifyContent(FlexAlign.Center)
          .alignItems(HorizontalAlign.Center)
          .backgroundColor(this.activePage === tab.pageName ? this.accentColor : Color.Transparent)
          .border(this.activePage === tab.pageName ? {
            width: 1,
            color: '#30ffffff'
          } : { width: 0, color: Color.Transparent })
          .shadow(this.activePage === tab.pageName ? {
            radius: 16,
            color: '#60b388ff',
            offsetX: 0,
            offsetY: 4
          } : { radius: 0, color: Color.Transparent, offsetX: 0, offsetY: 0 })
          .scale({ x: this.activePage === tab.pageName ? 1.06 : 1,
            y: this.activePage === tab.pageName ? 1.06 : 1 })
          .animation({ duration: MotionTokens.NORMAL, curve: Curve.FastOutSlowIn })
          .stateStyles({
            normal: { .opacity(1) },
            pressed: { .opacity(0.62) }
          })
          .onClick(() => {
            this.onSelect(tab.pageName)
          })
        }, (tab: NavTab) => tab.pageName)
      }
      .padding({ left: 8, right: 8, top: 10, bottom: 10 })
      .borderRadius(28)
      .backgroundColor(this.capsuleBg)
      .backdropBlur(50)
      .border({ width: 0.5, color: '#d8a8ff' })
      .shadow({ radius: 20, color: '#30b388ff', offsetX: 0, offsetY: 4 })
      .opacity(this.capsuleVisible ? 1 : 0)
      .scale({ x: this.capsuleVisible ? 1 : 0.88, y: this.capsuleVisible ? 1 : 0.88 })
      .animation({ duration: MotionTokens.PAGE, curve: Curve.FastOutSlowIn })
    }
    .width(this.capsuleWidth)
    .height(this.capsuleHeight)
    .hitTestBehavior(this.capsuleVisible ? HitTestMode.Default : HitTestMode.None)
    .position({ x: this.capsuleOffsetX, y: this.capsuleOffsetY })
    .priorityGesture(
      PanGesture({ direction: PanDirection.All })
        .onActionStart(() => {
          this.dragStartX = this.capsuleOffsetX
          this.dragStartY = this.capsuleOffsetY
          this.dragOffsetX = 0
          this.lastIsLeftHalf = this.capsuleOffsetX < NavCapsule.getScreenWidth() / 2
        })
        .onActionUpdate((event: GestureEvent) => {
          this.dragOffsetX = event.offsetX
          // 实时限位：X/Y 均限制在屏幕范围内，防止悬浮球丢失
          const bounds = NavCapsule.getBounds(this.capsuleVisible)
          let newX = this.dragStartX + event.offsetX
          let newY = this.dragStartY + event.offsetY
          if (newX < bounds.minX) newX = bounds.minX
          if (newX > bounds.maxX) newX = bounds.maxX
          if (newY < bounds.minY) newY = bounds.minY
          if (newY > bounds.maxY) newY = bounds.maxY
          this.capsuleOffsetX = newX
          this.capsuleOffsetY = newY
          // 展开状态下拖拽跨越中线：通知外部切换面板方向
          if (this.capsuleVisible) {
            const screenW = NavCapsule.getScreenWidth()
            const isLeftHalf = newX < screenW / 2
            if (isLeftHalf !== this.lastIsLeftHalf) {
              this.lastIsLeftHalf = isLeftHalf
              this.onSideChange(isLeftHalf)
            }
          }
        })
        .onActionEnd((event: GestureEvent) => {
          const screenW = NavCapsule.getScreenWidth()
          // 以手势开始时所在侧和结束总位移判断，快速滑动也不会漏判。
          const startedOnLeft = this.dragStartX < screenW / 2
          const totalOffsetX = Math.abs(event.offsetX) > Math.abs(this.dragOffsetX) ? event.offsetX : this.dragOffsetX
          const shouldHide = this.capsuleVisible &&
            ((startedOnLeft && totalOffsetX < -32) || (!startedOnLeft && totalOffsetX > 32))
          animateTo({ duration: 250, curve: Curve.EaseOut }, () => {
            if (shouldHide) {
              // 这里只隐藏悬浮导航，不能联动收起已经展开的侧边页面。
              this.capsuleVisible = false
              // 隐藏时仍按完整胶囊宽度保存坐标，避免右侧恢复后有一部分落在屏幕外。
              this.capsuleOffsetX = startedOnLeft ? 4 : NavCapsule.getBounds(true).maxX
            }
            // 拖拽结束后再次夹紧边界（安全兜底）
            const bounds = NavCapsule.getBounds(this.capsuleVisible)
            if (this.capsuleOffsetX < bounds.minX) this.capsuleOffsetX = bounds.minX
            if (this.capsuleOffsetX > bounds.maxX) this.capsuleOffsetX = bounds.maxX
            if (this.capsuleOffsetY < bounds.minY) this.capsuleOffsetY = bounds.minY
            if (this.capsuleOffsetY > bounds.maxY) this.capsuleOffsetY = bounds.maxY
          })
          this.dragOffsetX = 0
        })
    )
  }

  /** 计算胶囊可拖拽边界（vp），expanded 决定使用展开/收起尺寸 */
  private static getBounds(expanded: boolean): NavBounds {
    const bounds = new NavBounds()
    const screenW = NavCapsule.getScreenWidth()
    const screenH = NavCapsule.getScreenHeight()
    const size = expanded ? 72 : 40
    bounds.minX = 4
    bounds.maxX = screenW - size - 4
    bounds.minY = 40
    // 底部预留导航条区域（48vp），防止悬浮球被系统导航条遮挡
    bounds.maxY = screenH - size - 48
    return bounds
  }

  /** 获取屏幕宽度（vp），失败回退 1280 */
  private static getScreenWidth(): number {
    try {
      const d = display.getDefaultDisplaySync()
      return d.width / d.densityPixels
    } catch (err) {
      return 1280
    }
  }

  /** 获取屏幕高度（vp），失败回退 800 */
  private static getScreenHeight(): number {
    try {
      const d = display.getDefaultDisplaySync()
      return d.height / d.densityPixels
    } catch (err) {
      return 800
    }
  }
}

/** 拖拽边界 */
class NavBounds {
  minX: number = 4
  maxX: number = 1200
  minY: number = 40
  maxY: number = 700
}
