import { display } from '@kit.ArkUI'

/** 弹窗定位结果（vp 坐标） */
export class DialogPosition {
  x: number = 0
  y: number = 0
}

/**
 * 弹窗定位工具
 *
 * 将点击事件屏幕坐标转换为 vp 坐标，
 * 用于 CustomDialogController alignment=TopStart + offset 在点击位置展开弹窗。
 */
export class DialogPosUtils {
  /** 从点击事件获取 vp 坐标（弹窗左上角定位点，y 向下偏移 16 避免遮挡手指） */
  static fromClick(event: ClickEvent): DialogPosition {
    const density = DialogPosUtils.getDensity()
    const pos = new DialogPosition()
    pos.x = event.screenX / density
    pos.y = event.screenY / density + 16
    return pos
  }

  /** 从长按事件获取 vp 坐标（弹窗左上角定位点，y 向下偏移 16 避免遮挡手指） */
  static fromGesture(event: GestureEvent): DialogPosition {
    const density = DialogPosUtils.getDensity()
    const pos = new DialogPosition()
    const fingers = event.fingerList
    if (fingers && fingers.length > 0) {
      pos.x = fingers[0].displayX / density
      pos.y = fingers[0].displayY / density + 16
    }
    return pos
  }

  /** 屏幕宽度（vp） */
  static screenWidth(): number {
    try {
      return display.getDefaultDisplaySync().width / DialogPosUtils.getDensity()
    } catch (err) {
      return 0
    }
  }

  /** 屏幕高度（vp） */
  static screenHeight(): number {
    try {
      return display.getDefaultDisplaySync().height / DialogPosUtils.getDensity()
    } catch (err) {
      return 0
    }
  }

  private static getDensity(): number {
    try {
      return display.getDefaultDisplaySync().densityPixels
    } catch (err) {
      return 1
    }
  }
}
