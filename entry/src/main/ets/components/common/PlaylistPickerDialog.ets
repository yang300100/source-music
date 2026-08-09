import { MusicItem, LocalPlaylist } from 'common'
import { ThemeColors } from '../../theme/ThemeColors'
import { MotionTokens } from '../../theme/MotionTokens'

/**
 * 歌单选择弹窗（自定义毛玻璃底部卡片）
 *
 * 将歌曲添加到选中的歌单，支持新建歌单。
 */
@CustomDialog
export struct PlaylistPickerDialog {
  @StorageLink('themeIsDark') isDark: boolean = true
  controller: CustomDialogController
  /** 目标歌曲 */
  song: MusicItem | null = null
  /** 歌单列表 */
  playlists: LocalPlaylist[] = []
  /** 选择歌单回调（playlistId 或 'new'） */
  onPick: (playlistId: string, event: ClickEvent) => void = (playlistId: string, event: ClickEvent) => {}
  @State entered: boolean = false

  aboutToAppear(): void {
    setTimeout(() => { this.entered = true }, 20)
  }

  private get primaryText(): ResourceColor { return ThemeColors.primaryText(this.isDark) }
  private get secondaryText(): ResourceColor { return ThemeColors.secondaryText(this.isDark) }
  private get dialogBg(): ResourceColor { return this.isDark ? '#701e1a30' : '#88ffffff' }
  private get borderFaint(): ResourceColor { return ThemeColors.dialogBorderFaint(this.isDark) }
  private get rowBg(): ResourceColor { return this.isDark ? '#30181525' : '#90ffffff' }

  build() {
    Column({ space: 4 }) {
      Row({ space: 10 }) {
        Column({ space: 2 }) {
          Text('添加到歌单')
            .fontSize(16).fontWeight(FontWeight.Bold).fontColor(this.primaryText)
          Text(this.song ? `${this.song.name} - ${this.song.singer}` : '')
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

      if (this.playlists.length > 0) {
        ForEach(this.playlists, (pl: LocalPlaylist) => {
          this.PickRow(pl.name, pl.songs.length, pl.id)
        })
      }

      this.PickRow('新建歌单', 0, 'new')
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
  PickRow(name: string, count: number, playlistId: string) {
    Row() {
      Text(name)
        .fontSize(15).fontColor(this.primaryText)
      Blank()
      Text(count > 0 ? `${count} 首` : '')
        .fontSize(12).fontColor(this.secondaryText)
    }
    .width('100%')
    .padding({ left: 16, right: 16, top: 13, bottom: 13 })
    .backgroundColor(this.rowBg)
    .borderRadius(14)
    .stateStyles({
      normal: { .opacity(1).scale({ x: 1, y: 1 }) },
      pressed: { .opacity(0.72).scale({ x: MotionTokens.PRESSED_SCALE, y: MotionTokens.PRESSED_SCALE }) }
    })
    .onClick((event: ClickEvent) => {
      this.onPick(playlistId, event)
      this.controller?.close()
    })
  }
}
