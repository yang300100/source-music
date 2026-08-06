import {
  LocalPlaylist,
  MusicItem,
  LogUtils,
  StorageUtils
} from 'common'

const STORAGE_KEY_PLAYLISTS = 'local_playlists'

/**
 * 本地歌单管理器
 *
 * 提供歌单的完整 CRUD 操作，支持持久化存储。
 * 后续第二阶段支持导入/导出 .lxmc 格式。
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
