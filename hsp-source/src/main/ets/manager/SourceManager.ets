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
  StorageUtils,
  NetUtils
} from 'common'
import { BaseSource, DemoSource } from '../api/SourceAPI'
import { LocalFileSource } from '../sources/LocalFileSource'
import { JSSourceAdapter } from '../sources/JSSourceAdapter'
import { JSSandbox } from '../sandbox/JSSandbox'
import { fileIo } from '@kit.CoreFileKit'

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

    // 本地文件音源（优先级 50，高于演示音源）
    const localFile = new LocalFileSource()
    localFile.priority = 50
    this.sources.push(localFile)

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

  /** 从本地文件导入 JS 音源脚本 */
  private async importFromLocal(filePath: string): Promise<SourceImportResult> {
    LogUtils.info('导入本地音源', filePath)
    try {
      // 读取文件内容（支持 URI 或沙箱路径）
      const fd = fileIo.openSync(filePath, fileIo.OpenMode.READ_ONLY)
      const stat = fileIo.statSync(filePath)
      const buf = new ArrayBuffer(stat.size)
      fileIo.readSync(fd.fd, buf)
      fileIo.closeSync(fd)

      // 将 ArrayBuffer 转为字符串
      const uint8 = new Uint8Array(buf)
      let scriptContent = ''
      for (let i = 0; i < uint8.length; i++) {
        scriptContent += String.fromCharCode(uint8[i])
      }

      // 从 URI 或路径中提取文件名（用于兜底命名）
      const lastSlash = filePath.lastIndexOf('/')
      const rawName = lastSlash >= 0 ? filePath.substring(lastSlash + 1) : filePath
      const fileName = rawName.includes('?') ? rawName.substring(0, rawName.indexOf('?')) : rawName

      return this.registerJSSource(scriptContent, fileName)
    } catch (err) {
      LogUtils.error('读取本地音源文件失败', JSON.stringify(err))
      return { success: false, error: `读取文件失败: ${JSON.stringify(err)}` }
    }
  }

  /** 从在线 URL 导入 JS 音源脚本 */
  private async importFromUrl(url: string): Promise<SourceImportResult> {
    LogUtils.info('导入在线音源', url)
    try {
      const scriptContent = await NetUtils.getString(url)
      if (!scriptContent) {
        return { success: false, error: '下载音源脚本失败，请检查网络连接' }
      }
      return this.registerJSSource(scriptContent, '')
    } catch (err) {
      LogUtils.error('下载在线音源失败', JSON.stringify(err))
      return { success: false, error: `下载失败: ${JSON.stringify(err)}` }
    }
  }

  /** 注册 JS 音源（解析脚本并创建适配器） */
  private registerJSSource(scriptContent: string, fileName: string = ''): SourceImportResult {
    // 安全校验
    const securityError = JSSandbox.validateScript(scriptContent)
    if (securityError) {
      LogUtils.warn('音源脚本安全校验未通过', securityError)
      return { success: false, error: `安全校验失败: ${securityError}` }
    }

    // 创建 JS 适配器（元信息从脚本头部注释解析，解析不到时用文件名/日期兜底）
    const adapter = new JSSourceAdapter(scriptContent, fileName)

    // 检查是否已存在
    const existing = this.sources.find(s => s.info.id === adapter.info.id)
    if (existing) {
      // 更新现有音源
      const idx = this.sources.indexOf(existing)
      this.sources[idx] = adapter
      LogUtils.info(`更新音源: ${adapter.info.name}`)
    } else {
      this.sources.push(adapter)
      LogUtils.info(`导入音源: ${adapter.info.name} v${adapter.info.version}`)
    }

    this.save()
    return { success: true, source: adapter }
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
