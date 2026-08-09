import {
  SourceInstance,
  SourceInfo,
  SourceImportMethod,
  SourceImportResult,
  SourceTestResult,
  SourceType,
  SearchResult,
  MusicItem,
  ToggleMusicInfo,
  LyricLine,
  MusicQuality,
  LogUtils,
  StorageUtils,
  NetUtils
} from 'common'
import { BaseSource } from '../api/SourceAPI'
import { LocalFileSource } from '../sources/LocalFileSource'
import { KugouSource } from '../sources/KugouSource'
import { NeteaseSource } from '../sources/NeteaseSource'
import { QQSource } from '../sources/QQSource'
import { KuwoSource } from '../sources/KuwoSource'
import { MiguSource } from '../sources/MiguSource'
import { JSSourceAdapter } from '../sources/JSSourceAdapter'
import { JSScriptSource } from '../sources/JSScriptSource'
import { JSSandbox } from '../sandbox/JSSandbox'
import { fileIo } from '@kit.CoreFileKit'
import { util } from '@kit.ArkTS'

const STORAGE_KEY_SOURCES = 'source_list'
const STORAGE_KEY_SCRIPTS = 'source_scripts'
const STORAGE_KEY_ACTIVE_JS_SOURCE = 'active_js_source'
const STORAGE_KEY_EXTENDED_SEARCH = 'lx_extended_search'
const CACHE_KEY_PLAY_URL = 'play_url_cache'
const CACHE_KEY_LYRIC = 'lyric_cache'
const CACHE_KEY_TOGGLE_MAP = 'toggle_music_map'
const CACHE_MAX_SIZE = 200
const PLAY_URL_CACHE_TTL = 3 * 60 * 1000
const OTHER_SOURCE_CACHE_MAX = 10
const LYRIC_CACHE_MAX = 100
const LYRIC_CACHE_TTL = 7 * 24 * 3600 * 1000
const NATIVE_SEARCH_TIMEOUT_MS = 8000
const JS_SEARCH_TIMEOUT_MS = 15000

/** 持久化的音源记录（元信息 + 开关 + 优先级） */
interface SavedSource {
  info: SourceInfo
  enabled: boolean
  priority: number
}

/** 歌词缓存条目（含时间戳用于TTL） */
interface LyricCacheEntry {
  lines: LyricLine[]
  timestamp: number
}

/** 换源搜索缓存条目 */
interface OtherSourceCacheEntry {
  list: MusicItem[]
  timestamp: number
}

/** 匹配结果（带优先级分数） */
interface MatchResult {
  item: MusicItem
  score: number
}

/**
 * 多音源管理器 — 统一管理所有音源的生命周期
 *
 * 负责：
 * 1. 音源的注册、启用/禁用、优先级排序
 * 2. 聚合搜索（并发请求所有启用音源）
 * 3. 播放信息获取 + 换源重试（多轮匹配 + toggleMusicInfo）
 * 4. 音源列表持久化
 */
export class SourceManager {
  private sources: SourceInstance[] = []
  /** 缓存播放URL（含时间戳；缓存命中时校验过期与 https） */
  private playUrlCache: Map<string, MusicItem> = new Map()
  private playUrlCacheTs: Map<string, number> = new Map()
  /** 换源搜索结果缓存（避免重复搜索） */
  private otherSourceCache: Map<string, OtherSourceCacheEntry> = new Map()
  /** 歌词缓存（内存 Map，持久化到 StorageUtils） */
  private lyricCache: Map<string, LyricCacheEntry> = new Map()
  /** toggleMusicInfo 持久化映射（避免重启后重新换源） */
  private toggleMusicMap: Map<string, ToggleMusicInfo> = new Map()
  /** 换源全失败缓存（key → 时间戳，2 分钟内跳过重复换源搜索，避免音质降级链/重播重复耗时） */
  /** 换源失败缓存（已弃用：对齐参考 lx-music 失败立即重试；保留字段避免序列化兼容问题） */
  private fallbackFailCache: Map<string, number> = new Map()
  /**
   * 解析源优先模式（对齐参考 api-source 分层：用户 JS 源接管平台解析）
   * 默认 true = 已启用的用户解析源优先，行为与 lx-music 选择自定义 API 后一致。
   * UI 接入点：设置页/音源管理页开关（setParseSourceFirst）
   */
  private parseSourceFirst: boolean = true
  /**
   * 自定义源搜索扩展开关。
   * 默认关闭时严格遵循 LX：内置平台负责搜索，活动 JS 源只负责解析播放地址。
   */
  private extendedSearchEnabled: boolean = false

  /** 设置解析源优先模式（UI 接入点） */
  setParseSourceFirst(enabled: boolean): void {
    this.parseSourceFirst = enabled
    LogUtils.info(`[音源] 解析源优先模式: ${enabled ? '开启' : '关闭'}`)
  }

  /** 当前是否解析源优先模式 */
  isParseSourceFirst(): boolean {
    return this.parseSourceFirst
  }

  /** 当前是否允许声明 search 的活动 JS 源参与搜索。 */
  isExtendedSearchEnabled(): boolean {
    return this.extendedSearchEnabled
  }

  /** 切换自定义搜索扩展并持久化；关闭即恢复严格 LX 搜索路径。 */
  async setExtendedSearchEnabled(enabled: boolean): Promise<void> {
    this.extendedSearchEnabled = enabled
    await StorageUtils.putString(STORAGE_KEY_EXTENDED_SEARCH, enabled ? 'true' : 'false')
    LogUtils.info(`[音源] 扩展音源搜索: ${enabled ? '开启' : '关闭（严格 LX 模式）'}`)
  }
  /** 解析源失败冷却（源+平台+音质 → 到期时间；允许音质降级继续尝试） */
  private parseSourceCooldown: Map<string, number> = new Map()
  /** 主源失败标记（key → 时间戳，5 分钟内跳过原源直接换源；播放出错后由 PlayerEngine 标记） */
  private primaryFailCache: Map<string, number> = new Map()
  private static instance: SourceManager | null = null

  static getInstance(): SourceManager {
    if (!SourceManager.instance) {
      SourceManager.instance = new SourceManager()
    }
    return SourceManager.instance
  }

  /** 恢复已保存的 JS 音源（Web 执行器就绪后可再次调用重新加载） */
  async reloadJSSources(): Promise<void> {
    const saved = await StorageUtils.getObject<SavedSource[]>(STORAGE_KEY_SOURCES, [])
    const scripts = await StorageUtils.getObject<Record<string, string>>(STORAGE_KEY_SCRIPTS, {})
    const persistedActiveId = await StorageUtils.getString(STORAGE_KEY_ACTIVE_JS_SOURCE, '')
    const savedJsSources = saved.filter(item => {
      const id = item.info?.id ?? ''
      return !!id && !this.isSearchSourceId(id) && id !== 'local_source' && id !== 'demo' && !!scripts[id]
    })
    // 对齐 lx-music 的 common.apiSource：运行期只加载一个当前选中的用户解析源。
    // 旧版本没有单独保存当前源；迁移时取列表中最后一个历史启用源，通常就是最近选择的源。
    let activeSourceId = savedJsSources.some(item => item.info.id === persistedActiveId)
      ? persistedActiveId
      : ''
    if (!activeSourceId) {
      const legacyEnabled = savedJsSources.filter(item => item.enabled !== false)
      if (legacyEnabled.length > 0) {
        activeSourceId = legacyEnabled[legacyEnabled.length - 1].info.id
      }
    }
    // 移除旧 JS 源（重新初始化，避免重复）
    const oldJs = this.sources.filter(s => !this.isSearchSourceId(s.info.id) && s.info.id !== 'local_source' && s.info.id !== 'demo')
    for (const old of oldJs) {
      if (old instanceof JSScriptSource) old.destroy()
      const idx = this.sources.indexOf(old)
      if (idx >= 0) this.sources.splice(idx, 1)
    }
    let restoredCount = 0
    for (const savedSource of saved) {
      const info = savedSource.info
      // 跳过内置音源（演示/本地文件）
      if (!info || info.id === 'demo' || info.id === 'local_source') continue
      const script = scripts[info.id]
      if (!script) {
        LogUtils.warn(`音源脚本缺失，跳过: ${info.name}`)
        continue
      }
      try {
        // 对齐 lx-music：未启用的音源只恢复元数据与脚本，不在应用启动/导入阶段执行。
        let source: JSScriptSource = new JSScriptSource(script, info)
        source.enabled = false
        source.priority = savedSource.priority
        if (info.id === activeSourceId) {
          const initialized = await JSSandbox.createSource(script, info)
          if (initialized && initialized instanceof JSScriptSource) {
            source = initialized
            source.enabled = true
            source.priority = savedSource.priority
            restoredCount++
          } else {
            LogUtils.warn(`已保存音源初始化失败，保留脚本并暂时禁用: ${info.name}`)
            activeSourceId = ''
          }
        }
        this.sources.push(source)
      } catch (err) {
        LogUtils.error(`恢复音源失败: ${info.name}`, JSON.stringify(err))
        if (info.id === activeSourceId) activeSourceId = ''
        const source = new JSScriptSource(script, info)
        source.enabled = false
        source.priority = savedSource.priority
        this.sources.push(source)
      }
    }
    // 将旧版多 enabled 状态收敛成单一活动源，避免下次启动再次批量初始化。
    await this.save()
    LogUtils.info(`JS 音源恢复完成: ${restoredCount} 个（共 ${this.sources.length} 个音源）`)
  }

