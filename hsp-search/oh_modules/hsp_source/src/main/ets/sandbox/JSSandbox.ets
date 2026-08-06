import { LogUtils, SourceInstance, SourceInfo } from 'common'

/**
 * JS 音源沙箱
 *
 * 负责在受限环境中执行用户导入的 .js 音源脚本。
 * 与 lx-music 社区生态兼容，让用户能导入开源的音源脚本。
 *
 * 当前阶段说明：
 * - 元信息解析：直接正则解析脚本头部注释（对齐原版 lx-music 逻辑）
 * - 完整沙箱执行：需要 QuickJS NAPI 集成（见 Task 40 调研）
 *
 * 安全策略（对齐原版）：
 * - 导入时只校验"脚本是否为有效音源格式"（头部块注释存在）
 * - 危险 API（eval/Function/require 等）在真正执行时才需要沙箱隔离
 * - 当前不执行脚本，因此不阻断包含危险字符串的脚本导入
 */
export class JSSandbox {
  /**
   * 从文件内容创建音源实例（需要 QuickJS 沙箱，尚未实现）
   * 当前阶段元信息解析由 JSSourceAdapter 完成
   */
  static async createSource(
    scriptContent: string,
    sourceInfo: SourceInfo
  ): Promise<SourceInstance | null> {
    LogUtils.info('JSSandbox: 加载音源脚本', sourceInfo.name)
    LogUtils.warn('JSSandbox: 完整沙箱执行尚未实现（需要 QuickJS），当前仅做格式校验')
    return null
  }

  /**
   * 校验脚本是否为有效的 lx-music 音源格式（对齐原版 addUserApi 逻辑）
   *
   * 原版只检查：脚本开头必须包含块注释（以斜杠星号开头、星号斜杠结尾）
   * 危险 API 检查不做为导入拦截条件（脚本未真正执行）
   *
   * @param scriptContent JS 脚本源码
   * @returns 错误信息字符串，null 表示通过校验
   */
  static validateScript(scriptContent: string): string | null {
    if (!scriptContent || scriptContent.trim().length === 0) {
      return '脚本内容为空'
    }

    // 对齐原版：检查脚本开头是否有块注释
    const commentMatch = /^\/\*[\S\s]+?\*\//.exec(scriptContent)
    if (!commentMatch) {
      return '脚本格式无效：缺少开头的音源信息注释（/* @name ... */）'
    }

    // 危险模式仅记录日志（提示性），不阻断导入
    const suspiciousPatterns = [
      /require\s*\(/g,
      /import\s+/g,
      /eval\s*\(/g,
      /Function\s*\(/g,
      /child_process/g,
      /process\./g
    ]
    for (const pattern of suspiciousPatterns) {
      pattern.lastIndex = 0
      if (pattern.test(scriptContent)) {
        LogUtils.warn(`音源脚本包含可疑模式（仅提示）: ${pattern.source}`)
      }
    }

    return null
  }
}
