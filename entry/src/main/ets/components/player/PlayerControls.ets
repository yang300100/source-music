import { PlayerStatus, PlayMode } from 'common'
import { ThemeColors } from '../../theme/ThemeColors'

/**
 * 播放控制区组件（NowPlaying 播放栏）
 *
 * 操作行（收藏/下载/更多）+ 渐变进度条 + 时间显示、上一首/播放暂停/下一首、播放模式切换。
 * 进度条为自定义手势（无滑块、无阴影），时间显示在进度条下方左右两侧。
 */
@Component
export struct PlayerControls {
  @StorageLink('themeIsDark') @Watch('onThemeChanged') isDark: boolean = true
  /** 当前进度（毫秒） */
  @Prop @Watch('onProgressChanged') currentProgress: number = 0
  /** 总时长（毫秒） */
  @Prop duration: number = 0
  /** 播放器状态 */
  @Prop status: PlayerStatus = PlayerStatus.IDLE
  /** 播放模式 */
  @Prop mode: PlayMode = PlayMode.SEQUENCE
  /** 拖动进度中标记（外部控制，防止轮询覆盖） */
  @Prop isSeeking: boolean = false
  /** 是否已收藏 */
  @Prop isFavorited: boolean = false
  /** 是否下载中 */
  @Prop isDownloading: boolean = false
  /** 滑动切歌动画中：关闭毛玻璃模糊提升流畅度 */
  @Prop isSwiping: boolean = false
  /** 进度条拖动开始/变化回调 */
  onSeekStart: (seekMs: number) => void = (seekMs: number) => {}
  /** 进度条拖动结束回调（触发实际 seek） */
  onSeekEnd: (seekMs: number) => void = (seekMs: number) => {}
  /** 上一首 */
  onPrev: () => void = () => {}
  /** 播放/暂停 */
  onToggle: () => void = () => {}
  /** 下一首 */
  onNext: () => void = () => {}
  /** 切换播放模式 */
  onModeChange: () => void = () => {}
  /** 切换收藏 */
  onToggleFavorite: () => void = () => {}
  /** 下载歌曲 */
  onDownload: () => void = () => {}
  /** 更多操作（携带点击坐标） */
  onMore: (event: ClickEvent) => void = (event: ClickEvent) => {}

  /** 拖动中标记 */
  private barDragging: boolean = false
  /** 进度条 Canvas 上下文 */
  private barCtx: CanvasRenderingContext2D = new CanvasRenderingContext2D(new RenderingContextSettings(true))
  private barCanvasW: number = 0
  private barCanvasH: number = 0

  private get secondaryText(): ResourceColor { return ThemeColors.secondaryText(this.isDark) }
  private get accentColor(): ResourceColor { return ThemeColors.accentColor() }
  private get panelBg(): ResourceColor { return ThemeColors.panelBg(this.isDark) }
  private get trackColor(): ResourceColor { return this.isDark ? '#26ffffff' : '#16000000' }

  /** 计算进度百分比（0-100），NaN/非法值兜底为 0 */
  private calcPercent(): number {
    const d = this.duration
    const p = this.currentProgress
    if (isNaN(d) || isNaN(p) || !(d > 0)) return 0
    return Math.min(100, Math.max(0, (p / d) * 100))
  }

  /** 进度变化/主题变化时重绘进度条 */
  private onProgressChanged(): void { this.drawBar() }
  private onThemeChanged(): void { this.drawBar() }

  /** Canvas 绘制渐变进度条（轨道 + 粉紫渐变进度） */
  private drawBar(): void {
    if (this.barCanvasW <= 0 || this.barCanvasH <= 0) return
    const ctx = this.barCtx
    ctx.clearRect(0, 0, this.barCanvasW, this.barCanvasH)
    const barH = 4
    const y = (this.barCanvasH - barH) / 2
    // 轨道（未播放段，浅色）
    ctx.fillStyle = this.isDark ? '#12ffffff' : '#0c000000'
    ctx.fillRect(0, y, this.barCanvasW, barH)
    // 粉紫渐变进度
    const fillW = this.barCanvasW * this.calcPercent() / 100
    const segments = 24
    const segW = fillW / segments
    for (let i = 0; i < segments; i++) {
      const t = i / (segments - 1)
      ctx.fillStyle = this.gradientColor(t)
      ctx.fillRect(i * segW, y, segW + 0.5, barH)
    }
  }

  /** 三段粉紫渐变插值：#d9a8ff → #b388ff → #8a5cf5 */
  private gradientColor(t: number): string {
    const from = t < 0.5 ? 0xffd9a8ff : 0xffb388ff
    const to = t < 0.5 ? 0xffb388ff : 0xff8a5cf5
    const local = t < 0.5 ? t * 2 : (t - 0.5) * 2
    return this.lerpColor(from, to, local)
  }