  /** 初始化：注册内置官方音源（lx-music 同款 5 源）+ 恢复用户导入的 JS 音源 */
  async init(): Promise<void> {
    // 默认严格 LX 模式；只有用户主动开启后，自定义源的 search 扩展才会参与搜索。
    const extendedSearch = await StorageUtils.getString(STORAGE_KEY_EXTENDED_SEARCH, 'false')
    this.extendedSearchEnabled = extendedSearch === 'true'

    // 本地文件音源（本地音乐功能，非在线音源）
    const localFile = new LocalFileSource()
    localFile.priority = 50
    this.sources.push(localFile)

    // 内置官方音源（与 lx-music 一致：酷狗/网易/QQ/酷我/咪咕）
    const kugou = new KugouSource()
    this.sources.push(kugou)
    const netease = new NeteaseSource()
    this.sources.push(netease)
    const qq = new QQSource()
    this.sources.push(qq)
    const kuwo = new KuwoSource()
    this.sources.push(kuwo)
    const migu = new MiguSource()
    this.sources.push(migu)

    // 恢复已保存的 JS 音源（读取脚本内容 → 重新创建沙箱）
    await this.reloadJSSources()

    LogUtils.info('音源管理器初始化完成', `共 ${this.sources.length} 个音源`)

    // 恢复歌词缓存（跳过过期条目）
    const savedLyrics = await StorageUtils.getObject<Record<string, LyricCacheEntry>>(CACHE_KEY_LYRIC, {})
    const now = Date.now()
    for (const key of Object.keys(savedLyrics)) {
      const entry = savedLyrics[key]
      if (entry && entry.lines && now - entry.timestamp < LYRIC_CACHE_TTL) {
        this.lyricCache.set(key, entry)
      }
    }
    LogUtils.info('歌词缓存恢复', `${this.lyricCache.size} 条有效`)

    // 恢复 toggleMusicInfo 映射
    const savedToggles = await StorageUtils.getObject<Record<string, ToggleMusicInfo>>(CACHE_KEY_TOGGLE_MAP, {})
    for (const key of Object.keys(savedToggles)) {
      this.toggleMusicMap.set(key, savedToggles[key])
    }
    LogUtils.info('换源映射恢复', `${this.toggleMusicMap.size} 条`)
  }

  /** 获取所有音源 */
  getAllSources(): SourceInstance[] {
    return [...this.sources]
  }

  /** 获取已启用的音源（按优先级排序） */
  getEnabledSources(): SourceInstance[] {
    return this.sources
      .filter(s => s.enabled)
      .sort((a, b) => a.priority - b.priority)
  }

  /** 按 ID 查找音源 */
  getSourceById(id: string): SourceInstance | undefined {
    return this.sources.find(s => s.info.id === id)
  }

  /** 获取本地文件音源实例 */
  getLocalFileSource(): LocalFileSource | undefined {
    return this.sources.find(s => s.info.id === 'local_source') as LocalFileSource
  }

  /** 导入本地音乐文件（文件选择器多选） */
  async importLocalFiles(uriList: string[]): Promise<number> {
    const localSource = this.getLocalFileSource()
    if (!localSource) return 0
    return await localSource.importFiles(uriList)
  }

  /** 扫描指定文件夹导入本地音乐（递归，解析封面/歌手/专辑等元数据） */
  async scanLocalFolder(dirUri: string): Promise<number> {
    const localSource = this.getLocalFileSource()
    if (!localSource) return 0
    return await localSource.scanDirectoryWithMetadata(dirUri)
  }

  /** 获取本地音乐歌曲列表 */
  getLocalSongs(): MusicItem[] {
    const localSource = this.getLocalFileSource()
    if (!localSource) return []
    return localSource.getSongs()
  }

  /** 导入音源 */
  async importSource(method: SourceImportMethod, pathOrUrl: string): Promise<SourceImportResult> {
    switch (method) {
      case SourceImportMethod.LOCAL_FILE:
        return this.importFromLocal(pathOrUrl)
      case SourceImportMethod.ONLINE_URL:
        return this.importFromUrl(pathOrUrl)
      default:
        return { success: false, error: '不支持的导入方式' }
    }
  }

  /** 从本地文件导入 JS 音源脚本 */
  private async importFromLocal(filePath: string): Promise<SourceImportResult> {
    LogUtils.info('导入本地音源', filePath)
    let fd: fileIo.File | null = null
    try {
      // 读取文件内容（DocumentViewPicker 返回的 URI 可直接 openSync）
      fd = fileIo.openSync(filePath, fileIo.OpenMode.READ_ONLY)
      const stat = fileIo.statSync(filePath)
      if (stat.size <= 0) {
        return { success: false, error: '文件为空或无法读取（大小为 0）' }
      }
      const buf = new ArrayBuffer(stat.size)
      fileIo.readSync(fd.fd, buf)
      fileIo.closeSync(fd)
      fd = null

      // 使用 TextDecoder 解码为 UTF-8 字符串（避免手动转码乱码）
      const decoder = util.TextDecoder.create('utf-8')
      const scriptContent = decoder.decodeToString(new Uint8Array(buf))

      // 从 URI 或路径中提取文件名（用于兜底命名）
      const lastSlash = filePath.lastIndexOf('/')
      const rawName = lastSlash >= 0 ? filePath.substring(lastSlash + 1) : filePath
      const fileName = rawName.includes('?') ? rawName.substring(0, rawName.indexOf('?')) : rawName

      return this.registerJSSource(scriptContent, fileName)
    } catch (err) {
      if (fd) {
        try {
          fileIo.closeSync(fd)
        } catch (e) {
          // 忽略关闭失败
        }
      }
      const errMsg = JSON.stringify(err)
      LogUtils.error('读取本地音源文件失败', errMsg)
      return { success: false, error: `读取文件失败: ${errMsg}` }
    }
  }

  /** 从在线 URL 导入 JS 音源脚本 */
  private async importFromUrl(url: string): Promise<SourceImportResult> {
    LogUtils.info('导入在线音源', url)
    try {
      // 部分源站拒绝无 UA 请求（浏览器可访问但应用下载空），带浏览器 UA 重试
      const headers: Record<string, string> = {
        'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36'
      }
      let scriptContent = await NetUtils.getString(url, headers)
      // GitHub raw 直连失败（设备网络常被阻断）：自动尝试常见镜像加速
      if (!scriptContent && url.includes('raw.githubusercontent.com')) {
        const mirrors: string[] = [
          'https://ghproxy.com/',
          'https://mirror.ghproxy.com/',
          'https://ghfast.top/',
          'https://gh-proxy.com/'
        ]
        for (const m of mirrors) {
          LogUtils.info(`[导入] GitHub 直连失败，尝试镜像: ${m}`)
          scriptContent = await NetUtils.getString(`${m}${url}`, headers)
          if (scriptContent) {
            LogUtils.info(`[导入] 镜像下载成功: ${m}`)
            break
          }
        }
      }
      if (!scriptContent) {
        return { success: false, error: '下载音源脚本失败，请检查网络连接（GitHub 源可用 https://ghproxy.com/ 等镜像加速，或本地文件导入）' }
      }
      return this.registerJSSource(scriptContent, '')
    } catch (err) {
      LogUtils.error('下载在线音源失败', JSON.stringify(err))
      return { success: false, error: `下载失败: ${JSON.stringify(err)}` }
    }
  }

