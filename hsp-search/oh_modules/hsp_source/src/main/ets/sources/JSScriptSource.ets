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
  AbortableResponseRequest,
  RawHttpResponse
} from 'common'
import { BaseSource } from '../api/SourceAPI'
import { JsExecutor, JsExecutorRegistry } from '../executor/JsExecutor'
import { http } from '@kit.NetworkKit'

// 引入 native 桥接模块（jsvm_bridge.so，HSP 内标准加载方式）
import jsvmBridgeNative from 'libjsvm_bridge.so'
import quickJsBridgeNative from 'libquickjs_bridge.so'

interface JsvmBridgeApi {
  createVM(): number
  destroyVM(handle: number): void
  evalScript(handle: number, script: string): string
  callGlobalFunction(handle: number, fnName: string, argsJson: string): string
  setNativeResult(handle: number, requestId: string, errorJson: string, responseJson: string): void
}

interface ScriptSourceCapability {
  type: string
  actions: string[]
  qualitys: string[]
}

interface ScriptInitState {
  inited: boolean
  error: string
  sources: Record<string, ScriptSourceCapability>
}

/** sourceApi 运行环境注入脚本（对齐原版 user-api-preload.js 核心能力） */
const PRELOAD_SCRIPT: string = `
(function() {
  var EVENT_NAMES = { request: 'request', inited: 'inited', updateAlert: 'updateAlert' };
  var events = { request: null };
  var resultStore = {};
  var requestSeq = 0;
  var currentSourceKey = globalThis.__source_script_info__ && globalThis.__source_script_info__.name
    ? String(globalThis.__source_script_info__.name) : 'default';
  globalThis.__source_initByScript__ = globalThis.__source_initByScript__ || {};
  globalThis.__source_initByScript__[currentSourceKey] = { inited: false, error: '', sources: {} };

  // 严格对齐 社区音源 的 inited 数据校验，同时保留本项目显式 search 扩展能力。
  function normalizeInitData(data) {
    if (!data || !data.sources || typeof data.sources !== 'object') {
      throw new Error('Missing required parameter init info');
    }
    var allSources = ['kw', 'kg', 'tx', 'wy', 'mg', 'local'];
    var supportQualitys = ['128k', '320k', 'flac', 'flac24bit'];
    var normalized = {};
    for (var i = 0; i < allSources.length; i++) {
      var source = allSources[i];
      var item = data.sources[source];
      if (!item || item.type !== 'music') continue;
      if (!Array.isArray(item.actions) || !Array.isArray(item.qualitys)) {
        throw new Error('Invalid init source info: ' + source);
      }
      var allowedActions = source === 'local' ? ['musicUrl', 'lyric', 'pic', 'search'] : ['musicUrl', 'search'];
      normalized[source] = {
        type: 'music',
        actions: allowedActions.filter(function(action) { return item.actions.indexOf(action) >= 0; }),
        qualitys: supportQualitys.filter(function(quality) { return item.qualitys.indexOf(quality) >= 0; })
      };
    }
    return normalized;
  }

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
      var bitLength = s.length * 8;
      var words = rstr2binl(s);
      words[bitLength >> 5] |= 0x80 << (bitLength % 32);
      words[(((bitLength + 64) >>> 9) << 4) + 14] = bitLength;
      var state = [1732584193, -271733879, -1732584194, 271733878];
      for (var i = 0; i < words.length; i += 16) {
        var a = state[0], b = state[1], c = state[2], d = state[3];
        var X = words.slice(i, i + 16);
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

  function bytesToBase64(data) {
    var binary = '';
    for (var i = 0; i < data.length; i++) binary += String.fromCharCode(data[i] & 0xFF);
    return btoa(binary);
  }
  function dataToBase64(data) {
    if (typeof data === 'string') return bytesToBase64(createBuffer(data));
    if (Array.isArray(data) || ArrayBuffer.isView(data)) return bytesToBase64(data);
    throw new Error('data type error: ' + typeof data);
  }
  function createBuffer(input, encoding) {
    if (typeof input === 'string') {
      if (encoding === 'base64') {
        var decoded = atob(input.replace(/\s+/g, ''));
        var base64Bytes = new Uint8Array(decoded.length);
        for (var i = 0; i < decoded.length; i++) base64Bytes[i] = decoded.charCodeAt(i) & 0xFF;
        return base64Bytes;
      }
      if (encoding === 'hex') {
        if (input.length % 2 !== 0) throw new Error('Invalid hex string');
        var hexBytes = new Uint8Array(input.length / 2);
        for (var j = 0; j < input.length; j += 2) hexBytes[j / 2] = parseInt(input.substring(j, j + 2), 16);
        return hexBytes;
      }
      var utf8 = unescape(encodeURIComponent(input));
      var utf8Bytes = new Uint8Array(utf8.length);
      for (var k = 0; k < utf8.length; k++) utf8Bytes[k] = utf8.charCodeAt(k) & 0xFF;
      return utf8Bytes;
    }
    if (Array.isArray(input)) return new Uint8Array(input);
    if (ArrayBuffer.isView(input)) return new Uint8Array(input.buffer, input.byteOffset, input.byteLength);
    if (input instanceof ArrayBuffer) return new Uint8Array(input);
    throw new Error('Unsupported input type');
  }

  // ---- utils ----
  var utils = {
    crypto: {
      md5: function(str) {
        if (typeof str !== 'string') throw new Error('param required a string');
        // 参考预加载层会先编码，但原生层会 URL 解码后再计算；这里是纯 JS 实现，直接计算原字符串。
        return md5(str);
      },
      aesEncrypt: function(buffer, mode, key, iv) {
        if (typeof globalThis.__source_native_aes_encrypt__ !== 'function') {
          throw new Error('Native AES is unavailable in this executor');
        }
        var encrypted = globalThis.__source_native_aes_encrypt__(
          dataToBase64(buffer), dataToBase64(key), dataToBase64(iv || []), mode);
        return createBuffer(encrypted, 'base64');
      },
      rsaEncrypt: function(buffer, key) {
        if (typeof key !== 'string') throw new Error('Invalid RSA key');
        if (typeof globalThis.__source_native_rsa_encrypt__ !== 'function') {
          throw new Error('Native RSA is unavailable in this executor');
        }
        var derKey = key.replace(/-----BEGIN PUBLIC KEY-----/g, '')
          .replace(/-----END PUBLIC KEY-----/g, '')
          .replace(/-----BEGIN RSA PUBLIC KEY-----/g, '')
          .replace(/-----END RSA PUBLIC KEY-----/g, '')
          .replace(/\s+/g, '');
        return createBuffer(globalThis.__source_native_rsa_encrypt__(dataToBase64(buffer), derKey), 'base64');
      },
      randomBytes: function(size) {
        var arr = new Uint8Array(size);
        for (var i = 0; i < size; i++) arr[i] = Math.floor(Math.random() * 256);
        return arr;
      }
    },
    buffer: {
      from: function(input, encoding) { return createBuffer(input, encoding); },
      bufToString: function(buf, format) {
        if (!buf || !buf.length) return '';
        if (format === 'binary') return buf;
        if (format === 'hex') {
          var hex = '';
          for (var h = 0; h < buf.length; h++) hex += (buf[h] & 0xFF).toString(16).padStart(2, '0');
          return hex;
        }
        var str = '';
        for (var i = 0; i < buf.length; i++) str += String.fromCharCode(buf[i] & 0xFF);
        if (format === 'base64') return btoa(str);
        try { return decodeURIComponent(escape(str)); } catch (e) { return str; }
      }
    }
  };

  // ---- 请求队列（脚本侧不调原生，ArkTS 主动来取）----
  var pendingRequests = [];      // [{requestId, url, options}]
  var pendingCallbacks = {};    // requestId → callback

  // ---- 真实定时器（脚本兼容性关键：很多音源依赖 setTimeout）----
  var timers = {};              // id → { callback, expireAt }
  var timerSeq = 0;
  globalThis.setTimeout = function(cb, ms) {
    if (typeof cb !== 'function') return 0;
    var id = ++timerSeq;
    timers[id] = { callback: cb, expireAt: Date.now() + (typeof ms === 'number' ? ms : 0) };
    return id;
  };
  globalThis.clearTimeout = function(id) {
    delete timers[id];
  };
  // ArkTS 轮询调用：执行所有到期定时器
  globalThis.__source_tick__ = function() {
    var now = Date.now();
    var due = [];
    for (var k in timers) {
      if (timers[k].expireAt <= now) {
        due.push(timers[k].callback);
        delete timers[k];
      }
    }
    for (var i = 0; i < due.length; i++) {
      try { due[i](); } catch (e) {}
    }
    return due.length;
  };

  // ---- sourceApi 全局对象 ----
  var sourceApi = {
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
      return function() { delete pendingCallbacks[requestId]; };
    },
    send: function(eventName, data) {
      return new Promise(function(resolve, reject) {
        if (eventName === EVENT_NAMES.inited) {
          var initState = globalThis.__source_initByScript__[currentSourceKey];
          if (initState && initState.inited) return reject(new Error('Script is inited'));
          try {
            var normalizedSources = normalizeInitData(data);
            globalThis.__source_sources__ = normalizedSources;
            globalThis.__source_sourcesByScript__ = globalThis.__source_sourcesByScript__ || {};
            globalThis.__source_sourcesByScript__[currentSourceKey] = normalizedSources;
            globalThis.__source_initByScript__[currentSourceKey] = {
              inited: true,
              error: '',
              sources: normalizedSources
            };
            resolve();
          } catch (initError) {
            var initMessage = String(initError && initError.message || initError);
            globalThis.__source_initByScript__[currentSourceKey] = {
              inited: false,
              error: initMessage,
              sources: {}
            };
            reject(initError);
          }
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
    currentScriptInfo: globalThis.__source_script_info__ || {}
  };

  globalThis[String.fromCharCode(108, 120)] = sourceApi;

  // ---- fetch 兼容（部分社区脚本环境检测要求，基于 sourceApi.request 队列实现）----
  globalThis.fetch = function(url, options) {
    return new Promise(function(resolve, reject) {
      sourceApi.request(url, options || {}, function(err, response, responseBody) {
        if (err) {
          reject(err);
          return;
        }
        var body = responseBody !== undefined ? responseBody : (response && response.body);
        resolve({
          ok: !!response && response.statusCode >= 200 && response.statusCode < 300,
          status: response ? response.statusCode : 0,
          statusText: response ? response.statusMessage : '',
          headers: response ? response.headers : {},
          url: url,
          json: function() {
            return Promise.resolve(typeof body === 'string' ? JSON.parse(body) : body);
          },
          text: function() {
            return Promise.resolve(typeof body === 'string' ? body : JSON.stringify(body));
          }
        });
      });
    });
  };

  // ---- Node/浏览器兼容（社区音源 社区脚本常见依赖）----
  function enhanceBuffer(buf) {
    try {
      Object.defineProperty(buf, 'toString', {
        value: function(format) { return utils.buffer.bufToString(this, format); },
        configurable: true
      });
    } catch (e) {}
    return buf;
  }
  globalThis.Buffer = {
    from: function(input, encoding) {
      return enhanceBuffer(utils.buffer.from(input, encoding));
    },
    isBuffer: function(b) { return !!(b && b.buffer); },
    concat: function(list) {
      var total = 0, i;
      for (i = 0; i < list.length; i++) total += list[i].length;
      var out = new Uint8Array(total), pos = 0;
      for (i = 0; i < list.length; i++) { out.set(list[i], pos); pos += list[i].length; }
      return enhanceBuffer(out);
    },
    alloc: function(size, fill) {
      var out = new Uint8Array(size);
      if (fill !== undefined) out.fill(fill);
      return enhanceBuffer(out);
    }
  };
  var B64_CHARS = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/';
  globalThis.btoa = function(str) {
    var bytes = [];
    for (var i = 0; i < str.length; i++) bytes.push(str.charCodeAt(i) & 0xFF);
    var out = '', j = 0;
    while (j < bytes.length) {
      var c1 = bytes[j++];
      var c2 = j < bytes.length ? bytes[j++] : NaN;
      var c3 = j < bytes.length ? bytes[j++] : NaN;
      out += B64_CHARS.charAt(c1 >> 2);
      out += B64_CHARS.charAt(((c1 & 3) << 4) | ((c2 >> 4) & 0xF));
      out += isNaN(c2) ? '=' : B64_CHARS.charAt(((c2 & 0xF) << 2) | ((c3 >> 6) & 3));
      out += isNaN(c3) ? '=' : B64_CHARS.charAt(c3 & 0x3F);
    }
    return out;
  };
  globalThis.atob = function(b64) {
    var map = {};
    for (var i = 0; i < B64_CHARS.length; i++) map[B64_CHARS.charAt(i)] = i;
    var out = '', j = 0;
    while (j < b64.length) {
      var c1 = map[b64.charAt(j++)];
      var c2 = map[b64.charAt(j++)];
      var c3 = map[b64.charAt(j++)];
      var c4 = map[b64.charAt(j++)];
      if (isNaN(c2)) return out;
      out += String.fromCharCode(((c1 << 2) | (c2 >> 4)) & 0xFF);
      if (isNaN(c3)) return out;
      out += String.fromCharCode(((c2 << 4) | (c3 >> 2)) & 0xFF);
      if (isNaN(c4)) return out;
      out += String.fromCharCode(((c3 << 6) | c4) & 0xFF);
    }
    return out;
  };
  globalThis.window = globalThis;

  // ---- console（部分脚本大量调用，缺失会抛 ReferenceError）----
  globalThis.console = {
    log: function() {},
    info: function() {},
    warn: function() {},
    error: function() {},
    debug: function() {},
    trace: function() {}
  };

  // ---- Node 兼容占位（部分脚本 require('crypto') 做 md5/加密）----
  globalThis.module = { exports: {} };
  globalThis.exports = {};
  globalThis.global = globalThis;
  globalThis.require = function(name) {
    if (name === 'crypto') {
      return {
        createHash: function(alg) {
          var buf = null;
          return {
            update: function(data) { buf = data; return this; },
            digest: function() {
              var str = (typeof buf === 'string') ? buf : String(buf || '');
              return utils.crypto.md5(str);
            }
          };
        },
        createCipheriv: function(mode, key, iv) {
          var chunks = [];
          return {
            update: function(data) { chunks.push(utils.buffer.from(data)); return Buffer.from([]); },
            final: function() { return utils.crypto.aesEncrypt(Buffer.concat(chunks), mode, key, iv); }
          };
        },
        createDecipheriv: function() {
          return { update: function(data) { return String(data); }, final: function() { return ''; } };
        },
        randomBytes: function(size) { return utils.crypto.randomBytes(size); }
      };
    }
    if (name === 'path') {
      return {
        join: function() {
          var parts = [];
          for (var i = 0; i < arguments.length; i++) parts.push(String(arguments[i]));
          return parts.join('/');
        },
        resolve: function() { return Array.prototype.join.call(arguments, '/'); },
        basename: function(p) { return String(p).split('/').pop(); },
        extname: function(p) { var n = String(p); var i = n.lastIndexOf('.'); return i >= 0 ? n.substring(i) : ''; }
      };
    }
    if (name === 'os') {
      // 模板字符串需要保留反斜杠，否则会在生成的 JS 单引号中插入真实换行并触发 SyntaxError。
      return { platform: function() { return 'linux'; }, type: function() { return 'Linux'; }, EOL: '\\n' };
    }
    return {};
  };
  globalThis.process = {
    env: {},
    version: 'v16.0.0',
    platform: 'linux',
    browser: true
  };

  // 严格对齐社区 QuickJS 环境：不要伪造 Node/浏览器全局，否则混淆脚本会误判运行环境并走错解码分支。
  try {
    delete globalThis.Buffer;
    delete globalThis.window;
    delete globalThis.module;
    delete globalThis.exports;
    delete globalThis.global;
    delete globalThis.require;
    delete globalThis.process;
  } catch (e) {}

  // XMLHttpRequest 占位（部分脚本加载时同步校验，返回 200 假响应避免 404 判定失败）
  globalThis.XMLHttpRequest = function() {
    var self = this;
    this.open = function(method, url, async) { self._url = url; };
    this.send = function() {
      self.readyState = 4;
      self.status = 200;
      self.statusText = 'OK';
      self.responseText = '{}';
      if (self.onload) self.onload();
    };
    this.setRequestHeader = function() {};
    this.onload = null;
    this.onerror = null;
  };

  // 对齐参考实现：同时禁用 eval 与 Function 构造器，避免脚本环境探测走入错误分支。
  globalThis.eval = function() { throw new Error('eval is not available'); };
  (function() {
    var originalFunction = globalThis.Function;
    var originalToString = originalFunction.prototype.toString;
    originalFunction.prototype.toString = function() {
      var desc = Object.getOwnPropertyDescriptor(this, 'name');
      return desc && desc.configurable
        ? originalToString.apply(this)
        : 'function ' + String(this.name || '') + '() { [native code] }';
    };
    var blockedFunction = new Proxy(originalFunction.prototype.constructor, {
      apply: function() { throw new Error('Dynamic code execution is not allowed.'); },
      construct: function() { throw new Error('Dynamic code execution is not allowed.'); }
    });
    Object.defineProperty(originalFunction.prototype, 'constructor', {
      value: blockedFunction,
      writable: false,
      configurable: false,
      enumerable: false
    });
    globalThis.Function = blockedFunction;
  })();

  // ---- ArkTS 侧 action 调用入口 ----
  globalThis.__source_result__ = resultStore;
  // 能力查询：返回脚本 inited 声明的所有 actions（去重）
  globalThis.__source_getActions__ = function(sourceKey) {
    var list = [];
    var sourceMap = globalThis.__source_sourcesByScript__ || {};
    var srcs = (sourceKey && sourceMap[String(sourceKey)]) || globalThis.__source_sources__ || {};
    for (var k in srcs) {
      var item = srcs[k];
      if (item && item.actions && Array.isArray(item.actions)) {
        for (var i = 0; i < item.actions.length; i++) {
          if (list.indexOf(item.actions[i]) < 0) list.push(item.actions[i]);
        }
      }
    }
    return list;
  };
  globalThis.__source_call__ = function(requestId, action, info) {
    if (!events.request) {
      resultStore[requestId] = { status: false, error: 'Request event is not defined' };
      return;
    }
    var reqInfo = info || {};
    // handler 超时兜底：10 秒未完成则标记失败（避免无限挂起）
    var timeoutTimer = setTimeout(function() {
      if (!resultStore[requestId]) {
        resultStore[requestId] = { status: false, error: 'handler timeout: ' + action };
      }
    }, 10000);
    try {
      var handlerResult = events.request.call(sourceApi, {
        source: reqInfo.source || 'custom',
        action: action,
        info: reqInfo
      });
      Promise.resolve(handlerResult).then(function(result) {
        clearTimeout(timeoutTimer);
        resultStore[requestId] = { status: true, result: result };
      }).catch(function(err) {
        clearTimeout(timeoutTimer);
        var errMessage = String((err && err.message) || err || 'unknown error');
        var errStack = String((err && err.stack) || '');
        var msg = errStack && errStack.indexOf(errMessage) < 0
          ? errMessage + '\\n' + errStack : (errStack || errMessage);
        if (globalThis.__source_errors__) globalThis.__source_errors__.push('handlerReject: ' + msg.substring(0, 200));
        resultStore[requestId] = { status: false, error: msg };
      });
    } catch (e) {
      clearTimeout(timeoutTimer);
      var throwMessage = String((e && e.message) || e || 'unknown error');
      var throwStack = String((e && e.stack) || '');
      var m = throwStack && throwStack.indexOf(throwMessage) < 0
        ? throwMessage + '\\n' + throwStack : (throwStack || throwMessage);
      if (globalThis.__source_errors__) globalThis.__source_errors__.push('handlerThrow: ' + m.substring(0, 200));
      resultStore[requestId] = { status: false, error: m };
    }
  };
  globalThis.__source_takeResult__ = function(requestId) {
    if (!resultStore[requestId]) return null;
    var r = resultStore[requestId];
    delete resultStore[requestId];
    return r;
  };
  // 取走待发送的请求队列（ArkTS 轮询调用）
  globalThis.__source_takeRequests__ = function() {
    if (pendingRequests.length === 0) return [];
    return pendingRequests.splice(0, pendingRequests.length);
  };
  // ArkTS 回传网络结果，恢复 JS 回调（由 native 在干净栈上调用）
  // 社区音源 约定：回调签名 (err, body)，body 为响应体字符串
  globalThis.__source_resolveRequest__ = function(requestId, errorJson, responseJson) {
    var cb = pendingCallbacks[requestId];
    delete pendingCallbacks[requestId];
    if (typeof cb !== 'function') return;
    var err = null;
    var body = null;
    var responseMeta = { statusCode: 0, statusMessage: '', headers: {} };
    try {
      // native 桥可能已解析为对象传入，兼容字符串/对象两种形态
      if (errorJson && errorJson !== 'null') {
        if (typeof errorJson === 'string') {
          try {
            err = JSON.parse(errorJson);
          } catch (e) {
            // QuickJS 原生桥会把 JSON 字符串先解析成普通错误文本，不能再次强制 JSON.parse。
            err = errorJson;
          }
        } else {
          err = errorJson;
        }
      }
      if (responseJson && responseJson !== 'null') {
        var resp = (typeof responseJson === 'string') ? JSON.parse(responseJson) : responseJson;
        responseMeta.statusCode = Number(resp && resp.statusCode || 0);
        responseMeta.statusMessage = String(resp && resp.statusMessage || '');
        responseMeta.headers = (resp && resp.headers && typeof resp.headers === 'object') ? resp.headers : {};
        var rawBody = (resp && resp.body !== undefined && resp.body !== null) ? resp.body : '';
        // 对齐原版 userApi/request.js：body 尝试 JSON.parse（脚本期望对象，失败保留字符串）
        if (typeof rawBody === 'string') {
          try {
            body = JSON.parse(rawBody);
          } catch (e) {
            body = rawBody;
          }
        } else {
          body = rawBody;
        }
      }
    } catch (e) {
      err = e;
    }
    // 对齐原版：网络错误时回调 (err, null, null)，不能伪造一个 statusCode=0 的响应对象。
    if (err) {
      cb(err, null, null);
      return;
    }
    // 成功响应时第二参数为完整响应对象（{ statusCode, headers, body }），第三参数为 body。
    var respObj = {
      statusCode: responseMeta.statusCode,
      statusMessage: responseMeta.statusMessage,
      headers: responseMeta.headers,
      body: body
    };
    cb(err, respObj, body);
  };
  // 环境校验函数：验证 sourceApi 全局就绪
  globalThis.__source_check__ = function() {
    if (typeof globalThis[String.fromCharCode(108, 120)] === 'object' && globalThis[String.fromCharCode(108, 120)].on && globalThis[String.fromCharCode(108, 120)].request) {
      return 'ok';
    }
    return 'sourceApi not ready';
  };
  globalThis.__source_getInitState__ = function(sourceKey) {
    var key = sourceKey ? String(sourceKey) : currentSourceKey;
    return globalThis.__source_initByScript__[key] || { inited: false, error: '', sources: {} };
  };
})();
`

