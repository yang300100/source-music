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
      id: 'kg',
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
          imgUrl: this.extractCover(item),
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

  /** 获取播放 URL（wwwapi + kg_mid cookie，lx-music 同款；失败回退旧版 API） */
  async getMusicInfo(songmid: string, _quality: MusicQuality): Promise<MusicItem> {
    try {
      // 新版 wwwapi：需 kg_mid cookie（lx-music 酷狗源同款）
      const mid = KugouSource.randomMid()
      let url = `https://wwwapi.kugou.com/yy/index.php?r=play/getdata&hash=${songmid}&album_id=&mid=${mid}`
      LogUtils.info(`[播放] 酷狗 playInfo 请求(带kg_mid): ${url}`)
      let data = await NetUtils.getJSON<Record<string, Object>>(url, { 'Cookie': `kg_mid=${mid}` })
      let playUrl = ''
      if (data) {
        const inner = data['data'] as Record<string, Object>
        if (inner) {
          playUrl = (inner['play_url'] as string) ?? (inner['url'] as string) ?? ''
        }
        if (!playUrl) {
          playUrl = (data['url'] as string) ?? ''
        }
      }
      // 新版失败：回退旧版 API
      if (!playUrl) {
        url = `${KugouSource.PLAY_URL}?cmd=playInfo&hash=${songmid}`
        LogUtils.info(`[播放] 酷狗 旧版API: ${url}`)
        const oldData = await NetUtils.getJSON<Record<string, Object>>(url)
        if (oldData) {
          playUrl = (oldData['url'] as string) ?? ''
          if (!playUrl) {
            const backupUrl = (oldData['backup_url'] as Array<string>) ?? []
            if (backupUrl.length > 0) {
              playUrl = backupUrl[0] as string
            }
          }
        }
      }
      if (!playUrl) {
        throw new Error('酷狗接口未返回可用播放地址')
      }

      const types: Record<string, MusicQualityInfo> = {}
      types['128k'] = { url: playUrl, size: 0, br: 128000 }
      return {
        songmid: songmid,
        name: (data?.['songName'] as string) ?? '',
        singer: (data?.['author_name'] as string) ?? '',
        albumName: (data?.['album_name'] as string) ?? '',
        interval: Math.floor(Number(data?.['timeLength'] ?? 0) / 1000),
        imgUrl: (data?.['imgUrl'] as string) ?? '',
        lyricUrl: '',
        source: SourceType.KG,
        types: types
      }
    } catch (err) {
      throw new Error(`酷狗获取播放地址失败: ${JSON.stringify(err)}`)
    }
  }

  /** 生成随机 mid（lx-music 同款：40 位 hex，用作 kg_mid cookie 与 mid 参数） */
  private static randomMid(): string {
    const chars = '0123456789abcdef'
    let result = ''
    for (let i = 0; i < 40; i++) {
      result += chars.charAt(Math.floor(Math.random() * 16))
    }
    return result
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

  /** 提取封面：优先 trans_param.union_cover，其次 album_img，最后用 hash 拼接 */
  private extractCover(item: Record<string, Object>): string {
    const transParam = item['trans_param'] as Record<string, Object>
    if (transParam) {
      const unionCover = (transParam['union_cover'] as string) ?? ''
      if (unionCover) {
        return unionCover.replace(/\{size\}/g, '480')
      }
    }
    const albumImg = (item['album_img'] as string) ?? ''
    if (albumImg) {
      return albumImg.replace(/\{size\}/g, '480')
    }
    const hash = (item['hash'] as string) ?? ''
    if (hash) {
      return `https://imge.kugou.com/stdmusic/480/${hash}.jpg`
    }
    return ''
  }
}