  /** 注册 JS 音源：只校验并保存，真正执行放到用户启用音源时。 */
  private async registerJSSource(scriptContent: string, fileName: string = ''): Promise<SourceImportResult> {
    // 安全校验
    const securityError = JSSandbox.validateScript(scriptContent)
    if (securityError) {
      LogUtils.warn('音源脚本安全校验未通过', securityError)
      return { success: false, error: `安全校验失败: ${securityError}` }
    }

    // 解析元信息（头部注释 @标签，兜底用文件名/日期）
    const sourceInfo = JSSourceAdapter.parseSourceInfo(scriptContent, fileName)

    // 导入阶段不执行第三方脚本，避免死循环、网络等待或渲染进程异常阻塞文件导入。
    const source = new JSScriptSource(scriptContent, sourceInfo)
    source.enabled = false

    // 检查是否已存在（更新而非重复添加）
    const existing = this.sources.find(s => s.info.id === source.info.id)
    if (existing) {
      const idx = this.sources.indexOf(existing)
      source.priority = existing.priority
      if (existing instanceof JSScriptSource) existing.destroy()
      this.sources[idx] = source
      LogUtils.info(`更新音源: ${source.info.name}`)
    } else {
      this.sources.push(source)
      LogUtils.info(`导入音源: ${source.info.name} v${source.info.version}`)
    }

    await this.save()
    return { success: true, source: source }
  }

  /** 移除音源 */
  async removeSource(id: string): Promise<boolean> {
    const index = this.sources.findIndex(s => s.info.id === id)
    if (index < 0) return false
    // 销毁 JSVM 沙箱释放资源
    const removed = this.sources[index]
    if (removed instanceof JSScriptSource) {
      removed.destroy()
    }
    this.sources.splice(index, 1)
    await this.save()
    return true
  }

  /** 开关音源（JS 音源单选互斥；搜索源始终启用） */
  async toggleSource(id: string, enabled: boolean): Promise<SourceTestResult> {
    let source = this.getSourceById(id)
    if (!source) return { success: false, message: '音源不存在' }
    // 搜索源固定启用（在搜索页选择使用范围，不在音源管理中开关）
    if (this.isSearchSourceId(id)) {
      source.enabled = true
      await this.save()
      return { success: true, message: '内置音源已启用' }
    }

    if (enabled) {
      // 对齐 lx-music：只有用户明确启用时才创建执行环境并运行脚本。
      if (source instanceof JSScriptSource) {
        const initialized = await JSSandbox.createSource(source.getScriptContent(), source.info)
        if (!initialized || !(initialized instanceof JSScriptSource)) {
          source.enabled = false
          await this.save()
          return { success: false, message: '音源初始化失败或超时，脚本已保留但未启用' }
        }
        initialized.priority = source.priority
        initialized.enabled = true
        const sourceIndex = this.sources.indexOf(source)
        source.destroy()
        this.sources[sourceIndex] = initialized
        source = initialized
      }
      // 启用 JS 音源时，自动禁用其他 JS 音源（单选）
      for (const s of this.sources) {
        if (s.info.id === id) continue
        if (!this.isSearchSourceId(s.info.id) && !this.isProtectedSourceId(s.info.id) && !s.isNative) {
          s.enabled = false
          if (s instanceof JSScriptSource) s.destroy()
        }
      }
    } else if (source instanceof JSScriptSource) {
      source.destroy()
    }
    source.enabled = enabled
    await this.save()
    return { success: true, message: enabled ? '音源初始化成功并已启用' : '音源已禁用' }
  }

  /** 是否为内置官方音源（用于超时等差异化处理） */
  isSearchSourceId(id: string): boolean {
    return id === 'kg' || id === 'wy' || id === 'tx' || id === 'kw' || id === 'mg'
  }

  /** 是否为受保护的内置源（不可禁用/删除） */
  isProtectedSourceId(id: string): boolean {
    return this.isSearchSourceId(id) || id === 'local_source' || id === 'demo'
  }

  /** 获取搜索源列表：内置源始终参与；JS 搜索扩展仅在用户主动开启时参与。 */
  async getSearchSources(): Promise<SourceInstance[]> {
    const result: SourceInstance[] = []
    for (const source of this.sources) {
      if (!source.enabled || source.info.id === 'local_source' || source.info.id === 'demo') continue
      if (source instanceof JSScriptSource) {
        if (!this.extendedSearchEnabled || !await source.supportsSearch()) continue
      }
      result.push(source)
    }
    return result
  }

  /**
   * 获取用户可管理的导入音源。
   * 内置平台仅负责搜索与换源，不应混入音源管理列表。
   */
  getManageSources(): SourceInstance[] {
    return this.sources.filter((source: SourceInstance) => source instanceof JSScriptSource)
  }

  /** 按 ID 搜索单个音源 */
  async searchSourceById(
    id: string,
    query: string,
    page: number = 1,
    quality: MusicQuality = MusicQuality.HIGH
  ): Promise<SearchResult | null> {
    const source = this.getSourceById(id)
    if (!source || !source.enabled) return null
    try {
      if (source instanceof JSScriptSource) {
        if (!this.extendedSearchEnabled) {
          LogUtils.info(`严格 LX 模式已开启，音源 ${source.info.name} 仅用于解析，不执行搜索`)
          return null
        }
        if (!await source.supportsSearch()) {
          LogUtils.info(`音源 ${source.info.name} 是解析源，不执行搜索`)
          return null
        }
      }
      // JS 扩展源需要经过脚本与原生网络桥，不能沿用过短的 2.5 秒超时。
      const timeoutMs = this.isSearchSourceId(id) ? NATIVE_SEARCH_TIMEOUT_MS : JS_SEARCH_TIMEOUT_MS
      return await this.withTimeout(source.search(query, page, quality), timeoutMs, `音源 ${source.info.name} 搜索`)
    } catch (err) {
      LogUtils.warn(`音源 ${source.info.name} 搜索失败`, JSON.stringify(err))
      return null
    }
  }

  /** 测试音源是否可用：JS 解析源验证初始化能力，搜索源执行一次搜索。 */
  async testSource(sourceId: string): Promise<SourceTestResult> {
    const source = this.getSourceById(sourceId)
    if (!source) return { success: false, message: '音源不存在' }
    if (!source.enabled) return { success: false, message: '音源已禁用' }
    // lx-music 标准解析源不提供搜索；成功完成 inited 且声明 musicUrl 即视为初始化正常。
    if (source instanceof JSScriptSource) {
      const jsSource = source as JSScriptSource
      const actions = await jsSource.getDeclaredActions()
      if (actions.indexOf('search') < 0 && actions.indexOf('musicUrl') >= 0) {
        return { success: true, message: '初始化正常，解析源支持 musicUrl' }
      }
      if (actions.length === 0) return { success: false, message: '音源未上报可用 actions' }
    }
    try {
      const result = await this.withTimeout(source.search('周杰伦', 1, MusicQuality.HIGH), 15000, `测试 ${source.info.name}`)
      if (result && result.list.length > 0) {
        return { success: true, message: `正常，返回 ${result.list.length} 条` }
      }
      if (result) {
        return { success: false, message: '无搜索结果' }
      }
      return { success: false, message: '搜索失败（可能不支持搜索）' }
    } catch (err) {
      LogUtils.warn(`音源测试失败: ${source.info.name}`, JSON.stringify(err))
      return { success: false, message: '请求超时或异常' }
    }
  }

  /** 设置优先级 */
  async setPriority(id: string, priority: number): Promise<void> {
    const source = this.getSourceById(id)
    if (source) {
      source.priority = priority
      await this.save()
    }
  }

