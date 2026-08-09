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
  LogUtils
} from 'common'
import { BaseSource } from '../api/SourceAPI'
import { fileIo } from '@kit.CoreFileKit'
import { media } from '@kit.MediaKit'
import { image } from '@kit.ImageKit'

/**
 * 本地文件音源 — 扫描并播放设备上的音乐文件
 *
 * 支持格式：mp3, flac, wav, ogg, aac
 * 无需网络，直接读取本地文件系统。
 *
 * 哥哥说这是 MVP 阶段最快能跑通的方案~
 */
export class LocalFileSource extends BaseSource {
  /** 本地音乐文件缓存 */
  private localSongs: MusicItem[] = []
  /** 支持的音频扩展名 */
  private readonly supportedExts: string[] = ['.mp3', '.flac', '.wav', '.ogg', '.aac', '.m4a']

  constructor() {
    super({
      id: 'local_source',
      name: '本地音乐',
      version: '1.0.0',
      author: 'Yuki',
      description: '扫描设备本地音乐文件（mp3/flac/wav/ogg/aac），直接播放',
      type: SourceType.LOCAL
    })
    this.priority = 50
  }

  // ===== 搜索（从已扫描的本地文件库中匹配） =====
  async search(query: string, page: number, _quality: MusicQuality): Promise<SearchResult> {
    const q = query.toLowerCase().trim()
    let filtered = this.localSongs

    // 有搜索词时按歌名/歌手/专辑过滤
    if (q) {
      filtered = this.localSongs.filter(s =>
        s.name.toLowerCase().includes(q) ||
        s.singer.toLowerCase().includes(q) ||
        s.albumName.toLowerCase().includes(q)
      )
    }

    const pageSize = 30
    const start = (page - 1) * pageSize
    const paged = filtered.slice(start, start + pageSize)

    return {
      list: paged,
      total: filtered.length,
      limit: pageSize,
      page: page,
      source: SourceType.LOCAL
    }
  }

  // ===== 获取播放信息（本地文件直接用文件路径作为 URL） =====
  async getMusicInfo(songmid: string, _quality: MusicQuality): Promise<MusicItem> {
    const song = this.localSongs.find(s => s.songmid === songmid)
    if (!song) {
      throw new Error(`本地文件不存在: ${songmid}`)
    }
    return song
  }

  // ===== 本地文件无在线歌词，返回空 =====
  async getLyric(songmid: string): Promise<LyricLine[]> {
    // 尝试在同目录下查找同名 .lrc 文件
    const song = this.localSongs.find(s => s.songmid === songmid)
    if (song?.lyricUrl) {
      try {
        const content = await this.readTextFile(song.lyricUrl)
        return this.parseLRC(content)
      } catch (err) {
        LogUtils.warn('读取本地歌词失败', JSON.stringify(err))
      }
    }
    return []
  }

  // ===== 本地音源不支持在线歌单 =====
  async getPlaylistInfo(listid: string): Promise<PlaylistInfo> {
    throw new Error('本地音源不支持在线歌单')
  }

  // ===== 热搜 =====
  async getHotSearch(): Promise<HotSearchItem[]> {
    return []
  }

  // ===== 核心方法：扫描设备目录中的音乐文件 =====
  /**
   * 扫描指定目录，建立本地音乐索引
   * @param dirPath 要扫描的目录路径（如 /storage/media/100/local/files/Music/）
   */
  async scanDirectory(dirPath: string): Promise<number> {
    LogUtils.info(`开始扫描本地音乐: ${dirPath}`)
    const newSongs: MusicItem[] = []
    try {
      await this.scanRecursive(dirPath, newSongs)
    } catch (err) {
      LogUtils.error('扫描目录失败', JSON.stringify(err))
    }

    // 合并去重
    const existingIds = new Set(this.localSongs.map(s => s.songmid))
    const added = newSongs.filter(s => !existingIds.has(s.songmid))
    this.localSongs.push(...added)
    LogUtils.info(`本地音乐扫描完成: 新增 ${added.length} 首, 总计 ${this.localSongs.length} 首`)
    return added.length
  }

  /** 递归扫描目录 */
  private async scanRecursive(dirPath: string, result: MusicItem[]): Promise<void> {
    try {
      const files = fileIo.listFileSync(dirPath)
      for (const file of files) {
        const fullPath = `${dirPath}/${file}`
        try {
          const stat = fileIo.statSync(fullPath)
          if (stat.isDirectory()) {
            await this.scanRecursive(fullPath, result)
          } else if (this.isAudioFile(file)) {
            const song = this.createMusicItemSync(fullPath, file)
            if (song) result.push(song)
          }
        } catch (err) {
          // 跳过无法访问的文件
        }
      }
    } catch (err) {
      LogUtils.warn(`无法访问目录: ${dirPath}`)
    }
  }

