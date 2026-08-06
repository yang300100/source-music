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
}
