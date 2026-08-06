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
  NetUtils
} from 'common'
import { BaseSource } from '../api/SourceAPI'

/**
 * QQ 音乐搜索源（内置搜索音源）
 *
 * 调用 QQ 音乐公开搜索接口：
 * - 搜索: /soso/fcgi-bin/client_search_cp
 *
 * 说明：QQ 播放 URL 需要复杂签名（403），歌词需登录 cookie，
 * 因此本音源仅提供搜索能力，播放/歌词由换源解析（用户音源）完成。
 */
export class QQSource extends BaseSource {
  private static readonly SEARCH_URL = 'https://c.y.qq.com/soso/fcgi-bin/client_search_cp'

  constructor() {
    super({
      id: 'qqmusic',
      name: 'QQ音乐',
      version: '1.0.0',
      author: 'Yuki',
      description: '内置 QQ 音乐搜索源（公开接口）',
      type: SourceType.TX
    })
    this.priority = 30
  }

  /** 搜索歌曲 */
  async search(query: string, page: number, _quality: MusicQuality): Promise<SearchResult> {
    try {
      const url = `${QQSource.SEARCH_URL}?w=${encodeURIComponent(query)}&format=json&p=${page}&n=30`
      const data = await NetUtils.getJSON<Record<string, Object>>(url, { 'Referer': 'https://y.qq.com' })
      if (!data) return { list: [], total: 0, limit: 30, page, source: SourceType.TX }

      const d = data['data'] as Record<string, Object>
      const song = d ? d['song'] as Record<string, Object> : null
      const listData = song ? song['list'] as Array<Record<string, Object>> : null
      if (!listData || !Array.isArray(listData)) {
        return { list: [], total: 0, limit: 30, page, source: SourceType.TX }
      }

      const list: MusicItem[] = []
      for (const item of listData) {
        const songmid = (item['songmid'] as string) ?? ''
        const name = (item['songname'] as string) ?? ''
        if (!songmid || !name) continue
        const singers = item['singer'] as Array<Record<string, Object>>
        const singer = singers && singers.length > 0
          ? (singers.map(s => s['name'] as string).join('、'))
          : '未知歌手'

        const types: Record<string, MusicQualityInfo> = {}
        types['128k'] = { url: '', size: 0, br: 128000 }
        list.push({
          songmid: songmid,
          name: name,
          singer: singer,
          albumName: (item['albumname'] as string) ?? '',
          interval: Math.floor(Number(item['interval'] ?? 0)),
          imgUrl: '',
          lyricUrl: '',
          source: SourceType.TX,
          types: types
        })
      }
      return { list, total: list.length, limit: 30, page, source: SourceType.TX }
    } catch (err) {
      LogUtils.warn('QQ搜索失败', JSON.stringify(err))
      return { list: [], total: 0, limit: 30, page, source: SourceType.TX }
    }
  }

  /** 获取播放 URL（QQ 需签名，抛错由换源处理） */
  async getMusicInfo(songmid: string, _quality: MusicQuality, fullSong?: MusicItem): Promise<MusicItem> {
    throw new Error('QQ 播放解析请使用用户音源（换源）')
  }

  /** 获取歌词（需 cookie，返回空） */
  async getLyric(songmid: string, _fullSong?: MusicItem): Promise<LyricLine[]> {
    return []
  }

  /** 歌单（暂不支持） */
  async getPlaylistInfo(listid: string): Promise<PlaylistInfo> {
    throw new Error('QQ音源暂不支持歌单获取')
  }

  /** 热搜（暂不支持） */
  async getHotSearch(): Promise<HotSearchItem[]> {
    return []
  }
}