/**
 * WebView(ArkWeb) 执行环境注入脚本
 *
 * 与 JSVM 版差异：ArkWeb 提供完整浏览器环境（原生 fetch/setTimeout/Promise/XHR），
 * sourceApi.request 直接用 fetch 实现（无需 ArkTS 轮询队列），脚本异步逻辑可正常完成。
 * JSVM 的 RunScript 受 ACL 权限限制，Web 引擎无此限制。
 */
const WEB_PRELOAD_SCRIPT: string = `
(function() {
  var EVENT_NAMES = { request: 'request', inited: 'inited', updateAlert: 'updateAlert' };
  var events = globalThis.__source_events__ = globalThis.__source_events__ || { request: null };
  var resultStore = globalThis.__source_resultStore__ = globalThis.__source_resultStore__ || {};
  var currentSourceKey = globalThis.__source_script_info__ && globalThis.__source_script_info__.name
    ? String(globalThis.__source_script_info__.name) : 'default';
  globalThis.__source_initByScript__ = globalThis.__source_initByScript__ || {};
  globalThis.__source_initByScript__[currentSourceKey] = { inited: false, error: '', sources: {} };

  // 严格对齐 社区音源 的 inited 数据校验，同时保留本项目显式 search 扩展能力。
  function normalizeInitData(data) {
    if (!data || !data.sources || typeof data.sources !== 'object') {
      throw new Error('Missing required parameter init info');
    }
    var allSources = ['kw', 'kg', 'tx', 'wy', 'mg', 'local'];
    var supportQualitys = ['128k', '320k', 'flac', 'flac24bit'];
    var normalized = {};
    for (var i = 0; i < allSources.length; i++) {
      var source = allSources[i];
      var item = data.sources[source];
      if (!item || item.type !== 'music') continue;
      if (!Array.isArray(item.actions) || !Array.isArray(item.qualitys)) {
        throw new Error('Invalid init source info: ' + source);
      }
      var allowedActions = source === 'local' ? ['musicUrl', 'lyric', 'pic', 'search'] : ['musicUrl', 'search'];
      normalized[source] = {
        type: 'music',
        actions: allowedActions.filter(function(action) { return item.actions.indexOf(action) >= 0; }),
        qualitys: supportQualitys.filter(function(quality) { return item.qualitys.indexOf(quality) >= 0; })
      };
    }
    return normalized;
  }

  // ---- 内联 MD5（utils.crypto.md5）----
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
      var bitLength = s.length * 8;
      var words = rstr2binl(s);
      words[bitLength >> 5] |= 0x80 << (bitLength % 32);
      words[(((bitLength + 64) >>> 9) << 4) + 14] = bitLength;
      var state = [1732584193, -271733879, -1732584194, 271733878];
      for (var i = 0; i < words.length; i += 16) {
        var a = state[0], b = state[1], c = state[2], d = state[3];
        var X = words.slice(i, i + 16);
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

  function bytesToBase64(data) {
    var binary = '';
    for (var i = 0; i < data.length; i++) binary += String.fromCharCode(data[i] & 0xFF);
    return btoa(binary);
  }
  function dataToBase64(data) {
    if (typeof data === 'string') return bytesToBase64(createBuffer(data));
    if (Array.isArray(data) || ArrayBuffer.isView(data)) return bytesToBase64(data);
    throw new Error('data type error: ' + typeof data);
  }
  function createBuffer(input, encoding) {
    if (typeof input === 'string') {
      if (encoding === 'base64') {
        var decoded = atob(input.replace(/\s+/g, ''));
        var base64Bytes = new Uint8Array(decoded.length);
        for (var i = 0; i < decoded.length; i++) base64Bytes[i] = decoded.charCodeAt(i) & 0xFF;
        return base64Bytes;
      }
      if (encoding === 'hex') {
        if (input.length % 2 !== 0) throw new Error('Invalid hex string');
        var hexBytes = new Uint8Array(input.length / 2);
        for (var j = 0; j < input.length; j += 2) hexBytes[j / 2] = parseInt(input.substring(j, j + 2), 16);
        return hexBytes;
      }
      var utf8 = unescape(encodeURIComponent(input));
      var utf8Bytes = new Uint8Array(utf8.length);
      for (var k = 0; k < utf8.length; k++) utf8Bytes[k] = utf8.charCodeAt(k) & 0xFF;
      return utf8Bytes;
    }
    if (Array.isArray(input)) return new Uint8Array(input);
    if (ArrayBuffer.isView(input)) return new Uint8Array(input.buffer, input.byteOffset, input.byteLength);
    if (input instanceof ArrayBuffer) return new Uint8Array(input);
    throw new Error('Unsupported input type');
  }

  var utils = {
    crypto: {
      md5: function(str) {
        if (typeof str !== 'string') throw new Error('param required a string');
        // 参考预加载层会先编码，但原生层会 URL 解码后再计算；这里是纯 JS 实现，直接计算原字符串。
        return md5(str);
      },
      aesEncrypt: function(buffer, mode, key, iv) {
        if (typeof globalThis.__source_native_aes_encrypt__ !== 'function') {
          throw new Error('Native AES is unavailable in this executor');
        }
        var encrypted = globalThis.__source_native_aes_encrypt__(
          dataToBase64(buffer), dataToBase64(key), dataToBase64(iv || []), mode);
        return createBuffer(encrypted, 'base64');
      },
      rsaEncrypt: function(buffer, key) {
        if (typeof key !== 'string') throw new Error('Invalid RSA key');
        if (typeof globalThis.__source_native_rsa_encrypt__ !== 'function') {
          throw new Error('Native RSA is unavailable in this executor');
        }
        var derKey = key.replace(/-----BEGIN PUBLIC KEY-----/g, '')
          .replace(/-----END PUBLIC KEY-----/g, '')
          .replace(/-----BEGIN RSA PUBLIC KEY-----/g, '')
          .replace(/-----END RSA PUBLIC KEY-----/g, '')
          .replace(/\s+/g, '');
        return createBuffer(globalThis.__source_native_rsa_encrypt__(dataToBase64(buffer), derKey), 'base64');
      },
      randomBytes: function(size) {
        var arr = new Uint8Array(size);
        for (var i = 0; i < size; i++) arr[i] = Math.floor(Math.random() * 256);
        return arr;
      }
    },
    buffer: {
      from: function(input, encoding) { return createBuffer(input, encoding); },
      bufToString: function(buf, format) {
        if (!buf || !buf.length) return '';
        if (format === 'binary') return buf;
        if (format === 'hex') {
          var hex = '';
          for (var h = 0; h < buf.length; h++) hex += (buf[h] & 0xFF).toString(16).padStart(2, '0');
          return hex;
        }
        var str = '';
        for (var i = 0; i < buf.length; i++) str += String.fromCharCode(buf[i] & 0xFF);
        if (format === 'base64') return btoa(str);
        try { return decodeURIComponent(escape(str)); } catch (e) { return str; }
      }
    }
  };

  // ---- sourceApi 全局（Web 版：request 入队，由 ArkTS 轮询取队列直接发原生请求，绕开 Web 代理不稳定问题）----
  // 多源共享 Web 页面：队列/回调挂全局（各源 PRELOAD 闭包必须共享同一队列，否则只有最后加载的源能驱动请求）
  // 多个导入源共用同一 Web 页面，请求序号也必须全局共享，避免同毫秒发生 ID 冲突。
  globalThis.__source_netSeq__ = globalThis.__source_netSeq__ || 0;
  globalThis.__source_pendingRequests__ = globalThis.__source_pendingRequests__ || [];
  var pendingRequests = globalThis.__source_pendingRequests__;
  globalThis.__source_pendingCallbacks__ = globalThis.__source_pendingCallbacks__ || {};
  var pendingCallbacks = globalThis.__source_pendingCallbacks__;
  globalThis.__source_netLog__ = [];
  globalThis.__source_logNet__ = function(tag, url) {
    var arr = globalThis.__source_netLog__;
    if (arr.length > 20) arr.shift();
    arr.push(tag + ':' + String(url).substring(0, 120));
  };
  var sourceApi = {
    EVENT_NAMES: EVENT_NAMES,
    request: function(url, options, callback) {
      var cb = typeof options === 'function' ? options : callback;
      var opts = (typeof options === 'object' && options) ? options : {};
      var id = 'net_' + (++globalThis.__source_netSeq__) + '_' + Date.now();
      pendingRequests.push({ requestId: id, url: url, options: opts });
      if (typeof cb === 'function') pendingCallbacks[id] = cb;
      globalThis.__source_logNet__('sourceReq', url);
      return function() { delete pendingCallbacks[id]; };
    },
    send: function(eventName, data) {
      return new Promise(function(resolve, reject) {
        if (eventName === EVENT_NAMES.inited) {
          var initState = globalThis.__source_initByScript__[currentSourceKey];
          if (initState && initState.inited) return reject(new Error('Script is inited'));
          try {
            var normalizedSources = normalizeInitData(data);
            globalThis.__source_sources__ = normalizedSources;
            globalThis.__source_sourcesByScript__ = globalThis.__source_sourcesByScript__ || {};
            globalThis.__source_sourcesByScript__[currentSourceKey] = normalizedSources;
            globalThis.__source_initByScript__[currentSourceKey] = {
              inited: true,
              error: '',
              sources: normalizedSources
            };
            resolve();
          } catch (initError) {
            var initMessage = String(initError && initError.message || initError);
            globalThis.__source_initByScript__[currentSourceKey] = {
              inited: false,
              error: initMessage,
              sources: {}
            };
            reject(initError);
          }
        } else if (eventName === EVENT_NAMES.updateAlert) {
          resolve();
        } else {
          reject(new Error('The event is not supported: ' + eventName));
        }
      });
    },
    on: function(eventName, handler) {
      if (eventName === EVENT_NAMES.request) {
        events.request = handler;
        // 多源共享 Web 页面：按源名保存 handler，__source_call__ 按 sourceKey 路由（避免后加载源覆盖）
        globalThis.__source_handlers__ = globalThis.__source_handlers__ || {};
        globalThis.__source_handlers__[currentSourceKey] = handler;
      }
      return Promise.resolve();
    },
    utils: utils,
    version: '2.0.0',
    env: 'mobile',
    currentScriptInfo: globalThis.__source_script_info__ || {}
  };
  globalThis[String.fromCharCode(108, 120)] = sourceApi;
  // 原生网络结果回传入口（ArkTS 轮询驱动请求后调用）
  globalThis.__source_takeRequests__ = function() {
    if (pendingRequests.length === 0) return [];
    // 必须原地清空共享数组。若直接 pendingRequests = []，先加载音源的 request 闭包
    // 仍会向旧数组写入，后续请求便永远无法被 ArkTS 侧取走。
    return pendingRequests.splice(0, pendingRequests.length);
  };
  globalThis.__source_resolveRequest__ = function(id, errorJson, responseJson) {
    var cb = pendingCallbacks[id];
    delete pendingCallbacks[id];
    if (typeof cb !== 'function') return;
    var err = null;
    var body = null;
    var responseMeta = { statusCode: 0, statusMessage: '', headers: {} };
    try {
      if (errorJson && errorJson !== 'null') err = JSON.parse(errorJson);
      if (responseJson && responseJson !== 'null') {
        var resp = JSON.parse(responseJson);
        responseMeta.statusCode = Number(resp && resp.statusCode || 0);
        responseMeta.statusMessage = String(resp && resp.statusMessage || '');
        responseMeta.headers = (resp && resp.headers && typeof resp.headers === 'object') ? resp.headers : {};
        var rawBody = (resp && resp.body !== undefined && resp.body !== null) ? resp.body : '';
        // 对齐原版 userApi/request.js：body 尝试 JSON.parse（脚本期望对象，失败保留字符串）
        if (typeof rawBody === 'string') {
          try {
            body = JSON.parse(rawBody);
          } catch (e) {
            body = rawBody;
          }
        } else {
          body = rawBody;
        }
      }
    } catch (e) {
      err = e;
    }
    // 对齐原版：网络错误时回调 (err, null, null)，不能伪造一个 statusCode=0 的响应对象。
    if (err) {
      cb(err, null, null);
      return;
    }
    // 成功响应时第二参数为完整响应对象（{ statusCode, headers, body }），第三参数为 body。
    var respObj = {
      statusCode: responseMeta.statusCode,
      statusMessage: responseMeta.statusMessage,
      headers: responseMeta.headers,
      body: body
    };
    cb(err, respObj, body);
  };
  // 覆盖浏览器 fetch：同样入队（脚本无论用 sourceApi.request 还是 fetch 都走 ArkTS 原生网络）
  globalThis.fetch = function(url, options) {
    globalThis.__source_logNet__('fetch', url);
    return new Promise(function(resolve, reject) {
      var id = 'fetch_' + (++globalThis.__source_netSeq__) + '_' + Date.now();
      pendingRequests.push({ requestId: id, url: url, options: options || {} });
      pendingCallbacks[id] = function(err, response, responseBody) {
        if (err) {
          reject(err);
          return;
        }
        var body = responseBody !== undefined ? responseBody : (response && response.body);
        resolve({
          ok: !!response && response.statusCode >= 200 && response.statusCode < 300,
          status: response ? response.statusCode : 0,
          statusText: response ? response.statusMessage : '',
          headers: response ? response.headers : {},
          url: url,
          json: function() {
            return Promise.resolve(typeof body === 'string' ? JSON.parse(body) : body);
          },
          text: function() {
            return Promise.resolve(typeof body === 'string' ? body : JSON.stringify(body));
          }
        });
      };
    });
  };

  // ---- Node 兼容占位（Web 引擎原生已有 console/fetch/setTimeout/atob/btoa/window/XHR）----
  function enhanceBuffer(buf) {
    try {
      Object.defineProperty(buf, 'toString', {
        value: function(format) { return utils.buffer.bufToString(this, format); },
        configurable: true
      });
    } catch (e) {}
    return buf;
  }
  globalThis.Buffer = {
    from: function(input, encoding) {
      return enhanceBuffer(utils.buffer.from(input, encoding));
    },
    isBuffer: function(b) { return !!(b && b.buffer); },
    concat: function(list) {
      var total = 0, i;
      for (i = 0; i < list.length; i++) total += list[i].length;
      var out = new Uint8Array(total), pos = 0;
      for (i = 0; i < list.length; i++) { out.set(list[i], pos); pos += list[i].length; }
      return enhanceBuffer(out);
    },
    alloc: function(size, fill) {
      var out = new Uint8Array(size);
      if (fill !== undefined) out.fill(fill);
      return enhanceBuffer(out);
    }
  };
  globalThis.module = { exports: {} };
  globalThis.exports = {};
  globalThis.global = globalThis;
  globalThis.require = function(name) {
    if (name === 'crypto') {
      return {
        createHash: function(alg) {
          var buf = null;
          return {
            update: function(data) { buf = data; return this; },
            digest: function() { return md5(String(buf || '')); }
          };
        },
        createCipheriv: function(mode, key, iv) {
          var chunks = [];
          return {
            update: function(data) { chunks.push(utils.buffer.from(data)); return Buffer.from([]); },
            final: function() { return utils.crypto.aesEncrypt(Buffer.concat(chunks), mode, key, iv); }
          };
        },
        createDecipheriv: function() {
          return { update: function(data) { return String(data); }, final: function() { return ''; } };
        },
        randomBytes: function(size) { return utils.crypto.randomBytes(size); }
      };
    }
    return {};
  };
  globalThis.process = { env: {}, version: 'v16.0.0', platform: 'linux', browser: true };
  globalThis.__dirname = '';
  globalThis.__filename = 'executor.html';
  globalThis.setImmediate = function(cb) { return setTimeout(cb, 0); };
  globalThis.clearImmediate = function(id) { return clearTimeout(id); };
  // Web 运行时只保留浏览器原生对象，不伪造 Node 全局，避免脚本环境检测走错分支。
  try {
    delete globalThis.Buffer;
    delete globalThis.module;
    delete globalThis.exports;
    delete globalThis.global;
    delete globalThis.require;
    delete globalThis.process;
    delete globalThis.__dirname;
    delete globalThis.__filename;
    delete globalThis.setImmediate;
    delete globalThis.clearImmediate;
  } catch (e) {}
  // 对齐社区 Web 预加载环境，同样阻止动态代码执行。
  globalThis.eval = function() { throw new Error('eval is not available'); };
  (function() {
    var originalFunction = globalThis.Function;
    var originalToString = originalFunction.prototype.toString;
    originalFunction.prototype.toString = function() {
      var desc = Object.getOwnPropertyDescriptor(this, 'name');
      return desc && desc.configurable
        ? originalToString.apply(this)
        : 'function ' + String(this.name || '') + '() { [native code] }';
    };
    var blockedFunction = new Proxy(originalFunction.prototype.constructor, {
      apply: function() { throw new Error('Dynamic code execution is not allowed.'); },
      construct: function() { throw new Error('Dynamic code execution is not allowed.'); }
    });
    Object.defineProperty(originalFunction.prototype, 'constructor', {
      value: blockedFunction,
      writable: false,
      configurable: false,
      enumerable: false
    });
    globalThis.Function = blockedFunction;
  })();
  // 覆盖 XMLHttpRequest：Web 禁止同步 XHR（脚本加载校验用同步 XHR 会抛错），返回 200 假响应
  globalThis.XMLHttpRequest = function() {
    var self = this;
    this.open = function(method, url, async) { self._url = url; };
    this.send = function() {
      self.readyState = 4;
      self.status = 200;
      self.statusText = 'OK';
      self.responseText = '{}';
      if (self.onload) self.onload();
    };
    this.setRequestHeader = function() {};
    this.onload = null;
    this.onerror = null;
  };

  // ---- ArkTS action 调用入口（sourceKey = 源名，多源共享页面时路由到各自 handler） ----
  globalThis.__source_call__ = function(requestId, action, info, sourceKey) {
    // 指定源名时只允许使用该源自己的 handler；缺失时直接失败，不能串到后加载/前一个源。
    var handler = sourceKey ? null : events.request;
    if (sourceKey && globalThis.__source_handlers__) {
      handler = globalThis.__source_handlers__[String(sourceKey)] || null;
    }
    if (!handler) {
      resultStore[requestId] = { status: false, error: 'Request event is not defined' };
      return;
    }
    var reqInfo = info || {};
    // handler 超时兜底：10 秒未完成则标记失败（避免无限挂起）
    var timeoutTimer = setTimeout(function() {
      if (!resultStore[requestId]) {
        resultStore[requestId] = { status: false, error: 'handler timeout: ' + action };
      }
    }, 10000);
    try {
      var handlerResult = handler.call(sourceApi, {
        source: reqInfo.source || 'custom',
        action: action,
        info: reqInfo
      });
      Promise.resolve(handlerResult).then(function(result) {
        clearTimeout(timeoutTimer);
        resultStore[requestId] = { status: true, result: result };
      }).catch(function(err) {
        clearTimeout(timeoutTimer);
        var errMessage = String((err && err.message) || err || 'unknown error');
        var errStack = String((err && err.stack) || '');
        var msg = errStack && errStack.indexOf(errMessage) < 0
          ? errMessage + '\\n' + errStack : (errStack || errMessage);
        if (globalThis.__source_errors__) globalThis.__source_errors__.push('handlerReject: ' + msg.substring(0, 200));
        resultStore[requestId] = { status: false, error: msg };
      });
    } catch (e) {
      clearTimeout(timeoutTimer);
      var throwMessage = String((e && e.message) || e || 'unknown error');
      var throwStack = String((e && e.stack) || '');
      var m = throwStack && throwStack.indexOf(throwMessage) < 0
        ? throwMessage + '\\n' + throwStack : (throwStack || throwMessage);
      if (globalThis.__source_errors__) globalThis.__source_errors__.push('handlerThrow: ' + m.substring(0, 200));
      resultStore[requestId] = { status: false, error: m };
    }
  };
  // 全局错误捕获（诊断脚本内部异常）
  globalThis.__source_errors__ = [];
  if (typeof window !== 'undefined') {
    window.addEventListener('error', function(e) {
      globalThis.__source_errors__.push('error: ' + String(e.message));
    });
    window.addEventListener('unhandledrejection', function(e) {
      globalThis.__source_errors__.push('rejection: ' + String(e.reason));
    });
  }
  globalThis.__source_takeResult__ = function(requestId) {
    if (!resultStore[requestId]) return null;
    var r = resultStore[requestId];
    delete resultStore[requestId];
    return r;
  };
  // 能力查询：返回脚本 inited 声明的所有 actions（去重，原版 社区音源 协议）
  globalThis.__source_getActions__ = function(sourceKey) {
    var list = [];
    var sourceMap = globalThis.__source_sourcesByScript__ || {};
    // 指定源未上报能力时返回空，不能沿用别的音源最近一次 inited 声明。
    var srcs = sourceKey ? (sourceMap[String(sourceKey)] || {}) : (globalThis.__source_sources__ || {});
    for (var k in srcs) {
      var item = srcs[k];
      if (item && item.actions && Array.isArray(item.actions)) {
        for (var i = 0; i < item.actions.length; i++) {
          if (list.indexOf(item.actions[i]) < 0) list.push(item.actions[i]);
        }
      }
    }
    return list;
  };
  globalThis.__source_check__ = function() {
    if (typeof globalThis[String.fromCharCode(108, 120)] === 'object' && globalThis[String.fromCharCode(108, 120)].on && globalThis[String.fromCharCode(108, 120)].request) {
      return 'ok';
    }
    return 'sourceApi not ready';
  };
  globalThis.__source_getInitState__ = function(sourceKey) {
    var key = sourceKey ? String(sourceKey) : currentSourceKey;
    return globalThis.__source_initByScript__[key] || { inited: false, error: '', sources: {} };
  };
  // 单一活动源切换时清理旧源在共享 ArkWeb 页面中的注册状态。
  globalThis.__source_destroySource__ = function(sourceKey) {
    var key = String(sourceKey || '');
    if (!key) return false;
    if (globalThis.__source_handlers__) delete globalThis.__source_handlers__[key];
    if (globalThis.__source_sourcesByScript__) delete globalThis.__source_sourcesByScript__[key];
    if (globalThis.__source_initByScript__) delete globalThis.__source_initByScript__[key];
    return true;
  };
  // 诊断：脚本内部错误收集 + handler 注册状态 + 网络调用追踪（Web 执行器调试用）
  globalThis.__source_diag__ = function() {
    return JSON.stringify({
      handlerRegistered: typeof events.request === 'function',
      errors: globalThis.__source_errors__ || [],
      fetchType: typeof globalThis.fetch,
      nativeType: typeof globalThis.sourceNative,
      netLog: globalThis.__source_netLog__ || []
    });
  };
})();
`

