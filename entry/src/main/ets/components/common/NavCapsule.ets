import { display } from '@kit.ArkUI'
import { ThemeColors } from '../../theme/ThemeColors'

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
  /** 展开/收起状态（由 Index 持有，联动面板显隐） */
  @Link capsuleExpanded: boolean
  /** 展开时回调（携带胶囊所在侧：true=左半屏，false=右半屏） */
  onExpand: (isLeft: boolean) => void = (isLeft: boolean) => {}
  /** 展开状态下拖拽跨越中线时回调（面板方向跟随切换） */
  onSideChange: (isLeft: boolean) => void = (isLeft: boolean) => {}
  /** 拖拽贴边收起时回调（外部清空 dockSide，保证再次手势展开时 @Watch 能触发） */
  onCollapseByDrag: () => void = () => {}
  /** 外部手势锚定侧边：'left'/'right'（锚定到屏幕边缘垂直居中），''=自由拖拽 */
  @Prop @Watch('onDockSideChange') dockSide: string = ''
  /** 菜单展开状态（与 capsuleExpanded 解耦：面板可保持展开而菜单收起） */
  @State menuOpen: boolean = true
  @State capsuleOffsetX: number = 12
  @State capsuleOffsetY: number = 60
  private dragStartX: number = 0
  private dragStartY: number = 0
  private lastIsLeftHalf: boolean = true
  /** 展开态胶囊宽度 */
  private readonly capsuleWidth: number = 72

  private get secondaryText(): ResourceColor { return ThemeColors.secondaryText(this.isDark) }
  private get accentColor(): ResourceColor { return ThemeColors.accentColor() }
  private get capsuleBg(): ResourceColor { return ThemeColors.capsuleBg(this.isDark) }

  /**
   * 外部手势锚定：'left'/'right' 时定位到屏幕对应侧边缘垂直居中并展开菜单；
   * ''（收起）时菜单随之收起，悬浮球不再显示。
   */
  private onDockSideChange(): void {
    if (this.dockSide === '') {
      this.menuOpen = false
      return
    }
    this.menuOpen = true
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
      if (this.menuOpen) {
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
            .onClick(() => {
              this.onSelect(tab.pageName)
            })
          }, (tab: NavTab) => tab.pageName)
        }
        .padding({ left: 8, right: 8, top: 10, bottom: 10 })
        .borderRadius(28)
        .backgroundColor(this.capsuleBg)
        .backdropBlur(50)
        .border({ width: 0.5, color: this.isDark ? '#40b388ff' : '#10000000' })
        .shadow({ radius: 20, color: '#30b388ff', offsetX: 0, offsetY: 4 })
      }
    }
    .position({ x: this.capsuleOffsetX, y: this.capsuleOffsetY })
    .gesture(
      PanGesture({ direction: PanDirection.All })
        .onActionStart(() => {
          this.dragStartX = this.capsuleOffsetX
          this.dragStartY = this.capsuleOffsetY
          this.lastIsLeftHalf = this.capsuleOffsetX < NavCapsule.getScreenWidth() / 2
        })
        .onActionUpdate((event: GestureEvent) => {
          // 实时限位：X/Y 均限制在屏幕范围内，防止悬浮球丢失
          const bounds = NavCapsule.getBounds(this.menuOpen)
          let newX = this.dragStartX + event.offsetX
          let newY = this.dragStartY + event.offsetY
          if (newX < bounds.minX) newX = bounds.minX
          if (newX > bounds.maxX) newX = bounds.maxX
          if (newY < bounds.minY) newY = bounds.minY
          if (newY > bounds.maxY) newY = bounds.maxY
          this.capsuleOffsetX = newX
          this.capsuleOffsetY = newY
          // 展开状态下拖拽跨越中线：通知外部切换面板方向
          if (this.menuOpen) {
            const screenW = NavCapsule.getScreenWidth()
            const isLeftHalf = newX < screenW / 2
            if (isLeftHalf !== this.lastIsLeftHalf) {
              this.lastIsLeftHalf = isLeftHalf
              this.onSideChange(isLeftHalf)
            }
          }
        })
        .onActionEnd(() => {
          const screenW = NavCapsule.getScreenWidth()
          // 左半屏：仅左滑贴左边缘收起；右半屏：仅右滑贴右边缘收起
          const isLeftHalf = this.capsuleOffsetX < screenW / 2
          const isNearLeftEdge = isLeftHalf && this.capsuleOffsetX < 8
          const isNearRightEdge = !isLeftHalf && this.capsuleOffsetX > screenW - 72 - 8
          animateTo({ duration: 250, curve: Curve.EaseOut }, () => {
            if ((isNearLeftEdge || isNearRightEdge) && this.menuOpen) {
              this.menuOpen = false
              this.capsuleExpanded = false
              this.capsuleOffsetX = isNearLeftEdge ? 4 : NavCapsule.getBounds(false).maxX
              // 通知外部清空 dockSide（否则再次手势展开时 @Watch 不触发，菜单无法恢复）
              this.onCollapseByDrag()
            }
            // 拖拽结束后再次夹紧边界（安全兜底）
            const bounds = NavCapsule.getBounds(this.menuOpen)
            if (this.capsuleOffsetX < bounds.minX) this.capsuleOffsetX = bounds.minX
            if (this.capsuleOffsetX > bounds.maxX) this.capsuleOffsetX = bounds.maxX
            if (this.capsuleOffsetY < bounds.minY) this.capsuleOffsetY = bounds.minY
            if (this.capsuleOffsetY > bounds.maxY) this.capsuleOffsetY = bounds.maxY
          })
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