  /**
   * 在指定音源中搜索并匹配目标歌曲（手动换源，支持搜索源 + 解析源组合）
   * @param fullSong 目标歌曲（用歌名+歌手搜索匹配）
   * @param searchSourceId 搜索源 ID（如 'kg'/'wy'/'tx'/'kw'/'mg' 或 JS 源）
   * @param parseSourceId 解析源 ID（可选：用于获取播放地址，如导入的 JS 解析源；为空则用搜索源自身）
   * @returns 可播放的替代版本（保留原歌名/歌手/封面），失败返回 null
   */
  async searchSameSongInSource(
    fullSong: MusicItem,
    searchSourceId: string,
    parseSourceId: string = '',
    quality: MusicQuality = MusicQuality.HIGH
  ): Promise<MusicItem | null> {
    const searchSource = this.getEnabledSources().find(s => s.info.id === searchSourceId)
    if (!searchSource || !fullSong || !fullSong.name) return null
    try {
      const query = `${fullSong.name} ${fullSong.singer}`.trim()
      // 分层匹配：先组合词搜索匹配，失败后改用仅歌名搜索匹配
      let match = await this.searchAndMatch(searchSource, fullSong, query, quality)
      LogUtils.info(`[手动换源] ${searchSource.info.name} 组合词搜索完成`)
      if (!match) {
        LogUtils.info(`[手动换源] ${searchSource.info.name} 组合词无匹配，改用仅歌名搜索`)
        match = await this.searchAndMatch(searchSource, fullSong, fullSong.name, quality)
      }
      if (!match) {
        LogUtils.info(`[手动换源] ${searchSource.info.name} 未匹配到同名歌曲，尝试自动换源兜底`)
        // 所选源搜索不到时：自动换源兜底（在全部启用源中搜索匹配+解析，保证可播放）
        const fallbackInfo = await this.getMusicInfoWithFallback(
          fullSong.songmid, fullSong.source, quality, fullSong)
        if (fallbackInfo) {
          fallbackInfo.name = fullSong.name
          fallbackInfo.singer = fullSong.singer
          fallbackInfo.imgUrl = fullSong.imgUrl || fallbackInfo.imgUrl
          return fallbackInfo
        }
        return null
      }
      LogUtils.info(`[手动换源] 匹配: ${match.item.name} - ${match.item.singer} (${searchSource.info.name}, score=${match.score})`)

      // 指定解析源时：用解析源获取播放地址（lx-music 模式：搜索源找歌，解析源出 URL）
      let info: MusicItem | null = null
      let resolvedBySourceId: string | undefined = undefined
      if (parseSourceId && parseSourceId !== searchSourceId) {
        const parseSource = this.getEnabledSources().find(s => s.info.id === parseSourceId)
        if (parseSource) {
          if (this.sourceSupports(parseSource, match.item.source)) {
            try {
              info = await this.withTimeout(
                parseSource.getMusicInfo(match.item.songmid, quality, match.item),
                8000, `手动解析 ${parseSource.info.name}`
              )
              if (info) resolvedBySourceId = parseSource.info.id
            } catch (err) {
              LogUtils.warn(`[手动换源] 解析源 ${parseSource.info.name} 获取URL失败`, JSON.stringify(err))
            }
          } else {
            LogUtils.info(`[手动换源] 解析源 ${parseSource.info.name} 不支持解析 ${match.item.source}，跳过`)
          }
        }
      }
      // 未指定解析源或解析源失败：回退搜索源自身
      if (!info) {
        try {
          info = await this.withTimeout(
            searchSource.getMusicInfo(match.item.songmid, quality, match.item),
            5000, `手动换源URL ${searchSource.info.name}`
          )
        } catch (err) {
          LogUtils.warn(`[手动换源] 搜索源 ${searchSource.info.name} 获取URL失败`, JSON.stringify(err))
        }
      }
      // 全部手动解析失败：自动换源兜底（在全部启用源中重试，保证可播放）
      if (!info) {
        LogUtils.info('[手动换源] 手动解析失败，尝试自动换源兜底')
        const fallbackInfo = await this.getMusicInfoWithFallback(
          match.item.songmid, match.item.source, quality, match.item)
        if (fallbackInfo) {
          fallbackInfo.name = fullSong.name
          fallbackInfo.singer = fullSong.singer
          fallbackInfo.imgUrl = fullSong.imgUrl || fallbackInfo.imgUrl
          return fallbackInfo
        }
      }
      if (info) {
        info.name = fullSong.name
        info.singer = fullSong.singer
        info.imgUrl = fullSong.imgUrl || info.imgUrl
        const originalCacheKey = `${fullSong.source}_${fullSong.songmid}`
        this.saveToggleInfo(originalCacheKey, fullSong, {
          songmid: match.item.songmid,
          source: match.item.source,
          sourceId: resolvedBySourceId,
          name: match.item.name,
          singer: match.item.singer
        })
        return info
      }
    } catch (err) {
      LogUtils.warn(`[手动换源] ${searchSourceId} 失败`, JSON.stringify(err))
    }
    return null
  }

  /** 聚合搜索：严格模式只搜索内置平台；扩展模式可追加支持 search 的活动 JS 源。 */
  async searchAll(
    query: string,
    page: number = 1,
    quality: MusicQuality = MusicQuality.HIGH
  ): Promise<SearchResult[]> {
    const searchable = await this.getSearchSources()
    LogUtils.info(`聚合搜索: "${query}", ${searchable.length} 个可搜索音源`)

    const promises = searchable.map(source =>
      this.withTimeout(
        source.search(query, page, quality),
        this.isSearchSourceId(source.info.id) ? NATIVE_SEARCH_TIMEOUT_MS : JS_SEARCH_TIMEOUT_MS,
        `音源 ${source.info.name} 搜索`
      ).then((result: SearchResult) => {
        LogUtils.info(`音源 ${source.info.name} 返回 ${result.list.length} 条`)
        return result
      }).catch((err: Error) => {
        LogUtils.warn(`音源 ${source.info.name} 搜索失败`, JSON.stringify(err))
        return null
      })
    )

    const results = await Promise.all(promises)
    return results.filter(r => r !== null) as SearchResult[]
  }

  /** Promise 超时包装 */
  private async withTimeout<T>(promise: Promise<T>, timeoutMs: number, tag: string): Promise<T> {
    return new Promise<T>((resolve, reject) => {
      let settled = false
      const timer = setTimeout(() => {
        if (!settled) {
          settled = true
          LogUtils.warn(`${tag}超时(${timeoutMs}ms)，跳过`)
          reject(new Error('timeout'))
        }
      }, timeoutMs)
      promise.then((value: T) => {
        if (!settled) {
          settled = true
          clearTimeout(timer)
          resolve(value)
        }
      }).catch((err: Error) => {
        if (!settled) {
          settled = true
          clearTimeout(timer)
          reject(err)
        }
      })
    })
  }

