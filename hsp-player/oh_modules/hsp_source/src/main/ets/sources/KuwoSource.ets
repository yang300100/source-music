import {
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
 * 酷我音乐源（内置搜索音源，与原版 社区音源 内置音源思路一致）
 *
 * - 搜索: http://search.kuwo.cn/r.s
 * - 播放: http://antiserver.kuwo.cn/anti.s?type=convert_url&rid=
 * - 歌词: https://m.kuwo.cn/newh5/singles/songinfoandlrc?musicId=
 */
export class KuwoSource extends BaseSource {
  private static readonly SEARCH_URL = 'http://search.kuwo.cn/r.s'
  private static readonly PLAY_URL = 'http://antiserver.kuwo.cn/anti.s'
  private static readonly LYRIC_URL = 'https://m.kuwo.cn/newh5/singles/songinfoandlrc'

  constructor() {
    super({
      id: 'kw',
      name: '酷我音乐',
      version: '1.0.0',
      author: 'Yuki',
      description: '内置酷我搜索音源（公开接口）',
      type: SourceType.KW
    })
    this.priority = 35
  }

  /** 搜索歌曲 */
  async search(query: string, page: number, _quality: MusicQuality): Promise<SearchResult> {
    try {
      const url = `${KuwoSource.SEARCH_URL}?all=${encodeURIComponent(query)}&ft=music&itemset=web_2013&client=kt&pn=${page - 1}&rn=30&rformat=json&encoding=utf8`
      // r.s 接口返回单引号 JSON（{'key':'value'}），JSON.parse 无法直接解析，
      // 与 社区音源 内置酷我源一致：先获取原始文本再转换
      const body = await NetUtils.getString(url)
      if (!body) return { list: [], total: 0, limit: 30, page, source: SourceType.KW }
      let data: Record<string, Object> | null = null
      try {
        data = JSON.parse(body.replace(/'/g, '"')) as Record<string, Object>
      } catch (parseErr) {
        LogUtils.warn('酷我响应解析失败', JSON.stringify(parseErr))
        return { list: [], total: 0, limit: 30, page, source: SourceType.KW }
      }
      if (!data) return { list: [], total: 0, limit: 30, page, source: SourceType.KW }

      const abslist = data['abslist'] as Array<Record<string, Object>>
      if (!abslist || !Array.isArray(abslist)) {
        return { list: [], total: 0, limit: 30, page, source: SourceType.KW }
      }

      const list: MusicItem[] = []
      for (const item of abslist) {
        const rid = (item['MUSICRID'] as string) ?? ''
        const name = (item['SONGNAME'] as string) ?? ''
        if (!rid || !name) continue
        const types: Record<string, MusicQualityInfo> = {}
        types['128k'] = { url: '', size: 0, br: 128000 }
        list.push({
          songmid: rid,
          name: name,
          singer: (item['ARTIST'] as string) ?? '未知歌手',
          albumName: (item['ALBUM'] as string) ?? '',
          interval: Math.floor(Number(item['DURATION'] ?? 0)),
          imgUrl: (item['web_albumpic_short'] as string) ?? '',
          lyricUrl: '',
          source: SourceType.KW,
          types: types
        })
      }
      return { list, total: list.length, limit: 30, page, source: SourceType.KW }
    } catch (err) {
      LogUtils.warn('酷我搜索失败', JSON.stringify(err))
      return { list: [], total: 0, limit: 30, page, source: SourceType.KW }
    }
  }

  /** 获取播放 URL（anti.s 返回纯文本地址） */
  async getMusicInfo(songmid: string, _quality: MusicQuality): Promise<MusicItem> {
    try {
      const url = `${KuwoSource.PLAY_URL}?type=convert_url&rid=${songmid}&format=mp3&response=url`
      const playUrl = await NetUtils.getString(url)
      // 酷我受保护歌曲返回提示文本/HTML 页面而非音频地址，需识别并抛错以触发换源
      const isInvalid = !playUrl || !playUrl.startsWith('http') ||
        playUrl.includes('仅能在酷我音乐手机版中播放') ||
        playUrl.includes('<!DOCTYPE') || playUrl.includes('<html') ||
        playUrl.includes('.html') || playUrl.includes('html')
      if (isInvalid) {
        LogUtils.warn(`[播放] 酷我歌曲受保护，无法获取有效播放地址: ${playUrl ? playUrl.substring(0, 80) : '(空)'}`)
        throw new Error('酷我该歌曲受保护，请换源播放')
      }
      const types: Record<string, MusicQualityInfo> = {}
      types['128k'] = { url: playUrl, size: 0, br: 128000 }
      return {
        songmid: songmid,
        name: '',
        singer: '',
        albumName: '',
        interval: 0,
        imgUrl: '',
        lyricUrl: '',
        source: SourceType.KW,
        types: types
      }
    } catch (err) {
      throw new Error(`酷我获取播放地址失败: ${JSON.stringify(err)}`)
    }
  }

  /** 获取歌词（musicId 去掉 MUSIC_ 前缀） */
  async getLyric(songmid: string): Promise<LyricLine[]> {
    try {
      const musicId = songmid.replace(/^MUSIC_/, '')
      const url = `${KuwoSource.LYRIC_URL}?musicId=${musicId}`
      const data = await NetUtils.getJSON<Record<string, Object>>(url)
      if (!data) return []
      const innerData = data['data'] as Record<string, Object>
      const lrclist = (innerData?.['lrclist'] ?? data['lrclist']) as Array<Record<string, Object>>
      if (!lrclist || !Array.isArray(lrclist)) return []

      const lines: LyricLine[] = []
      for (const item of lrclist) {
        const timeStr = (item['time'] as string) ?? ''
        const text = (item['line'] as string) ?? ''
        if (!timeStr || !text) continue
        const timeMs = KuwoSource.parseTime(timeStr)
        lines.push({ time: timeMs, text: text, transText: '' })
      }
      return lines
    } catch (err) {
      LogUtils.warn('酷我歌词获取失败', JSON.stringify(err))
      return []
    }
  }

  /** 解析 "mm:ss.xx" 为毫秒 */
  private static parseTime(timeStr: string): number {
    const parts = timeStr.split(':')
    if (parts.length < 2) return 0
    const min = parseInt(parts[0])
    const sec = parseFloat(parts[1])
    if (isNaN(min) || isNaN(sec)) return 0
    return Math.floor((min * 60 + sec) * 1000)
  }

  /** 歌单（暂不支持） */
  async getPlaylistInfo(listid: string): Promise<PlaylistInfo> {
    throw new Error('酷我音源暂不支持歌单获取')
  }

  /** 热搜（暂不支持） */
  async getHotSearch(): Promise<HotSearchItem[]> {
    return []
  }
}
