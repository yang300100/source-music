import {
  SourceInfo,
  MusicItem,
  SearchResult,
  LyricLine,
  PlaylistInfo,
  MusicQuality,
  MusicQualityInfo,
  SourceType,
  HotSearchItem,
  LogUtils,
  NetUtils
} from 'common'
import { BaseSource } from '../api/SourceAPI'

// 引入 native 桥接模块（jsvm_bridge.so，HSP 内标准加载方式）
import jsvmBridgeNative from 'libjsvm_bridge.so'

interface JsvmBridgeApi {
  createVM(): number
  destroyVM(handle: number): void
  evalScript(handle: number, script: string): string
  callGlobalFunction(handle: number, fnName: string, argsJson: string): string
  setNativeResult(handle: number, requestId: string, errorJson: string, responseJson: string): void
}

/** lx 运行环境注入脚本（对齐原版 user-api-preload.js 核心能力） */
const PRELOAD_SCRIPT: string = `
(function() {
  var EVENT_NAMES = { request: 'request', inited: 'inited', updateAlert: 'updateAlert' };
  var events = { request: null };
  var resultStore = {};
  var requestSeq = 0;

  // ---- 内联 MD5 实现（供 utils.crypto.md5 使用）----
  var md5 = (function() {
    function safeAdd(x, y) { var lsw = (x & 0xFFFF) + (y & 0xFFFF); return (((x >> 16) + (y >> 16) + (lsw >> 16)) << 16) | (lsw & 0xFFFF); }
    function bitRotateLeft(num, cnt) { return (num << cnt) | (num >>> (32 - cnt)); }
    function md5cmn(q, a, b, x, s, t) { return safeAdd(bitRotateLeft(safeAdd(safeAdd(a, q), safeAdd(x, t)), s), b); }
    function md5ff(a, b, c, d, x, s, t) { return md5cmn((b & c) | (~b & d), a, b, x, s, t); }
    function md5gg(a, b, c, d, x, s, t) { return md5cmn((b & d) | (c & ~d), a, b, x, s, t); }
    function md5hh(a, b, c, d, x, s, t) { return md5cmn(b ^ c ^ d, a, b, x, s, t); }
    function md5ii(a, b, c, d, x, s, t) { return md5cmn(c ^ (b | ~d), a, b, x, s, t); }
    function binl2hex(binarray) {
      var hexTab = '0123456789abcdef', str = '';
      for (var i = 0; i < binarray.length * 4; i++) {
        str += hexTab.charAt((binarray[i >> 2] >> ((i % 4) * 8 + 4)) & 0xF) + hexTab.charAt((binarray[i >> 2] >> ((i % 4) * 8)) & 0xF);
      }
      return str;
    }
    function binl2rstr(input) {
      var output = '';
      for (var i = 0; i < input.length * 32; i += 8) {
        output += String.fromCharCode((input[i >> 5] >>> (i % 32)) & 0xFF);
      }
      return output;
    }
    function rstr2binl(input) {
      var output = [], i, ol = input.length * 8;
      for (i = 0; i < ol; i += 8) output[i >> 5] |= (input.charCodeAt(i / 8) & 0xFF) << (i % 32);
      return output;
    }
    function rstr2hex(input) { return binl2hex(rstr2binl(input)); }
    function str2rstrUTF8(input) { return unescape(encodeURIComponent(input)); }
    function rstrMD5(s) {
      var n = s.length, state = [1732584193, -271733879, -1732584194, 271733878];
      var i, tail = [(n >> 2) & 0x3F], count = (n & 0x3F) << 3;
      for (i = 0; i < 64; i++) tail[i < 14 ? i : 15] = 0;
      tail[14] = n << 3; tail[15] = n >>> 29; tail[count / 8] |= 0x80;
      for (i = 0; i < tail.length; i += 16) {
        var a = state[0], b = state[1], c = state[2], d = state[3];
        var X = tail.slice(i, i + 16);
        a = md5ff(a, b, c, d, X[0], 7, -680876936); d = md5ff(d, a, b, c, X[1], 12, -389564586);
        c = md5ff(c, d, a, b, X[2], 17, 606105819); b = md5ff(b, c, d, a, X[3], 22, -1044525330);
        a = md5ff(a, b, c, d, X[4], 7, -176418897); d = md5ff(d, a, b, c, X[5], 12, 1200080426);
        c = md5ff(c, d, a, b, X[6], 17, -1473231341); b = md5ff(b, c, d, a, X[7], 22, -45705983);
        a = md5ff(a, b, c, d, X[8], 7, 1770035416); d = md5ff(d, a, b, c, X[9], 12, -1958414417);
        c = md5ff(c, d, a, b, X[10], 17, -42063); b = md5ff(b, c, d, a, X[11], 22, -1990404162);
        a = md5ff(a, b, c, d, X[12], 7, 1804603682); d = md5ff(d, a, b, c, X[13], 12, -40341101);
        c = md5ff(c, d, a, b, X[14], 17, -1502002290); b = md5ff(b, c, d, a, X[15], 22, 1236535329);
        a = md5gg(a, b, c, d, X[1], 5, -165796510); d = md5gg(d, a, b, c, X[6], 9, -1069501632);
        c = md5gg(c, d, a, b, X[11], 14, 643717713); b = md5gg(b, c, d, a, X[0], 20, -373897302);
        a = md5gg(a, b, c, d, X[5], 5, -701558691); d = md5gg(d, a, b, c, X[10], 9, 38016083);
        c = md5gg(c, d, a, b, X[15], 14, -660478335); b = md5gg(b, c, d, a, X[4], 20, -405537848);
        a = md5gg(a, b, c, d, X[9], 5, 568446438); d = md5gg(d, a, b, c, X[14], 9, -1019803690);
        c = md5gg(c, d, a, b, X[3], 14, -187363961); b = md5gg(b, c, d, a, X[8], 20, 1163531501);
        a = md5gg(a, b, c, d, X[13], 5, -1444681467); d = md5gg(d, a, b, c, X[2], 9, -51403784);
        c = md5gg(c, d, a, b, X[7], 14, 1735328473); b = md5gg(b, c, d, a, X[12], 20, -1926607734);
        a = md5hh(a, b, c, d, X[5], 4, -378558); d = md5hh(d, a, b, c, X[8], 11, -2022574463);
        c = md5hh(c, d, a, b, X[11], 16, 1839030562); b = md5hh(b, c, d, a, X[14], 23, -35309556);
        a = md5hh(a, b, c, d, X[1], 4, -1530992060); d = md5hh(d, a, b, c, X[4], 11, 1272893353);
        c = md5hh(c, d, a, b, X[7], 16, -155497632); b = md5hh(b, c, d, a, X[10], 23, -1094730640);
        a = md5hh(a, b, c, d, X[13], 4, 681279174); d = md5hh(d, a, b, c, X[0], 11, -358537222);
        c = md5hh(c, d, a, b, X[3], 16, -722521979); b = md5hh(b, c, d, a, X[6], 23, 76029189);
        a = md5hh(a, b, c, d, X[9], 4, -640364487); d = md5hh(d, a, b, c, X[12], 11, -421815835);
        c = md5hh(c, d, a, b, X[15], 16, 530742520); b = md5hh(b, c, d, a, X[2], 23, -995338651);
        a = md5ii(a, b, c, d, X[0], 6, -198630844); d = md5ii(d, a, b, c, X[7], 10, 1126891415);
        c = md5ii(c, d, a, b, X[14], 15, -1416354905); b = md5ii(b, c, d, a, X[5], 21, -57434055);
        a = md5ii(a, b, c, d, X[12], 6, 1700485571); d = md5ii(d, a, b, c, X[3], 10, -1894986606);
        c = md5ii(c, d, a, b, X[10], 15, -1051523); b = md5ii(b, c, d, a, X[1], 21, -2054922799);
        a = md5ii(a, b, c, d, X[8], 6, 1873313359); d = md5ii(d, a, b, c, X[15], 10, -30611744);
        c = md5ii(c, d, a, b, X[6], 15, -1560198380); b = md5ii(b, c, d, a, X[13], 21, 1309151649);
        a = md5ii(a, b, c, d, X[4], 6, -145523070); d = md5ii(d, a, b, c, X[11], 10, -1120210379);
        c = md5ii(c, d, a, b, X[2], 15, 718787259); b = md5ii(b, c, d, a, X[9], 21, -343485551);
        state[0] = safeAdd(a, state[0]); state[1] = safeAdd(b, state[1]);
        state[2] = safeAdd(c, state[2]); state[3] = safeAdd(d, state[3]);
      }
      return binl2rstr(state);
    }
    function md5(s) { return rstr2hex(rstrMD5(str2rstrUTF8(s))); }
    return md5;
  })();

  // ---- utils ----
  var utils = {
    crypto: {
      md5: function(str) {
        if (typeof str !== 'string') throw new Error('param required a string');
        return md5(str);
      },
      aesEncrypt: function() { throw new Error('aesEncrypt not supported yet'); },
      rsaEncrypt: function() { throw new Error('rsaEncrypt not supported yet'); },
      randomBytes: function(size) {
        var arr = new Uint8Array(size);
        for (var i = 0; i < size; i++) arr[i] = Math.floor(Math.random() * 256);
        return arr;
      }
    },
    buffer: {
      from: function(input, encoding) {
        if (typeof input === 'string') {
          var bytes = [];
          for (var i = 0; i < input.length; i++) bytes.push(input.charCodeAt(i) & 0xFF);
          return new Uint8Array(bytes);
        }
        if (Array.isArray(input)) return new Uint8Array(input);
        throw new Error('Unsupported input type');
      },
      bufToString: function(buf, format) {
        if (!buf || !buf.length) return '';
        var str = '';
        for (var i = 0; i < buf.length; i++) str += String.fromCharCode(buf[i] & 0xFF);
        if (format === 'base64') {
          // 简易 base64 编码
          var b64 = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/';
          var out = '', j = 0;
          while (j < str.length) {
            var c1 = str.charCodeAt(j++) & 0xFF;
            var c2 = j < str.length ? str.charCodeAt(j++) & 0xFF : NaN;
            var c3 = j < str.length ? str.charCodeAt(j++) & 0xFF : NaN;
            out += b64.charAt(c1 >> 2);
            out += b64.charAt(((c1 & 3) << 4) | ((c2 >> 4) & 0xF));
            out += isNaN(c2) ? '=' : b64.charAt(((c2 & 0xF) << 2) | ((c3 >> 6) & 3));
            out += isNaN(c3) ? '=' : b64.charAt(c3 & 0x3F);
          }
          return out;
        }
        return str;
      }
    }
  };

  // ---- 请求队列（脚本侧不调原生，ArkTS 主动来取）----
  var pendingRequests = [];      // [{requestId, url, options}]
  var pendingCallbacks = {};    // requestId → callback

  // ---- lx 全局对象 ----
  var lx = {
    EVENT_NAMES: EVENT_NAMES,
    request: function(url, options, callback) {
      var cb = typeof options === 'function' ? options : callback;
      var opts = typeof options === 'object' && options ? options : {};
      var requestId = 'req_' + (++requestSeq) + '_' + Date.now();
      // 只入队，不调用原生（避免脚本执行栈内触发 V8 原生回调崩溃）
      pendingRequests.push({ requestId: requestId, url: url, options: opts });
      if (typeof cb === 'function') {
        pendingCallbacks[requestId] = cb;
      }
      return function() {};
    },
    send: function(eventName, data) {
      return new Promise(function(resolve, reject) {
        if (eventName === EVENT_NAMES.inited) {
          resolve();
        } else if (eventName === EVENT_NAMES.updateAlert) {
          resolve();
        } else {
          reject(new Error('The event is not supported: ' + eventName));
        }
      });
    },
    on: function(eventName, handler) {
      if (eventName === EVENT_NAMES.request) events.request = handler;
      return Promise.resolve();
    },
    utils: utils,
    version: '2.0.0',
    env: 'mobile',
    currentScriptInfo: {}
  };

  globalThis.lx = lx;

  // 安全：禁用 eval（沙箱核心措施之一）
  globalThis.eval = function() { throw new Error('eval is not available'); };

  // ---- ArkTS 侧 action 调用入口 ----
  globalThis.__lx_result__ = resultStore;
  globalThis.__lx_call__ = function(requestId, action, info) {
    if (!events.request) {
      resultStore[requestId] = { status: false, error: 'Request event is not defined' };
      return;
    }
    var reqInfo = info || {};
    Promise.resolve(events.request.call(lx, {
      source: reqInfo.source || 'custom',
      action: action,
      info: reqInfo
    })).then(function(result) {
      resultStore[requestId] = { status: true, result: result };
    }).catch(function(err) {
      resultStore[requestId] = { status: false, error: String((err && err.message) || err) };
    });
  };
  globalThis.__lx_takeResult__ = function(requestId) {
    if (!resultStore[requestId]) return null;
    var r = resultStore[requestId];
    delete resultStore[requestId];
    return r;
  };
  // 取走待发送的请求队列（ArkTS 轮询调用）
  globalThis.__lx_takeRequests__ = function() {
    if (pendingRequests.length === 0) return [];
    var list = pendingRequests;
    pendingRequests = [];
    return list;
  };
  // ArkTS 回传网络结果，恢复 JS 回调（由 native 在干净栈上调用）
  globalThis.__lx_resolveRequest__ = function(requestId, errorJson, responseJson) {
    var cb = pendingCallbacks[requestId];
    delete pendingCallbacks[requestId];
    if (typeof cb !== 'function') return;
    var err = null;
    var resp = null;
    try {
      if (errorJson && errorJson !== 'null') err = JSON.parse(errorJson);
      if (responseJson && responseJson !== 'null') resp = JSON.parse(responseJson);
    } catch (e) {
      err = e;
    }
    cb(err, resp, resp ? resp.body : null);
  };
  globalThis.setTimeout = globalThis.setTimeout || function() { return 0; };
  globalThis.clearTimeout = globalThis.clearTimeout || function() {};

  // 环境校验函数：验证 lx 全局就绪
  globalThis.__lx_check__ = function() {
    if (typeof globalThis.lx === 'object' && globalThis.lx.on && globalThis.lx.request) {
      return 'ok';
    }
    return 'lx not ready';
  };
})();
`

