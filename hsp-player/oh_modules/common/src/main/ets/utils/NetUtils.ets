import { http } from '@kit.NetworkKit'
import { LogUtils } from './LogUtils'

/**
 * HTTP 网络请求封装
 */
export class NetUtils {
  static async getString(url: string, headers: Record<string, string> = {}): Promise<string> {
    try {
      const request = http.createHttp()
      const response = await request.request(url, {
        method: http.RequestMethod.GET,
        header: headers,
        connectTimeout: 15000,
        readTimeout: 15000
      })
      request.destroy()
      if (response.responseCode === 200) {
        return response.result as string
      }
      LogUtils.warn(`HTTP GET ${url} 返回 ${response.responseCode}`)
      return ''
    } catch (err) {
      LogUtils.error(`HTTP GET ${url} 失败: ${JSON.stringify(err)}`)
      return ''
    }
  }

  static async getJSON<T>(url: string, headers: Record<string, string> = {}): Promise<T | null> {
    const body = await NetUtils.getString(url, headers)
    if (!body) return null
    try {
      return JSON.parse(body) as T
    } catch {
      LogUtils.error(`JSON 解析失败: ${url}`)
      return null
    }
  }

  /**
   * 通用请求（支持 GET/POST 等，供 JS 音源脚本桥接使用）
   * @param url 请求地址
   * @param method 请求方法（GET/POST/HEAD 等）
   * @param headers 请求头
   * @param body 请求体（字符串）
   * @returns 响应体字符串（失败返回空串）
   */
  static async requestRaw(
    url: string,
    method: string = 'GET',
    headers: Record<string, string> = {},
    body: string = ''
  ): Promise<string> {
    try {
      const request = http.createHttp()
      const methodMap: Record<string, http.RequestMethod> = {
        'GET': http.RequestMethod.GET,
        'POST': http.RequestMethod.POST,
        'PUT': http.RequestMethod.PUT,
        'DELETE': http.RequestMethod.DELETE,
        'HEAD': http.RequestMethod.HEAD
      }
      const httpMethod = methodMap[method.toUpperCase()] ?? http.RequestMethod.GET

      const response = await request.request(url, {
        method: httpMethod,
        header: headers,
        extraData: body,
        connectTimeout: 30000,
        readTimeout: 30000,
        expectDataType: http.HttpDataType.STRING
      })
      request.destroy()
      if (response.responseCode >= 200 && response.responseCode < 300) {
        return response.result as string
      }
      LogUtils.warn(`HTTP ${method} ${url} 返回 ${response.responseCode}`)
      return ''
    } catch (err) {
      LogUtils.error(`HTTP ${method} ${url} 失败: ${JSON.stringify(err)}`)
      return ''
    }
  }
}