  private lerpColor(from: number, to: number, t: number): string {
    const r1 = (from >> 16) & 0xff
    const g1 = (from >> 8) & 0xff
    const b1 = from & 0xff
    const r2 = (to >> 16) & 0xff
    const g2 = (to >> 8) & 0xff
    const b2 = to & 0xff
    const r = Math.round(r1 + (r2 - r1) * t)
    const g = Math.round(g1 + (g2 - g1) * t)
    const b = Math.round(b1 + (b2 - b1) * t)
    return `#ff${r.toString(16).padStart(2, '0')}${g.toString(16).padStart(2, '0')}${b.toString(16).padStart(2, '0')}`
  }

  build() {
    Column() {
      // 操作行：喜欢 / 下载 / 更多（显示在进度条上方）
      Row({ space: 24 }) {
        Image(this.isFavorited ? $r('app.media.ic_favorite_active') : $r('app.media.ic_favorite'))
          .width(20).height(20)
          .fillColor(this.isFavorited ? this.accentColor : this.secondaryText)
          .onClick(() => { this.onToggleFavorite() })

        Image($r('app.media.ic_download'))
          .width(20).height(20)
          .fillColor(this.isDownloading ? '#e86090' : this.secondaryText)
          .opacity(this.isDownloading ? 0.5 : 1)
          .onClick(() => { this.onDownload() })

        Image($r('app.media.ic_more'))
          .width(20).height(20).fillColor(this.secondaryText)
          .onClick((event: ClickEvent) => { this.onMore(event) })
      }
      .padding({ top: 14, bottom: 10 })
      .justifyContent(FlexAlign.Center)

      // 渐变进度条（Canvas 绘制，左右各保留 5% 间距）
      Canvas(this.barCtx)
        .width('90%')
        .height(28)
        .onReady(() => { this.drawBar() })
        .onAreaChange((oldValue: Area, newValue: Area) => {
          void oldValue
          const w = Number(newValue.width)
          const h = Number(newValue.height)
          if (w > 0 && h > 0) {
            this.barCanvasW = w
            this.barCanvasH = h
            this.drawBar()
          }
        })
        .onTouch((event: TouchEvent) => {
          if (this.barCanvasW <= 0) return
          const touch = event.touches[0]
          if (!touch) return
          const ratio = Math.min(1, Math.max(0, touch.x / this.barCanvasW))
          if (event.type === TouchType.Down) {
            this.barDragging = true
            this.onSeekStart(ratio * this.duration)
          } else if (event.type === TouchType.Move && this.barDragging) {
            this.onSeekStart(ratio * this.duration)
          } else if (event.type === TouchType.Up || event.type === TouchType.Cancel) {
            if (this.barDragging) {
              this.barDragging = false
              this.onSeekEnd(ratio * this.duration)
            }
          }
        })

      // 时间显示：进度条下方左右两侧
      Row() {
        Text(this.formatTime(this.currentProgress))
          .fontSize(11).fontColor(this.secondaryText)
        Blank()
        Text(this.formatTime(this.duration))
          .fontSize(11).fontColor(this.secondaryText)
      }
      .width('90%')
      .padding({ top: 2 })

      Row({ space: 20 }) {
        Image($r('app.media.ic_previous')).width(28).height(28)
          .onClick(() => { this.onPrev() })

        Image(this.status === PlayerStatus.PLAYING ? $r('app.media.ic_pause') : $r('app.media.ic_play'))
          .width(48).height(48)
          .onClick(() => { this.onToggle() })

        Image($r('app.media.ic_next')).width(28).height(28)
          .onClick(() => { this.onNext() })
      }
      .padding({ top: 12, bottom: 4 })
      .justifyContent(FlexAlign.Center)

      Row({ space: 16 }) {
        Image(this.getModeIconRes())
          .width(20).height(20).fillColor(this.accentColor)
          .onClick(() => { this.onModeChange() })
      }
      .width('100%').justifyContent(FlexAlign.Center).padding({ bottom: 8 })
    }
    .width('100%')
    .backgroundColor(this.panelBg)
    .backdropBlur(this.isSwiping ? 0 : 20)
    .borderRadius(16)
  }

  private getModeIconRes(): Resource {
    switch (this.mode) {
      case PlayMode.LOOP_ONE: return $r('app.media.ic_loop_one')
      case PlayMode.LOOP_ALL: return $r('app.media.ic_loop_all')
      case PlayMode.SHUFFLE: return $r('app.media.ic_shuffle')
      default: return $r('app.media.ic_loop_all')
    }
  }

  private formatTime(ms: number): string {
    const totalSec = Math.floor(ms / 1000)
    const min = Math.floor(totalSec / 60)
    const sec = totalSec % 60
    return `${min.toString().padStart(2, '0')}:${sec.toString().padStart(2, '0')}`
  }
}