/**
 * JS 音源脚本源（基于 JSVM 沙箱完整执行）
 *
 * 流程：
 * 1. 创建 JSVM VM + Env（native 层）
 * 2. 执行 PRELOAD_SCRIPT 注入 lx 全局环境
 * 3. 执行用户音源脚本（脚本注册 request 事件处理器）
 * 4. search/getMusicInfo/getLyric 通过 __lx_call__ 触发脚本处理器
 * 5. 脚本内 lx.request → __lx_request__ → native → ArkTS 网络层 → 回调恢复
 */
export class JSScriptSource extends BaseSource {
  private handle: number = 0
  private bridge: JsvmBridgeApi | null = null
  private isReady: boolean = false
  private scriptContent: string = ''

  constructor(scriptContent: string, sourceInfo: SourceInfo) {
    super(sourceInfo)
    this.scriptContent = scriptContent
    this.isNative = false
  }

  /** 初始化沙箱：创建 VM、注入环境、执行脚本 */
  async init(): Promise<boolean> {
    // 1. 加载 native 桥接模块（import libjsvm_bridge.so 方式）
    this.bridge = jsvmBridgeNative as JsvmBridgeApi
    if (!this.bridge || !this.bridge.createVM) {
      LogUtils.error('JSVM 桥接模块加载失败（import 模块为空或无 createVM）')
      return false
    }
    LogUtils.info('JSVM 桥接模块加载成功')

    // 2. 创建 VM（无需回调：脚本请求通过 ArkTS 主动轮询队列获取）
    try {
      this.handle = this.bridge.createVM()
    } catch (vmErr) {
      LogUtils.error('JSVM VM 创建异常', JSON.stringify(vmErr))
      return false
    }
    if (!this.handle) {
      LogUtils.error('JSVM VM 创建失败（返回 0）')
      return false
    }
    LogUtils.info(`JSVM VM 创建成功: handle=${this.handle}`)

    // 3+4. 注入 lx 运行环境 + 执行用户音源脚本
    // 重要：JSVM 每次 RunScript 之间全局不共享，必须合并为一次执行！
    try {
      const scriptRet = this.bridge.evalScript(this.handle, PRELOAD_SCRIPT + '\n' + this.scriptContent)
      LogUtils.info(`音源脚本执行结果: ${scriptRet}`)
      // 检查脚本执行是否报错（native 在出错时返回错误信息字符串）
      if (scriptRet && (scriptRet.includes('Error') || scriptRet.includes('error') || scriptRet.includes('异常'))) {
        LogUtils.error(`音源脚本执行报错: ${scriptRet}`)
        return false
      }
    } catch (scriptErr) {
      LogUtils.error('音源脚本执行异常', JSON.stringify(scriptErr))
      return false
    }

    // 5. 验证 lx 全局对象就绪
    try {
      const checkRet = this.bridge.callGlobalFunction(this.handle, '__lx_check__', '[]')
      LogUtils.info(`lx 环境校验: ${checkRet}`)
      if (checkRet !== '"ok"' && checkRet !== 'ok') {
        LogUtils.error(`lx 环境校验失败: ${checkRet}`)
        return false
      }
    } catch (checkErr) {
      LogUtils.error('lx 环境校验异常', JSON.stringify(checkErr))
      return false
    }

    this.isReady = true
    LogUtils.info(`JSVM 沙箱初始化完成: ${this.info.name} v${this.info.version}`)
    return true
  }

