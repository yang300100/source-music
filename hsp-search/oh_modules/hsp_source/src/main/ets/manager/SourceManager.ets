import {
  SourceInstance,
  SourceInfo,
  SourceImportMethod,
  SourceImportResult,
  SourceType,
  SearchResult,
  MusicItem,
  LyricLine,
  MusicQuality,
  LogUtils,
  StorageUtils
} from 'common'
import { BaseSource, DemoSource } from '../api/SourceAPI'

const STORAGE_KEY_SOURCES = 'source_list'

/**
 * 多音源管理器 — 统一管理所有音源的生命周期
 *
 * 负责：
 * 1. 音源的注册、启用/禁用、优先级排序
 * 2. 聚合搜索（并发请求所有启用音源）
 * 3. 播放信息获取 + 换源重试
 * 4. 音源列表持久化
 */
export class SourceManager {
  private sources: SourceInstance[] = []
  private static instance: SourceManager | null = null

  static getInstance(): SourceManager {
    if (!SourceManager.instance) {
      SourceManager.instance = new SourceManager()
    }
    return SourceManager.instance
  }

  /** 初始化：加载已保存的音源 + 注册内置演示音源 */
  async init(): Promise<void> {
    const saved = await StorageUtils.getObject<SourceInfo[]>(STORAGE_KEY_SOURCES, [])

    // 内置演示音源（最低优先级，保证始终有一个可用音源）
    const demo = new DemoSource()
    demo.priority = 999
    this.sources.push(demo)

    LogUtils.info('音源管理器初始化完成', `共 ${this.sources.length} 个音源`)
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

  /** 从本地文件导入 */
  private async importFromLocal(filePath: string): Promise<SourceImportResult> {
    LogUtils.info('导入本地音源', filePath)
    return { success: false, error: '本地 JS 音源导入将在 JSSandbox 实现后支持' }
  }

  /** 从在线 URL 导入 */
  private async importFromUrl(url: string): Promise<SourceImportResult> {
    LogUtils.info('导入在线音源', url)
    return { success: false, error: '在线音源导入将在 JSSandbox 实现后支持' }
  }

  /** 移除音源 */
  async removeSource(id: string): Promise<boolean> {
    const index = this.sources.findIndex(s => s.info.id === id)
    if (index < 0) return false
    this.sources.splice(index, 1)
    await this.save()
    return true
  }

  /** 开关音源 */
  async toggleSource(id: string, enabled: boolean): Promise<void> {
    const source = this.getSourceById(id)
    if (source) {
      source.enabled = enabled
      await this.save()
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

  /** 聚合搜索：并发请求所有启用音源 */
  async searchAll(
    query: string,
    page: number = 1,
    quality: MusicQuality = MusicQuality.HIGH
  ): Promise<SearchResult[]> {
    const enabled = this.getEnabledSources()
    LogUtils.info(`聚合搜索: "${query}", ${enabled.length} 个音源`)

    const promises = enabled.map(source =>
      source.search(query, page, quality).catch((err: Error) => {
        LogUtils.warn(`音源 ${source.info.name} 搜索失败`, JSON.stringify(err))
        return null
      })
    )

    const results = await Promise.all(promises)
    return results.filter(r => r !== null) as SearchResult[]
  }

  /** 获取播放信息（尝试所有音源直到成功） */
  async getMusicInfoWithFallback(
    songmid: string,
    sourceType: SourceType,
    quality: MusicQuality = MusicQuality.HIGH
  ): Promise<MusicItem | null> {
    const enabled = this.getEnabledSources()

    // 优先用原始音源
    const primary = enabled.find(s => s.info.type === sourceType)
    if (primary) {
      try {
        return await primary.getMusicInfo(songmid, quality)
      } catch (err) {
        LogUtils.warn(`主音源获取失败，尝试换源`, JSON.stringify(err))
      }
    }

    // 换源重试
    for (const source of enabled) {
      if (source.info.type === sourceType) continue
      try {
        const info = await source.getMusicInfo(songmid, quality)
        if (info) return info
      } catch (err) {
        continue
      }
    }

    return null
  }

  /** 持久化音源列表 */
  private async save(): Promise<void> {
    const infos = this.sources.map(s => s.info)
    await StorageUtils.putObject(STORAGE_KEY_SOURCES, infos)
  }
}
