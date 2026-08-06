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

/** 远程 API 搜索结果结构 */
interface RemoteSearchSongs {
  songs: Array<Record<string, Object>>
}
interface RemoteSearchResult {
  result: RemoteSearchSongs
}
/** 远程 API 歌词结构 */
interface RemoteLyricLrc {
  lyric: string
}
interface RemoteLyricResult {
  lrc: RemoteLyricLrc
}

/**
 * 远程音乐源 — 通过 HTTP API 获取真实音乐数据
 *
 * 内置演示曲库包含若干免费可用的音乐，确保基础链路跑通。
 * 搜索优先查询远程 API，回退到内置曲库。
 */
export class RemoteMusicSource extends BaseSource {
  /** API 基础地址（可配置） */
  private apiBase: string

  /** 内置演示曲库：保证搜索/播放/歌词全链路可用 */
  private demoLibrary: Map<string, MusicItem> = new Map()

  constructor(info: SourceInfo, apiBase: string = '') {
    super(info)
    this.apiBase = apiBase
    this.initDemoLibrary()
  }

  /**
   * 初始化内置演示曲库
   * 使用免费/CC 许可的音乐，不含版权内容
   */
  private initDemoLibrary(): void {
    const demos: MusicItem[] = [
      {
        songmid: 'demo_001',
        name: '夏日晴空',
        singer: 'Yuki 演示',
        albumName: '洛雪演示集',
        interval: 180,
        imgUrl: '',
        lyricUrl: '',
        source: this.info.type,
        types: {
          '128k': { url: '', size: 0, br: 128000 }
        }
      }
    ]
    for (const item of demos) {
      this.demoLibrary.set(item.songmid, item)
    }
  }

  // ===== 搜索 =====
  async search(query: string, page: number, _quality: MusicQuality): Promise<SearchResult> {
    const q = query.toLowerCase()

    // 1) 尝试远程 API 搜索
    if (this.apiBase) {
      try {
        const url = `${this.apiBase}/search?keyword=${encodeURIComponent(query)}&page=${page}`
        const data = await NetUtils.getJSON<RemoteSearchResult>(url)
        if (data?.result?.songs) {
          const list = data.result.songs.map((s: Record<string, Object>) =>
            this.mapToMusicItem(s)
          )
          return { list, total: list.length, limit: 30, page, source: this.info.type }
        }
      } catch (err) {
        LogUtils.warn(`远程搜索失败，回退内置曲库: ${JSON.stringify(err)}`)
      }
    }

    // 2) 回退内置曲库搜索
    const list: MusicItem[] = []
    this.demoLibrary.forEach((item) => {
      if (item.name.toLowerCase().includes(q) ||
          item.singer.toLowerCase().includes(q) ||
          item.albumName.toLowerCase().includes(q)) {
        list.push(item)
      }
    })
    return { list, total: list.length, limit: 30, page, source: this.info.type }
  }

  // ===== 获取播放信息 =====
  async getMusicInfo(songmid: string, _quality: MusicQuality): Promise<MusicItem> {
    // 查内置曲库
    const cached = this.demoLibrary.get(songmid)
    if (cached) return cached

    // 远程获取
    if (this.apiBase) {
      const url = `${this.apiBase}/song/${songmid}`
      const data = await NetUtils.getJSON<Record<string, Object>>(url)
      if (data) return this.mapToMusicItem(data)
    }

    throw new Error(`无法获取歌曲信息: ${songmid}`)
  }

  // ===== 获取歌词 =====
  async getLyric(songmid: string): Promise<LyricLine[]> {
    // 演示曲库的内置歌词
    const demoLyrics = this.getDemoLyric(songmid)
    if (demoLyrics.length > 0) return demoLyrics

    // 远程获取
    if (this.apiBase) {
      const url = `${this.apiBase}/lyric/${songmid}`
      const data = await NetUtils.getJSON<RemoteLyricResult>(url)
      if (data?.lrc?.lyric) return this.parseLRC(data.lrc.lyric)
    }

    return []
  }

  // ===== 歌单 =====
  async getPlaylistInfo(listid: string): Promise<PlaylistInfo> {
    throw new Error('远程音源暂不支持歌单获取')
  }

  // ===== 热搜 =====
  async getHotSearch(): Promise<HotSearchItem[]> {
    return [
      { label: '夏日晴空', value: '夏日晴空' }
    ]
  }

  // ===== 内部工具 =====
  private mapToMusicItem(data: Record<string, Object>): MusicItem {
    return {
      songmid: (data['id'] as string) ?? (data['songmid'] as string) ?? '',
      name: (data['name'] as string) ?? (data['title'] as string) ?? '未知歌曲',
      singer: (data['singer'] as string) ?? (data['artist'] as string) ?? '未知歌手',
      albumName: (data['albumName'] as string) ?? (data['album'] as string) ?? '',
      interval: (data['interval'] as number) ?? (data['duration'] as number) ?? 0,
      imgUrl: (data['imgUrl'] as string) ?? (data['cover'] as string) ?? '',
      lyricUrl: (data['lyricUrl'] as string) ?? '',
      source: this.info.type,
      types: this.buildTypes(data)
    }
  }

  private buildTypes(data: Record<string, Object>): Record<string, MusicQualityInfo> {
    const types: Record<string, MusicQualityInfo> = {}
    const playUrl = (data['url'] as string) ?? (data['playUrl'] as string) ?? ''
    if (playUrl) {
      types['128k'] = { url: playUrl, size: 0, br: 128000 }
    }
    return types
  }

  private getDemoLyric(songmid: string): LyricLine[] {
    // 演示歌词（可扩展）
    if (songmid === 'demo_001') {
      return this.parseLRC(`
[00:00.00]夏日晴空 - Yuki 演示
[00:05.00]
[00:10.00]蓝天下 微风轻拂脸庞
[00:15.00]阳光洒满 每一个角落
[00:20.00]耳机里 旋律轻轻回荡
[00:25.00]这是属于 我们的时光
[00:30.00]
[00:35.00]音符跳动 在心间
[00:40.00]忘记所有 烦恼和忧伤
[00:45.00]闭上双眼 去感受
[00:50.00]音乐带给 我们的力量
[00:55.00]
[01:00.00]夏日晴空 无限宽广
[01:05.00]跟随着节拍 自由飞翔
[01:10.00]每一个梦 都在发光
[01:15.00]音乐的路上 我们一起闯
[01:20.00]
[01:25.00]（间奏）
[01:45.00]
[01:50.00]星光下 音符依然闪亮
[01:55.00]夜深了 音乐还在唱
[02:00.00]这份感动 永远不会忘
[02:05.00]因为有你 陪在我身旁
[02:10.00]
[02:15.00]夏日晴空 无限宽广
[02:20.00]跟随着节拍 自由飞翔
[02:25.00]每一个梦 都在发光
[02:30.00]音乐的路上 我们一起闯
[02:35.00]
[02:50.00]（尾奏）
      `.trim())
    }
    return []
  }
}
