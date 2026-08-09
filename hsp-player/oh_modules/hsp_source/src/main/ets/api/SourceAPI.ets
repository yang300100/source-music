import {
  SourceInfo,
  SourceInstance,
  MusicItem,
  SearchResult,
  LyricLine,
  PlaylistInfo,
  MusicQuality,
  SourceType,
  HotSearchItem,
  LogUtils
} from 'common'

/**
 * ArkTS 原生音源基类 — 所有音源（原生/JS兼容）都继承此类
 * 哥哥大人说这是"壳与源分离"架构的核心抽象层~
 */
export abstract class BaseSource implements SourceInstance {
  info: SourceInfo
  enabled: boolean = true
  priority: number = 99
  isNative: boolean = true

  constructor(info: SourceInfo) {
    this.info = info
  }

  abstract search(query: string, page: number, quality: MusicQuality): Promise<SearchResult>
  abstract getMusicInfo(songmid: string, quality: MusicQuality, fullSong?: MusicItem): Promise<MusicItem>
  abstract getLyric(songmid: string, fullSong?: MusicItem): Promise<LyricLine[]>
  abstract getPlaylistInfo(listid: string): Promise<PlaylistInfo>
  abstract getHotSearch(): Promise<HotSearchItem[]>

  /**
   * 该音源支持解析的歌曲源列表（社区音源 sources 语义）
   * 空数组 = 未声明/不限；非空时仅解析列表内的源
   */
  getSupportedSources(): string[] {
    return []
  }

  /**
   * 解析 LRC 歌词文本为 LyricLine 数组
   * 支持标准 [mm:ss.xx] 和 [mm:ss.xxx] 两种时间戳格式
   */
  protected parseLRC(lrcText: string): LyricLine[] {
    const lines: LyricLine[] = []
    const timeRegex = /\[(\d{2}):(\d{2})\.(\d{2,3})\]/g

    for (const line of lrcText.split('\n')) {
      const text = line.replace(timeRegex, '').trim()
      if (!text) continue

      timeRegex.lastIndex = 0
      const matches = line.matchAll(timeRegex)
      for (const match of matches) {
        const min = parseInt(match[1])
        const sec = parseInt(match[2])
        // 两位毫秒（xx）补零成三位，三位毫秒（xxx）直接使用
        const ms = match[3].length === 2 ? parseInt(match[3]) * 10 : parseInt(match[3])
        lines.push({
          time: (min * 60 + sec) * 1000 + ms,
          text: text
        })
      }
    }
    const result = lines.sort((a, b) => a.time - b.time)
    LogUtils.info(`[歌词] parseLRC: 输入${lrcText.split('\n').length}行 → 解析得${result.length}行`)
    return result
  }
}

/**
 * 内置演示音源 — 用于测试播放链路（不含版权内容）
 * 优先级设为最高值999，保证始终有一个可用音源垫底~
 */
export class DemoSource extends BaseSource {
  constructor() {
    super({
      id: 'demo',
      name: '演示音源',
      version: '1.0.0',
      author: 'Yuki',
      description: '内置演示音源，用于测试播放链路，不含版权音乐',
      type: SourceType.CUSTOM
    })
  }

  async search(query: string, page: number, _quality: MusicQuality): Promise<SearchResult> {
    return {
      list: [],
      total: 0,
      limit: 30,
      page: page,
      source: SourceType.CUSTOM
    }
  }

  async getMusicInfo(songmid: string, _quality: MusicQuality): Promise<MusicItem> {
    throw new Error('演示音源不支持获取真实播放地址，请导入社区音源~')
  }

  async getLyric(songmid: string): Promise<LyricLine[]> {
    return []
  }

  async getPlaylistInfo(listid: string): Promise<PlaylistInfo> {
    throw new Error('演示音源不支持获取歌单')
  }

  async getHotSearch(): Promise<HotSearchItem[]> {
    return []
  }
}