/**
 * JS 音源脚本源（基于 WebView 执行器或 JSVM 沙箱执行）
 *
 * 流程：
 * 1. 优先使用应用内 QuickJS 独立 Context，失败时回退 ArkWeb/JSVM
 * 2. 执行 PRELOAD 注入 sourceApi 全局环境
 * 3. 执行用户音源脚本（脚本注册 request 事件处理器）
 * 4. search/getMusicInfo/getLyric 通过 __source_call__ 触发脚本处理器
 * 5. 脚本内 sourceApi.request → 原生网络桥（sourceNative）→ ArkTS 网络层 → 回调恢复
 */
export class JSScriptSource extends BaseSource {
  private handle: number = 0
  private bridge: JsvmBridgeApi | null = null
  private isReady: boolean = false
  private scriptContent: string = ''
  /** Web 执行器模式（ArkWeb 引擎，无 JSVM ACL 限制） */
  private useWebExecutor: boolean = false
  /** 进行中的驱动请求（可取消：调用方放弃时 abort） */
  private inflightWebRequests: Map<string, AbortableResponseRequest> = new Map()
  /** 脚本通过 sourceApi.send(inited) 上报的逐平台运行时能力。 */
  private sourceCapabilities: Record<string, ScriptSourceCapability> = {}

  constructor(scriptContent: string, sourceInfo: SourceInfo) {
    super(sourceInfo)
    this.scriptContent = scriptContent
    this.isNative = false
  }

