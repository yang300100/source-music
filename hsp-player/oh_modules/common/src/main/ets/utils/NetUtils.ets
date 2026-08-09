import { http } from '@kit.NetworkKit'
import { LogUtils } from './LogUtils'

/**
 * 可取消的 HTTP 请求句柄（对齐参考 社区音源 { promise, cancelFn } 模式）
 */
export interface AbortableRequest {
  promise: Promise<string>
  abort: () => void
}

/** 完整 HTTP 响应，供 社区音源 音源协议桥接使用。 */
export interface RawHttpResponse {
  statusCode: number
  statusMessage: string
  headers: Record<string, string>
  body: string | number[]
}

/** 可取消的完整 HTTP 请求句柄。 */
export interface AbortableResponseRequest {
  promise: Promise<RawHttpResponse>
  abort: () => void
}

/**
 * HTTP 网络请求封装
 */
export class NetUtils {
  /** 进行中的 GET 请求去重（相同 URL 复用同一 Promise，避免重复请求） */
  private static inflightGet: Map<string, Promise<string>> = new Map()

  static async getString(url: string, headers: Record<string, string> = {}): Promise<string> {
    // 请求去重：相同 URL + headers 的并发请求只发一次
    const dedupKey = `${url}_${JSON.stringify(headers)}`
    const existing = NetUtils.inflightGet.get(dedupKey)
    if (existing) {
      return existing
    }
    const promise = NetUtils.doGet(url, headers)
    NetUtils.inflightGet.set(dedupKey, promise)
    promise.finally(() => {
      NetUtils.inflightGet.delete(dedupKey)
    })
    return promise
  }