  /** 获取播放信息（优先toggleMusicInfo → 缓存 → 原源 → 换源搜索） */
  async getMusicInfoWithFallback(
    songmid: string,
    sourceType: SourceType,
    quality: MusicQuality = MusicQuality.HIGH,
    fullSong?: MusicItem,
    isRefresh: boolean = false,
    onToggleSource?: (text: string) => void
  ): Promise<MusicItem | null> {
    const cacheKey = `${sourceType}_${songmid}`

    // 1. 非刷新时，优先使用 toggleMusicInfo（内存对象或持久化映射）
    let toggle: ToggleMusicInfo | null = fullSong?.toggleMusicInfo ?? null
    if (!toggle && !isRefresh) {
      const savedToggle = this.toggleMusicMap.get(cacheKey)
      if (savedToggle) {
        toggle = savedToggle
        LogUtils.info(`[播放] 持久化toggleMusicInfo命中: source=${toggle.source}, songmid=${toggle.songmid}`)
      }
    }
    if (!isRefresh && toggle) {
      const toggleInfo = toggle
      // 旧数据曾把“解析源类型”写进 source；有 sourceId 时按原歌曲平台兼容迁移。
      const togglePlatform = toggleInfo.source === SourceType.CUSTOM ? sourceType : toggleInfo.source
      // 没有自定义解析源且仍指向原平台原 ID 的 toggle 没有任何换源意义，直接清理。
      if (!toggleInfo.sourceId && togglePlatform === sourceType && toggleInfo.songmid === songmid) {
        LogUtils.warn(`[播放] 无效 toggle（仍为原平台原歌曲），清除: ${cacheKey}`)
        this.clearToggleInfo(cacheKey, fullSong)
      } else {
        LogUtils.info(`[播放] toggleMusicInfo存在，优先使用: platform=${togglePlatform}, parser=${toggleInfo.sourceId ?? 'native'}, songmid=${toggleInfo.songmid}`)
        try {
          const toggleSource = this.getEnabledSources().find(s =>
            toggleInfo.sourceId ? s.info.id === toggleInfo.sourceId : s.info.type === togglePlatform)
          if (toggleSource) {
            // 解析源需要真实平台与替代平台 songmid，不能继续传入原歌曲的平台信息。
            const toggleSong: MusicItem = {
              songmid: toggleInfo.songmid,
              name: toggleInfo.name || fullSong?.name || '',
              singer: toggleInfo.singer || fullSong?.singer || '',
              albumName: fullSong?.albumName ?? '',
              interval: fullSong?.interval ?? 0,
              imgUrl: fullSong?.imgUrl ?? '',
              lyricUrl: fullSong?.lyricUrl ?? '',
              source: togglePlatform,
              types: {}
            }
            const result = await toggleSource.getMusicInfo(toggleInfo.songmid, quality, toggleSong)
            if (result) {
              result.name = fullSong?.name ?? result.name
              result.singer = fullSong?.singer ?? result.singer
              result.imgUrl = fullSong?.imgUrl || result.imgUrl
              if (toggleInfo.source !== togglePlatform) {
                this.saveToggleInfo(cacheKey, fullSong, {
                  songmid: toggleInfo.songmid,
                  source: togglePlatform,
                  sourceId: toggleInfo.sourceId,
                  name: toggleInfo.name,
                  singer: toggleInfo.singer
                })
              }
              this.cachePlayUrl(cacheKey, result)
              return result
            }
          }
        } catch (err) {
          LogUtils.warn(`[播放] toggleMusicInfo获取失败，回退到原源`, JSON.stringify(err))
        }
        // toggle 源失败：删除持久化映射（含 fullSong 上的），避免下次仍命中同一个坏源
        this.clearToggleInfo(cacheKey, fullSong)
        LogUtils.info(`[播放] 已清除失效的toggleMusicInfo: ${cacheKey}`)
      }
    }

    // 2. 非刷新时，检查URL缓存（30分钟TTL + https校验，避免命中过期/明文URL）
    if (!isRefresh) {
      const cached = this.playUrlCache.get(cacheKey)
      if (cached) {
        const cachedTs = this.playUrlCacheTs.get(cacheKey) ?? 0
        const cachedUrl = Object.keys(cached.types).length > 0 ? cached.types[Object.keys(cached.types)[0]]?.url : ''
        const urlExpired = Date.now() - cachedTs > PLAY_URL_CACHE_TTL
        const urlHttp = cachedUrl ? cachedUrl.startsWith('http://') : false
        if (urlExpired || urlHttp) {
          // 过期或明文URL：清除并重新获取
          this.playUrlCache.delete(cacheKey)
          this.playUrlCacheTs.delete(cacheKey)
          LogUtils.info(`[播放] URL缓存失效(expired=${urlExpired}, http=${urlHttp})，重新获取: ${cacheKey}`)
        } else {
          LogUtils.info(`[播放] URL缓存命中: ${cacheKey}`)
          return cached
        }
      }
    }

    // 2.5 解析源优先模式（对齐参考 api-source 分层：用户 JS 源可接管平台解析，如 VIP 歌换源）
    // 默认开启：已启用的用户解析源先接管播放 URL，失败后再回退内置源。
    const enabled = this.getEnabledSources()
    if (fullSong && this.parseSourceFirst) {
      const parseFirst = await this.tryParseSources(enabled, sourceType, songmid, quality, fullSong, cacheKey, onToggleSource)
      if (parseFirst) return parseFirst
    }

    // 3. 原源获取（失败后内部重试1次，参考lx-music getMusicPlayUrl）
    // 主源失败标记：5 分钟内跳过原源（播放出错后避免再次踩到无效地址），直接走解析源/换源
    const primaryFailTs = this.primaryFailCache.get(cacheKey) ?? 0
    const skipPrimary = Date.now() - primaryFailTs < 5 * 60 * 1000
    const primary = skipPrimary ? undefined : enabled.find(s => s.info.type === sourceType)
    if (primary) {
      for (let attempt = 0; attempt < 2; attempt++) {
        try {
          const result = await primary.getMusicInfo(songmid, quality, fullSong)
          if (result) {
            this.cachePlayUrl(cacheKey, result)
            return result
          }
          LogUtils.warn(`主音源返回空(第${attempt + 1}次)，${attempt === 0 ? '重试1次' : '尝试换源'}`)
        } catch (err) {
          LogUtils.warn(`主音源获取失败(第${attempt + 1}次)，${attempt === 0 ? '重试1次' : '尝试换源'}`, JSON.stringify(err))
        }
      }
    }

    // 3.5 解析源直接解析（lx-music 核心：JS 解析源按原歌信息(musicInfo)直接解析，无需搜索）
    // 注意：仅限用户导入的 JS 源；内置源 getMusicInfo 依赖本平台 songmid，跨源调用会返回错误歌曲，必须走换源搜索
    if (fullSong && !this.parseSourceFirst) {
      const parseInfo = await this.tryParseSources(enabled, sourceType, songmid, quality, fullSong, cacheKey, onToggleSource)
      if (parseInfo) return parseInfo
    }

    // 4. 换源搜索（单轮：组合词查询，每源内已做"组合词无匹配→纯歌名"兜底）
    // 对齐参考 lx-music：换源失败不缓存，播放重试时立即重新尝试（服务恢复后可及时生效）
    if (fullSong && fullSong.name) {
      const searchSources = enabled.filter(s => s.info.type !== sourceType && this.isSearchSourceId(s.info.id))
      const otherSources = enabled.filter(s => s.info.type !== sourceType && !this.isSearchSourceId(s.info.id))
      // lx-music 语义：按音源优先级排序（数字越小越靠前）
      const orderedSources = [...searchSources, ...otherSources].sort((a, b) => a.priority - b.priority)

      const query = fullSong.singer ? `${fullSong.name} ${fullSong.singer}` : fullSong.name
      if (onToggleSource) {
        onToggleSource('正在换源搜索可播放版本...')
      }
      const fallbackInfo = await this.tryFallbackRound(
        fullSong, query, quality, enabled, orderedSources, cacheKey, 0
      )
      if (fallbackInfo) {
        return fallbackInfo
      }

      LogUtils.info('[换源] 所有源均未匹配或获取URL失败')
    }

    return null
  }

  /** 执行一轮换源搜索：并发搜索、按匹配质量排序，再由活动解析源优先获取 URL。 */
  private async tryFallbackRound(
    fullSong: MusicItem,
    query: string,
    quality: MusicQuality,
    enabled: SourceInstance[],
    orderedSources: SourceInstance[],
    cacheKey: string,
    round: number
  ): Promise<MusicItem | null> {
    // 原源已在 getMusicInfoWithFallback 步骤 3 失败过（重试 2 次），换源轮询直接跳过
    const ordered: SourceInstance[] = orderedSources
    LogUtils.info(`[换源] 第${round}轮: 并发搜索 ${ordered.map(s => s.info.name).join(', ')}`)

    // 阶段1：并发组合词搜索匹配（慢源不阻塞整体）
    let results: Array<MatchResult | null> = await Promise.all(
      ordered.map((source: SourceInstance) =>
        this.searchAndMatch(source, fullSong, query, quality).catch((): MatchResult | null => null))
    )
    // 阶段2：组合词无匹配的源，并发纯歌名搜索匹配
    const needRetry: number[] = []
    for (let i = 0; i < results.length; i++) {
      if (!results[i]) needRetry.push(i)
    }
    if (needRetry.length > 0) {
      const retryResults = await Promise.all(
        needRetry.map((idx: number) =>
          this.searchAndMatch(ordered[idx], fullSong, fullSong.name, quality).catch((): MatchResult | null => null))
      )
      for (let i = 0; i < needRetry.length; i++) {
        if (retryResults[i]) results[needRetry[i]] = retryResults[i]
      }
    }

    // 对齐 LX findMusic：先按匹配质量排序，同分时再按音源优先级排序。
    const matchedIndexes: number[] = []
    for (let i = 0; i < results.length; i++) {
      if (results[i]) matchedIndexes.push(i)
    }
    matchedIndexes.sort((left: number, right: number) => {
      const leftScore = results[left]?.score ?? 0
      const rightScore = results[right]?.score ?? 0
      if (leftScore !== rightScore) return rightScore - leftScore
      return ordered[left].priority - ordered[right].priority
    })

    // 每个匹配先交给活动 JS 解析源；失败后才回退该平台的内置 URL 接口。
    for (const i of matchedIndexes) {
      const match = results[i]
      if (!match) continue
      const source = ordered[i]
      LogUtils.info(`[换源] ${source.info.name} 匹配(层级${match.score}): ${match.item.name} - ${match.item.singer}`)

      const parsedInfo = await this.tryParseSources(
        enabled, match.item.source, match.item.songmid, quality, match.item, cacheKey, undefined, fullSong
      )
      if (parsedInfo) {
        LogUtils.info(`[换源] 匹配结果已由活动解析源处理: platform=${match.item.source}`)
        return parsedInfo
      }

      // 自定义搜索源已经在上一步作为解析候选尝试过，避免重复调用同一个失效接口。
      if (!source.isNative) continue
      try {
        const info = await this.withTimeout(
          source.getMusicInfo(match.item.songmid, quality, match.item),
          5000, `换源URL ${source.info.name}`
        )
        if (info) {
          info.name = fullSong.name
          info.singer = fullSong.singer
          info.imgUrl = fullSong.imgUrl || info.imgUrl
          // 保存替代平台，下次播放同歌时直接用该平台歌曲重新取 URL。
          this.saveToggleInfo(cacheKey, fullSong, {
            songmid: match.item.songmid,
            source: match.item.source,
            name: match.item.name,
            singer: match.item.singer
          })
          LogUtils.info(`[换源] 保存toggleMusicInfo: source=${match.item.source}, songmid=${match.item.songmid}`)
          this.cachePlayUrl(cacheKey, info)
          return info
        }
      } catch (err) {
        LogUtils.warn(`[换源] ${source.info.name} 获取URL失败`, JSON.stringify(err))
        continue
      }
    }

    return null
  }

