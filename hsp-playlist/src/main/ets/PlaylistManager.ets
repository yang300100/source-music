import {
  LocalPlaylist,
  MusicItem,
  SourceType,
  LogUtils,
  StorageUtils
} from 'common'
import { fileIo } from '@kit.CoreFileKit'
import { media } from '@kit.MediaKit'
import { image } from '@kit.ImageKit'

const STORAGE_KEY_PLAYLISTS = 'local_playlists'
const FAVORITES_NAME = '我的收藏'

/** 歌单归档格式（兼容既有 playListPart_v2 数据） */
interface PlaylistArchiveListData {
  id?: string
  name?: string
  description?: string
  list?: Array<Record<string, Object>>
}
interface PlaylistArchiveFile {
  type: string
  data?: PlaylistArchiveListData
}

/**
 * 本地歌单管理器
 *
 * 提供歌单的完整 CRUD 操作，支持持久化存储。
 * 支持 JSON 歌单归档导入与导出，并兼容既有歌单数据结构。
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

  /**
   * 更新歌单中的歌曲为换源后的新版本（所有歌单中 songmid+source 匹配的旧歌曲）
   * @returns 是否更新了至少一首
   */
  async updateSongSource(oldSong: MusicItem, newSong: MusicItem): Promise<boolean> {
    let changed = false
    for (const pl of this.playlists) {
      for (let i = 0; i < pl.songs.length; i++) {
        const s = pl.songs[i]
        if (s.songmid === oldSong.songmid && s.source === oldSong.source) {
          pl.songs[i] = newSong
          changed = true
        }
      }
    }
    if (changed) {
      await this.save()
      LogUtils.info(`已更新歌单中的歌曲音源: ${newSong.name} → ${newSong.source}/${newSong.songmid}`)
    }
    return changed
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

  /** 移动歌单位置（direction: -1 上移 / 1 下移），持久化 */
  async movePlaylist(id: string, direction: number): Promise<void> {
    const idx = this.playlists.findIndex(p => p.id === id)
    if (idx < 0) return
    const target = idx + direction
    if (target < 0 || target >= this.playlists.length) return
    const item = this.playlists.splice(idx, 1)[0]
    this.playlists.splice(target, 0, item)
    await this.save()
    LogUtils.info(`歌单排序: ${item.name} → 第 ${target + 1} 位`)
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

  // ===== 我的收藏（自动歌单） =====

  /** 获取"我的收藏"歌单，不存在则自动创建 */
  async getOrCreateFavorites(): Promise<LocalPlaylist> {
    const existing = this.playlists.find(p => p.name === FAVORITES_NAME)
    if (existing) return existing
    return await this.create(FAVORITES_NAME, '自动收藏的歌单')
  }

  /** 判断歌曲是否已在收藏歌单（按 songmid + source 匹配） */
  async isFavorited(song: MusicItem): Promise<boolean> {
    const fav = this.playlists.find(p => p.name === FAVORITES_NAME)
    if (!fav) return false
    return fav.songs.some(s => s.songmid === song.songmid && s.source === song.source)
  }

  /**
   * 切换收藏状态：未收藏则加入，已收藏则移除
   * @returns 操作后的最终收藏状态（true=已收藏）
   */
  async toggleFavorite(song: MusicItem): Promise<boolean> {
    const fav = await this.getOrCreateFavorites()
    const index = fav.songs.findIndex(s => s.songmid === song.songmid && s.source === song.source)
    if (index >= 0) {
      await this.removeSongs(fav.id, [index])
      LogUtils.info(`取消收藏: ${song.name} - ${song.singer}`)
      return false
    }
    await this.addSongs(fav.id, [song])
    LogUtils.info(`收藏成功: ${song.name} - ${song.singer}`)
    return true
  }

  // ===== JSON 歌单归档导入/导出 =====

  /**
   * 导出歌单为 JSON 归档字符串
   * 格式：{ type: 'playListPart_v2', data: { id, name, description, list } }
   * @param playlistId 要导出的歌单 ID
   * @returns JSON 字符串
   */
  exportArchive(playlistId: string): string {
    const playlist = this.getById(playlistId)
    if (!playlist) return ''

    // 将 MusicItem 转换为兼容的 MusicInfo 字段
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

    const data: PlaylistArchiveFile = {
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
   * 从 JSON 归档内容导入歌单
   * 兼容格式：playListPart / playListPart_v2（单歌单）、playList_v2（多歌单数组）
   * @param jsonContent JSON 文件内容
   * @returns 创建的歌单（多歌单时返回最后一个），失败返回 null
   */
  async importArchive(jsonContent: string): Promise<LocalPlaylist | null> {
    try {
      const parsed = JSON.parse(jsonContent) as PlaylistArchiveFile
      if (!parsed || typeof parsed.type !== 'string') return null

      // playList_v2 的 data 为歌单数组，逐个转为单歌单结构递归导入。
      if (parsed.type === 'playList_v2' && Array.isArray(parsed.data)) {
        const plList = parsed.data as Array<Record<string, Object>>
        let lastCreated: LocalPlaylist | null = null
        for (const pl of plList) {
          const single: PlaylistArchiveFile = {
            type: 'playListPart_v2',
            data: {
              id: pl['id'] as string,
              name: pl['name'] as string,
              description: pl['description'] as string,
              list: pl['list'] as Array<Record<string, Object>>
            }
          }
          lastCreated = await this.importArchive(JSON.stringify(single))
        }
        LogUtils.info(`导入 playList_v2 完成: ${plList.length} 个歌单`)
        return lastCreated
      }

      // 支持旧版 playListPart 和新版 playListPart_v2
      let listData: PlaylistArchiveListData | null = null
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
        const intervalNum = this.parseInterval(raw['interval'] ?? raw['duration'] ?? 0)
        const meta = raw['meta'] as Record<string, Object> | null
        songs.push({
          songmid: (raw['id'] as string) ?? (raw['songmid'] as string) ?? '',
          name: (raw['name'] as string) ?? '未知歌曲',
          singer: (raw['singer'] as string) ?? (raw['artist'] as string) ?? '未知歌手',
          albumName: (raw['albumName'] as string) ?? (meta?.['albumName'] as string) ?? '',
          interval: intervalNum,
          imgUrl: (raw['imgUrl'] as string) ?? (raw['img'] as string) ?? (meta?.['imgUrl'] as string) ?? '',
          lyricUrl: (raw['lyricUrl'] as string) ?? '',
          source: source,
          types: {}
        })
      }

      // 创建歌单
      const name = (listData.name ?? '导入歌单').toString()
      const description = (listData.description ?? '从 JSON 歌单文件导入').toString()
      const playlist = await this.create(name, description)
      if (songs.length > 0) {
        await this.addSongs(playlist.id, songs)
      }
      LogUtils.info(`导入歌单完成: ${name}, ${songs.length} 首`)
      // 本地歌曲无封面时异步提取内嵌封面（不阻塞导入返回）
      if (songs.some(s => s.source === SourceType.LOCAL)) {
        this.fillLocalSongCovers(songs)
      }
      return this.getById(playlist.id) ?? null
    } catch (err) {
      LogUtils.error('解析歌单归档失败', JSON.stringify(err))
      return null
    }
  }

  /** 解析时长：数字（秒）或 "mm:ss" 字符串，单位统一为秒 */
  private parseInterval(value: Object | number): number {
    if (typeof value === 'number') {
      return isNaN(value) ? 0 : value
    }
    if (typeof value === 'string') {
      const num = Number(value)
      if (!isNaN(num)) return num
      const parts = (value as string).split(':')
      if (parts.length >= 2) {
        const min = parseInt(parts[parts.length - 2])
        const sec = parseInt(parts[parts.length - 1])
        return (isNaN(min) ? 0 : min) * 60 + (isNaN(sec) ? 0 : sec)
      }
    }
    return 0
  }

  /** 为无封面的本地歌曲提取内嵌封面（保存到沙箱 covers/ 并持久化） */
  private async fillLocalSongCovers(songs: MusicItem[]): Promise<void> {
    for (const song of songs) {
      if (song.source !== SourceType.LOCAL || song.imgUrl) continue
      const filePath = this.resolveLocalFilePath(song)
      if (!filePath) continue
      try {
        if (!fileIo.accessSync(filePath)) continue
        const stat = fileIo.statSync(filePath)
        const fd = fileIo.openSync(filePath, fileIo.OpenMode.READ_ONLY)
        const extractor = await media.createAVMetadataExtractor()
        extractor.fdSrc = { fd: fd.fd, offset: 0, length: stat.size }
        const cover = await extractor.fetchAlbumCover()
        extractor.release()
        fileIo.closeSync(fd)
        if (cover) {
          song.imgUrl = await this.saveCoverToLocal(cover, filePath)
          await this.save()
          LogUtils.info(`[封面] 已为本地歌曲补封面: ${song.name}`)
        }
      } catch (err) {
        // 无内嵌封面或解析失败，忽略
      }
    }
  }

  /** 从歌曲信息解析本地文件路径 */
  private resolveLocalFilePath(song: MusicItem): string {
    let p = song.songmid
    if (p.startsWith('local_')) p = p.substring(6)
    if (p.startsWith('file://')) p = p.substring(7)
    if (!p) {
      const url = song.types['320k']?.url ?? ''
      if (url.startsWith('file://')) p = url.substring(7)
    }
    return p
  }

  /** 内嵌封面保存到沙箱 filesDir/covers/，返回 file:// 路径 */
  private async saveCoverToLocal(pixelMap: image.PixelMap, filePath: string): Promise<string> {
    try {
      const context = getContext()
      const coverDir = `${context.filesDir}/covers`
      if (!fileIo.accessSync(coverDir)) {
        fileIo.mkdirSync(coverDir)
      }
      let hash = 0
      for (let i = 0; i < filePath.length; i++) {
        hash = (hash * 31 + filePath.charCodeAt(i)) >>> 0
      }
      const coverPath = `${coverDir}/${hash}.jpg`
      if (fileIo.accessSync(coverPath)) {
        return `file://${coverPath}`
      }
      const packer = image.createImagePacker()
      try {
        const buffer = await packer.packing(pixelMap, { format: 'image/jpeg', quality: 85 })
        const coverFile = fileIo.openSync(coverPath,
          fileIo.OpenMode.READ_WRITE | fileIo.OpenMode.CREATE | fileIo.OpenMode.TRUNC)
        fileIo.writeSync(coverFile.fd, buffer)
        fileIo.closeSync(coverFile)
      } finally {
        packer.release()
      }
      return `file://${coverPath}`
    } catch (err) {
      LogUtils.warn('[封面] 保存封面失败', JSON.stringify(err))
      return ''
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
