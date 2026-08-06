import { LogUtils, SourceInstance, SourceInfo } from 'common'
import { JSScriptSource } from '../sources/JSScriptSource'

/**
 * JS 音源沙箱（完整实现）
 *
 * 基于鸿蒙系统 JSVM-API（libjsvm.so）提供完整的 JavaScript 执行环境：
 * 1. 创建隔离的 JS 虚拟机（VM + Env）
 * 2. 注入受限的 lx 全局环境（对齐原版 lx-music preload）
 * 3. 执行用户导入的音源脚本
 * 4. 脚本的 lx.request 网络请求桥接到 ArkTS 网络层
 *
 * 安全措施（对齐原版）：
 * - 引擎隔离：脚本无法直接访问文件/系统
 * - 只注入白名单 API（__lx_request__/__lx_log__）
 * - 禁用 eval（preload 脚本内覆盖）
 * - 超时终止：脚本 action 调用 5 秒超时
 */
export class JSSandbox {
  /**
   * 从脚本内容创建可用的音源实例
   * @param scriptContent JS 音源脚本源码
   * @param sourceInfo 音源元信息（来自头部注释解析）
   * @returns 可用的音源实例，失败返回 null
   */
  static async createSource(
    scriptContent: string,
    sourceInfo: SourceInfo
  ): Promise<SourceInstance | null> {
    LogUtils.info('JSSandbox: 加载音源脚本', sourceInfo.name)
    try {
      const source = new JSScriptSource(scriptContent, sourceInfo)
      const ok = await source.init()
      if (!ok) {
        LogUtils.error('JSSandbox: 沙箱初始化失败', sourceInfo.name)
        return null
      }
      return source
    } catch (err) {
      LogUtils.error('JSSandbox: 创建音源失败', JSON.stringify(err))
      return null
    }
  }

  /**
   * 校验脚本是否为有效的 lx-music 音源格式（对齐原版 addUserApi 逻辑）
   *
   * 原版只检查：脚本开头必须包含块注释（以斜杠星号开头、星号斜杠结尾）
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
    return null
  }
}