  /** 判断音源是否支持解析指定源的歌曲（lx-music sources 声明；未声明=不限） */
  private sourceSupports(source: SourceInstance, songSource: SourceType): boolean {
    const supported = source.getSupportedSources()
    if (supported.length === 0) return true
    return supported.indexOf(String(songSource)) >= 0
  }

  /**
   * 尝试用用户解析源直接解析（对齐参考 api-source 分层：JS 解析源按原歌信息 musicInfo 直接解析）
   * 仅限用户导入的 JS 源；内置源 getMusicInfo 依赖本平台 songmid，跨源调用会返回错误歌曲
   * 失败源进入 30 秒冷却：避免音质降级/整体重试时反复请求失效或受限服务（触发"禁止批量下载"等防滥用限制）
   * @returns 解析成功返回带播放地址的歌曲信息，全部失败返回 null
   */
  private async tryParseSources(
    enabled: SourceInstance[],
    sourceType: SourceType,
    songmid: string,
    quality: MusicQuality,
    fullSong: MusicItem,
    cacheKey: string,
    onToggleSource?: (text: string) => void,
    toggleTarget?: MusicItem
  ): Promise<MusicItem | null> {
    const now = Date.now()
    const displaySong = toggleTarget ?? fullSong
    const parseCandidates = enabled.filter(s =>
      !s.isNative && s.info.type !== sourceType && this.sourceSupports(s, sourceType))
      .sort((a, b) => a.priority - b.priority)
    for (const parseSource of parseCandidates) {
      const cooldownKey = `${parseSource.info.id}_${sourceType}_${quality}`
      // 冷却中的源跳过（上次失败后 30 秒内不再请求，减少无效请求量与服务端限流）
      const cooldownTs = this.parseSourceCooldown.get(cooldownKey) ?? 0
      if (now < cooldownTs) {
        LogUtils.info(`[解析] ${parseSource.info.name} 冷却中(剩余${Math.ceil((cooldownTs - now) / 1000)}s)，跳过`)
        continue
      }
      if (onToggleSource) {
        onToggleSource(`正在用 ${parseSource.info.name} 解析播放地址...`)
      }
      try {
        const result = await this.withTimeout(
          parseSource.getMusicInfo(songmid, quality, fullSong),
          8000, `解析源 ${parseSource.info.name}`
        )
        if (result && Object.keys(result.types).length > 0 &&
          result.types[Object.keys(result.types)[0]]?.url) {
          result.name = displaySong.name
          result.singer = displaySong.singer
          result.imgUrl = displaySong.imgUrl || result.imgUrl
          // source 保存真实歌曲平台，sourceId 保存实际提供 URL 的用户解析源。
          this.saveToggleInfo(cacheKey, displaySong, {
            songmid: songmid,
            source: sourceType,
            sourceId: parseSource.info.id,
            name: fullSong.name ?? '',
            singer: fullSong.singer ?? ''
          })
          this.cachePlayUrl(cacheKey, result)
          LogUtils.info(`[解析] ${parseSource.info.name} 直接解析成功`)
          return result
        }
        LogUtils.warn(`[解析] ${parseSource.info.name} 返回空地址`)
        this.parseSourceCooldown.set(cooldownKey, Date.now() + 30000)
      } catch (err) {
        LogUtils.warn(`[解析] ${parseSource.info.name} 解析失败`, JSON.stringify(err))
        this.parseSourceCooldown.set(cooldownKey, Date.now() + 30000)
      }
    }
    return null
  }

  /** 保存换源映射：source 是歌曲真实平台，sourceId 是可选的用户解析源。 */
  private saveToggleInfo(cacheKey: string, targetSong: MusicItem | undefined, info: ToggleMusicInfo): void {
    if (targetSong) targetSong.toggleMusicInfo = info
    this.toggleMusicMap.set(cacheKey, info)
    const snapshot: Record<string, ToggleMusicInfo> = {}
    this.toggleMusicMap.forEach((item: ToggleMusicInfo, key: string) => {
      snapshot[key] = item
    })
    StorageUtils.putObject(CACHE_KEY_TOGGLE_MAP, snapshot).catch(() => {})
  }

  /** 清除失效换源映射，避免后续播放重复命中同一坏地址。 */
  private clearToggleInfo(cacheKey: string, targetSong?: MusicItem): void {
    this.toggleMusicMap.delete(cacheKey)
    if (targetSong) targetSong.toggleMusicInfo = undefined
    const snapshot: Record<string, ToggleMusicInfo> = {}
    this.toggleMusicMap.forEach((item: ToggleMusicInfo, key: string) => {
      snapshot[key] = item
    })
    StorageUtils.putObject(CACHE_KEY_TOGGLE_MAP, snapshot).catch(() => {})
  }

  /** 单源搜索+分层匹配（带缓存；无匹配返回 null） */
  private async searchAndMatch(
    source: SourceInstance,
    fullSong: MusicItem,
    query: string,
    quality: MusicQuality
  ): Promise<MatchResult | null> {
    const result = await this.searchForFallback(source, fullSong, query, quality)
    if (!result || result.list.length === 0) return null
    const matches = this.findMusicMatches(fullSong, result.list)
    matches.sort((left: MatchResult, right: MatchResult) => right.score - left.score)
    return matches.length > 0 ? matches[0] : null
  }

  /** 单源换源搜索（带缓存 + 分级超时；失败返回 null，不抛出） */
  private async searchForFallback(
    source: SourceInstance,
    fullSong: MusicItem,
    query: string,
    quality: MusicQuality
  ): Promise<SearchResult | null> {
    try {
      // 换源与歌词兜底同样遵守搜索模式：严格 LX 模式绝不调用自定义源的 search。
      if (source instanceof JSScriptSource) {
        if (!this.extendedSearchEnabled || !await source.supportsSearch()) return null
      }
      // 缓存 key 包含查询词：不同查询词的搜索结果不同，避免两轮换源查询相互污染
      const cacheKeySearch = `${source.info.type}_${fullSong.songmid}_${query}`
      const cachedSearch = this.otherSourceCache.get(cacheKeySearch)
      if (cachedSearch && Date.now() - cachedSearch.timestamp < 120000) {
        LogUtils.info(`[换源] 搜索缓存命中: ${source.info.name}`)
        return { list: cachedSearch.list, total: cachedSearch.list.length, limit: 25, page: 1, source: source.info.type }
      }
      LogUtils.info(`[换源] 在 ${source.info.name} 搜索: "${query}"`)
      // 内置搜索源（kg/wy/tx）给 8 秒，JS 音源给 2.5 秒，避免慢源阻塞整体换源
      const timeoutMs = this.isSearchSourceId(source.info.id) ? 8000 : 2500
      const result = await this.withTimeout(
        source.search(query, 1, quality), timeoutMs, `换源 ${source.info.name} 搜索`
      )
      if (result.list.length > 0) {
        this.cacheOtherSourceResult(cacheKeySearch, result.list)
      }
      return result
    } catch (err) {
      LogUtils.warn(`[换源] ${source.info.name} 失败`, JSON.stringify(err))
      return null
    }
  }

  /** 清除指定歌曲的URL缓存（刷新URL时调用） */
  clearPlayUrlCache(songmid: string, sourceType: SourceType): void {
    const cacheKey = `${sourceType}_${songmid}`
    this.playUrlCache.delete(cacheKey)
    this.playUrlCacheTs.delete(cacheKey)
    LogUtils.info(`[缓存] 清除URL缓存: ${cacheKey}`)
  }