  /** 判断是否为音频文件 */
  private isAudioFile(fileName: string): boolean {
    const lower = fileName.toLowerCase()
    return this.supportedExts.some(ext => lower.endsWith(ext))
  }

  /** 扫描指定文件夹（含子目录递归），并解析音频元数据（标题/歌手/专辑/时长/封面） */
  async scanDirectoryWithMetadata(dirPath: string): Promise<number> {
    LogUtils.info(`开始扫描本地音乐(带元数据): ${dirPath}`)
    const newSongs: MusicItem[] = []
    try {
      await this.scanRecursiveWithMetadata(dirPath, newSongs)
    } catch (err) {
      LogUtils.error('扫描目录失败', JSON.stringify(err))
    }

    const existingIds = new Set(this.localSongs.map(s => s.songmid))
    const added = newSongs.filter(s => !existingIds.has(s.songmid))
    this.localSongs.push(...added)
    LogUtils.info(`本地音乐扫描完成: 新增 ${added.length} 首, 总计 ${this.localSongs.length} 首`)
    return added.length
  }

  /** 递归扫描目录（带元数据解析） */
  private async scanRecursiveWithMetadata(dirPath: string, result: MusicItem[]): Promise<void> {
    try {
      const files = fileIo.listFileSync(dirPath)
      for (const file of files) {
        const fullPath = `${dirPath}/${file}`
        try {
          const stat = fileIo.statSync(fullPath)
          if (stat.isDirectory()) {
            await this.scanRecursiveWithMetadata(fullPath, result)
          } else if (this.isAudioFile(file)) {
            const song = await this.createMusicItemWithMetadata(fullPath, file)
            if (song) result.push(song)
          }
        } catch (err) {
          // 跳过无法访问的文件
        }
      }
    } catch (err) {
      LogUtils.warn(`无法访问目录: ${dirPath}`)
    }
  }

  /** 用 AVMetadataExtractor 解析音频元数据创建 MusicItem（标题/歌手/专辑/时长/封面） */
  private async createMusicItemWithMetadata(filePath: string, fileName: string): Promise<MusicItem | null> {
    let fd: fileIo.File | null = null
    let extractor: media.AVMetadataExtractor | null = null
    try {
      fd = fileIo.openSync(filePath, fileIo.OpenMode.READ_ONLY)
      const stat = fileIo.statSync(filePath)

      let title = ''
      let singer = ''
      let album = ''
      let interval = 0
      let imgUrl = ''

      try {
        extractor = await media.createAVMetadataExtractor()
        extractor.fdSrc = { fd: fd.fd, offset: 0, length: stat.size }
        const metadata = await extractor.fetchMetadata()
        title = metadata.title ?? ''
        singer = metadata.artist ?? ''
        album = metadata.album ?? ''
        interval = Number(metadata.duration ?? 0)
        try {
          const cover = await extractor.fetchAlbumCover()
          if (cover) {
            imgUrl = await this.saveAlbumCover(cover, filePath)
          }
        } catch (coverErr) {
          // 无内嵌封面，忽略
        }
      } catch (metaErr) {
        LogUtils.warn(`元数据解析失败: ${fileName}`)
      }

      // 元数据缺失时回退文件名解析 "歌手 - 歌名"
      const dotIndex = fileName.lastIndexOf('.')
      const baseName = dotIndex > 0 ? fileName.substring(0, dotIndex) : fileName
      if (!title) {
        title = baseName
        const dashIndex = baseName.indexOf(' - ')
        if (dashIndex > 0) {
          singer = baseName.substring(0, dashIndex).trim()
          title = baseName.substring(dashIndex + 3).trim()
        }
      }
      if (!singer) singer = '未知歌手'
      if (!album) album = '本地音乐'

      // 查找同目录下的 .lrc 歌词文件
      const lrcPath = filePath.replace(/\.[^.]+$/, '.lrc')

      return {
        songmid: `local_${filePath}`,
        name: title,
        singer: singer,
        albumName: album,
        interval: interval,
        imgUrl: imgUrl,
        lyricUrl: lrcPath,
        source: SourceType.LOCAL,
        types: {
          '320k': {
            url: filePath.startsWith('file://') ? filePath : `file://${filePath}`,
            size: stat.size,
            br: 320000
          }
        }
      }
    } catch (err) {
      LogUtils.warn(`无法读取音乐文件: ${fileName}`)
      return null
    } finally {
      if (extractor) {
        try { extractor.release() } catch (e) { /* 忽略 */ }
      }
      if (fd) {
        try { fileIo.closeSync(fd) } catch (e) { /* 忽略 */ }
      }
    }
  }

