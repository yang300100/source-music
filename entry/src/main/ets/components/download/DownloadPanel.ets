import { DownloadedSong, DownloadUtils, SourceType, MusicItem } from 'common'
import { ThemeColors } from '../../theme/ThemeColors'

/**
 * 已下载歌曲面板
 *
 * 展示本地已下载歌曲（封面/歌名/歌手），支持播放与删除。
 * 自持数据：进入面板即加载，3 秒轮询刷新（下载完成后自动出现）。
 */
@Component
export struct DownloadPanel {
  @StorageLink('themeIsDark') isDark: boolean = true
  /** 播放已下载歌曲 */
  onPlay: (song: MusicItem) => void = (song: MusicItem) => {}
  @State downloads: DownloadedSong[] = []
  private refreshTimer: number = -1

  private get primaryText(): ResourceColor { return ThemeColors.primaryText(this.isDark) }
  private get secondaryText(): ResourceColor { return ThemeColors.secondaryText(this.isDark) }

  aboutToAppear(): void {
    this.refreshList()
    this.refreshTimer = setInterval(() => {
      this.refreshList()
    }, 3000)
  }

  aboutToDisappear(): void {
    if (this.refreshTimer >= 0) {
      clearInterval(this.refreshTimer)
      this.refreshTimer = -1
    }
  }

  private refreshList(): void {
    DownloadUtils.getDownloadList().then((list: DownloadedSong[]) => {
      this.downloads = list
    }).catch(() => {})
  }

  private deleteDownload(songmid: string): void {
    DownloadUtils.removeDownload(songmid).then((ok: boolean) => {
      if (ok) {
        this.refreshList()
      }
    })
  }

  build() {
    Column() {
      Row() {
        Text('已下载')
          .fontSize(16).fontWeight(FontWeight.Bold).fontColor(this.primaryText)
        Blank()
        Text(`${this.downloads.length} 首`).fontSize(12).fontColor(this.secondaryText)
      }
      .width('100%')
      .padding({ left: 16, right: 16, top: 16, bottom: 8 })

      if (this.downloads.length === 0) {
        Column() {
          Text('暂无下载').fontSize(14).fontColor(this.secondaryText)
        }
        .width('100%').height('100%').justifyContent(FlexAlign.Center)
      } else {
        List({ space: 2 }) {
          ForEach(this.downloads, (item: DownloadedSong) => {
            ListItem() {
              Row({ space: 10 }) {
                if (item.imgUrl) {
                  Image(item.imgUrl)
                    .width(40).height(40).borderRadius(8)
                    .objectFit(ImageFit.Cover).alt($r('app.media.startIcon'))
                } else {
                  Image($r('app.media.startIcon'))
                    .width(40).height(40).borderRadius(8)
                    .objectFit(ImageFit.Cover).opacity(0.2)
                }
                Column({ space: 2 }) {
                  Text(item.name)
                    .fontSize(13).fontColor(this.primaryText)
                    .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
                  Text(item.singer)
                    .fontSize(11).fontColor(this.secondaryText)
                    .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
                }
                .layoutWeight(1)

                Image($r('app.media.ic_delete')).width(14).height(14).fillColor(this.secondaryText)
                  .onClick(() => { this.deleteDownload(item.songmid) })
              }
              .width('100%')
              .padding({ left: 12, right: 12, top: 8, bottom: 8 })
              .borderRadius(10)
              .onClick(() => { this.onPlay(this.toMusicItem(item)) })
            }
          })
        }
        .width('100%').layoutWeight(1)
        .scrollBar(BarState.Off)
        .padding({ left: 4, right: 4 })
      }
    }
    .width('100%')
    .height('100%')
  }

  private toMusicItem(item: DownloadedSong): MusicItem {
    const source = DownloadPanel.parseSourceType(item.source)
    const song: MusicItem = {
      songmid: item.songmid,
      name: item.name,
      singer: item.singer,
      albumName: '',
      interval: item.interval,
      imgUrl: item.imgUrl,
      lyricUrl: '',
      source: source,
      types: {
        '128k': { url: `file://${item.filePath}`, size: 0, br: 128000 }
      }
    }
    return song
  }

  private static parseSourceType(source: string): SourceType {
    switch (source) {
      case 'kg': return SourceType.KG
      case 'wy': return SourceType.WY
      case 'tx': return SourceType.TX
      case 'kw': return SourceType.KW
      case 'mg': return SourceType.MG
      case 'local': return SourceType.LOCAL
      default: return SourceType.CUSTOM
    }
  }
}