  /** 中止全部进行中的驱动网络请求（切歌/放弃等待时调用） */
  abortInflightRequests(): void {
    this.inflightWebRequests.forEach((req) => {
      try {
        req.abort()
      } catch (e) {
        // 忽略中止异常
      }
    })
    this.inflightWebRequests.clear()
  }

  /** 清理共享 ArkWeb 执行器中属于当前源的 handler 与能力状态。 */
  private cleanupWebSourceState(executor: JsExecutor): void {
    executor.callGlobalFunction('__source_destroySource__', JSON.stringify([this.info.name]))
      .catch((err: Error) => {
        LogUtils.warn(`[Web执行器] 清理旧音源状态失败: ${JSON.stringify(err)}`)
      })
  }

  /** 初始化：优先使用独立 QuickJS Context，失败时回退 ArkWeb 与系统 JSVM。 */
  async init(): Promise<boolean> {
    this.sourceCapabilities = {}
    const scriptInfoJson = JSON.stringify({
      'name': this.info.name,
      'version': this.info.version,
      'description': this.info.description,
      'author': this.info.author,
      'homepage': this.info.scriptUrl ?? '',
      'rawScript': this.scriptContent
    })

    // QuickJS 是解释器，不依赖 JSVM 的可执行内存 ACL；每个音源拥有独立 Context。
    const quickBridge = quickJsBridgeNative as JsvmBridgeApi
    const quickReady = await this.initWithNativeBridge(quickBridge, 'QuickJS', scriptInfoJson)
    if (quickReady) return true
    LogUtils.warn(`[QuickJS] 音源初始化失败，尝试 ArkWeb 回退: ${this.info.name}`)

    // Web 执行器模式（兼容依赖浏览器专有 API 的社区脚本）
    if (JsExecutorRegistry.isAvailable()) {
      const executor = JsExecutorRegistry.instance
      if (executor) {
        this.useWebExecutor = true
        try {
          LogUtils.info(`[Web执行器] 初始化音源: ${this.info.name}`)
          // 包裹 try-catch：捕获脚本真实错误（Web 未捕获错误会被简化为 "Script error."）
          const wrapped = `(function(){ try { globalThis.__source_script_info__=${scriptInfoJson};\n${WEB_PRELOAD_SCRIPT}\n${this.scriptContent} } catch(e) { globalThis.__source_errors__ = globalThis.__source_errors__ || []; globalThis.__source_errors__.push('evalError: ' + String(e && e.message || e)); } })()`
          const scriptRet = await executor.evalScript(wrapped)
          LogUtils.info(`音源脚本执行结果: ${scriptRet ? scriptRet.substring(0, 200) : '(空)'}`)
          if (scriptRet && (scriptRet.includes('Error') || scriptRet.includes('error') || scriptRet.includes('异常'))) {
            throw new Error(`音源脚本执行报错: ${scriptRet}`)
          }
          // 与参考项目一致：音源初始化时发出的版本校验/配置请求必须立即完成。
          // 否则请求会残留到第一次播放，既拖慢取歌，也可能让脚本始终处于未初始化状态。
          const initState = await this.driveWebInitRequests(executor)
          if (!initState.inited) {
            throw new Error(`音源未完成 sourceApi.send(inited): ${initState.error || '等待超时'}`)
          }
          this.sourceCapabilities = initState.sources
          const checkRet = await executor.callGlobalFunction('__source_check__', '[]')
          LogUtils.info(`sourceApi 环境校验: ${checkRet}`)
          if (checkRet !== '"ok"' && checkRet !== 'ok' && checkRet !== '"\\"ok\\""') {
            throw new Error(`sourceApi 环境校验失败: ${checkRet}`)
          }
          this.isReady = true
          // init 后立即诊断（脚本内部错误/注册状态）
          try {
            const diag = await executor.callGlobalFunction('__source_diag__', '[]')
            LogUtils.info(`[Web执行器] init诊断(${this.info.name}): ${diag}`)
          } catch (diagErr) {
            LogUtils.warn(`[Web执行器] init诊断异常: ${JSON.stringify(diagErr)}`)
          }
          LogUtils.info(`Web执行器初始化完成: ${this.info.name} v${this.info.version}`)
          return true
        } catch (webErr) {
          LogUtils.error('Web执行器初始化异常', JSON.stringify(webErr))
          this.cleanupWebSourceState(executor)
          this.useWebExecutor = false
          this.sourceCapabilities = {}
        }
      }
    }

    // 系统 JSVM 作为最后回退；普通签名应用可能因 ACL 限制无法使用。
    const jsvmBridge = jsvmBridgeNative as JsvmBridgeApi
    if (!jsvmBridge || !jsvmBridge.createVM) {
      LogUtils.error('JSVM 桥接模块加载失败（import 模块为空或无 createVM）')
      return false
    }
    return this.initWithNativeBridge(jsvmBridge, 'JSVM', scriptInfoJson)
  }

