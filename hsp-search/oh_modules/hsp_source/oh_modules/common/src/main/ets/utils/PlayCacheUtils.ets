import { fileIo } from '@kit.CoreFileKit'
import { http } from '@kit.NetworkKit'
import { MusicItem } from '../types/MusicTypes'
import { LogUtils } from './LogUtils'
import { StorageUtils } from './StorageUtils'

const CACHE_DIR_NAME = 'playcache'
const META_KEY = 'play_cache_meta'
/** 缓存保留期：7 天（不在任何歌单的缓存到期删除） */
const CACHE_TTL_MS = 7 * 24 * 60 * 60 * 1000

/** 播放缓存条目 */
interface PlayCacheEntry {
  songmid: string
  source: string
  name: string
  filePath: string
  lastPlayed: number
}

/**
 * 播放缓存管理器
 *
 * 将播放过的音频缓存到沙箱 playcache/ 目录：
 * - 播放时后台缓存（不阻塞播放），已缓存则刷新最后播放时间
 * - 启动时清理：不在任何歌单且超过 7 天的缓存删除；在歌单中的缓存永不删除
 */
export class PlayCacheUtils {
  /** 获取缓存目录路径 */
  static getCacheDir(): string {
    const context = getContext()
    return `${context.filesDir}/${CACHE_DIR_NAME}`
  }

  /** 缓存播放过的音频（已有缓存则刷新时间；后台执行，失败静默） */
  static async cacheSong(song: MusicItem, playUrl: string): Promise<void> {
    try {
      if (!playUrl || !playUrl.startsWith('http') || !song || !song.songmid) return
      const dir = PlayCacheUtils.getCacheDir()
      if (!fileIo.accessSync(dir)) {
        fileIo.mkdirSync(dir)
      }
      const fileName = `${PlayCacheUtils.hash(`${song.source}_${song.songmid}`)}.mp3`
      const filePath = `${dir}/${fileName}`

      // 已缓存：仅刷新最后播放时间
      if (fileIo.accessSync(filePath)) {
        await PlayCacheUtils.updateLastPlayed(song, filePath)
        return
      }

      // 下载音频到缓存目录
      const request = http.createHttp()
      const response = await request.request(playUrl, {
        method: http.RequestMethod.GET,
        expectDataType: http.HttpDataType.ARRAY_BUFFER,
        connectTimeout: 30000,
        readTimeout: 120000
      })
      request.destroy()
      if (response.responseCode !== 200 || !response.result) {
        LogUtils.warn(`[播放缓存] 下载失败 HTTP ${response.responseCode}`)
        return
      }
      const file = fileIo.openSync(filePath,
        fileIo.OpenMode.READ_WRITE | fileIo.OpenMode.CREATE | fileIo.OpenMode.TRUNC)
      fileIo.writeSync(file.fd, response.result as ArrayBuffer)
      fileIo.closeSync(file)

      // 记录元信息
      const meta = await StorageUtils.getObject<PlayCacheEntry[]>(META_KEY, [])
      meta.push({
        songmid: song.songmid,
        source: String(song.source),
        name: song.name,
        filePath: filePath,
        lastPlayed: Date.now()
      })
      await StorageUtils.putObject(META_KEY, meta)
      LogUtils.info(`[播放缓存] 已缓存: ${song.name} (${filePath})`)
    } catch (err) {
      LogUtils.warn(`[播放缓存] 缓存失败: ${JSON.stringify(err)}`)
    }
  }

  /** 刷新缓存条目的最后播放时间 */
  private static async updateLastPlayed(song: MusicItem, filePath: string): Promise<void> {
    const meta = await StorageUtils.getObject<PlayCacheEntry[]>(META_KEY, [])
    let found = false
    for (const entry of meta) {
      if (entry.songmid === song.songmid && entry.source === String(song.source)) {
        entry.lastPlayed = Date.now()
        found = true
        break
      }
    }
    if (!found) {
      meta.push({
        songmid: song.songmid,
        source: String(song.source),
        name: song.name,
        filePath: filePath,
        lastPlayed: Date.now()
      })
    }
    await StorageUtils.putObject(META_KEY, meta)
  }

  /**
   * 清理过期缓存：不在任何歌单（isInPlaylist 返回 false）且超过 7 天未播放的缓存删除；
   * 在歌单中的缓存永不删除。
   */
  static async cleanup(isInPlaylist: (songmid: string, source: string) => boolean): Promise<void> {
    try {
      const meta = await StorageUtils.getObject<PlayCacheEntry[]>(META_KEY, [])
      const now = Date.now()
      const kept: PlayCacheEntry[] = []
      let removed = 0
      for (const entry of meta) {
        const expired = now - entry.lastPlayed > CACHE_TTL_MS
        const inList = isInPlaylist(entry.songmid, entry.source)
        if (expired && !inList) {
          try {
            if (fileIo.accessSync(entry.filePath)) {
              fileIo.unlinkSync(entry.filePath)
            }
            removed++
          } catch (e) {
            // 文件删除失败（可能已不存在），忽略
          }
        } else {
          kept.push(entry)
        }
      }
      await StorageUtils.putObject(META_KEY, kept)
      LogUtils.info(`[播放缓存] 清理完成: 删除 ${removed} 条, 保留 ${kept.length} 条`)
    } catch (err) {
      LogUtils.warn(`[播放缓存] 清理异常: ${JSON.stringify(err)}`)
    }
  }

  /** 简单字符串哈希（用于缓存文件名） */
  private static hash(text: string): string {
    let h = 0
    for (let i = 0; i < text.length; i++) {
      h = (h * 31 + text.charCodeAt(i)) >>> 0
    }
    return h.toString(16)
  }
}
