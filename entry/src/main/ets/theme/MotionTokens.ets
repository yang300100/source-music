/**
 * 应用统一动效参数。
 *
 * 所有页面和组件共用同一套节奏，后续调整动效时不需要逐个查找魔法数字。
 */
export class MotionTokens {
  /** 按压、聚焦等即时反馈 */
  static readonly FAST: number = 140

  /** 开关、选中态和内容状态切换 */
  static readonly NORMAL: number = 240

  /** 页面、面板及弹窗进出 */
  static readonly PAGE: number = 320

  /** 列表单项进入动画 */
  static readonly LIST: number = 280

  /** 普通按钮按下时的缩放比例 */
  static readonly PRESSED_SCALE: number = 0.96

  /** 小型标签按下时的缩放比例 */
  static readonly CHIP_PRESSED_SCALE: number = 0.94

  /**
   * 列表条目错峰延迟。
   * 只错开首屏附近的条目，避免超长列表需要等待数秒才能显示完整。
   */
  static staggerDelay(index: number): number {
    return Math.min(Math.max(index, 0), 12) * 36
  }
}