  private static async doGet(url: string, headers: Record<string, string>): Promise<string> {
    try {
      const request = http.createHttp()
      const response = await request.request(url, {
        method: http.RequestMethod.GET,
        header: headers,
        connectTimeout: 30000,
        readTimeout: 30000
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

  static async head(url: string, headers: Record<string, string> = {}): Promise<number> {
    try {
      const request = http.createHttp()
      const response = await request.request(url, {
        method: http.RequestMethod.HEAD,
        header: headers,
        connectTimeout: 10000,
        readTimeout: 10000
      })
      request.destroy()
      return response.responseCode
    } catch (err) {
      LogUtils.error(`HTTP HEAD ${url} 失败: ${JSON.stringify(err)}`)
      return -1
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
      const response = await NetUtils.requestResponse(url, method, headers, body)
      if (response.statusCode >= 200 && response.statusCode < 300) {
        return response.body as string
      }
      LogUtils.warn(`HTTP ${method} ${url} 返回 ${response.statusCode}`)
      return ''
    } catch (err) {
      LogUtils.error(`HTTP ${method} ${url} 失败: ${JSON.stringify(err)}`)
      return ''
    }
  }

  /**
   * 返回真实状态码、响应头和响应体，不把非 2xx 响应伪装成空的 200。
   * 网络层异常会抛出，由音源请求桥转换为 callback(err, null, null)。
   */
  static async requestResponse(
    url: string,
    method: string = 'GET',
    headers: Record<string, string> = {},
    body: string = '',
    timeout: number = 30000,
    binary: boolean = false
  ): Promise<RawHttpResponse> {
    const request = http.createHttp()
    try {
      const response = await request.request(url, {
        method: NetUtils.toRequestMethod(method),
        header: headers,
        extraData: body,
        connectTimeout: timeout,
        readTimeout: timeout,
        expectDataType: binary ? http.HttpDataType.ARRAY_BUFFER : http.HttpDataType.STRING
      })
      let responseBody: string | number[] = ''
      if (binary) {
        const view = new Uint8Array(response.result as ArrayBuffer)
        const bytes: number[] = []
        for (let i = 0; i < view.length; i++) bytes.push(view[i])
        responseBody = bytes
      } else {
        responseBody = typeof response.result === 'string' ? response.result : JSON.stringify(response.result)
      }
      return {
        statusCode: response.responseCode,
        statusMessage: NetUtils.toStatusMessage(response.responseCode),
        headers: NetUtils.normalizeResponseHeaders(response.header as Record<string, Object>),
        body: responseBody
      }
    } finally {
      request.destroy()
    }
  }

  /**
   * 可取消的通用请求（对齐参考 社区音源 { promise, cancelFn } 模式）
   * 调用方在快速切歌/放弃等待时可调用 abort() 中止进行中的网络请求
   */
  static requestRawWithAbort(
    url: string,
    method: string = 'GET',
    headers: Record<string, string> = {},
    body: string = ''
  ): AbortableRequest {
    const request = http.createHttp()
    const methodMap: Record<string, http.RequestMethod> = {
      'GET': http.RequestMethod.GET,
      'POST': http.RequestMethod.POST,
      'PUT': http.RequestMethod.PUT,
      'DELETE': http.RequestMethod.DELETE,
      'HEAD': http.RequestMethod.HEAD
    }
    const httpMethod = methodMap[method.toUpperCase()] ?? http.RequestMethod.GET

    const promise = request.request(url, {
      method: httpMethod,
      header: headers,
      extraData: body,
      connectTimeout: 30000,
      readTimeout: 30000,
      expectDataType: http.HttpDataType.STRING
    }).then((response) => {
      request.destroy()
      if (response.responseCode >= 200 && response.responseCode < 300) {
        return response.result as string
      }
      LogUtils.warn(`HTTP ${method} ${url} 返回 ${response.responseCode}`)
      return ''
    }).catch((err: Error) => {
      request.destroy()
      LogUtils.error(`HTTP ${method} ${url} 失败: ${JSON.stringify(err)}`)
      return ''
    })

    const abort = (): void => {
      try {
        request.destroy()
      } catch (e) {
        // 忽略销毁异常
      }
    }
    return { promise: promise, abort: abort }
  }

  /** 可取消的完整响应请求，语义与 社区音源 的 request/cancelFn 一致。 */
  static requestResponseWithAbort(
    url: string,
    method: string = 'GET',
    headers: Record<string, string> = {},
    body: string = '',
    timeout: number = 30000,
    binary: boolean = false
  ): AbortableResponseRequest {
    const request = http.createHttp()
    const promise = request.request(url, {
      method: NetUtils.toRequestMethod(method),
      header: headers,
      extraData: body,
      connectTimeout: timeout,
      readTimeout: timeout,
      expectDataType: binary ? http.HttpDataType.ARRAY_BUFFER : http.HttpDataType.STRING
    }).then((response) => {
      let responseBody: string | number[] = ''
      if (binary) {
        const view = new Uint8Array(response.result as ArrayBuffer)
        const bytes: number[] = []
        for (let i = 0; i < view.length; i++) bytes.push(view[i])
        responseBody = bytes
      } else {
        responseBody = typeof response.result === 'string' ? response.result : JSON.stringify(response.result)
      }
      const result: RawHttpResponse = {
        statusCode: response.responseCode,
        statusMessage: NetUtils.toStatusMessage(response.responseCode),
        headers: NetUtils.normalizeResponseHeaders(response.header as Record<string, Object>),
        body: responseBody
      }
      return result
    }).finally(() => {
      request.destroy()
    })

    const abort = (): void => {
      try {
        request.destroy()
      } catch (e) {
        // 忽略销毁异常
      }
    }
    return { promise: promise, abort: abort }
  }

  private static toRequestMethod(method: string): http.RequestMethod {
    const methodMap: Record<string, http.RequestMethod> = {
      'GET': http.RequestMethod.GET,
      'POST': http.RequestMethod.POST,
      'PUT': http.RequestMethod.PUT,
      'DELETE': http.RequestMethod.DELETE,
      'HEAD': http.RequestMethod.HEAD
    }
    return methodMap[method.toUpperCase()] ?? http.RequestMethod.GET
  }

  private static normalizeResponseHeaders(raw: Record<string, Object>): Record<string, string> {
    const headers: Record<string, string> = {}
    if (!raw) return headers
    const keys = Object.keys(raw)
    for (let i = 0; i < keys.length; i++) {
      const value = raw[keys[i]]
      headers[keys[i]] = value === undefined || value === null ? '' : String(value)
    }
    return headers
  }

  private static toStatusMessage(statusCode: number): string {
    const messages: Record<number, string> = {
      200: 'OK', 201: 'Created', 202: 'Accepted', 204: 'No Content',
      301: 'Moved Permanently', 302: 'Found', 304: 'Not Modified',
      400: 'Bad Request', 401: 'Unauthorized', 403: 'Forbidden', 404: 'Not Found',
      408: 'Request Timeout', 429: 'Too Many Requests',
      500: 'Internal Server Error', 502: 'Bad Gateway', 503: 'Service Unavailable', 504: 'Gateway Timeout'
    }
    return messages[statusCode] ?? ''
  }
}