  /** QuickJS/JSVM 共用的独立 Context 初始化流程。 */
  private async initWithNativeBridge(
    bridge: JsvmBridgeApi,
    engineName: string,
    scriptInfoJson: string
  ): Promise<boolean> {
    this.bridge = bridge
    try {
      this.handle = bridge.createVM()
      if (!this.handle) throw new Error('创建 VM 返回 0')
      LogUtils.info(`[${engineName}] VM 创建成功: handle=${this.handle}`)

      const scriptRet = bridge.evalScript(this.handle,
        ';globalThis.__source_script_info__=' + scriptInfoJson + ';\n' + PRELOAD_SCRIPT + '\n' + this.scriptContent)
      LogUtils.info(`[${engineName}] 音源脚本执行结果: ${scriptRet ? scriptRet.substring(0, 200) : '(空)'}`)
      if (scriptRet && (scriptRet.includes('Error') || scriptRet.includes('error') || scriptRet.includes('异常'))) {
        throw new Error(scriptRet)
      }

      let initState: ScriptInitState = { inited: false, error: '', sources: {} }
      const loadDeadline = Date.now() + 6000
      while (Date.now() < loadDeadline) {
        await this.driveTick()
        initState = this.readJsvmInitState()
        if (initState.inited || initState.error) break
        await new Promise<void>((resolve) => setTimeout(resolve, 50))
      }
      if (!initState.inited) {
        throw new Error(`音源未完成 sourceApi.send(inited): ${initState.error || '等待超时'}`)
      }
      this.sourceCapabilities = initState.sources

      const checkRet = bridge.callGlobalFunction(this.handle, '__source_check__', '[]')
      if (checkRet !== '"ok"' && checkRet !== 'ok') {
        throw new Error(`sourceApi 环境校验失败: ${checkRet}`)
      }
      this.isReady = true
      LogUtils.info(`[${engineName}] 沙箱初始化完成: ${this.info.name} v${this.info.version}`)
      return true
    } catch (err) {
      LogUtils.error(`[${engineName}] 沙箱初始化失败`, JSON.stringify(err))
      if (this.handle) {
        try { bridge.destroyVM(this.handle) } catch (destroyErr) {}
      }
      this.handle = 0
      this.bridge = null
      this.isReady = false
      this.sourceCapabilities = {}
      return false
    }
  }

