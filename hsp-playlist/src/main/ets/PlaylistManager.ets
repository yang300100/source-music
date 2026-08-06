import {
  LocalPlaylist,
  MusicItem,
  SourceType,
  LogUtils,
  StorageUtils
} from 'common'

const STORAGE_KEY_PLAYLISTS = 'local_playlists'

/** .lxmc 文件格式（兼容 lx-music 原版 playListPart_v2） */
interface LxmcListData {
  id?: string
  name?: string
  description?: string
  list?: Array<Record<string, Object>>
}
interface LxmcFile {
  type: string
  data?: LxmcListData
}

/**
 * 本地歌单管理器
 *
 * 提供歌单的完整 CRUD 操作，支持持久化存储。
 * 支持 .lxmc 格式导入/导出（兼容 lx-music 原版）。
 */
export class PlaylistManager {
  private playlists: LocalPlaylist[] = []
  private static instance: PlaylistManager | null = null

  static getInstance(): PlaylistManager {
    if (!PlaylistManager.instance) {
      PlaylistManager.instance = new PlaylistManager()
    }
    return PlaylistManager.instance
  }

  /** 初始化：从本地存储加载歌单 */
  async init(): Promise<void> {
    this.playlists = await StorageUtils.getObject<LocalPlaylist[]>(
      STORAGE_KEY_PLAYLISTS, []
    )
    LogUtils.info(`歌单管理器初始化: ${this.playlists.length} 个歌单`)
  }

  /** 获取所有歌单 */
  getAll(): LocalPlaylist[] {
    return [...this.playlists]
  }

  /** 按 ID 获取歌单 */
  getById(id: string): LocalPlaylist | undefined {
    return this.playlists.find(p => p.id === id)
  }

  /** 创建新歌单 */
  async create(name: string, description: string = ''): Promise<LocalPlaylist> {
    const playlist: LocalPlaylist = {
      id: this.generateId(),
      name: name,
      description: description,
      songs: [],
      createdAt: Date.now(),
      updatedAt: Date.now()
    }
    this.playlists.push(playlist)
    await this.save()
    LogUtils.info(`创建歌单: ${name}`)
    return playlist
  }

  /** 更新歌单信息 */
  async update(id: string, name: string, description: string = ''): Promise<boolean> {
    const playlist = this.getById(id)
    if (!playlist) return false
    playlist.name = name
    playlist.description = description
    playlist.updatedAt = Date.now()
    await this.save()
    return true
  }

  /** 删除歌单 */
  async delete(id: string): Promise<boolean> {
    const index = this.playlists.findIndex(p => p.id === id)
    if (index < 0) return false
    this.playlists.splice(index, 1)
    await this.save()
    LogUtils.info(`删除歌单: ${id}`)
    return true
  }

  /** 添加歌曲到歌单（自动去重） */
  async addSongs(playlistId: string, songs: MusicItem[]): Promise<boolean> {
    const playlist = this.getById(playlistId)
    if (!playlist) return false

    const existing = new Set(playlist.songs.map(s => `${s.name}_${s.singer}`))
    const newSongs = songs.filter(s => !existing.has(`${s.name}_${s.singer}`))

    playlist.songs.push(...newSongs)
    playlist.updatedAt = Date.now()
    await this.save()
    LogUtils.info(`添加到歌单 ${playlist.name}: ${newSongs.length} 首`)
    return true
  }

  /** 从歌单移除歌曲 */
  async removeSongs(playlistId: string, songIndices: number[]): Promise<boolean> {
    const playlist = this.getById(playlistId)
    if (!playlist) return false

    // 从大到小排序移除，避免索引偏移
    const sorted = songIndices.sort((a, b) => b - a)
    for (const index of sorted) {
      playlist.songs.splice(index, 1)
    }
    playlist.updatedAt = Date.now()
    await this.save()
    return true
  }

  // ===== .lxmc 导入/导出（兼容 lx-music 原版格式） =====

