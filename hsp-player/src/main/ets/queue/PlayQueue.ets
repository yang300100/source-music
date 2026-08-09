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
    // 随机模式下新队列也要立刻洗牌，让界面展示的顺序就是后续播放顺序。
    if (this.mode === PlayMode.SHUFFLE) {
      this.shuffleForPlayback()
    }
    LogUtils.info(`播放队列已更新: ${this.list.length} 首, 当前第 ${this.currentIndex + 1} 首`)
  }

  /**
   * 一次性生成随机播放顺序。
   * 当前歌曲固定在原索引，其余歌曲使用 Fisher-Yates 洗牌；这样切换模式时不会打断正在播放的歌曲。
   */
  shuffleForPlayback(): void {
    if (this.list.length <= 1) return
    const current = this.getCurrentSong()
    const remaining: MusicItem[] = []
    for (let i = 0; i < this.list.length; i++) {
      if (i !== this.currentIndex) remaining.push(this.list[i])
    }
    for (let i = remaining.length - 1; i > 0; i--) {
      const target = Math.floor(Math.random() * (i + 1))
      const temp = remaining[i]
      remaining[i] = remaining[target]
      remaining[target] = temp
    }
    let remainingIndex = 0
    for (let i = 0; i < this.list.length; i++) {
      if (i === this.currentIndex && current) {
        this.list[i] = current
      } else {
        this.list[i] = remaining[remainingIndex]
        remainingIndex++
      }
    }
    // 换成新数组引用，确保 ArkUI 的播放列表面板能立即观察到顺序变化。
    this.list = [...this.list]
    LogUtils.info(`随机播放顺序已生成: ${this.list.length} 首, 当前索引=${this.currentIndex}`)
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

  /** 移动歌曲位置（拖拽排序），并修正当前播放索引 */
  move(from: number, to: number): void {
    if (from < 0 || from >= this.list.length) return
    if (to < 0 || to >= this.list.length) return
    if (from === to) return
    const item = this.list.splice(from, 1)[0]
    this.list.splice(to, 0, item)
    // 修正当前索引（移动的是当前歌曲或跨过当前歌曲时）
    if (this.currentIndex === from) {
      this.currentIndex = to
    } else if (from < this.currentIndex && to >= this.currentIndex) {
      this.currentIndex--
    } else if (from > this.currentIndex && to <= this.currentIndex) {
      this.currentIndex++
    }
    LogUtils.info(`播放队列排序: ${from} → ${to}, 当前索引=${this.currentIndex}`)
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
        // 顺序已在进入随机模式时一次性洗牌，这里沿可见队列向后播放。
        this.currentIndex = (this.currentIndex + 1) % this.list.length
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

  /** 获取下一首歌曲（不改变当前位置，用于预加载） */
  peekNext(): MusicItem | null {
    if (this.list.length === 0) return null
    switch (this.mode) {
      case PlayMode.LOOP_ONE:
        return this.list[this.currentIndex]
      case PlayMode.SHUFFLE:
        return this.list[(this.currentIndex + 1) % this.list.length]
      case PlayMode.LOOP_ALL:
        return this.list[(this.currentIndex + 1) % this.list.length]
      case PlayMode.SEQUENCE:
      default:
        if (this.currentIndex < this.list.length - 1) {
          return this.list[this.currentIndex + 1]
        }
        return null // 队列末尾
    }
  }

  /** 切到上一首 */
  previous(): MusicItem | null {
    if (this.list.length === 0) return null
    switch (this.mode) {
      case PlayMode.LOOP_ONE:
        return this.list[this.currentIndex]
      case PlayMode.SHUFFLE:
        this.currentIndex = (this.currentIndex - 1 + this.list.length) % this.list.length
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