  /** 销毁沙箱 */
  destroy(): void {
    this.abortInflightRequests()
    if (this.useWebExecutor) {
      const executor = JsExecutorRegistry.instance
      if (executor) this.cleanupWebSourceState(executor)
    }
    if (this.bridge && this.handle) {
      try {
        this.bridge.destroyVM(this.handle)
      } catch (err) {
        // 忽略销毁错误
      }
    }
    this.handle = 0
    this.bridge = null
    this.useWebExecutor = false
    this.isReady = false
    this.sourceCapabilities = {}
  }

  /** 获取脚本内容（用于持久化保存） */
  getScriptContent(): string {
    return this.scriptContent
  }

  /** 解析脚本声明的支持音源列表；运行期严格使用 inited.sources，未初始化时才正则兜底。 */
  getSupportedSources(): string[] {
    const capabilityKeys = Object.keys(this.sourceCapabilities)
    if (capabilityKeys.length > 0) {
      return capabilityKeys.filter((source: string) =>
        this.sourceCapabilities[source].actions.indexOf('musicUrl') >= 0)
    }
    const match = this.scriptContent.match(/sources\s*:\s*\[([^\]]*)\]/)
    if (!match) return []
    const result: string[] = []
    const itemRegex = /['"]([^'"]+)['"]/g
    let item: RegExpExecArray | null = itemRegex.exec(match[1])
    while (item !== null) {
      if (item[1]) result.push(item[1])
      item = itemRegex.exec(match[1])
    }
    return result
  }

  // ===== 请求处理（ArkTS 主动轮询，脚本侧不回调原生） =====

  /**
   * 将脚本请求参数转换为 HarmonyOS HTTP 可用的请求体。
   * 对齐参考 userApi/request.js：支持 form、对象 JSON body 与普通字符串 body。
   */
  private buildRequestBody(
    opts: Record<string, Object>,
    method: string,
    headers: Record<string, string>
  ): string {
    let contentType = headers['Content-Type'] ?? headers['content-type'] ?? ''
    const form = opts['form'] as Record<string, Object> | undefined
    if (method.toUpperCase() === 'POST' && form) {
      if (!contentType) {
        headers['Content-Type'] = 'application/x-www-form-urlencoded'
      }
      const parts: string[] = []
      const keys = Object.keys(form)
      for (let i = 0; i < keys.length; i++) {
        parts.push(`${encodeURIComponent(keys[i])}=${encodeURIComponent(String(form[keys[i]]))}`)
      }
      return parts.join('&')
    }

    const formData = opts['formData'] as Record<string, Object> | undefined
    if (method.toUpperCase() === 'POST' && formData) {
      const boundary = `----sourceMusic${Date.now()}${Math.floor(Math.random() * 100000)}`
      headers['Content-Type'] = `multipart/form-data; boundary=${boundary}`
      const parts: string[] = []
      const keys = Object.keys(formData)
      for (let i = 0; i < keys.length; i++) {
        const fieldName = keys[i].replace(/"/g, '%22')
        parts.push(`--${boundary}\r\nContent-Disposition: form-data; name="${fieldName}"\r\n\r\n${String(formData[keys[i]])}\r\n`)
      }
      parts.push(`--${boundary}--\r\n`)
      return parts.join('')
    }

    const rawBody = opts['body']
    if (rawBody === undefined || rawBody === null) return ''
    if (typeof rawBody === 'string') return rawBody
    if (!contentType && method.toUpperCase() === 'POST') {
      headers['Content-Type'] = 'application/json'
      contentType = 'application/json'
    }
    return JSON.stringify(rawBody)
  }

  /**
   * 音源沙箱专用原生请求。
   * 放在 hsp_source 内部，避免运行时加载到旧版 common HAR 时新增静态方法不可调用。
   */
  private createResponseRequest(
    url: string,
    method: string,
    headers: Record<string, string>,
    body: string,
    timeout: number,
    binary: boolean
  ): AbortableResponseRequest {
    const request = http.createHttp()
    const methodMap: Record<string, http.RequestMethod> = {
      'GET': http.RequestMethod.GET,
      'POST': http.RequestMethod.POST,
      'PUT': http.RequestMethod.PUT,
      'DELETE': http.RequestMethod.DELETE,
      'HEAD': http.RequestMethod.HEAD
    }
    const promise = request.request(url, {
      method: methodMap[method.toUpperCase()] ?? http.RequestMethod.GET,
      header: headers,
      extraData: body,
      connectTimeout: timeout,
      readTimeout: timeout,
      expectDataType: binary ? http.HttpDataType.ARRAY_BUFFER : http.HttpDataType.STRING
    }).then((response): RawHttpResponse => {
      let responseBody: string | number[] = ''
      if (binary) {
        const view = new Uint8Array(response.result as ArrayBuffer)
        const bytes: number[] = []
        for (let i = 0; i < view.length; i++) bytes.push(view[i])
        responseBody = bytes
      } else {
        responseBody = typeof response.result === 'string' ? response.result : JSON.stringify(response.result)
      }
      const responseHeaders: Record<string, string> = {}
      const rawHeaders = response.header as Record<string, Object>
      if (rawHeaders) {
        const keys = Object.keys(rawHeaders)
        for (let i = 0; i < keys.length; i++) {
          const value = rawHeaders[keys[i]]
          responseHeaders[keys[i]] = value === undefined || value === null ? '' : String(value)
        }
      }
      return {
        statusCode: response.responseCode,
        statusMessage: this.getHttpStatusMessage(response.responseCode),
        headers: responseHeaders,
        body: responseBody
      }
    }).then((response): RawHttpResponse => {
      request.destroy()
      return response
    }).catch((err: Error): RawHttpResponse => {
      request.destroy()
      throw err
    })
    return {
      promise: promise,
      abort: (): void => {
        try {
          request.destroy()
        } catch (e) {
          // 请求可能已经结束，重复销毁无需继续处理。
        }
      }
    }
  }

  /** 常见 HTTP 状态文本，行为与浏览器/sourceApi request 响应一致。 */
  private getHttpStatusMessage(statusCode: number): string {
    const messages: Record<number, string> = {
      200: 'OK', 201: 'Created', 202: 'Accepted', 204: 'No Content',
      301: 'Moved Permanently', 302: 'Found', 304: 'Not Modified',
      400: 'Bad Request', 401: 'Unauthorized', 403: 'Forbidden', 404: 'Not Found',
      408: 'Request Timeout', 429: 'Too Many Requests',
      500: 'Internal Server Error', 502: 'Bad Gateway', 503: 'Service Unavailable', 504: 'Gateway Timeout'
    }
    return messages[statusCode] ?? String(statusCode)
  }

  /** 解析脚本侧返回的初始化状态，兼容 ArkWeb/JSVM 的单层或双层 JSON 字符串。 */
  private parseInitState(raw: string): ScriptInitState {
    if (!raw || raw === 'null' || raw === 'undefined') return { inited: false, error: '', sources: {} }
    try {
      let value: Object = JSON.parse(raw) as Object
      if (typeof value === 'string') value = JSON.parse(value) as Object
      const state = value as Record<string, Object>
      const sources: Record<string, ScriptSourceCapability> = {}
      const rawSources = state['sources'] as Record<string, Object>
      if (rawSources && typeof rawSources === 'object') {
        const sourceKeys = Object.keys(rawSources)
        for (let i = 0; i < sourceKeys.length; i++) {
          const source = sourceKeys[i]
          const rawItem = rawSources[source] as Record<string, Object>
          if (!rawItem || typeof rawItem !== 'object') continue
          const actions: string[] = []
          const qualitys: string[] = []
          const rawActions = rawItem['actions'] as Array<Object>
          const rawQualitys = rawItem['qualitys'] as Array<Object>
          if (Array.isArray(rawActions)) {
            for (let j = 0; j < rawActions.length; j++) actions.push(String(rawActions[j]))
          }
          if (Array.isArray(rawQualitys)) {
            for (let j = 0; j < rawQualitys.length; j++) qualitys.push(String(rawQualitys[j]))
          }
          sources[source] = {
            type: rawItem['type'] ? String(rawItem['type']) : '',
            actions: actions,
            qualitys: qualitys
          }
        }
      }
      return {
        inited: state['inited'] === true,
        error: state['error'] ? String(state['error']) : '',
        sources: sources
      }
    } catch (err) {
      return { inited: false, error: '', sources: {} }
    }
  }

  /** 读取 JSVM 独立上下文的初始化状态。 */
  private readJsvmInitState(): ScriptInitState {
    if (!this.bridge || !this.handle) return { inited: false, error: '', sources: {} }
    try {
      const raw = this.bridge.callGlobalFunction(
        this.handle, '__source_getInitState__', JSON.stringify([this.info.name]))
      return this.parseInitState(raw)
    } catch (err) {
      return { inited: false, error: '', sources: {} }
    }
  }

  /** Web 模式初始化请求驱动：持续处理请求，直到脚本真实发送 inited，最长 6 秒。 */
  private async driveWebInitRequests(executor: JsExecutor): Promise<ScriptInitState> {
    const deadline = Date.now() + 6000
    let initState: ScriptInitState = { inited: false, error: '', sources: {} }
    while (Date.now() < deadline) {
      let handled = 0
      try {
        const reqsJson = await executor.callGlobalFunction('__source_takeRequests__', '[]')
        if (reqsJson && reqsJson !== 'null' && reqsJson !== '[]') {
          const reqs = JSON.parse(reqsJson) as Array<Record<string, Object>>
          for (let i = 0; i < reqs.length; i++) {
            const reqId = (reqs[i]['requestId'] as string) ?? ''
            const reqUrl = (reqs[i]['url'] as string) ?? ''
            if (!reqId || !reqUrl) continue
            handled++
            const reqOpts = JSON.stringify(reqs[i]['options'] ?? {})
            this.doWebRequest(executor, reqId, reqUrl, reqOpts)
          }
        }
      } catch (err) {
        LogUtils.warn(`[Web执行器] 初始化请求驱动异常: ${JSON.stringify(err)}`)
      }
      const rawState = await executor.callGlobalFunction(
        '__source_getInitState__', JSON.stringify([this.info.name]))
      initState = this.parseInitState(rawState)
      if (initState.inited || initState.error) break
      await new Promise<void>((resolve) => setTimeout(resolve, 50))
    }
    LogUtils.info(`[Web执行器] 初始化请求驱动完成: ${this.info.name}, inited=${initState.inited}`)
    return initState
  }

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
      const method = ((opts['method'] as string) ?? 'GET').toUpperCase()
      const headers = (opts['headers'] as Record<string, string>) ?? {}
      // 对齐原版 userApi/request.js：默认补 Accept，脚本未带 UA 时补浏览器 UA
      const mergedHeaders: Record<string, string> = { 'Accept': 'application/json' }
      const hKeys = Object.keys(headers)
      for (let i = 0; i < hKeys.length; i++) {
        mergedHeaders[hKeys[i]] = headers[hKeys[i]]
      }
      if (!mergedHeaders['User-Agent'] && !mergedHeaders['user-agent']) {
        mergedHeaders['User-Agent'] = 'Mozilla/5.0 (Windows NT 10.0; WOW64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/69.0.3497.100 Safari/537.36'
      }
      const body = this.buildRequestBody(opts, method, mergedHeaders)
      const timeout = typeof opts['timeout'] === 'number' ?
        Math.min(Math.max(opts['timeout'] as number, 1), 60000) : 30000
      const binary = opts['binary'] === true
      const req = this.createResponseRequest(url, method, mergedHeaders, body, timeout, binary)
      this.inflightWebRequests.set(requestId, req)
      const response = await req.promise
      this.inflightWebRequests.delete(requestId)
      LogUtils.info(`[沙箱] 网络请求完成: status=${response.statusCode}, len=${response.body.length}`)
      const respObj: Record<string, Object> = {}
      respObj['statusCode'] = response.statusCode
      respObj['statusMessage'] = response.statusMessage
      respObj['headers'] = response.headers
      respObj['body'] = response.body
      const respJson = JSON.stringify(respObj)
      this.bridge.setNativeResult(this.handle, requestId, 'null', respJson)
    } catch (err) {
      this.inflightWebRequests.delete(requestId)
      LogUtils.warn(`[沙箱] 网络请求失败: ${url.substring(0, 120)}`, String(err))
      this.bridge.setNativeResult(this.handle, requestId, JSON.stringify(String(err)), 'null')
    }
  }

  /** 驱动一轮脚本请求循环：驱动定时器 + 处理挂起网络请求（init 加载阶段与 callAction 共用） */
  private async driveTick(): Promise<void> {
    if (!this.bridge) return
    // 0. 驱动脚本内 setTimeout 定时器
    try {
      this.bridge.callGlobalFunction(this.handle, '__source_tick__', '[]')
    } catch (tickErr) {
      // 忽略 tick 异常
    }
    // 1. 取脚本挂起的网络请求并发起
    try {
      const reqsJson = this.bridge.callGlobalFunction(this.handle, '__source_takeRequests__', '[]')
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
  }

  /** 驱动 Web 模式的脚本网络请求：直接 ArkTS 原生 http，完成后回传脚本 */
  private async doWebRequest(executor: JsExecutor, reqId: string, url: string, optionsJson: string): Promise<void> {
    try {
      let opts: Record<string, Object> = {}
      try {
        opts = JSON.parse(optionsJson) as Record<string, Object>
      } catch (e) {
        opts = {}
      }
      const method = ((opts['method'] as string) ?? 'GET').toUpperCase()
      const headers = (opts['headers'] as Record<string, string>) ?? {}
      // 对齐原版 userApi/request.js：默认补 Accept，脚本未带 UA 时补浏览器 UA
      const mergedHeaders: Record<string, string> = { 'Accept': 'application/json' }
      const hKeys = Object.keys(headers)
      for (let i = 0; i < hKeys.length; i++) {
        mergedHeaders[hKeys[i]] = headers[hKeys[i]]
      }
      if (!mergedHeaders['User-Agent'] && !mergedHeaders['user-agent']) {
        mergedHeaders['User-Agent'] = 'Mozilla/5.0 (Windows NT 10.0; WOW64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/69.0.3497.100 Safari/537.36'
      }
      const body = this.buildRequestBody(opts, method, mergedHeaders)
      const timeout = typeof opts['timeout'] === 'number' ?
        Math.min(Math.max(opts['timeout'] as number, 1), 60000) : 30000
      LogUtils.info(`[Web执行器] 驱动请求: ${method} ${url.substring(0, 120)}`)
      // 可取消请求（对齐参考 { promise, cancelFn }：调用方超时/放弃时可中止网络请求）
      const binary = opts['binary'] === true
      const req = this.createResponseRequest(url, method, mergedHeaders, body, timeout, binary)
      this.inflightWebRequests.set(reqId, req)
      const response = await req.promise
      this.inflightWebRequests.delete(reqId)
      LogUtils.info(`[Web执行器] 驱动请求完成: status=${response.statusCode}, len=${response.body.length}`)
      const respObj: Record<string, Object> = {}
      respObj['statusCode'] = response.statusCode
      respObj['statusMessage'] = response.statusMessage
      respObj['headers'] = response.headers
      respObj['body'] = response.body
      const respJson = JSON.stringify(respObj)
      await executor.callGlobalFunction('__source_resolveRequest__', JSON.stringify([reqId, 'null', respJson]))
    } catch (err) {
      this.inflightWebRequests.delete(reqId)
      LogUtils.warn(`[Web执行器] 驱动请求失败: ${JSON.stringify(err)}`)
      await executor.callGlobalFunction('__source_resolveRequest__', JSON.stringify([reqId, JSON.stringify(String(err)), 'null']))
    }
  }

  /** 触发脚本 action 并等待结果（内含请求处理循环） */
  private async callAction(action: string, info: Record<string, Object>): Promise<string> {
    if (!this.isReady) return '{"status":false,"error":"sandbox not ready"}'
    const requestId = `call_${Date.now()}_${Math.floor(Math.random() * 100000)}`
    // 注入 source 标识（原版协议：source = 歌曲平台 wy/kg/tx...，调用方显式传入时优先保留）
    const callInfo: Record<string, Object> = {}
    const keys = Object.keys(info)
    for (let i = 0; i < keys.length; i++) {
      callInfo[keys[i]] = info[keys[i]]
    }
    if (!callInfo['source']) {
      callInfo['source'] = String(this.info.type)
    }
    LogUtils.info(`[沙箱] action=${action} requestId=${requestId} source=${String(this.info.name)} 开始`)

    // Web 执行器模式：原生异步环境，直接轮询结果 + 驱动请求队列（ArkTS 原生网络）
    if (this.useWebExecutor) {
      const executor = JsExecutorRegistry.instance
      if (!executor || !JsExecutorRegistry.isAvailable()) {
        return '{"status":false,"error":"executor not available"}'
      }
      await executor.callGlobalFunction('__source_call__', JSON.stringify([requestId, action, callInfo, this.info.name]))
      const deadline = Date.now() + 20000
      while (Date.now() < deadline) {
        // 驱动脚本挂起的网络请求（直接 ArkTS 原生网络，绕开 Web 代理）
        const reqsJson = await executor.callGlobalFunction('__source_takeRequests__', '[]')
        if (reqsJson && reqsJson !== 'null' && reqsJson !== '[]') {
          try {
            const reqs = JSON.parse(reqsJson) as Array<Record<string, Object>>
            for (let i = 0; i < reqs.length; i++) {
              const req = reqs[i]
              const reqId = (req['requestId'] as string) ?? ''
              const reqUrl = (req['url'] as string) ?? ''
              const reqOpts = JSON.stringify(req['options'] ?? {})
              if (reqId && reqUrl) {
                this.doWebRequest(executor, reqId, reqUrl, reqOpts)
              }
            }
          } catch (reqErr) {
            LogUtils.warn(`[沙箱] 请求队列解析异常: ${JSON.stringify(reqErr)}`)
          }
        }
        const r = await executor.callGlobalFunction('__source_takeResult__', JSON.stringify([requestId]))
        if (r && r !== 'null' && r !== '""' && r !== '') {
          LogUtils.info(`[沙箱] action=${action} 结果: ${r.substring(0, 200)}`)
          return r
        }
        await new Promise<void>((resolve) => setTimeout(resolve, 50))
      }
      LogUtils.warn(`[沙箱] action=${action} 超时`)
      // 超时诊断：读取脚本侧全局错误与注册状态
      try {
        const errs = await executor.callGlobalFunction('__source_takeResult__', JSON.stringify([requestId]))
        LogUtils.warn(`[沙箱] 超时最终结果: ${errs}`)
        const diag = await executor.callGlobalFunction('__source_diag__', '[]')
        LogUtils.warn(`[沙箱] 诊断: ${diag}`)
      } catch (diagErr) {
        LogUtils.warn(`[沙箱] 诊断异常: ${JSON.stringify(diagErr)}`)
      }
      return '{"status":false,"error":"script timeout"}'
    }

    // 启动脚本 handler
    let callRet = ''
    if (!this.bridge) return '{"status":false,"error":"bridge not ready"}'
    try {
      callRet = this.bridge.callGlobalFunction(this.handle, '__source_call__', JSON.stringify([requestId, action, callInfo]))
    } catch (callErr) {
      LogUtils.error(`[沙箱] __source_call__ 调用异常`, JSON.stringify(callErr))
      return '{"status":false,"error":"call exception"}'
    }
    LogUtils.info(`[沙箱] __source_call__ 返回: ${callRet}`)

    // 等待循环：处理脚本请求 + 驱动定时器 + 轮询结果（最多 15 秒）
    const deadline = Date.now() + 15000
    while (Date.now() < deadline) {
      // 驱动定时器 + 发起脚本挂起的网络请求
      await this.driveTick()

      // 2. 检查脚本结果
      try {
        const r = this.bridge.callGlobalFunction(this.handle, '__source_takeResult__', JSON.stringify([requestId]))
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

  /**
   * 查询脚本声明的 actions 能力（原版 社区音源 协议：inited 上报 sources.actions）
   * 返回空数组 = 未上报能力声明，按标准解析源处理，不参与搜索。
   */
  async getDeclaredActions(): Promise<string[]> {
    const result: string[] = []
    const capabilityKeys = Object.keys(this.sourceCapabilities)
    if (capabilityKeys.length > 0) {
      for (let i = 0; i < capabilityKeys.length; i++) {
        const actions = this.sourceCapabilities[capabilityKeys[i]].actions
        for (let j = 0; j < actions.length; j++) {
          if (result.indexOf(actions[j]) < 0) result.push(actions[j])
        }
      }
      return result
    }
    const argsJson = JSON.stringify([this.info.name])
    try {
      if (this.useWebExecutor) {
        const executor = JsExecutorRegistry.instance
        if (!executor) return result
        const raw = await executor.callGlobalFunction('__source_getActions__', argsJson)
        if (raw && raw !== 'null' && raw !== '[]' && raw !== '""') {
          return JSON.parse(raw) as Array<string>
        }
        return result
      }
      if (this.bridge && this.handle) {
        const raw = this.bridge.callGlobalFunction(this.handle, '__source_getActions__', argsJson)
        if (raw && raw !== 'null' && raw !== '[]' && raw !== '""') {
          return JSON.parse(raw) as Array<string>
        }
      }
    } catch (err) {
      LogUtils.warn(`[沙箱] 能力查询异常: ${JSON.stringify(err)}`)
    }
    return result
  }

  /**
   * 该 JS 源是否支持搜索（供测试/UI 提示：解析源不支持搜索，仅用于播放换源解析）
   */
  async supportsSearch(): Promise<boolean> {
    const actions = await this.getDeclaredActions()
    // 社区音源 标准导入源只定义 musicUrl/lyric/pic；只有显式声明 search 的扩展源才参与搜索。
    return actions.indexOf('search') >= 0
  }

  /** 搜索歌曲 */
  async search(query: string, page: number, _quality: MusicQuality): Promise<SearchResult> {
    const emptyResult: SearchResult = { list: [], total: 0, limit: 30, page: page, source: this.info.type }
    // 能力检查：只有显式声明 search 扩展能力的脚本才触发搜索 handler。
    const declaredActions = await this.getDeclaredActions()
    if (declaredActions.indexOf('search') < 0) {
      const actionText = declaredActions.length > 0 ? declaredActions.join('/') : '未上报'
      LogUtils.info(`音源 ${this.info.name} 未声明 search 能力（actions=${actionText}），跳过搜索`)
      return emptyResult
    }
    // 补全社区音源约定的所有搜索参数字段（不同音源脚本用不同字段名）
    const searchInfo: Record<string, Object> = {}
    searchInfo['text'] = query
    searchInfo['keyword'] = query
    searchInfo['name'] = query
    searchInfo['query'] = query
    searchInfo['key'] = query
    searchInfo['page'] = page
    searchInfo['limit'] = 30
    searchInfo['type'] = 'music'
    searchInfo['pageSize'] = 30
    const raw = await this.callAction('search', searchInfo)
    const list: MusicItem[] = []
    let total = 0
    try {
      const parsed = JSON.parse(raw) as Record<string, Object>
      if (parsed['status'] === false) {
        LogUtils.warn(`音源搜索失败: ${parsed['error']}`)
        return emptyResult
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

  /** 根据脚本对指定平台声明的 qualitys，从目标音质向下选择可用音质。 */
  private resolveSupportedQuality(source: string, requested: MusicQuality): MusicQuality {
    const capability = this.sourceCapabilities[source]
    if (!capability || capability.qualitys.length === 0) return requested
    if (capability.qualitys.indexOf(String(requested)) >= 0) return requested
    const ordered: MusicQuality[] = [
      MusicQuality.HIRES,
      MusicQuality.LOSSLESS,
      MusicQuality.HIGH,
      MusicQuality.LOW
    ]
    const requestedIndex = ordered.indexOf(requested)
    const start = requestedIndex >= 0 ? requestedIndex + 1 : 0
    for (let i = start; i < ordered.length; i++) {
      if (capability.qualitys.indexOf(String(ordered[i])) >= 0) return ordered[i]
    }
    for (let i = 0; i < start; i++) {
      if (capability.qualitys.indexOf(String(ordered[i])) >= 0) return ordered[i]
    }
    return requested
  }

  /**
   * 轻量探测解析结果，阻止 404/HTML 错误页被误当成音频交给 AVPlayer。
   * HarmonyOS 对部分地址的 HEAD 请求会直接报错，因此用 Range GET 只读取首字节。
   */
  private async validateResolvedUrl(url: string): Promise<boolean> {
    try {
      const headers: Record<string, string> = {
        'Accept': '*/*',
        'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; WOW64) AppleWebKit/537.36',
        'Range': 'bytes=0-0'
      }
      const probe = this.createResponseRequest(url, 'GET', headers, '', 5000, true)
      const response = await probe.promise
      const statusCode = response.statusCode
      if (statusCode < 200 || statusCode >= 400) {
        LogUtils.warn(`[解析] 播放地址探测失败: HTTP ${statusCode}`)
        return false
      }
      // 未自动跟随的重定向交给 AVPlayer 处理，重定向响应本身可能声明 JSON 类型。
      if (statusCode >= 300) return true
      let contentType = ''
      const headerKeys = Object.keys(response.headers)
      for (let i = 0; i < headerKeys.length; i++) {
        if (headerKeys[i].toLowerCase() === 'content-type') {
          contentType = response.headers[headerKeys[i]].toLowerCase()
          break
        }
      }
      if (contentType.indexOf('text/html') >= 0 || contentType.indexOf('application/json') >= 0) {
        LogUtils.warn(`[解析] 播放地址返回非音频内容: ${contentType}`)
        return false
      }
      return true
    } catch (err) {
      LogUtils.warn(`[解析] 播放地址探测异常，判定本次解析失败: ${String(err)}`)
      return false
    }
  }

  /** 获取播放 URL（对齐原版：info: { source, type, musicInfo: 完整歌曲对象 }） */
  async getMusicInfo(songmid: string, quality: MusicQuality, fullSong?: MusicItem): Promise<MusicItem> {
    const platformSource = fullSong ? String(fullSong.source) : ''
    const capabilityKeys = Object.keys(this.sourceCapabilities)
    if (platformSource && capabilityKeys.length > 0) {
      const capability = this.sourceCapabilities[platformSource]
      if (!capability || capability.actions.indexOf('musicUrl') < 0) {
        throw new Error(`音源未声明 ${platformSource} 平台的 musicUrl 能力`)
      }
    }
    const requestQuality = this.resolveSupportedQuality(platformSource, quality)
    const musicInfo: Record<string, Object> = {}
    musicInfo['type'] = String(requestQuality)
    musicInfo['musicInfo'] = this.buildSongInfo(songmid, fullSong)
    // 原版协议：event.source = 歌曲平台（wy/kg/tx/kw/mg），解析 API 据此确定参数
    if (fullSong) {
      musicInfo['source'] = String(fullSong.source)
    }
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
      if (!await this.validateResolvedUrl(url)) {
        throw new Error('解析服务返回的地址不可播放')
      }
      const types: Record<string, MusicQualityInfo> = {}
      types[String(requestQuality)] = { url: url, size: 0, br: 0 }
      return {
        songmid: songmid,
        name: fullSong?.name ?? '',
        singer: fullSong?.singer ?? '',
        albumName: fullSong?.albumName ?? '',
        interval: fullSong?.interval ?? 0,
        imgUrl: fullSong?.imgUrl ?? '',
        lyricUrl: fullSong?.lyricUrl ?? '',
        source: this.info.type,
        types: types
      }
    } catch (err) {
      throw new Error(`获取播放地址失败: ${JSON.stringify(err)}`)
    }
  }

  /** 获取歌词（对齐原版：info: { musicInfo }） */
  async getLyric(songmid: string, fullSong?: MusicItem): Promise<LyricLine[]> {
    const lyricInfo: Record<string, Object> = {}
    lyricInfo['musicInfo'] = this.buildSongInfo(songmid, fullSong)
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

  /** 构造社区音源使用的 MusicInfo 结构 */
  private buildSongInfo(songmid: string, fullSong?: MusicItem): Record<string, Object> {
    const song: Record<string, Object> = {}
    song['id'] = songmid
    song['songmid'] = songmid
    song['hash'] = songmid
    song['name'] = fullSong?.name ?? ''
    song['singer'] = fullSong?.singer ?? ''
    song['source'] = String(fullSong?.source ?? this.info.type)
    song['interval'] = fullSong?.interval ?? 0
    song['albumName'] = fullSong?.albumName ?? ''
    song['imgUrl'] = fullSong?.imgUrl ?? ''
    song['lyricUrl'] = fullSong?.lyricUrl ?? ''
    return song
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

  /**
   * 读取自定义搜索结果携带的真实音乐平台。
   * 搜索动作由导入源提供，但歌曲 source 仍必须是社区约定的平台标识，
   * 否则后续 musicUrl 会收到 custom 并报“无效的平台参数”。
   */
  private getSongSource(item: Record<string, Object>): SourceType {
    const rawSource = String(item['source'] ?? item['platform'] ?? '').trim().toLowerCase()
    switch (rawSource) {
      case 'kg':
      case 'kugou':
        return SourceType.KG
      case 'kw':
      case 'kuwo':
        return SourceType.KW
      case 'tx':
      case 'qq':
      case 'qqmusic':
        return SourceType.TX
      case 'wy':
      case 'netease':
      case 'wyy':
        return SourceType.WY
      case 'mg':
      case 'migu':
        return SourceType.MG
      case 'local':
        return SourceType.LOCAL
      default:
        return this.info.type
    }
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
      source: this.getSongSource(item),
      types: {}
    }
  }
}
