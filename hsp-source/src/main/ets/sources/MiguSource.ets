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
 * 咪咕音乐源（内置搜索音源，与原版 lx-music 内置音源思路一致）
 *
 * - 搜索: https://m.music.migu.cn/migu/remoting/scr_search_tag
 * - 播放: https://app.pd.nf.migu.cn/MIGUM2.0/v1.0/content/sub/listenSong.do
 * - 歌词: https://c.musicapp.migu.cn/MIGUM2.0/v1.0/content/resourceinfo.do
 */
export class MiguSource extends BaseSource {
  private static readonly SEARCH_URL = 'https://m.music.migu.cn/migu/remoting/scr_search_tag'
  private static readonly PLAY_URL = 'https://app.pd.nf.migu.cn/MIGUM2.0/v1.0/content/sub/listenSong.do'
  private static readonly LYRIC_INFO_URL = 'https://c.musicapp.migu.cn/MIGUM2.0/v1.0/content/resourceinfo.do'

  constructor() {
    super({
      id: 'mg',
      name: '咪咕音乐',
      version: '1.0.0',
      author: 'Yuki',
      description: '内置咪咕搜索音源（公开接口）',
      type: SourceType.MG
    })
    this.priority = 40
  }

  /** 搜索歌曲 */
  async search(query: string, page: number, _quality: MusicQuality): Promise<SearchResult> {
    try {
      const url = `${MiguSource.SEARCH_URL}?rows=30&type=2&pgc=1&keyword=${encodeURIComponent(query)}`
      const data = await NetUtils.getJSON<Record<string, Object>>(url)
      if (!data) return { list: [], total: 0, limit: 30, page, source: SourceType.MG }

      const musics = data['musics'] as Array<Record<string, Object>>
      if (!musics || !Array.isArray(musics)) {
        return { list: [], total: 0, limit: 30, page, source: SourceType.MG }
      }

      const list: MusicItem[] = []
      for (const item of musics) {
        const id = (item['id'] as string) ?? ''
        const name = (item['title'] as string) ?? ''
        if (!id || !name) continue
        const singers = item['singer'] as Array<Record<string, Object>>
        const album = item['album'] as Record<string, Object>
        const types: Record<string, MusicQualityInfo> = {}
        types['128k'] = { url: '', size: 0, br: 128000 }
        list.push({
          songmid: id,
          name: name,
          singer: (singers && singers.length > 0 ? (singers[0]['name'] as string) : '') ?? '未知歌手',
          albumName: (album?.['title'] as string) ?? '',
          interval: Math.floor(Number(item['timeLength'] ?? 0) / 1000),
          imgUrl: (album?.['cover'] as string) ?? '',
          lyricUrl: '',
          source: SourceType.MG,
          types: types
        })
      }
      return { list, total: list.length, limit: 30, page, source: SourceType.MG }
    } catch (err) {
      LogUtils.warn('咪咕搜索失败', JSON.stringify(err))
      return { list: [], total: 0, limit: 30, page, source: SourceType.MG }
    }
  }

  /** 获取播放 URL（listenSong.do） */
  async getMusicInfo(songmid: string, quality: MusicQuality): Promise<MusicItem> {
    try {
      const toneFlag = MiguSource.mapQuality(quality)
      const url = `${MiguSource.PLAY_URL}?toneFlag=${toneFlag}&netType=01&userId=15548614588710179085069&ua=Android_migu&version=5.1&format=1&resourceType=2&songId=${songmid}`
      const data = await NetUtils.getJSON<Record<string, Object>>(url, {
        'User-Agent': 'Mozilla/5.0 (Linux; Android 10) AppleWebKit/537.36'
      })
      if (!data) throw new Error('咪咕接口无响应')

      const resource = data['resource'] as Array<Record<string, Object>>
      if (!resource || resource.length === 0) throw new Error('咪咕未返回可用播放地址')
      const rateFormats = resource[0]['rateFormats'] as Array<Record<string, Object>>
      if (!rateFormats || rateFormats.length === 0) throw new Error('咪咕未返回可用播放地址')

      const fmt = rateFormats[0]
      const playUrl = (fmt['url'] as string) ?? ''
      if (!playUrl) throw new Error('咪咕未返回可用播放地址')

      const types: Record<string, MusicQualityInfo> = {}
      types['128k'] = { url: playUrl, size: 0, br: 128000 }
      return {
        songmid: songmid,
        name: (resource[0]['songName'] as string) ?? '',
        singer: (resource[0]['singer'] as string) ?? '',
        albumName: (resource[0]['album'] as string) ?? '',
        interval: Math.floor(Number(resource[0]['timeLength'] ?? 0) / 1000),
        imgUrl: (resource[0]['albumImgs'] as string) ?? '',
        lyricUrl: '',
        source: SourceType.MG,
        types: types
      }
    } catch (err) {
      throw new Error(`咪咕获取播放地址失败: ${JSON.stringify(err)}`)
    }
  }

  /** 获取歌词（resourceinfo → lyricUrl → lrc） */
  async getLyric(songmid: string): Promise<LyricLine[]> {
    try {
      const url = `${MiguSource.LYRIC_INFO_URL}?resourceId=${songmid}&resourceType=2`
      const data = await NetUtils.getJSON<Record<string, Object>>(url)
      if (!data) return []
      const resource = data['resource'] as Array<Record<string, Object>>
      if (!resource || resource.length === 0) return []
      const lyricUrl = (resource[0]['lyricUrl'] as string) ?? ''
      if (!lyricUrl) return []
      const body = await NetUtils.getString(lyricUrl)
      if (!body) return []
      return this.parseLRC(body)
    } catch (err) {
      LogUtils.warn('咪咕歌词获取失败', JSON.stringify(err))
      return []
    }
  }

  /** 音质 → 咪咕 toneFlag */
  private static mapQuality(quality: MusicQuality): string {
    switch (quality) {
      case MusicQuality.LOSSLESS:
      case MusicQuality.HIRES:
        return 'SQ'
      case MusicQuality.HIGH:
        return 'HQ'
      default:
        return 'PQ'
    }
  }

  /** 歌单（暂不支持） */
  async getPlaylistInfo(listid: string): Promise<PlaylistInfo> {
    throw new Error('咪咕音源暂不支持歌单获取')
  }

  /** 热搜（暂不支持） */
  async getHotSearch(): Promise<HotSearchItem[]> {
    return []
  }
}
