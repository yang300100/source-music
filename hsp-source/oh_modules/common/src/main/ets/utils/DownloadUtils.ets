import { http } from '@kit.NetworkKit'
import { fileIo } from '@kit.CoreFileKit'
import { MusicItem } from '../types/MusicTypes'
import { LogUtils } from './LogUtils'
import { StorageUtils } from './StorageUtils'

const STORAGE_KEY_DOWNLOADS = 'download_list'
const MAX_DOWNLOADS = 50

/** 已下载歌曲元信息 */
export class DownloadedSong {
  songmid: string = ''
  name: string = ''
  singer: string = ''
  source: string = ''
  filePath: string = ''
  imgUrl: string = ''
  interval: number = 0
  downloadTime: number = 0
}

/**
 * 下载管理器
 *
 * 将在线歌曲下载到应用沙箱 files/downloads/ 目录，
 * 并维护已下载清单（持久化 Storage）。
 */
export class DownloadUtils {
  /** 获取下载目录路径 */
  static getDownloadDir(): string {
    const context = getContext()
    const filesDir = context.filesDir
    return `${filesDir}/downloads`
  }

  /**
   * 下载歌曲到本地（直接落盘，不弹窗选位置）
   * @returns 成功返回本地文件路径，失败返回空串
   */
  static async downloadToLocal(song: MusicItem, playUrl: string): Promise<string> {
    try {
      if (!playUrl) return ''
      const dir = DownloadUtils.getDownloadDir()
      if (!fileIo.accessSync(dir)) {
        fileIo.mkdirSync(dir)
      }
      const safeName = DownloadUtils.sanitizeFileName(`${song.name} - ${song.singer}`)
      const filePath = `${dir}/${safeName}.mp3`

      const request = http.createHttp()
      const response = await request.request(playUrl, {
        method: http.RequestMethod.GET,
        expectDataType: http.HttpDataType.ARRAY_BUFFER,
        connectTimeout: 30000,
        readTimeout: 60000
      })
      request.destroy()
      if (response.responseCode !== 200 || !response.result) {
        LogUtils.warn(`[下载] HTTP ${response.responseCode}: ${playUrl.substring(0, 80)}`)
        return ''
      }

      const file = fileIo.openSync(filePath, fileIo.OpenMode.READ_WRITE | fileIo.OpenMode.CREATE | fileIo.OpenMode.TRUNC)
      const buffer = response.result as ArrayBuffer
      fileIo.writeSync(file.fd, buffer)
      fileIo.closeSync(file)

      // 更新清单
      await DownloadUtils.addToDownloadList(song, filePath)
      LogUtils.info(`[下载] 成功: ${song.name} - ${song.singer} (${buffer.byteLength} bytes)`)
      return filePath
    } catch (err) {
      LogUtils.error(`[下载] 失败: ${JSON.stringify(err)}`)
      return ''
    }
  }

  /** 获取已下载列表（最新在前） */
  static async getDownloadList(): Promise<DownloadedSong[]> {
    const list = await StorageUtils.getObject<DownloadedSong[]>(STORAGE_KEY_DOWNLOADS, [])
    return list ?? []
  }

  /** 将下载记录加入清单（去重 songmid+source，最新在前，上限 50） */
  private static async addToDownloadList(song: MusicItem, filePath: string): Promise<void> {
    const list = await DownloadUtils.getDownloadList()
    const key = `${song.source}_${song.songmid}`
    const filtered = list.filter(d => `${d.source}_${d.songmid}` !== key)
    const item: DownloadedSong = new DownloadedSong()
    item.songmid = song.songmid
    item.name = song.name
    item.singer = song.singer
    item.source = String(song.source)
    item.filePath = filePath
    item.imgUrl = song.imgUrl ?? ''
    item.interval = song.interval
    item.downloadTime = Date.now()
    filtered.unshift(item)
    const trimmed = filtered.slice(0, MAX_DOWNLOADS)
    await StorageUtils.putObject(STORAGE_KEY_DOWNLOADS, trimmed)
  }

  /** 删除下载记录（含文件） */
  static async removeDownload(songmid: string): Promise<boolean> {
    const list = await DownloadUtils.getDownloadList()
    const target = list.find(d => d.songmid === songmid)
    if (!target) return false
    try {
      if (fileIo.accessSync(target.filePath)) {
        fileIo.unlinkSync(target.filePath)
      }
    } catch (err) {
      LogUtils.warn(`[下载] 删除文件失败: ${JSON.stringify(err)}`)
    }
    const filtered = list.filter(d => d.songmid !== songmid)
    await StorageUtils.putObject(STORAGE_KEY_DOWNLOADS, filtered)
    LogUtils.info(`[下载] 已删除: ${target.name}`)
    return true
  }

  /** 清洗文件名中的非法字符 */
  private static sanitizeFileName(name: string): string {
    const cleaned = name.replace(/[\\/:*?"<>|\s]+/g, '_')
    return cleaned.length > 80 ? cleaned.substring(0, 80) : cleaned
  }
}
