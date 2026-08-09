import { hilog } from '@kit.PerformanceAnalysisKit'

const DOMAIN = 0x0001
const TAG = 'SourceMusic'

/**
 * 统一日志工具，封装 hilog
 */
export class LogUtils {
  static debug(msg: string, ...args: string[]): void {
    hilog.debug(DOMAIN, TAG, `[D] ${msg}`, args)
  }

  static info(msg: string, ...args: string[]): void {
    hilog.info(DOMAIN, TAG, `[I] ${msg}`, args)
  }

  static warn(msg: string, ...args: string[]): void {
    hilog.warn(DOMAIN, TAG, `[W] ${msg}`, args)
  }

  static error(msg: string, ...args: string[]): void {
    hilog.error(DOMAIN, TAG, `[E] ${msg}`, args)
  }
}
