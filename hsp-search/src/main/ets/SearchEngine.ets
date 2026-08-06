import {
  MusicItem,
  SearchResult,
  SourceType,
  MusicQuality,
  LogUtils,
  StorageUtils
} from 'common'
import { SourceManager } from 'hsp_source'

const STORAGE_KEY_HISTORY = 'search_history'
const MAX_HISTORY = 50

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

    return SearchEngine.sortBySourcePriority(merged)
  }

  /**
   * 合并多个音源的结果
   * 同名 + 同歌手视为同一首歌，保留所有音源信息到 _types
   */
  private static mergeResults(results: SearchResult[]): MusicItem[] {
    const map = new Map<string, MusicItem>()

    for (const result of results) {
      for (const item of result.list) {
        const key = `${item.name}_${item.singer}`.toLowerCase()
        const existing = map.get(key)

        if (existing) {
          // 合并音源信息到 _types（手动逐字段复制，避免 Object.assign）
          if (!existing._types) {
            existing._types = {} as Record<string, import('common').MusicQualityInfo>
          }
          const existingTypes = existing._types!
          const itemTypes = item.types
          const typeKeys = Object.keys(itemTypes)
          for (let k = 0; k < typeKeys.length; k++) {
            const key = typeKeys[k]
            existingTypes[key] = itemTypes[key]
          }
        } else {
          const newTypes: Record<string, import('common').MusicQualityInfo> = {}
          const itemTypes = item.types
          const typeKeys = Object.keys(itemTypes)
          for (let k = 0; k < typeKeys.length; k++) {
            const key = typeKeys[k]
            newTypes[key] = itemTypes[key]
          }
          item._types = newTypes
          map.set(key, item)
        }
      }
    }

    // 手动遍历 Map，避免使用受限的 forEach
    const result: MusicItem[] = []
    const mapKeys: string[] = []
    map.forEach((_value: MusicItem, mapKey: string) => {
      mapKeys.push(mapKey)
    })
    for (let i = 0; i < mapKeys.length; i++) {
      const item = map.get(mapKeys[i])
      if (item) {
        result.push(item)
      }
    }
    return result
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
}