  /** 标记主源失败（播放出错后调用）：5 分钟内跳过原源，直接走解析源/换源 */
  markPrimaryFailed(songmid: string, sourceType: SourceType): void {
    const cacheKey = `${sourceType}_${songmid}`
    this.primaryFailCache.set(cacheKey, Date.now())
    LogUtils.info(`[缓存] 标记主源失败: ${cacheKey}`)
  }

  /** 估算当前缓存占用大小（字节）：内存缓存 + Storage 持久化缓存 */
  async getCacheSize(): Promise<number> {
    let total = 0
    // 内存缓存（按字符串近似估算）
    for (const key of this.playUrlCache.keys()) {
      total += key.length * 2
    }
    for (const key of this.lyricCache.keys()) {
      const entry = this.lyricCache.get(key)
      if (entry && entry.lines) {
        for (const line of entry.lines) {
          total += (line.text.length + (line.transText ? line.transText.length : 0)) * 2
        }
      }
    }
    for (const key of this.otherSourceCache.keys()) {
      const entry = this.otherSourceCache.get(key)
      if (entry && entry.list) {
        for (const item of entry.list) {
          total += (item.name.length + item.singer.length) * 2
        }
      }
    }
    // Storage 持久化缓存（歌词 + 换源映射）
    const lyricStr = await StorageUtils.getString(CACHE_KEY_LYRIC, '')
    total += lyricStr.length * 2
    const toggleStr = await StorageUtils.getString(CACHE_KEY_TOGGLE_MAP, '')
    total += toggleStr.length * 2
    return total
  }

  /** 清理全部缓存（内存 + Storage），返回是否成功 */
  async clearAllCaches(): Promise<boolean> {
    try {
      // 内存缓存
      this.playUrlCache.clear()
      this.playUrlCacheTs.clear()
      this.lyricCache.clear()
      this.otherSourceCache.clear()
      this.toggleMusicMap.clear()
      // Storage 持久化缓存
      await StorageUtils.delete(CACHE_KEY_LYRIC)
      await StorageUtils.delete(CACHE_KEY_TOGGLE_MAP)
      LogUtils.info('[缓存] 全部缓存已清理')
      return true
    } catch (err) {
      LogUtils.error('[缓存] 清理失败', JSON.stringify(err))
      return false
    }
  }

  /** 缓存播放URL */
  private cachePlayUrl(key: string, info: MusicItem): void {
    if (this.playUrlCache.size >= CACHE_MAX_SIZE) {
      const iter = this.playUrlCache.keys()
      const firstEntry = iter.next()
      if (!firstEntry.done && firstEntry.value !== undefined) {
        this.playUrlCache.delete(firstEntry.value as string)
        this.playUrlCacheTs.delete(firstEntry.value as string)
      }
    }
    this.playUrlCache.set(key, info)
    this.playUrlCacheTs.set(key, Date.now())
  }

  /** 缓存换源搜索结果 */
  private cacheOtherSourceResult(key: string, list: MusicItem[]): void {
    if (this.otherSourceCache.size >= OTHER_SOURCE_CACHE_MAX) {
      // 清空全部（与lx-music一致）
      this.otherSourceCache.clear()
    }
    this.otherSourceCache.set(key, { list, timestamp: Date.now() })
  }

  /** 缓存歌词（内存 + 持久化，最多100条，7天TTL） */
  private cacheLyric(key: string, lines: LyricLine[]): void {
    if (this.lyricCache.size >= LYRIC_CACHE_MAX) {
      const iter = this.lyricCache.keys()
      const firstEntry = iter.next()
      if (!firstEntry.done && firstEntry.value !== undefined) {
        this.lyricCache.delete(firstEntry.value as string)
      }
    }
    this.lyricCache.set(key, { lines, timestamp: Date.now() })
    // 异步持久化（不阻塞播放流程）
    const snapshot: Record<string, LyricCacheEntry> = {}
    this.lyricCache.forEach((entry, k) => {
      snapshot[k] = entry
    })
    StorageUtils.putObject(CACHE_KEY_LYRIC, snapshot).catch(() => {})
  }

  /**
   * 多轮匹配算法（参考lx-music findMusic）
   *
   * 第1轮: 歌名完全匹配 AND 歌手包含匹配 AND 时长差<5秒
   * 第2轮: 歌手完全匹配 AND 歌名包含匹配
   * 第3轮: 专辑完全匹配 AND 歌手包含匹配 AND 歌名包含匹配
   *
   * 匹配结果按优先级排序:
   * 1. 歌名== AND 歌手== AND 时长==
   * 2. 歌名== AND 歌手== AND 专辑==
   * 3. 歌名== AND 歌手==
   * 4. 歌名== AND 时长==
   * 5. 歌手== AND 时长==
   * 6. 时长==
   * 7. 歌名==
   * 8. 歌手==
   * 9. 专辑==
   */
  private findMusicMatches(target: MusicItem, list: MusicItem[]): MatchResult[] {
    const targetName = this.normalizeName(target.name)
    if (!targetName) return []
    const targetSinger = this.normalizeSinger(target.singer)
    const targetSingerParts = targetSinger.split(/[、,，\s]+/).filter((s: string) => s.length > 0)
    const targetAlbum = this.normalizeName(target.albumName)
    const targetDuration = target.interval > 0 ? target.interval : 0
    const DURATION_THRESHOLD = 5 // 时长匹配阈值（秒）

    const results: MatchResult[] = []

    for (const item of list) {
      const itemName = this.normalizeName(item.name)
      const itemSinger = this.normalizeSinger(item.singer)
      const itemSingerParts = itemSinger.split(/[、,，\s]+/).filter((s: string) => s.length > 0)
      const itemAlbum = this.normalizeName(item.albumName)
      const itemDuration = item.interval > 0 ? item.interval : 0

      const nameExact = itemName === targetName
      const nameContains = nameExact || itemName.includes(targetName) || targetName.includes(itemName)
      const singerExact = itemSinger === targetSinger
      const singerContains = targetSingerParts.length === 0 || singerExact ||
        this.singerPartsOverlap(targetSingerParts, itemSingerParts)
      const durationMatch = targetDuration > 0 && itemDuration > 0 &&
        Math.abs(itemDuration - targetDuration) < DURATION_THRESHOLD
      // LX 在进入三轮匹配前先过滤明显不同时长；任一侧缺少时长时保持兼容。
      const durationCompatible = targetDuration === 0 || itemDuration === 0 || durationMatch
      const albumExact = targetAlbum.length > 0 && itemAlbum.length > 0 && itemAlbum === targetAlbum
      const albumContains = albumExact || (targetAlbum.length > 0 && itemAlbum.length > 0 &&
        (itemAlbum.includes(targetAlbum) || targetAlbum.includes(itemAlbum)))

      if (!durationCompatible) continue

      // 第1轮: 歌名完全 AND 歌手包含（前置已校验时长）
      if (nameExact && singerContains) {
        results.push({ item, score: this.calcMatchScore(nameExact, singerExact, durationMatch, albumExact, albumContains, nameContains, singerContains) })
        continue
      }

      // 第2轮: 歌手完全 AND 歌名包含
      if (singerExact && nameContains) {
        results.push({ item, score: this.calcMatchScore(nameExact, singerExact, durationMatch, albumExact, albumContains, nameContains, singerContains) })
        continue
      }

      // 第3轮: 专辑完全 AND 歌手包含 AND 歌名包含
      if (albumExact && singerContains && nameContains) {
        results.push({ item, score: this.calcMatchScore(nameExact, singerExact, durationMatch, albumExact, albumContains, nameContains, singerContains) })
        continue
      }
    }

    return results
  }

  /** 计算匹配优先级分数（分数越高优先级越高） */
  private calcMatchScore(
    nameExact: boolean, singerExact: boolean, durationMatch: boolean,
    albumExact: boolean, albumContains: boolean,
    nameContains: boolean, singerContains: boolean
  ): number {
    // 优先级1: 歌名== AND 歌手== AND 时长==
    if (nameExact && singerExact && durationMatch) return 1000
    // 优先级2: 歌名== AND 歌手== AND 专辑==
    if (nameExact && singerExact && albumExact) return 900
    // 优先级3: 歌名== AND 歌手==
    if (nameExact && singerExact) return 800
    // 优先级4: 歌名== AND 时长==
    if (nameExact && durationMatch) return 700
    // 优先级5: 歌手== AND 时长==
    if (singerExact && durationMatch) return 600
    // 优先级6: 时长==
    if (durationMatch) return 500
    // 优先级7: 歌名==
    if (nameExact) return 400
    // 优先级8: 歌手==
    if (singerExact) return 300
    // 优先级9: 专辑==
    if (albumExact) return 200
    // 歌名包含 + 歌手包含
    if (nameContains && singerContains) return 150
    // 歌名包含
    if (nameContains) return 100
    // 歌手包含
    if (singerContains) return 50
    // 专辑包含
    if (albumContains) return 10
    return 0
  }

