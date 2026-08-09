import {
  SourceInfo,
  SourceInstance,
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

/**
 * JS 音源适配器
 *
 * 读取 社区音源 社区 JS 音源脚本，解析其 HTTP 请求模式，
 * 在 ArkTS 层原生执行等效的网络请求，无需 QuickJS。
 *
 * 支持的音源格式：
 * 1. 新版事件驱动：通过全局音源接口注册 request 事件（社区主流）
 * 2. 旧版 module.exports 格式
 *
 * 参考原版 社区音源-mobile 的音源接口规范实现~
 */

/** 音源元信息字段长度限制 */
interface SourceInfoLen {
  name: number
  description: number
  author: number
  homepage: number
  version: number
}
export class JSSourceAdapter extends BaseSource {
  /** 原始 JS 脚本内容 */
  private scriptContent: string
  /** 从脚本中提取的 API 基础 URL */
  private apiBaseUrl: string = ''
  /** 搜索 API 路径模板 */
  private searchApiPath: string = ''
  /** 歌曲详情 API 路径模板 */
  private songApiPath: string = ''
  /** 歌词 API 路径模板 */
  private lyricApiPath: string = ''
  /** 平台标识 */
  private platform: string = ''

  constructor(scriptContent: string, fileName: string = '') {
    // 先从脚本中提取音源元信息（头部注释 @标签，兜底用文件名）
    const sourceInfo = JSSourceAdapter.parseSourceInfo(scriptContent, fileName)
    super(sourceInfo)
    this.scriptContent = scriptContent
    this.isNative = false // JS 音源非原生

    // 解析脚本中的 API 配置
    this.parseAPIConfig()
  }

  /** 从 JS 脚本中解析音源元信息（兼容 社区音源 社区标准注释格式） */
  static parseSourceInfo(scriptContent: string, fileName: string = ''): SourceInfo {
    // 社区音源 标准格式：脚本开头的块注释内用 @标签 声明元信息
    // 例如：/* * @name 六音 * @version 1.0.0 ... */
    const maxLen: SourceInfoLen = {
      name: 24, description: 36, author: 56, homepage: 1024, version: 36
    }

    // 1. 提取脚本开头的块注释 /* ... */
    let parsedName: string = ''
    let parsedVersion: string = ''
    let parsedAuthor: string = ''
    let parsedDesc: string = ''
    const commentMatch = /^\/\*[\S\s]+?\*\//.exec(scriptContent)
    if (commentMatch) {
      const lines = commentMatch[0].split(/\r?\n/)
      // 2. 逐行匹配 * @tag value（只支持已知标签）
      const tagRegex = /^\s?\*\s?@(\w+)\s(.+)$/
      for (const line of lines) {
        const result = tagRegex.exec(line)
        if (!result) continue
        const key = result[1]
        const value = result[2].trim()
        if (key === 'name' && parsedName === '') parsedName = value
        else if (key === 'version' && parsedVersion === '') parsedVersion = value
        else if (key === 'author' && parsedAuthor === '') parsedAuthor = value
        else if (key === 'description' && parsedDesc === '') parsedDesc = value
      }
    }

    // 3. 兜底：从文件名生成名称（例如 "sixyin.js" → "sixyin"）
    let name = parsedName
    if (!name) {
      if (fileName) {
        const base = fileName.replace(/\.js$/i, '')
        name = base
      } else {
        const now = new Date()
        const dateStr = `${now.getFullYear()}-${(now.getMonth() + 1).toString().padStart(2, '0')}-${now.getDate().toString().padStart(2, '0')} ${now.getHours().toString().padStart(2, '0')}:${now.getMinutes().toString().padStart(2, '0')}`
        name = `音源_${dateStr}`
      }
    }

    // 4. 字段长度限制
    const truncate = (value: string, len: number): string => {
      if (value.length > len) return value.substring(0, len) + '...'
      return value
    }

    const finalName = truncate(name, maxLen.name)
    const finalVersion = truncate(parsedVersion || '0.0.0', maxLen.version)
    const finalAuthor = truncate(parsedAuthor || '未知作者', maxLen.author)
    const finalDesc = truncate(parsedDesc || '社区 JS 音源', maxLen.description)

    // 生成唯一 ID
    const id = `js_${finalName.replace(/[^a-zA-Z0-9一-龥]/g, '_').toLowerCase()}`

    return {
      id: id,
      name: finalName,
      version: finalVersion,
      author: finalAuthor,
      description: finalDesc,
      type: SourceType.CUSTOM,
      scriptUrl: ''
    }
  }

  /** 解析 API 配置（从脚本中提取关键 API 路径） */
  private parseAPIConfig(): void {
    // 尝试提取 API 基础 URL
    const apiUrlMatch = this.scriptContent.match(/(?:api[_\s]*(?:url|base|host)|hostUrl)\s*[:=]\s*['"]([^'"]+)['"]/)
    if (apiUrlMatch) {
      this.apiBaseUrl = apiUrlMatch[1]
    }

    // 提取平台标识（kg/kw/tx/wy/mg）
    const platformMatch = this.scriptContent.match(/(?:source|platform|type)\s*[:=]\s*['"]([^'"]+)['"]/)
    if (platformMatch) {
      this.platform = platformMatch[1]
    }

    LogUtils.info(`JSSourceAdapter: 解析完成 - ${this.info.name} v${this.info.version} by ${this.info.author}`)
  }

  // ===== 搜索 =====
  async search(query: string, page: number, _quality: MusicQuality): Promise<SearchResult> {
    // 从脚本中提取搜索逻辑并执行
    const searchFn = this.extractFunction('search')
    if (searchFn) {
      return await this.executeSearchFunction(searchFn, query, page)
    }
    return { list: [], total: 0, limit: 30, page, source: this.info.type }
  }

  // ===== 获取播放信息 =====
  async getMusicInfo(songmid: string, _quality: MusicQuality): Promise<MusicItem> {
    const fn = this.extractFunction('getMusicInfo')
    if (fn) {
      return await this.executeMusicInfoFunction(fn, songmid)
    }
    throw new Error(`音源 ${this.info.name} 不支持获取播放信息`)
  }

  // ===== 获取歌词 =====
  async getLyric(songmid: string): Promise<LyricLine[]> {
    const fn = this.extractFunction('getLyric')
    if (fn) {
      try {
        const lrcText = await this.executeLyricFunction(fn, songmid)
        if (lrcText) return this.parseLRC(lrcText)
      } catch (err) {
        LogUtils.warn(`歌词获取失败: ${songmid}`, JSON.stringify(err))
      }
    }
    return []
  }

  // ===== 歌单 =====
  async getPlaylistInfo(listid: string): Promise<PlaylistInfo> {
    throw new Error('JS 音源暂不支持歌单获取')
  }

  // ===== 热搜 =====
  async getHotSearch(): Promise<HotSearchItem[]> {
    const fn = this.extractFunction('getHotSearch')
    if (fn) {
      try {
        const result = await this.executeHotSearchFunction(fn)
        return result
      } catch (err) {
        LogUtils.warn('热搜获取失败')
      }
    }
    return []
  }

  // ===== 函数提取与执行 =====

  /** 从脚本中提取指定函数体 */
  private extractFunction(funcName: string): string | null {
    // 匹配 async function xxx 或 function xxx 的定义
    const patterns = [
      new RegExp(`async\\s+${funcName}\\s*\\([^)]*\\)\\s*\\{`, 's'),
      new RegExp(`${funcName}\\s*:\\s*async\\s+function`, 's'),
      new RegExp(`${funcName}\\s*:\\s*async\\s*\\(`, 's'),
      new RegExp(`${funcName}\\s*:\\s*function`, 's'),
    ]

    for (const pattern of patterns) {
      const match = this.scriptContent.match(pattern)
      if (match) {
        // 找到了函数定义，提取到匹配的闭合括号
        const startIdx = match.index ?? 0
        const remaining = this.scriptContent.substring(startIdx)
        let depth = 0
        let inString = false
        let endIdx = -1
        for (let i = 0; i < remaining.length; i++) {
          const ch = remaining[i]
          if (ch === '"' || ch === "'" || ch === '`') {
            if (i === 0 || remaining[i - 1] !== '\\') {
              inString = !inString
            }
          }
          if (!inString) {
            if (ch === '{') depth++
            if (ch === '}') {
              depth--
              if (depth === 0 && i > 0) {
                endIdx = i + 1
                break
              }
            }
          }
        }
        if (endIdx > 0) {
          return remaining.substring(0, endIdx)
        }
      }
    }
    return null
  }

  /** 解析并执行搜索函数 */
  private async executeSearchFunction(fnBody: string, query: string, page: number): Promise<SearchResult> {
    // 从函数体中提取 HTTP 请求 URL 模式
    const urlPattern = fnBody.match(/['"]([^'"]*\${?\s*(?:query|keyword|key|wd)\s*}?[^'"]*)['"]/)
    if (urlPattern) {
      const urlTemplate = urlPattern[1]
      // 替换模板变量
      const url = urlTemplate
        .replace(/\$\{?\s*(?:query|keyword|key|wd)\s*\}?/g, encodeURIComponent(query))
        .replace(/\$\{?\s*(?:page|pn)\s*\}?/g, String(page))

      // 补全 URL
      const fullUrl = url.startsWith('http') ? url : `${this.apiBaseUrl}${url}`
      LogUtils.info(`JS音源搜索: ${fullUrl}`)

      try {
        const data = await NetUtils.getJSON<Record<string, Object>>(fullUrl)
        if (data) {
          return this.mapSearchResponse(data, query, page)
        }
      } catch (err) {
        LogUtils.error('JS音源搜索请求失败', JSON.stringify(err))
      }
    }

    return { list: [], total: 0, limit: 30, page, source: this.info.type }
  }

  /** 解析并执行获取播放信息函数 */
  private async executeMusicInfoFunction(fnBody: string, songmid: string): Promise<MusicItem> {
    const urlPattern = fnBody.match(/['"]([^'"]*\${?\s*(?:songmid|id|mid)\s*}?[^'"]*)['"]/)
    if (urlPattern) {
      const url = urlPattern[1].replace(/\$\{?\s*(?:songmid|id|mid)\s*\}?/g, songmid)
      const fullUrl = url.startsWith('http') ? url : `${this.apiBaseUrl}${url}`
      LogUtils.info(`JS音源获取播放: ${fullUrl}`)

      try {
        const data = await NetUtils.getJSON<Record<string, Object>>(fullUrl)
        if (data) {
          return this.mapMusicInfoResponse(data, songmid)
        }
      } catch (err) {
        LogUtils.error('JS音源播放请求失败', JSON.stringify(err))
      }
    }
    throw new Error(`无法获取歌曲: ${songmid}`)
  }

  /** 解析并执行歌词获取 */
  private async executeLyricFunction(fnBody: string, songmid: string): Promise<string> {
    const urlPattern = fnBody.match(/['"]([^'"]*\${?\s*(?:songmid|id|mid|lyricid)\s*}?[^'"]*)['"]/)
    if (urlPattern) {
      const url = urlPattern[1].replace(/\$\{?\s*(?:songmid|id|mid|lyricid)\s*\}?/g, songmid)
      const fullUrl = url.startsWith('http') ? url : `${this.apiBaseUrl}${url}`
      LogUtils.info(`JS音源获取歌词: ${fullUrl}`)

      try {
        const data = await NetUtils.getJSON<Record<string, Object>>(fullUrl)
        if (data) {
          // 尝试从常见字段提取歌词
          const lyric = (data['lyric'] as string) ?? (data['lrc'] as string) ?? ''
          const lrcData = data['lrc'] as Record<string, Object>
          return (lyric || (lrcData?.['lyric'] as string)) ?? ''
        }
      } catch (err) {
        LogUtils.error('JS音源歌词请求失败', JSON.stringify(err))
      }
    }
    return ''
  }

  /** 解析热搜函数 */
  private async executeHotSearchFunction(fnBody: string): Promise<HotSearchItem[]> {
    const urlPattern = fnBody.match(/['"]([^'"]+)['"]/)
    if (urlPattern) {
      const url = urlPattern[1]
      const fullUrl = url.startsWith('http') ? url : `${this.apiBaseUrl}${url}`
      try {
        const data = await NetUtils.getJSON<Record<string, Object>>(fullUrl)
        if (data) {
          const list = data['list'] ?? data['data'] ?? []
          if (Array.isArray(list)) {
            const result: HotSearchItem[] = []
            const itemList = list as Record<string, Object>[]
            for (let i = 0; i < itemList.length; i++) {
              const item = itemList[i]
              const label = (item['label'] ?? item['name'] ?? item['word'] ?? '') as string
              const value = (item['value'] ?? item['keyword'] ?? item['word'] ?? '') as string
              result.push({ label: label, value: value })
            }
            return result
          }
        }
      } catch (err) {
        // 静默失败
      }
    }
    return []
  }

  /** 映射搜索响应为标准格式 */
  private mapSearchResponse(data: Record<string, Object>, query: string, page: number): SearchResult {
    // 尝试多种常见的响应格式
    const rawResult = data['result'] as Record<string, Object>
    const rawData = data['data'] as Record<string, Object>
    const list = (data['list'] ?? data['songs'] ?? (rawResult ? rawResult['songs'] : undefined) ?? (rawData ? rawData['list'] : undefined) ?? []) as Record<string, Object>[]
    const total = (data['total'] ?? data['totalCount'] ?? data['count'] ?? list.length) as number

    const songs: MusicItem[] = []
    if (Array.isArray(list)) {
      for (const item of list) {
        songs.push(this.mapSongItem(item as Record<string, Object>))
      }
    }

    return { list: songs, total: total, limit: 30, page, source: this.info.type }
  }

  /** 映射播放信息响应 */
  private mapMusicInfoResponse(data: Record<string, Object>, songmid: string): MusicItem {
    const songData = (data['data'] ?? data['song'] ?? data) as Record<string, Object>
    return this.mapSongItem(songData)
  }

  /** 映射单个歌曲项 */
  private mapSongItem(item: Record<string, Object>): MusicItem {
    const id = (item['id'] ?? item['songmid'] ?? item['mid'] ?? '') as string
    const name = (item['name'] ?? item['title'] ?? item['songname'] ?? '未知') as string
    const singer = (item['singer'] ?? item['artist'] ?? item['author'] ?? '未知') as string
    const album = (item['album'] ?? item['albumName'] ?? item['albumname'] ?? '') as string
    const duration = (item['duration'] ?? item['interval'] ?? item['dt'] ?? 0) as number
    const cover = (item['cover'] ?? item['pic'] ?? item['img'] ?? item['imgUrl'] ?? '') as string

    const types: Record<string, MusicQualityInfo> = {}
    // 提取播放 URL
    const url = (item['url'] ?? item['playUrl'] ?? item['play_url'] ?? item['musicUrl'] ?? '') as string
    if (url) {
      types['128k'] = { url: url, size: 0, br: 128000 }
    }
    // 高清
    const url320 = (item['url320'] ?? item['url_320'] ?? '') as string
    if (url320) {
      types['320k'] = { url: url320, size: 0, br: 320000 }
    }
    // 无损
    const urlFlac = (item['urlFlac'] ?? item['url_flac'] ?? item['flac'] ?? '') as string
    if (urlFlac) {
      types['flac'] = { url: urlFlac, size: 0, br: 0 }
    }

    return {
      songmid: id || `js_${name}`,
      name: name,
      singer: singer,
      albumName: album,
      interval: Math.floor(duration),
      imgUrl: cover,
      lyricUrl: '',
      source: this.info.type,
      types: types
    }
  }
}
