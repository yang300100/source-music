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
 * 酷狗音乐源（内置搜索音源）
 *
 * 直接调用酷狗公开接口（与原版 lx-music 内置音源思路一致）：
 * - 搜索: /api/v3/search/song
 * - 播放: /app/i/getSongInfo.php?cmd=playInfo&hash=
 * - 歌词: /app/i/krc.php?cmd=100&hash=&timelength=
 *
 * 提供真实的搜索能力，让聚合搜索出结果；
 * 用户的 JS 音源（解析源）可在播放时参与换源解析。
 */
export class KugouSource extends BaseSource {
  private static readonly SEARCH_URL = 'http://mobilecdn.kugou.com/api/v3/search/song'
  private static readonly PLAY_URL = 'http://m.kugou.com/app/i/getSongInfo.php'
  private static readonly LYRIC_URL = 'http://m.kugou.com/app/i/krc.php'

  constructor() {
    super({
      id: 'kugou',
      name: '酷狗音乐',
      version: '1.0.0',
      author: 'Yuki',
      description: '内置酷狗搜索音源（公开接口）',
      type: SourceType.KG
    })
    this.priority = 20
  }

  /** 搜索歌曲 */
  async search(query: string, page: number, _quality: MusicQuality): Promise<SearchResult> {
    try {
      const url = `${KugouSource.SEARCH_URL}?format=json&keyword=${encodeURIComponent(query)}&page=${page}&pagesize=30&showtype=1`
      const data = await NetUtils.getJSON<Record<string, Object>>(url)
      if (!data) return { list: [], total: 0, limit: 30, page, source: SourceType.KG }

      const d = data['data'] as Record<string, Object>
      const info = d ? d['info'] as Array<Record<string, Object>> : null
      if (!info || !Array.isArray(info)) {
        return { list: [], total: 0, limit: 30, page, source: SourceType.KG }
      }

      const list: MusicItem[] = []
      for (const item of info) {
        const hash = (item['hash'] as string) ?? ''
        const name = (item['songname'] as string) ?? ''
        if (!hash || !name) continue
        const types: Record<string, MusicQualityInfo> = {}
        types['128k'] = { url: '', size: 0, br: 128000 }
        // 320k hash 存在时也可解析
        const hash320 = (item['320hash'] as string) ?? ''
        if (hash320) {
          types['320k'] = { url: '', size: 0, br: 320000 }
        }
        list.push({
          songmid: hash,
          name: name,
          singer: (item['singername'] as string) ?? '未知歌手',
          albumName: (item['album_name'] as string) ?? '',
          interval: Math.floor(Number(item['duration'] ?? 0)),
          imgUrl: '',
          lyricUrl: '',
          source: SourceType.KG,
          types: types
        })
      }
      return { list, total: list.length, limit: 30, page, source: SourceType.KG }
    } catch (err) {
      LogUtils.warn('酷狗搜索失败', JSON.stringify(err))
      return { list: [], total: 0, limit: 30, page, source: SourceType.KG }
    }
  }

  /** 获取播放 URL（hash → playInfo） */
  async getMusicInfo(songmid: string, _quality: MusicQuality): Promise<MusicItem> {
    try {
      const url = `${KugouSource.PLAY_URL}?cmd=playInfo&hash=${songmid}`
      const data = await NetUtils.getJSON<Record<string, Object>>(url)
      if (!data) throw new Error('获取播放信息失败')

      const playUrl = (data['url'] as string) ?? ''
      if (!playUrl) {
        // 尝试备用字段
        const backupUrl = (data['backup_url'] as Array<string>) ?? []
        if (backupUrl.length > 0) {
          throw new Error('酷狗接口未返回可用播放地址')
        }
        throw new Error('酷狗接口未返回可用播放地址')
      }

      const types: Record<string, MusicQualityInfo> = {}
      types['128k'] = { url: playUrl, size: 0, br: 128000 }
      return {
        songmid: songmid,
        name: (data['songName'] as string) ?? '',
        singer: (data['author_name'] as string) ?? '',
        albumName: (data['album_name'] as string) ?? '',
        interval: Math.floor(Number(data['timeLength'] ?? 0) / 1000),
        imgUrl: (data['imgUrl'] as string) ?? '',
        lyricUrl: '',
        source: SourceType.KG,
        types: types
      }
    } catch (err) {
      throw new Error(`酷狗获取播放地址失败: ${JSON.stringify(err)}`)
    }
  }

  /** 获取歌词（krc.php 返回明文 LRC） */
  async getLyric(songmid: string): Promise<LyricLine[]> {
    try {
      const url = `${KugouSource.LYRIC_URL}?cmd=100&hash=${songmid}&timelength=300000`
      const body = await NetUtils.getString(url)
      if (!body || body.includes('err')) return []
      return this.parseLRC(body)
    } catch (err) {
      return []
    }
  }

  /** 歌单（暂不支持） */
  async getPlaylistInfo(listid: string): Promise<PlaylistInfo> {
    throw new Error('酷狗音源暂不支持歌单获取')
  }

  /** 热搜（暂不支持） */
  async getHotSearch(): Promise<HotSearchItem[]> {
    return []
  }
}