  /** 销毁沙箱 */
  destroy(): void {
    if (this.bridge && this.handle) {
      try {
        this.bridge.destroyVM(this.handle)
      } catch (err) {
        // 忽略销毁错误
      }
    }
    this.handle = 0
    this.isReady = false
  }

  /** 获取脚本内容（用于持久化保存） */
  getScriptContent(): string {
    return this.scriptContent
  }

  // ===== 请求处理（ArkTS 主动轮询，脚本侧不回调原生） =====

  /** 发送网络请求并回传结果给 JS */
  private async doNetworkRequest(requestId: string, url: string, optionsJson: string): Promise<void> {
    if (!this.bridge) return
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
      const respBody = await NetUtils.requestRaw(url, method, headers, body)
      // 构造响应结构 { statusCode, headers, body }
      const respObj: Record<string, Object> = {}
      respObj['statusCode'] = 200
      const emptyHeaders: Record<string, string> = {}
      respObj['headers'] = emptyHeaders
      respObj['body'] = respBody
      const respJson = JSON.stringify(respObj)
      this.bridge.setNativeResult(this.handle, requestId, 'null', respJson)
    } catch (err) {
      this.bridge.setNativeResult(this.handle, requestId, JSON.stringify(String(err)), 'null')
    }
  }

  /** 触发脚本 action 并等待结果（内含请求处理循环） */
  private async callAction(action: string, info: Record<string, Object>): Promise<string> {
    if (!this.bridge || !this.isReady) return '{"status":false,"error":"sandbox not ready"}'
    const requestId = `call_${Date.now()}_${Math.floor(Math.random() * 100000)}`
    // 注入 source 标识
    const callInfo: Record<string, Object> = {}
    const keys = Object.keys(info)
    for (let i = 0; i < keys.length; i++) {
      callInfo[keys[i]] = info[keys[i]]
    }
    callInfo['source'] = String(this.info.type)
    LogUtils.info(`[沙箱] action=${action} requestId=${requestId} 开始`)

    // 启动脚本 handler
    let callRet = ''
    try {
      callRet = this.bridge.callGlobalFunction(this.handle, '__lx_call__', JSON.stringify([requestId, action, callInfo]))
    } catch (callErr) {
      LogUtils.error(`[沙箱] __lx_call__ 调用异常`, JSON.stringify(callErr))
      return '{"status":false,"error":"call exception"}'
    }
    LogUtils.info(`[沙箱] __lx_call__ 返回: ${callRet}`)

    // 等待循环：处理脚本请求 + 轮询结果（最多 15 秒）
    const deadline = Date.now() + 15000
    while (Date.now() < deadline) {
      // 1. 取脚本挂起的网络请求并发起
      try {
        const reqsJson = this.bridge.callGlobalFunction(this.handle, '__lx_takeRequests__', '[]')
        if (reqsJson && reqsJson !== '[]' && reqsJson !== 'null') {
          const reqs = JSON.parse(reqsJson) as Array<Record<string, Object>>
          for (let i = 0; i < reqs.length; i++) {
            const req = reqs[i]
            const reqId = (req['requestId'] as string) ?? ''
            const reqUrl = (req['url'] as string) ?? ''
            const reqOpts = JSON.stringify(req['options'] ?? {})
            if (reqId && reqUrl) {
              LogUtils.info(`[沙箱] 网络请求: ${reqUrl.substring(0, 120)}`)
              this.doNetworkRequest(reqId, reqUrl, reqOpts)
            }
          }
        }
      } catch (reqErr) {
        LogUtils.error(`[沙箱] 取请求队列异常`, JSON.stringify(reqErr))
      }

      // 2. 检查脚本结果
      try {
        const r = this.bridge.callGlobalFunction(this.handle, '__lx_takeResult__', JSON.stringify([requestId]))
        if (r && r !== 'null' && r !== '') {
          LogUtils.info(`[沙箱] action=${action} 结果: ${r.substring(0, 200)}`)
          return r
        }
      } catch (resultErr) {
        LogUtils.error(`[沙箱] 取结果异常`, JSON.stringify(resultErr))
        return '{"status":false,"error":"result exception"}'
      }

      // 3. 等待 50ms 再轮询
      await new Promise<void>((resolve) => setTimeout(resolve, 50))
    }

    LogUtils.warn(`[沙箱] action=${action} 超时`)
    return '{"status":false,"error":"script timeout"}'
  }

  // ===== BaseSource 接口实现 =====

  /** 搜索歌曲 */
  async search(query: string, page: number, _quality: MusicQuality): Promise<SearchResult> {
    const searchInfo: Record<string, Object> = {}
    searchInfo['query'] = query
    searchInfo['page'] = page
    searchInfo['type'] = 'music'
    const raw = await this.callAction('search', searchInfo)
    const list: MusicItem[] = []
    let total = 0
    try {
      const parsed = JSON.parse(raw) as Record<string, Object>
      if (parsed['status'] === false) {
        LogUtils.warn(`音源搜索失败: ${parsed['error']}`)
        return { list: [], total: 0, limit: 30, page: page, source: this.info.type }
      }
      // 兼容多种返回结构
      const result = parsed['result'] as Object
      const songs = this.extractSongs(result)
      for (const song of songs) {
        const item = this.mapSongItem(song)
        if (item) list.push(item)
      }
      total = list.length
    } catch (err) {
      LogUtils.warn('解析搜索结果失败', JSON.stringify(err))
    }
    return { list: list, total: total, limit: 30, page: page, source: this.info.type }
  }

  /** 获取播放 URL */
  async getMusicInfo(songmid: string, quality: MusicQuality): Promise<MusicItem> {
    const musicInfo: Record<string, Object> = {}
    musicInfo['songmid'] = songmid
    musicInfo['id'] = songmid
    musicInfo['quality'] = String(quality)
    const raw = await this.callAction('musicUrl', musicInfo)
    try {
      const parsed = JSON.parse(raw) as Record<string, Object>
      if (parsed['status'] === false) {
        throw new Error(String(parsed['error']))
      }
      // musicUrl action 返回 URL 字符串
      const url = parsed['result'] as string
      if (!url || !url.startsWith('http')) {
        throw new Error('无效的播放地址')
      }
      const types: Record<string, MusicQualityInfo> = {}
      types[String(quality)] = { url: url, size: 0, br: 0 }
      return {
        songmid: songmid,
        name: '',
        singer: '',
        albumName: '',
        interval: 0,
        imgUrl: '',
        lyricUrl: '',
        source: this.info.type,
        types: types
      }
    } catch (err) {
      throw new Error(`获取播放地址失败: ${JSON.stringify(err)}`)
    }
  }

  /** 获取歌词 */
  async getLyric(songmid: string): Promise<LyricLine[]> {
    const lyricInfo: Record<string, Object> = {}
    lyricInfo['songmid'] = songmid
    lyricInfo['id'] = songmid
    const raw = await this.callAction('lyric', lyricInfo)
    try {
      const parsed = JSON.parse(raw) as Record<string, Object>
      if (parsed['status'] === false) return []
      const result = parsed['result'] as Record<string, Object>
      const lyric = (result['lyric'] as string) ?? ''
      if (!lyric) return []
      return this.parseLRC(lyric)
    } catch (err) {
      return []
    }
  }

  /** 获取歌单（暂不支持） */
  async getPlaylistInfo(listid: string): Promise<PlaylistInfo> {
    throw new Error('JS 音源暂不支持歌单获取')
  }

  /** 获取热搜 */
  async getHotSearch(): Promise<HotSearchItem[]> {
    const raw = await this.callAction('hotSearch', {})
    const result: HotSearchItem[] = []
    try {
      const parsed = JSON.parse(raw) as Record<string, Object>
      if (parsed['status'] === false) return result
      const songs = this.extractHotSearch(parsed['result'] as Object)
      for (const item of songs) {
        result.push(item)
      }
    } catch (err) {
      // 忽略
    }
    return result
  }

  // ===== 结果解析工具 =====

  /** 从各种响应结构中提取歌曲数组 */
  private extractSongs(result: Object): Array<Record<string, Object>> {
    const arr = result as Array<Record<string, Object>>
    if (Array.isArray(arr)) return arr
    const obj = result as Record<string, Object>
    if (!obj) return []
    const candidates = ['list', 'songs', 'data', 'results']
    for (const key of candidates) {
      const v = obj[key]
      if (Array.isArray(v)) return v as Array<Record<string, Object>>
    }
    // 嵌套：data.list / result.list
    const data = obj['data'] as Record<string, Object>
    if (data) {
      for (const key of candidates) {
        const v = data[key]
        if (Array.isArray(v)) return v as Array<Record<string, Object>>
      }
    }
    return []
  }

  /** 从各种响应结构中提取热搜 */
  private extractHotSearch(result: Object): HotSearchItem[] {
    const arr = result as Array<Record<string, Object>>
    const list = Array.isArray(arr) ? arr : this.extractSongs(result)
    const items: HotSearchItem[] = []
    for (const item of list) {
      const label = (item['label'] ?? item['name'] ?? item['word'] ?? '') as string
      const value = (item['value'] ?? item['keyword'] ?? item['word'] ?? '') as string
      if (label) items.push({ label: label, value: value || label })
    }
    return items
  }

  /** 映射歌曲字段为标准 MusicItem */
  private mapSongItem(item: Record<string, Object>): MusicItem | null {
    const id = (item['id'] ?? item['songmid'] ?? item['mid'] ?? '') as string
    const name = (item['name'] ?? item['title'] ?? item['songname'] ?? '') as string
    if (!id || !name) return null
    const singer = (item['singer'] ?? item['artist'] ?? item['author'] ?? '未知') as string
    const album = (item['album'] ?? item['albumName'] ?? item['albumname'] ?? '') as string
    const duration = Number(item['interval'] ?? item['duration'] ?? item['dt'] ?? 0)
    const cover = (item['cover'] ?? item['pic'] ?? item['imgUrl'] ?? item['img'] ?? '') as string
    return {
      songmid: id,
      name: name,
      singer: singer,
      albumName: album,
      interval: isNaN(duration) ? 0 : Math.floor(duration),
      imgUrl: cover,
      lyricUrl: '',
      source: this.info.type,
      types: {}
    }
  }
}