  /** 将内嵌封面保存到沙箱 filesDir/covers/，返回 file:// 路径 */
  private async saveAlbumCover(pixelMap: image.PixelMap, filePath: string): Promise<string> {
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
      LogUtils.warn('保存封面失败', JSON.stringify(err))
      return ''
    }
  }

  /** 从文件路径创建 MusicItem */
  private createMusicItemSync(filePath: string, fileName: string): MusicItem | null {
    try {
      // 解析文件名：去除扩展名
      const dotIndex = fileName.lastIndexOf('.')
      const baseName = dotIndex > 0 ? fileName.substring(0, dotIndex) : fileName

      // 尝试从文件名解析 "歌手 - 歌名" 格式
      let singer = '未知歌手'
      let name = baseName
      const dashIndex = baseName.indexOf(' - ')
      if (dashIndex > 0) {
        singer = baseName.substring(0, dashIndex).trim()
        name = baseName.substring(dashIndex + 3).trim()
      }

      // 查找同目录下的 .lrc 歌词文件
      const lrcPath = filePath.replace(/\.[^.]+$/, '.lrc')

      return {
        songmid: `local_${filePath}`,
        name: name,
        singer: singer,
        albumName: '本地音乐',
        interval: 0,
        imgUrl: '',
        lyricUrl: lrcPath,
        source: SourceType.LOCAL,
        types: {
          '320k': {
            url: `file://${filePath}`,
            size: 0,
            br: 320000
          }
        }
      }
    } catch (err) {
      LogUtils.warn(`无法读取音乐文件: ${fileName}`)
      return null
    }
  }

  /** 读取文本文件内容 */
  private async readTextFile(filePath: string): Promise<string> {
    const normalized = filePath.replace('file://', '')
    try {
      const fdFile = fileIo.openSync(normalized, fileIo.OpenMode.READ_ONLY)
      const stat = fileIo.statSync(normalized)
      const buf = new ArrayBuffer(stat.size)
      fileIo.readSync(fdFile.fd, buf)
      fileIo.closeSync(fdFile)
      return ''
    } catch (err) {
      LogUtils.error('读取文件失败', filePath)
      return ''
    }
  }

  /**
   * 从文件选择器导入音频文件（uri 列表）
   * 文件选择器返回的 uri 具有临时访问权限，可直接读取
   * @param uriList DocumentViewPicker 返回的文件 uri 数组
   */
  async importFiles(uriList: string[]): Promise<number> {
    if (!uriList || uriList.length === 0) return 0
    LogUtils.info(`导入本地音乐文件: ${uriList.length} 个`)

    let addedCount = 0
    const existingIds = new Set(this.localSongs.map(s => s.songmid))

    for (let i = 0; i < uriList.length; i++) {
      const uri = uriList[i]
      try {
        const song = await this.createMusicItemFromUri(uri)
        if (song && !existingIds.has(song.songmid)) {
          this.localSongs.push(song)
          existingIds.add(song.songmid)
          addedCount++
        }
      } catch (err) {
        LogUtils.warn(`导入文件失败: ${uri}`, JSON.stringify(err))
      }
    }

    LogUtils.info(`本地音乐导入完成: 新增 ${addedCount} 首, 总计 ${this.localSongs.length} 首`)
    return addedCount
  }

  /** 从文件 uri 创建 MusicItem */
  private async createMusicItemFromUri(uri: string): Promise<MusicItem | null> {
    try {
      const fdFile = fileIo.openSync(uri, fileIo.OpenMode.READ_ONLY)
      const stat = fileIo.statSync(uri)

      // 从 uri 提取文件名
      const lastSlash = uri.lastIndexOf('/')
      let fileName = lastSlash >= 0 ? uri.substring(lastSlash + 1) : uri
      // 去掉 uri 参数
      const qIdx = fileName.indexOf('?')
      if (qIdx > 0) fileName = fileName.substring(0, qIdx)
      // 去掉扩展名
      const dotIndex = fileName.lastIndexOf('.')
      const baseName = dotIndex > 0 ? fileName.substring(0, dotIndex) : fileName

      // 尝试解析 "歌手 - 歌名" 格式
      let singer = '未知歌手'
      let name = baseName
      const dashIndex = baseName.indexOf(' - ')
      if (dashIndex > 0) {
        singer = baseName.substring(0, dashIndex).trim()
        name = baseName.substring(dashIndex + 3).trim()
      }

      const song: MusicItem = {
        songmid: `local_${uri}`,
        name: name,
        singer: singer,
        albumName: '本地音乐',
        interval: 0,
        imgUrl: '',
        lyricUrl: '',
        source: SourceType.LOCAL,
        types: {
          '320k': {
            url: `file://${uri}`,
            size: stat.size,
            br: 320000
          }
        }
      }
      fileIo.closeSync(fdFile)
      return song
    } catch (err) {
      LogUtils.warn(`无法读取音乐文件: ${uri}`, JSON.stringify(err))
      return null
    }
  }

  /** 获取已扫描的歌曲列表 */
  getSongs(): MusicItem[] {
    return [...this.localSongs]
  }

  /** 清空已扫描的歌曲 */
  clear(): void {
    this.localSongs = []
    LogUtils.info('本地音乐缓存已清空')
  }
}