  /** 歌手名标准化：全角转半角、分隔符统一→按字母排序→用"、"连接 */
  private normalizeSinger(singer: string): string {
    const parts = this.toHalfWidth(singer).trim().split(/[、/&/;/；//|/,，\s]+/).filter((s: string) => s.length > 0)
    parts.sort()
    return parts.join('、').toLowerCase()
  }

  /** 歌名/专辑名标准化：全角转半角、去除特殊字符 */
  private normalizeName(name: string): string {
    return this.toHalfWidth(name).trim().replace(/[\s'""'',，.。!！?？·・\-—–()（）\[\]【】]/g, '').toLowerCase()
  }

  /** 全角字符转半角（全角空格/字母/数字/标点） */
  private toHalfWidth(text: string): string {
    let result = ''
    for (let i = 0; i < text.length; i++) {
      const code = text.charCodeAt(i)
      if (code === 0x3000) {
        result += ' '
      } else if (code >= 0xff01 && code <= 0xff5e) {
        result += String.fromCharCode(code - 0xfee0)
      } else {
        result += text.charAt(i)
      }
    }
    return result
  }

  /**
   * 分层匹配（模糊匹配，不区分全角半角）：
   * 先"歌名+歌手"，失败后"仅歌名"；score: 2=歌名+歌手, 1=仅歌名
   */
  private matchInSource(target: MusicItem, list: MusicItem[]): MatchResult | null {
    const targetName = this.normalizeName(target.name)
    const targetSingerParts = this.normalizeSinger(target.singer).split(/[、,，\s]+/).filter((s: string) => s.length > 0)
    if (!targetName) return null

    // 第1层：歌名匹配 AND 歌手匹配
    for (const item of list) {
      const itemName = this.normalizeName(item.name)
      if (itemName.length > 0 && this.nameMatch(targetName, itemName) &&
        this.singerMatch(targetSingerParts, this.normalizeSinger(item.singer))) {
        return { item, score: 2 }
      }
    }
    // 第2层：仅歌名匹配
    for (const item of list) {
      const itemName = this.normalizeName(item.name)
      if (itemName.length > 0 && this.nameMatch(targetName, itemName)) {
        return { item, score: 1 }
      }
    }
    return null
  }

  /** 歌名模糊匹配：相等或互相包含 */
  private nameMatch(target: string, item: string): boolean {
    return target === item || item.includes(target) || target.includes(item)
  }

  /** 歌手模糊匹配：任一分隔部分相等或互相包含 */
  private singerMatch(targetParts: string[], itemSinger: string): boolean {
    if (targetParts.length === 0) return true
    const itemParts = itemSinger.split(/[、,，\s]+/).filter((s: string) => s.length > 0)
    if (itemParts.length === 0) return false
    for (const t of targetParts) {
      for (const i of itemParts) {
        if (t === i || i.includes(t) || t.includes(i)) return true
      }
    }
    return false
  }

  /** 两个歌手列表是否有重叠部分 */
  private singerPartsOverlap(partsA: string[], partsB: string[]): boolean {
    for (const a of partsA) {
      for (const b of partsB) {
        if (a === b || a.includes(b) || b.includes(a)) return true
      }
    }
    return false
  }

  /** 获取歌词（带缓存 + 换源：原始源失败后，在其他源搜索+获取歌词） */
  async getLyricWithFallback(songmid: string, sourceId: string, fullSong?: MusicItem): Promise<LyricLine[]> {
    const lyricKey = `${sourceId}_${songmid}`

    // 1. 查歌词缓存
    const cached = this.lyricCache.get(lyricKey)
    if (cached && Date.now() - cached.timestamp < LYRIC_CACHE_TTL) {
      LogUtils.info(`[歌词] 缓存命中: ${lyricKey} (${cached.lines.length} 行)`)
      return cached.lines
    }

    const source = this.getSourceById(sourceId)
    if (source) {
      try {
        const result = await source.getLyric(songmid, fullSong)
        if (result.length > 0) {
          LogUtils.info(`[歌词] ${source.info.name} 获取成功: ${result.length} 行`)
          this.cacheLyric(lyricKey, result)
          return result
        }
        LogUtils.info(`[歌词] ${source.info.name} 返回空，尝试换源`)
      } catch (err) {
        LogUtils.warn(`[歌词] ${source.info.name} 获取失败，尝试换源`, JSON.stringify(err))
      }
    }

    if (!fullSong || !fullSong.name) {
      LogUtils.info('[歌词] 无歌曲名信息，无法换源')
      return []
    }

    const query = fullSong.singer ? `${fullSong.name} ${fullSong.singer}` : fullSong.name
    const enabled = this.getEnabledSources()
    const searchSources = enabled.filter(s => s.info.id !== sourceId && this.isSearchSourceId(s.info.id))
    const otherSources = enabled.filter(s => s.info.id !== sourceId && !this.isSearchSourceId(s.info.id))
    const orderedSources = [...searchSources, ...otherSources]

    // 两轮查询：组合词 → 纯歌名（与播放换源一致）
    const queries: string[] = []
    if (fullSong.singer) {
      queries.push(query)
    }
    queries.push(fullSong.name)

    for (const q of queries) {
      // 并发搜索所有源（参考 lx-music searchMusic: Promise.all + catch(null)，慢源不阻塞其他源）
      const searchTasks: Promise<SearchResult | null>[] = orderedSources.map((fallbackSource: SourceInstance) => {
        return this.searchForFallback(fallbackSource, fullSong, q, MusicQuality.HIGH)
      })
      const searchResults = await Promise.all(searchTasks)

      // 收集所有搜索结果，分层匹配（歌名+歌手 → 仅歌名，模糊/全角半角不敏感）
      const allMatched: MatchResult[] = []
      for (const searchResult of searchResults) {
        if (searchResult && searchResult.list.length > 0) {
          const match = this.matchInSource(fullSong, searchResult.list)
          if (match) allMatched.push(match)
        }
      }

      // 按优先级排序，逐个尝试获取歌词
      allMatched.sort((a, b) => b.score - a.score)
      for (const match of allMatched) {
        try {
          const matchSource = this.getSourceById(String(match.item.source))
          if (!matchSource) continue
          LogUtils.info(`[歌词换源] 尝试: ${match.item.name} - ${match.item.singer} (source=${match.item.source}, score=${match.score})`)
          const lyrics = await this.withTimeout(
            matchSource.getLyric(match.item.songmid, match.item),
            5000, `歌词换源 ${match.item.source}`
          )
          if (lyrics.length > 0) {
            LogUtils.info(`[歌词换源] 获取成功: ${lyrics.length} 行`)
            this.cacheLyric(lyricKey, lyrics)
            return lyrics
          }
        } catch (err) {
          LogUtils.warn(`[歌词换源] 获取失败`, JSON.stringify(err))
          continue
        }
      }
    }

    LogUtils.info('[歌词] 所有源均未获取到歌词')
    return []
  }

  /** 持久化音源列表（元信息 + 开关 + 优先级 + JS 音源脚本内容） */
  private async save(): Promise<void> {
    const savedList: SavedSource[] = []
    for (const s of this.sources) {
      const item: SavedSource = {
        info: s.info,
        enabled: s.enabled,
        priority: s.priority
      }
      savedList.push(item)
    }
    await StorageUtils.putObject(STORAGE_KEY_SOURCES, savedList)

    // 保存 JS 音源的脚本内容（用于重启后恢复）
    const scripts: Record<string, string> = {}
    for (const s of this.sources) {
      if (!s.isNative && s instanceof JSScriptSource) {
        const script = s.getScriptContent()
        if (script) {
          scripts[s.info.id] = script
        }
      }
    }
    await StorageUtils.putObject(STORAGE_KEY_SCRIPTS, scripts)

    // 用户解析源采用单选模型；独立保存活动源 ID，恢复时不再依赖历史 enabled 布尔值。
    const activeSource = this.sources.find(s =>
      s.enabled && !s.isNative && s instanceof JSScriptSource)
    await StorageUtils.putString(STORAGE_KEY_ACTIVE_JS_SOURCE, activeSource?.info.id ?? '')
  }
}
