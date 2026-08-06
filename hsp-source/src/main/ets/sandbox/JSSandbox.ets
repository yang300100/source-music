import { LogUtils, SourceInstance, SourceInfo } from 'common'

/**
 * JS 音源沙箱
 *
 * 负责在受限环境中执行用户导入的 .js 音源脚本。
 * 与 lx-music 社区生态兼容，让用户能导入开源的音源脚本。
 *
 * MVP 阶段提供框架骨架，后续实现方案之一：
 * - 方案 A：集成 QuickJS C 库（最佳兼容性，需要 NAPI 封装）
 * - 方案 B：使用鸿蒙 WebView 的 JS 引擎
 * - 方案 C：使用 Worker 线程 + 受限全局对象
 *
 * 当前阶段：API 占位 + 脚本安全校验
 */
export class JSSandbox {
  /**
   * 从文件内容创建音源实例（MVP 占位框架）
   * @param scriptContent JS 音源脚本内容
   * @param sourceInfo 音源元信息
   * @returns 音源实例，沙箱未完整实现时返回 null
   */
  static async createSource(
    scriptContent: string,
    sourceInfo: SourceInfo
  ): Promise<SourceInstance | null> {
    LogUtils.info('JSSandbox: 加载音源脚本', sourceInfo.name)
    LogUtils.warn('JSSandbox: 沙箱尚未完整实现，返回空结果')

    // 先做安全校验
    const securityError = this.validateScript(scriptContent)
    if (securityError) {
      LogUtils.error('JSSandbox: 脚本安全校验未通过', securityError)
      return null
    }

    // TODO: 在沙箱中执行脚本，获取 SourceInstance
    return null
  }

  /**
   * 验证脚本安全性（危险 API 黑名单检查）
   *
   * 检查脚本是否包含以下危险操作：
   * - require/import（模块加载）
   * - eval/Function（动态代码执行）
   * - fs/child_process/process（Node.js 原生模块访问）
   *
   * @param scriptContent JS 脚本源码
   * @returns 错误信息字符串，null 表示通过校验
   */
  static validateScript(scriptContent: string): string | null {
    const blockedPatterns = [
      /require\s*\(/g,
      /import\s+/g,
      /eval\s*\(/g,
      /Function\s*\(/g,
      /fs\./g,
      /child_process/g,
      /process\./g
    ]

    for (const pattern of blockedPatterns) {
      if (pattern.test(scriptContent)) {
        return `脚本包含禁止的操作: ${pattern.source}`
      }
    }

    return null
  }
}
