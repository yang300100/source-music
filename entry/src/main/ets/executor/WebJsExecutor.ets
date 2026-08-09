import { webview } from '@kit.ArkWeb'
import { NetUtils, LogUtils } from 'common'
import { JsExecutor } from 'hsp_source'

/**
 * 基于 WebView(ArkWeb) 的 JS 执行器
 *
 * 与 JSVM 不同：ArkWeb 引擎执行脚本无需 ACL 受限权限，且提供完整浏览器环境。
 * 脚本网络请求通过 JavaScriptProxy 桥接到 ArkTS 原生 http
 * （Web 页面 fetch 受 CORS/混合内容限制会静默挂起，原生网络无此限制）。
 * 由 Index 挂载隐藏 Web 组件后注册到 JsExecutorRegistry。
 */
export class WebJsExecutor implements JsExecutor {
  /** 单次 runJavaScript 最长等待时间，避免第三方脚本占死 ArkWeb 渲染进程 */
  private static readonly EXECUTION_TIMEOUT_MS: number = 8000
  private controller: webview.WebviewController | null = null
  private ready: boolean = false

  /** 绑定 Web 组件控制器（Web 组件加载完成后调用） */
  attach(controller: webview.WebviewController): void {
    this.controller = controller
  }

  /** 标记页面就绪 */
  markReady(): void {
    this.ready = true
  }

  /** 渲染进程退出或页面开始恢复时，暂停接收新的脚本调用 */
  markNotReady(): void {
    this.ready = false
  }

  isReady(): boolean {
    return this.ready && this.controller !== null
  }

  /** 在 Web 引擎中执行脚本，返回结果字符串（错误时返回 script error: ...） */
  async evalScript(script: string): Promise<string> {
    LogUtils.info(`[Web执行器] evalScript 长度=${script.length}, 前120: ${script.substring(0, 120)}`)
    const r = await this.runJs(script)
    LogUtils.info(`[Web执行器] evalScript 结果前100: ${r ? r.substring(0, 100) : '(空)'}`)
    return r
  }

  /** 调用全局函数，返回 JSON 字符串结果（ArkWeb runJavaScript 已自动 JSON 序列化，无需再包装） */
  async callGlobalFunction(fnName: string, argsJson: string): Promise<string> {
    // argsJson 为 JSON 数组字符串，用 spread 展开为多个实参（如 ["id","action",{...}] → fn("id","action",{...})）
    const js = `globalThis[${JSON.stringify(fnName)}] ? (globalThis[${JSON.stringify(fnName)}](...${argsJson}) ?? null) : null`
    LogUtils.info(`[Web执行器] callGlobalFunction: ${fnName}, args前80: ${argsJson.substring(0, 80)}`)
    const r = await this.runJs(js)
    LogUtils.info(`[Web执行器] callGlobalFunction 结果: ${r ? r.substring(0, 100) : '(空)'}`)
    return r
  }

  /**
   * 原生网络请求（JavaScriptProxy 桥接：Web 页面音源请求 → 这里）
   * 请求完成后通过 runJavaScript 调用 window.__sourceNetCb__ 回传结果
   */
  async nativeRequest(url: string, optionsJson: string, callbackId: string): Promise<void> {
    LogUtils.info(`[Web执行器] 原生请求收到: url=${url.substring(0, 100)}, id=${callbackId}, opts=${optionsJson.substring(0, 100)}`)
    try {
      let opts: Record<string, Object> = {}
      try {
        opts = JSON.parse(optionsJson) as Record<string, Object>
      } catch (e) {
        opts = {}
      }
      const method = (opts['method'] as string) ?? 'GET'
      const headers = (opts['headers'] as Record<string, string>) ?? {}
      const body = (opts['body'] as string) ?? ''
      LogUtils.info(`[Web执行器] 发起原生请求: ${method} ${url.substring(0, 120)}`)
      const respBody = await NetUtils.requestRaw(url, method, headers, body)
      LogUtils.info(`[Web执行器] 原生请求完成: len=${respBody.length}, 前80=${respBody.substring(0, 80)}`)
      await this.runJs(
        `window.__sourceNetCb__(${JSON.stringify(callbackId)}, 'null', ${JSON.stringify(respBody)})`)
    } catch (err) {
      LogUtils.warn(`[Web执行器] 原生请求失败: ${JSON.stringify(err)}`)
      await this.runJs(
        `window.__sourceNetCb__(${JSON.stringify(callbackId)}, ${JSON.stringify(JSON.stringify(String(err)))}, '')`)
    }
  }

  private runJs(js: string): Promise<string> {
    return new Promise<string>((resolve) => {
      const controller = this.controller
      if (!controller) {
        resolve('script error: webview not ready')
        return
      }
      let settled = false
      const timer = setTimeout(() => {
        if (settled) return
        settled = true
        this.ready = false
        LogUtils.error(`[Web执行器] 执行超时(${WebJsExecutor.EXECUTION_TIMEOUT_MS}ms)，刷新执行页面`)
        try {
          controller.stop()
          controller.refresh()
        } catch (recoverErr) {
          LogUtils.warn(`[Web执行器] 超时恢复失败: ${JSON.stringify(recoverErr)}`)
        }
        resolve('script error: webview execution timeout')
      }, WebJsExecutor.EXECUTION_TIMEOUT_MS)
      try {
        controller.runJavaScript(js, (error: Error, result: string) => {
          if (settled) return
          settled = true
          clearTimeout(timer)
          if (error) {
            LogUtils.warn(`[Web执行器] 执行异常: ${error.message}`)
            resolve(`script error: ${error.message}`)
          } else {
            resolve(result)
          }
        })
      } catch (err) {
        if (settled) return
        settled = true
        clearTimeout(timer)
        LogUtils.warn(`[Web执行器] 调用异常: ${JSON.stringify(err)}`)
        resolve(`script error: ${JSON.stringify(err)}`)
      }
    })
  }
}