  /**
   * 导出歌单为 .lxmc 格式 JSON 字符串
   * 格式：{ type: 'playListPart_v2', data: { id, name, description, list } }
   * @param playlistId 要导出的歌单 ID
   * @returns JSON 字符串
   */
  exportToLxmc(playlistId: string): string {
    const playlist = this.getById(playlistId)
    if (!playlist) return ''

    // 将 MusicItem 转换为 lx-music 原版 MusicInfo 字段
    const list: Array<Record<string, Object>> = []
    for (const song of playlist.songs) {
      const item: Record<string, Object> = {}
      item['id'] = song.songmid
      item['name'] = song.name
      item['singer'] = song.singer
      item['source'] = String(song.source)
      item['interval'] = song.interval
      item['albumName'] = song.albumName
      item['imgUrl'] = song.imgUrl
      item['lyricUrl'] = song.lyricUrl
      list.push(item)
    }

    const data: LxmcFile = {
      type: 'playListPart_v2',
      data: {
        id: playlist.id,
        name: playlist.name,
        description: playlist.description,
        list: list
      }
    }
    return JSON.stringify(data)
  }

  /**
   * 从 .lxmc JSON 内容导入歌单（兼容 playListPart 和 playListPart_v2 两种格式）
   * @param jsonContent .lxmc 文件内容
   * @returns 创建的歌单，失败返回 null
   */
  async importFromLxmc(jsonContent: string): Promise<LocalPlaylist | null> {
    try {
      const parsed = JSON.parse(jsonContent) as LxmcFile
      if (!parsed || typeof parsed.type !== 'string') return null

      // 支持旧版 playListPart 和新版 playListPart_v2
      let listData: LxmcListData | null = null
      if (parsed.type === 'playListPart_v2' && parsed.data) {
        listData = parsed.data
      } else if (parsed.type === 'playListPart' && parsed.data) {
        listData = parsed.data
      } else {
        LogUtils.warn('不支持的文件格式', parsed.type)
        return null
      }

      // 映射歌曲字段（原版 id → 我们的 songmid）
      const songs: MusicItem[] = []
      const rawList = listData.list ?? []
      for (const raw of rawList) {
        const sourceStr = (raw['source'] as string) ?? 'custom'
        const source = this.parseSourceType(sourceStr)
        const intervalNum = Number(raw['interval'] ?? raw['duration'] ?? 0)
        songs.push({
          songmid: (raw['id'] as string) ?? (raw['songmid'] as string) ?? '',
          name: (raw['name'] as string) ?? '未知歌曲',
          singer: (raw['singer'] as string) ?? (raw['artist'] as string) ?? '未知歌手',
          albumName: (raw['albumName'] as string) ?? '',
          interval: isNaN(intervalNum) ? 0 : intervalNum,
          imgUrl: (raw['imgUrl'] as string) ?? (raw['img'] as string) ?? '',
          lyricUrl: (raw['lyricUrl'] as string) ?? '',
          source: source,
          types: {}
        })
      }

      // 创建歌单
      const name = (listData.name ?? '导入歌单').toString()
      const description = (listData.description ?? '从 .lxmc 文件导入').toString()
      const playlist = await this.create(name, description)
      if (songs.length > 0) {
        await this.addSongs(playlist.id, songs)
      }
      LogUtils.info(`导入歌单完成: ${name}, ${songs.length} 首`)
      return this.getById(playlist.id) ?? null
    } catch (err) {
      LogUtils.error('解析 .lxmc 文件失败', JSON.stringify(err))
      return null
    }
  }

  /** 将字符串音源标识转为 SourceType */
  private parseSourceType(sourceStr: string): SourceType {
    switch (sourceStr) {
      case 'kg': return SourceType.KG
      case 'kw': return SourceType.KW
      case 'tx': return SourceType.TX
      case 'wy': return SourceType.WY
      case 'mg': return SourceType.MG
      case 'local': return SourceType.LOCAL
      default: return SourceType.CUSTOM
    }
  }

  /** 持久化保存 */
  private async save(): Promise<void> {
    await StorageUtils.putObject(STORAGE_KEY_PLAYLISTS, this.playlists)
  }

  /** 生成唯一 ID */
  private generateId(): string {
    const chars = 'abcdefghijklmnopqrstuvwxyz0123456789'
    let result = ''
    for (let i = 0; i < 16; i++) {
      result += chars.charAt(Math.floor(Math.random() * chars.length))
    }
    return `pl_${result}_${Date.now()}`
  }
}
