/**
 * JS 脚本执行器接口（替代 JSVM 沙箱的可插拔执行引擎）
 *
 * JSVM 的 RunScript 需要 ACL 受限权限（ohos.permission.kernel.ALLOW_EXECUTABLE_FORT_MEMORY），
 * 普通签名应用无法获得，导致部分脚本被系统拒绝执行。
 * 方案：由 entry 提供基于 WebView(ArkWeb) 的执行器（无 ACL 限制、完整浏览器环境），
 * 通过注册表注入；JSScriptSource 优先使用外部执行器，无注册时回退 JSVM。
 */
export interface JsExecutor {
  /** 当前执行页面是否可以接受脚本调用 */
  isReady(): boolean
  /** 执行脚本（注入环境或用户脚本），返回执行结果字符串 */
  evalScript(script: string): Promise<string>
  /** 调用全局函数（带 JSON 参数），返回 JSON 字符串结果 */
  callGlobalFunction(fnName: string, argsJson: string): Promise<string>
}

/** 执行器注册表（entry 启动时注册 WebView 执行器） */
export class JsExecutorRegistry {
  static instance: JsExecutor | null = null

  static register(executor: JsExecutor): void {
    JsExecutorRegistry.instance = executor
  }

  static isAvailable(): boolean {
    return JsExecutorRegistry.instance !== null && JsExecutorRegistry.instance.isReady()
  }
}
