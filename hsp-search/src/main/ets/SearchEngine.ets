import {
  MusicItem,
  SearchResult,
  SourceType,
  MusicQuality,
  HotSearchItem,
  LogUtils,
  StorageUtils
} from 'common'
import { SourceManager } from 'hsp_source'

const STORAGE_KEY_HISTORY = 'search_history'
const MAX_HISTORY = 50
const SEARCH_CACHE_MAX = 20
const SEARCH_CACHE_TTL = 3 * 60 * 1000
/** 热搜缓存 TTL（10 分钟） */
const HOT_SEARCH_TTL = 10 * 60 * 1000

/** 搜索缓存条目 */
interface SearchCacheEntry {
  items: MusicItem[]
  timestamp: number
}

/** 热搜缓存条目 */
interface HotSearchCacheEntry {
  items: HotSearchItem[]
  timestamp: number
  mode: string
}

/**
 * 聚合搜索引擎 — 小 Yuki 帮哥哥找歌喵~
 *
 * 核心逻辑：
 * 1. 并发请求所有启用音源
 * 2. 统一标准化格式
 * 3. 按（歌名 + 歌手）去重
 * 4. 合并不同音源的同一首歌（_types 字段）
 * 5. 按音源优先级排序展示
 */
export class SearchEngine {
  /** 搜索结果内存缓存（3分钟TTL，避免重复搜索相同关键词） */
  private static searchCache: Map<string, SearchCacheEntry> = new Map()
  /** 热搜缓存（内存，10分钟TTL） */
  private static hotSearchCache: HotSearchCacheEntry | null = null

  /**
   * 执行搜索
   * @param sourceId 指定搜索源 ID（'' = 全部启用源）
   */
  static async search(
    query: string,
    page: number = 1,
    quality: MusicQuality = MusicQuality.HIGH,
    sourceId: string = ''
  ): Promise<MusicItem[]> {
    if (!query.trim()) return []

    // 异步保存搜索历史（不阻塞搜索）
    SearchEngine.saveHistory(query)

    const sourceMgr = SourceManager.getInstance()
    // 严格/扩展模式必须隔离缓存，避免关闭扩展搜索后仍返回旧的自定义结果。
    const searchMode = sourceMgr.isExtendedSearchEnabled() ? 'ext' : 'lx'
    const cacheKey = `${searchMode}_${sourceId}_${page}_${query.trim()}`
    const cached = SearchEngine.searchCache.get(cacheKey)
    if (cached && Date.now() - cached.timestamp < SEARCH_CACHE_TTL) {
      LogUtils.info(`[搜索] 缓存命中: "${query}" (${cached.items.length} 首)`)
      return cached.items
    }

    let results: SearchResult[]
    if (sourceId) {
      // 指定源搜索（单选）
      const single = await sourceMgr.searchSourceById(sourceId, query, page, quality)
      results = single ? [single] : []
    } else {
      // 聚合搜索全部启用源
      results = await sourceMgr.searchAll(query, page, quality)
    }

    // 合并去重
    const merged = SearchEngine.mergeResults(results)
    LogUtils.info(`搜索完成: ${merged.length} 首去重结果`)

    const sorted = SearchEngine.sortBySourcePriority(merged)

    // 存入缓存
    if (SearchEngine.searchCache.size >= SEARCH_CACHE_MAX) {
      const iter = SearchEngine.searchCache.keys()
      const firstEntry = iter.next()
      if (!firstEntry.done && firstEntry.value !== undefined) {
        SearchEngine.searchCache.delete(firstEntry.value as string)
      }
    }
    SearchEngine.searchCache.set(cacheKey, { items: sorted, timestamp: Date.now() })

    return sorted
  }

  /**
   * 合并多个音源的结果
   * 每个源的每首歌独立保留（不做去重合并），确保 songmid + source 完整对应
   */
  private static mergeResults(results: SearchResult[]): MusicItem[] {
    const allItems: MusicItem[] = []

    for (const result of results) {
      for (const item of result.list) {
        // 按源+songmid去重（同一源内不重复）
        const dup = allItems.findIndex((existing: MusicItem) =>
          existing.songmid === item.songmid && existing.source === item.source
        )
        if (dup < 0) {
          const newTypes: Record<string, import('common').MusicQualityInfo> = {}
          const itemTypes = item.types
          const typeKeys = Object.keys(itemTypes)
          for (let k = 0; k < typeKeys.length; k++) {
            const key = typeKeys[k]
            newTypes[key] = itemTypes[key]
          }
          item._types = newTypes
          allItems.push(item)
        }
      }
    }

    return allItems
  }

  /** 按音源优先级排序（数字越小越靠前） */
  static sortBySourcePriority(items: MusicItem[]): MusicItem[] {
    const sourceMgr = SourceManager.getInstance()
    const enabled = sourceMgr.getEnabledSources()
    const priorityMap = new Map<SourceType, number>()
    enabled.forEach(s => priorityMap.set(s.info.type, s.priority))

    return items.sort((a, b) => {
      const pa = priorityMap.get(a.source) ?? 999
      const pb = priorityMap.get(b.source) ?? 999
      return pa - pb
    })
  }

  /** 获取搜索历史（最近搜索在前） */
  static async getHistory(): Promise<string[]> {
    return await StorageUtils.getObject<string[]>(STORAGE_KEY_HISTORY, [])
  }

  /** 保存搜索历史（去重 + 限制数量） */
  private static async saveHistory(keyword: string): Promise<void> {
    const history = await SearchEngine.getHistory()
    const filtered = history.filter(h => h !== keyword)
    filtered.unshift(keyword)
    await StorageUtils.putObject(STORAGE_KEY_HISTORY, filtered.slice(0, MAX_HISTORY))
  }

  /** 清除搜索历史 */
  static async clearHistory(): Promise<void> {
    await StorageUtils.delete(STORAGE_KEY_HISTORY)
  }

  /** 获取热搜榜（带内存缓存；启动时预加载后搜索页秒显） */
  static async getHotSearch(): Promise<HotSearchItem[]> {
    const sourceMgr = SourceManager.getInstance()
    const searchMode = sourceMgr.isExtendedSearchEnabled() ? 'ext' : 'lx'
    const cached = SearchEngine.hotSearchCache
    if (cached && cached.mode === searchMode && Date.now() - cached.timestamp < HOT_SEARCH_TTL) {
      return cached.items
    }
    const searchable = await sourceMgr.getSearchSources()
    const tasks: Promise<HotSearchItem[]>[] = searchable.map((source) => {
      return source.getHotSearch().catch((): HotSearchItem[] => [])
    })
    const results = await Promise.all(tasks)
    const seen = new Set<string>()
    const merged: HotSearchItem[] = []
    for (const list of results) {
      for (const item of list) {
        if (!seen.has(item.value)) {
          seen.add(item.value)
          merged.push(item)
        }
      }
    }
    const trimmed = merged.slice(0, 30)
    SearchEngine.hotSearchCache = { items: trimmed, timestamp: Date.now(), mode: searchMode }
    return trimmed
  }
}
