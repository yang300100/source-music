import { MusicItem, PlayMode, LogUtils } from 'common'

/**
 * 播放队列管理器
 *
 * 维护当前播放列表、索引、播放模式。
 * 支持搜索结果临时队列 / 歌单队列 / 本地文件队列三种来源。
 */
export class PlayQueue {
  list: MusicItem[] = []
  currentIndex: number = -1
  mode: PlayMode = PlayMode.SEQUENCE

  /** 一次性替换整个队列并从头播放 */
  replaceList(songs: MusicItem[], startIndex: number = 0): void {
    this.list = [...songs]
    this.currentIndex = Math.min(startIndex, this.list.length - 1)
    LogUtils.info(`播放队列已更新: ${this.list.length} 首, 当前第 ${this.currentIndex + 1} 首`)
  }

  /** 追加歌曲到队列末尾 */
  appendSongs(songs: MusicItem[]): void {
    this.list.push(...songs)
    LogUtils.info(`已添加 ${songs.length} 首到队列`)
  }

  /** 在指定位置插入歌曲 */
  insertAt(song: MusicItem, index: number): void {
    this.list.splice(index, 0, song)
    if (this.currentIndex >= index) {
      this.currentIndex++
    }
  }

  /** 移除指定位置的歌曲 */
  removeAt(index: number): MusicItem | null {
    if (index < 0 || index >= this.list.length) return null
    const removed = this.list.splice(index, 1)[0]
    if (index < this.currentIndex) {
      this.currentIndex--
    } else if (index === this.currentIndex && this.list.length === 0) {
      this.currentIndex = -1
    }
    return removed
  }

  /** 获取当前歌曲 */
  getCurrentSong(): MusicItem | null {
    if (this.currentIndex < 0 || this.currentIndex >= this.list.length) return null
    return this.list[this.currentIndex]
  }

  /** 切到下一首 */
  next(): MusicItem | null {
    if (this.list.length === 0) return null
    switch (this.mode) {
      case PlayMode.LOOP_ONE:
        return this.list[this.currentIndex]
      case PlayMode.SHUFFLE:
        this.currentIndex = Math.floor(Math.random() * this.list.length)
        return this.list[this.currentIndex]
      case PlayMode.LOOP_ALL:
        this.currentIndex = (this.currentIndex + 1) % this.list.length
        return this.list[this.currentIndex]
      case PlayMode.SEQUENCE:
      default:
        if (this.currentIndex < this.list.length - 1) {
          this.currentIndex++
          return this.list[this.currentIndex]
        }
        return null // 播放完毕
    }
  }

  /** 切到上一首 */
  previous(): MusicItem | null {
    if (this.list.length === 0) return null
    switch (this.mode) {
      case PlayMode.LOOP_ONE:
        return this.list[this.currentIndex]
      case PlayMode.SHUFFLE:
        this.currentIndex = Math.floor(Math.random() * this.list.length)
        return this.list[this.currentIndex]
      default:
        if (this.currentIndex > 0) {
          this.currentIndex--
          return this.list[this.currentIndex]
        }
        return this.list[this.currentIndex]
    }
  }

  /** 跳转到指定索引 */
  skipTo(index: number): MusicItem | null {
    if (index < 0 || index >= this.list.length) return null
    this.currentIndex = index
    return this.list[index]
  }

  /** 清空队列 */
  clear(): void {
    this.list = []
    this.currentIndex = -1
  }

  /** 队列总长度 */
  get length(): number {
    return this.list.length
  }

  /** 是否为空 */
  get isEmpty(): boolean {
    return this.list.length === 0
  }
}
