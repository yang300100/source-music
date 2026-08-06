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
import { KugouSource } from '../sources/KugouSource'
import { NeteaseSource } from '../sources/NeteaseSource'
import { JSSourceAdapter } from '../sources/JSSourceAdapter'
import { JSScriptSource } from '../sources/JSScriptSource'
import { JSSandbox } from '../sandbox/JSSandbox'
import { fileIo } from '@kit.CoreFileKit'
import { util } from '@kit.ArkTS'

const STORAGE_KEY_SOURCES = 'source_list'
const STORAGE_KEY_SCRIPTS = 'source_scripts'

/** 持久化的音源记录（元信息 + 开关 + 优先级） */
interface SavedSource {
  info: SourceInfo
  enabled: boolean
  priority: number
}

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

  /** 初始化：恢复已保存的 JS 音源 + 注册内置音源 */
  async init(): Promise<void> {
    // 内置演示音源（最低优先级，保证始终有一个可用音源）
    const demo = new DemoSource()
    demo.priority = 999
    this.sources.push(demo)

    // 本地文件音源（优先级 50，高于演示音源）
    const localFile = new LocalFileSource()
    localFile.priority = 50
    this.sources.push(localFile)

    // 内置酷狗搜索音源（优先级 20，提供真实搜索能力）
    const kugou = new KugouSource()
    this.sources.push(kugou)

    // 内置网易云搜索音源（优先级 25）
    const netease = new NeteaseSource()
    this.sources.push(netease)

    // 恢复已保存的 JS 音源（读取脚本内容 → 重新创建沙箱）
    const saved = await StorageUtils.getObject<SavedSource[]>(STORAGE_KEY_SOURCES, [])
    const scripts = await StorageUtils.getObject<Record<string, string>>(STORAGE_KEY_SCRIPTS, {})
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
        const source = await JSSandbox.createSource(script, info)
        if (source) {
          // enabled 兼容旧数据（undefined 视为启用）
          source.enabled = savedSource.enabled !== false
          source.priority = savedSource.priority
          this.sources.push(source)
          restoredCount++
        }
      } catch (err) {
        LogUtils.error(`恢复音源失败: ${info.name}`, JSON.stringify(err))
      }
    }

    LogUtils.info('音源管理器初始化完成', `共 ${this.sources.length} 个音源（恢复 ${restoredCount} 个 JS 音源）`)
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

  /** 注册 JS 音源（JSVM 完整沙箱执行） */
  private async registerJSSource(scriptContent: string, fileName: string = ''): Promise<SourceImportResult> {
    // 安全校验
    const securityError = JSSandbox.validateScript(scriptContent)
    if (securityError) {
      LogUtils.warn('音源脚本安全校验未通过', securityError)
      return { success: false, error: `安全校验失败: ${securityError}` }
    }

    // 解析元信息（头部注释 @标签，兜底用文件名/日期）
    const sourceInfo = JSSourceAdapter.parseSourceInfo(scriptContent, fileName)

    // 创建 JSVM 沙箱音源（真正执行脚本）
    const source = await JSSandbox.createSource(scriptContent, sourceInfo)
    if (!source) {
      return { success: false, error: 'JSVM 沙箱初始化失败，请检查脚本兼容性' }
    }

    // 检查是否已存在（更新而非重复添加）
    const existing = this.sources.find(s => s.info.id === source.info.id)
    if (existing) {
      const idx = this.sources.indexOf(existing)
      this.sources[idx] = source
      LogUtils.info(`更新音源: ${source.info.name}`)
    } else {
      this.sources.push(source)
      LogUtils.info(`导入音源: ${source.info.name} v${source.info.version}`)
    }

    this.save()
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

  /** 聚合搜索：并发请求所有启用音源（每源 8 秒超时，慢源不拖累整体） */
  async searchAll(
    query: string,
    page: number = 1,
    quality: MusicQuality = MusicQuality.HIGH
  ): Promise<SearchResult[]> {
    const enabled = this.getEnabledSources()
    LogUtils.info(`聚合搜索: "${query}", ${enabled.length} 个音源`)

    const promises = enabled.map(source =>
      this.withTimeout(
        source.search(query, page, quality),
        8000,
        `音源 ${source.info.name} 搜索`
      ).catch((err: Error) => {
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

  /** 获取播放信息（尝试所有音源直到成功） */
  async getMusicInfoWithFallback(
    songmid: string,
    sourceType: SourceType,
    quality: MusicQuality = MusicQuality.HIGH,
    fullSong?: MusicItem
  ): Promise<MusicItem | null> {
    const enabled = this.getEnabledSources()

    // 优先用原始音源
    const primary = enabled.find(s => s.info.type === sourceType)
    if (primary) {
      try {
        return await primary.getMusicInfo(songmid, quality, fullSong)
      } catch (err) {
        LogUtils.warn(`主音源获取失败，尝试换源`, JSON.stringify(err))
      }
    }

    // 换源重试
    for (const source of enabled) {
      if (source.info.type === sourceType) continue
      try {
        const info = await source.getMusicInfo(songmid, quality, fullSong)
        if (info) return info
      } catch (err) {
        continue
      }
    }

    return null
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
  }
}
