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
 * 网易云音乐源（内置搜索音源）
 *
 * 调用网易云公开接口：
 * - 搜索: /api/search/get/web
 * - 歌词: /api/song/lyric
 * - 播放: /song/media/outer/url（免费歌可用，VIP 歌返回 HTML → 抛错换源）
 *
 * 搜索 + 歌词稳定可用；播放免费歌曲可用，VIP 歌曲由用户音源（六音等）换源解析。
 */
export class NeteaseSource extends BaseSource {
  private static readonly SEARCH_URL = 'https://music.163.com/api/search/get/web'
  private static readonly LYRIC_URL = 'https://music.163.com/api/song/lyric'
  private static readonly PLAY_URL = 'https://music.163.com/song/media/outer/url'

  constructor() {
    super({
      id: 'netease',
      name: '网易云音乐',
      version: '1.0.0',
      author: 'Yuki',
      description: '内置网易云搜索音源（公开接口）',
      type: SourceType.WY
    })
    this.priority = 25
  }

  /** 搜索歌曲 */
  async search(query: string, page: number, _quality: MusicQuality): Promise<SearchResult> {
    try {
      const url = `${NeteaseSource.SEARCH_URL}?s=${encodeURIComponent(query)}&type=1&limit=30&offset=${(page - 1) * 30}`
      const data = await NetUtils.getJSON<Record<string, Object>>(url, { 'Referer': 'https://music.163.com' })
      if (!data) return { list: [], total: 0, limit: 30, page, source: SourceType.WY }

      const result = data['result'] as Record<string, Object>
      const songs = result ? result['songs'] as Array<Record<string, Object>> : null
      if (!songs || !Array.isArray(songs)) {
        return { list: [], total: 0, limit: 30, page, source: SourceType.WY }
      }

      const list: MusicItem[] = []
      for (const item of songs) {
        const id = (item['id'] as number) ?? 0
        const name = (item['name'] as string) ?? ''
        if (!id || !name) continue
        const artists = item['artists'] as Array<Record<string, Object>>
        const singer = artists && artists.length > 0
          ? (artists.map(a => a['name'] as string).join('、'))
          : '未知歌手'
        const album = item['album'] as Record<string, Object>
        const albumName = album ? (album['name'] as string) ?? '' : ''
        const duration = Math.floor(Number(item['duration'] ?? 0) / 1000)

        const types: Record<string, MusicQualityInfo> = {}
        types['128k'] = { url: '', size: 0, br: 128000 }
        list.push({
          songmid: String(id),
          name: name,
          singer: singer,
          albumName: albumName,
          interval: duration,
          imgUrl: '',
          lyricUrl: '',
          source: SourceType.WY,
          types: types
        })
      }
      return { list, total: list.length, limit: 30, page, source: SourceType.WY }
    } catch (err) {
      LogUtils.warn('网易搜索失败', JSON.stringify(err))
      return { list: [], total: 0, limit: 30, page, source: SourceType.WY }
    }
  }

  /** 获取播放 URL（免费歌可用，VIP 歌抛错换源） */
  async getMusicInfo(songmid: string, _quality: MusicQuality, fullSong?: MusicItem): Promise<MusicItem> {
    try {
      const url = `${NeteaseSource.PLAY_URL}?id=${songmid}.mp3`
      const body = await NetUtils.getString(url, { 'Referer': 'https://music.163.com' })
      // 外链播放：免费歌返回音频（body 非 HTML），VIP 歌返回 HTML 页面
      if (!body || body.includes('<!DOCTYPE') || body.includes('<html')) {
        throw new Error('网易歌曲需换源解析（VIP）')
      }
      const types: Record<string, MusicQualityInfo> = {}
      types['128k'] = { url: url, size: 0, br: 128000 }
      return {
        songmid: songmid,
        name: fullSong?.name ?? '',
        singer: fullSong?.singer ?? '',
        albumName: fullSong?.albumName ?? '',
        interval: fullSong?.interval ?? 0,
        imgUrl: fullSong?.imgUrl ?? '',
        lyricUrl: fullSong?.lyricUrl ?? '',
        source: SourceType.WY,
        types: types
      }
    } catch (err) {
      throw new Error(`网易获取播放地址失败: ${JSON.stringify(err)}`)
    }
  }

  /** 获取歌词 */
  async getLyric(songmid: string, _fullSong?: MusicItem): Promise<LyricLine[]> {
    try {
      const url = `${NeteaseSource.LYRIC_URL}?id=${songmid}&lv=1&kv=1&tv=-1`
      const data = await NetUtils.getJSON<Record<string, Object>>(url, { 'Referer': 'https://music.163.com' })
      if (!data) return []
      const lrc = data['lrc'] as Record<string, Object>
      const lyric = lrc ? (lrc['lyric'] as string) ?? '' : ''
      if (!lyric) return []
      return this.parseLRC(lyric)
    } catch (err) {
      return []
    }
  }

  /** 歌单（暂不支持） */
  async getPlaylistInfo(listid: string): Promise<PlaylistInfo> {
    throw new Error('网易音源暂不支持歌单获取')
  }

  /** 热搜（暂不支持） */
  async getHotSearch(): Promise<HotSearchItem[]> {
    return []
  }
}
