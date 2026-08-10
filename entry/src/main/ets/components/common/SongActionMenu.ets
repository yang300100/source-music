import { MusicItem } from 'common'
import { ThemeColors } from '../../theme/ThemeColors'
import { MotionTokens } from '../../theme/MotionTokens'

/**
 * 歌曲操作菜单（自定义毛玻璃弹窗）
 *
 * 通过 actions 数组控制显示哪些操作。支持的操作：
 *   'playlist'    - 添加到歌单
 *   'nextPlay'    - 下一首播放
 *   'favorite'    - 收藏/取消收藏
 *   'download'    - 下载到本地
 *   'share'       - 分享歌曲
 *   'sourceSwitch'- 歌曲换源
 *   'searchSinger'- 搜索该歌手
 *   'searchSong'  - 搜索该歌曲
 *   'copyName'    - 复制歌曲名
 *   'setPosition' - 调整位置（仅歌单场景）
 *   'remove'      - 从歌单/队列移除
 */
@CustomDialog
export struct SongActionMenu {
  @StorageLink('themeIsDark') isDark: boolean = true
  controller: CustomDialogController
  /** 当前歌曲 */
  song: MusicItem | null = null
  /** 是否已收藏 */
  isFavorited: boolean = false
  /** 要显示的操作列表 */
  actions: string[] = ['playlist', 'nextPlay', 'favorite', 'download', 'share']
  /** 操作回调 */
  onAction: (action: string, event: ClickEvent) => void = (action: string, event: ClickEvent) => {}
  @State entered: boolean = false

  aboutToAppear(): void {
    setTimeout(() => { this.entered = true }, 20)
  }

  private get primaryText(): ResourceColor { return ThemeColors.primaryText(this.isDark) }
  private get secondaryText(): ResourceColor { return ThemeColors.secondaryText(this.isDark) }
  private get dialogBg(): ResourceColor { return this.isDark ? '#701e1a30' : '#88ffffff' }
  private get borderFaint(): ResourceColor { return ThemeColors.dialogBorderFaint(this.isDark) }
  private get rowBg(): ResourceColor { return this.isDark ? '#30181525' : '#90ffffff' }
  private get dangerColor(): ResourceColor { return '#e86090' }

  /** 操作标签与样式映射 */
  private actionLabel(action: string): string {
    switch (action) {
      case 'playlist': return '添加到歌单'
      case 'nextPlay': return '下一首播放'
      case 'favorite': return this.isFavorited ? '取消收藏' : '收藏'
      case 'download': return '下载到本地'
      case 'share': return '分享歌曲'
      case 'sourceSwitch': return '歌曲换源'
      case 'searchSinger': return '搜索该歌手'
      case 'searchSong': return '搜索该歌曲'
      case 'copyName': return '复制歌曲名'
      case 'setPosition': return '调整位置'
      case 'remove': return '从列表中移除'
      default: return action
    }
  }

  private isDanger(action: string): boolean {
    return action === 'remove'
  }

  build() {
    Column({ space: 4 }) {
      // 头部：歌曲名 + 歌手
      Row({ space: 10 }) {
        Column({ space: 2 }) {
          Text(this.song ? this.song.name : '未知歌曲')
            .fontSize(16).fontWeight(FontWeight.Bold).fontColor(this.primaryText)
            .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
          Text(this.song ? this.song.singer : '')
            .fontSize(12).fontColor(this.secondaryText)
            .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
        }
        .alignItems(HorizontalAlign.Start)
        .layoutWeight(1)

        Text('✕')
          .fontSize(16).fontColor(this.secondaryText)
          .padding(6)
          .onClick(() => { this.controller?.close() })
      }
      .width('100%')
      .padding({ left: 20, right: 12, top: 20, bottom: 8 })

      ForEach(this.actions, (action: string) => {
        this.ActionRow(this.actionLabel(action), this.isDanger(action), (event: ClickEvent) => {
          this.onAction(action, event)
          this.controller?.close()
        })
      }, (action: string) => action)
    }
    .width(300)
    .padding({ left: 8, right: 8, bottom: 16 })
    .backgroundColor(this.dialogBg)
    .linearGradient({
      angle: 180,
      colors: [['#22ffffff', 0.0], ['#00000000', 0.4], ['#00000000', 0.75], ['#10b388ff', 1.0]]
    })
    .backgroundEffect({
      radius: 32,
      saturation: 1.35,
      brightness: 1.0,
      adaptiveColor: AdaptiveColor.AVERAGE
    })
    .borderRadius({ topLeft: 28, topRight: 28, bottomLeft: 20, bottomRight: 20 })
    .border({ width: 0.5, color: this.borderFaint })
    .shadow({ radius: 30, color: '#60b388ff', offsetX: 0, offsetY: 4 })
    .opacity(this.entered ? 1 : 0)
    .scale({ x: this.entered ? 1 : 0.92, y: this.entered ? 1 : 0.92 })
    .translate({ x: 0, y: this.entered ? 0 : 12 })
    .animation({ duration: MotionTokens.PAGE, curve: Curve.FastOutSlowIn })
  }

  @Builder
  ActionRow(label: string, danger: boolean, action: (event: ClickEvent) => void) {
    Row() {
      Text(label)
        .fontSize(15).fontColor(danger ? this.dangerColor : this.primaryText)
      Blank()
      Text('›')
        .fontSize(15).fontColor(this.secondaryText)
    }
    .width('100%')
    .padding({ left: 16, right: 16, top: 13, bottom: 13 })
    .backgroundColor(this.rowBg)
    .borderRadius(14)
    .stateStyles({
      normal: { .opacity(1).scale({ x: 1, y: 1 }) },
      pressed: { .opacity(0.72).scale({ x: MotionTokens.PRESSED_SCALE, y: MotionTokens.PRESSED_SCALE }) }
    })
    .onClick((event: ClickEvent) => { action(event) })
  }
}
