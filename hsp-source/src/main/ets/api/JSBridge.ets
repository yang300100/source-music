import { LogUtils, NetUtils } from 'common'

/**
 * JS 音源脚本桥接对象
 *
 * 注入到 JS 沙箱中，为音源脚本提供受限的能力。
 * 音源脚本通过全局对象访问这些 API。
 * MVP 阶段定义桥接接口契约，实际 JS 执行在 JSSandbox 中对接。
 *
 * 设计思路：
 * - 只暴露必要的 HTTP 请求和日志能力
 * - 不开放文件系统、进程等危险 API
 * - 通过静态方法提供，方便在 Native 侧做权限校验
 */
export class JSBridge {
  /** HTTP GET 请求 */
  static async httpGet(url: string, headers: Record<string, string> = {}): Promise<string> {
    return await NetUtils.getString(url, headers)
  }

  /** 输出日志到 Native 日志系统 */
  static log(level: string, msg: string): void {
    switch (level) {
      case 'error':
        LogUtils.error(`[音源脚本] ${msg}`)
        break
      case 'warn':
        LogUtils.warn(`[音源脚本] ${msg}`)
        break
      default:
        LogUtils.info(`[音源脚本] ${msg}`)
    }
  }

  /**
   * 构建注入到 JS 沙箱的桥接代码（字符串形式）
   *
   * 在沙箱中创建音源接口，并动态挂载社区脚本需要的兼容全局名。
   * __nativeCall__ 由沙箱运行时实现，负责转发到 Native 侧对应方法。
   */
  static buildBridgeScript(): string {
    return `
      var sourceApi = {
        httpGet: function(url, headers) {
          return __nativeCall__('httpGet', url, headers || {})
        },
        log: function(level, msg) {
          __nativeCall__('log', level, msg)
        }
      };
      globalThis[String.fromCharCode(108, 120)] = sourceApi;
    `
  }
}
