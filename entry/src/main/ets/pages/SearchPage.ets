import { SearchEngine } from 'hsp_search'
import { SourceManager } from 'hsp_source'
import { PlaylistManager } from 'hsp_playlist'
import { PlayerEngine } from 'hsp_player'
import { MusicItem, MusicQuality, LocalPlaylist, HotSearchItem } from 'common'
import { SearchBar } from '../components/search/SearchBar'
import { SourceChipBar, SearchSourceOption } from '../components/search/SourceChipBar'
import { SearchResultList } from '../components/search/SearchResultList'
import { MusicItemView } from '../components/MusicItemView'
import { PlaylistNameDialog } from '../components/PlaylistNameDialog'
import { PlaylistPickerDialog } from '../components/common/PlaylistPickerDialog'
import { ThemeColors } from '../theme/ThemeColors'
import { DialogPosUtils } from '../utils/DialogPosUtils'
import { MotionTokens } from '../theme/MotionTokens'

@Component
export struct SearchContent {
  @StorageLink('themeIsDark') isDark: boolean = true
  @State keyword: string = ''
  @State results: MusicItem[] = []
  @State isLoading: boolean = false
  @State showHistory: boolean = true
  @State history: string[] = []
  @State activeSourceId: string = ''
  @State searchSources: SearchSourceOption[] = []
  @State playHistory: MusicItem[] = []
  @State hotSearch: HotSearchItem[] = []
  private playlistPickerController: CustomDialogController | null = null
  private newPlaylistDialogController: CustomDialogController | null = null

  private get primaryText(): ResourceColor { return ThemeColors.primaryText(this.isDark) }
  private get secondaryText(): ResourceColor { return ThemeColors.secondaryText(this.isDark) }

  aboutToAppear(): void {
    SearchEngine.getHistory().then((h: string[]) => { this.history = h })
    SearchEngine.getHotSearch().then((h: HotSearchItem[]) => { this.hotSearch = h })
    SourceManager.getInstance().getSearchSources().then((sources) => {
      const list: SearchSourceOption[] = []
      for (const source of sources) {
        const opt: SearchSourceOption = { id: source.info.id, name: source.info.name }
        list.push(opt)
      }
      this.searchSources = list
    })
    this.activeSourceId = ''
    PlayerEngine.getInstance().getPlayHistory().then((h: MusicItem[]) => {
      this.playHistory = h.slice(0, 10)
    })
  }

  build() {
    Column() {
      SearchBar({
        keyword: this.keyword,
        onKeywordChange: (value: string) => { this.keyword = value; this.showHistory = !value },
        onSearch: () => { this.doSearch() }
      })

      SourceChipBar({
        options: this.searchSources,
        activeSourceId: this.activeSourceId,
        onSourceChange: (sourceId: string) => {
          this.activeSourceId = sourceId
          if (this.keyword.trim()) { this.doSearch() }
        }
      })

      if (this.showHistory) {
        Scroll() {
          Column() {
            if (this.hotSearch.length > 0) {
              Row() {
                Text('热搜榜').fontSize(14).fontColor(this.secondaryText)
              }
              .width('100%').padding(16)

              Flex({ wrap: FlexWrap.Wrap }) {
                ForEach(this.hotSearch.slice(0, 15), (item: HotSearchItem, index: number) => {
                  Text(`${index + 1}. ${item.label}`)
                    .fontSize(13)
                    .fontColor(this.isDark ? '#a898c0' : '#5a5078')
                    .backgroundColor(this.isDark ? '#30181525' : '#90ffffff')
                    .padding({ left: 12, right: 12, top: 6, bottom: 6 })
                    .borderRadius(14)
                    .margin({ left: 12, bottom: 8 })
                    .onClick(() => {
                      this.keyword = item.value
                      this.doSearch()
                    })
                })
              }
              .width('100%')
              .padding({ bottom: 4 })
            }

            Row() {
              Text('搜索历史').fontSize(14).fontColor(this.secondaryText)
              Blank()
              Text('清除').fontSize(12).fontColor('#e86090')
                .onClick(() => { SearchEngine.clearHistory(); this.history = [] })
            }
            .width('100%').padding(16)

            ForEach(this.history, (keyword: string) => {
              Row() {
                Text(keyword).fontSize(14).fontColor(this.isDark ? '#a898c0' : '#5a5078')
              }
              .width('100%')
              .padding({ left: 16, top: 10, bottom: 10 })
              .onClick(() => { this.keyword = keyword; this.doSearch() })
            })

            if (this.playHistory.length > 0) {
              Row() {
                Text('最近播放').fontSize(14).fontColor(this.secondaryText)
              }
              .width('100%').padding(16)

              ForEach(this.playHistory.slice(0, 10), (song: MusicItem) => {
                Row() {
                  MusicItemView({
                    song: song,
                    queueSongs: this.playHistory,
                    showSource: true
                  })
                }
                .width('100%')
              })
            }
          }
          .width('100%')
        }
        .width('100%').layoutWeight(1)
        .scrollBar(BarState.Off)
        .align(Alignment.Top)
        .transition(TransitionEffect.OPACITY.animation({ duration: MotionTokens.PAGE, curve: Curve.EaseOut })
          .combine(TransitionEffect.translate({ x: 0, y: 12 })
            .animation({ duration: MotionTokens.PAGE, curve: Curve.FastOutSlowIn })))
      } else if (this.isLoading) {
        Column({ space: 12 }) {
          LoadingProgress().color('#b388ff').width(40).height(40)
          Text('正在搜索...').fontSize(12).fontColor(this.secondaryText)
        }
        .width('100%').height('100%').justifyContent(FlexAlign.Center)
        .transition(TransitionEffect.OPACITY.animation({ duration: MotionTokens.NORMAL, curve: Curve.EaseOut })
          .combine(TransitionEffect.scale({ x: 0.92, y: 0.92 })
            .animation({ duration: MotionTokens.NORMAL, curve: Curve.FastOutSlowIn })))
      } else if (this.results.length === 0) {
        Column() {
          Text('未找到相关歌曲').fontSize(15).fontColor(this.secondaryText)
        }
        .width('100%').height('100%').justifyContent(FlexAlign.Center)
        .transition(TransitionEffect.OPACITY.animation({ duration: MotionTokens.NORMAL, curve: Curve.EaseOut })
          .combine(TransitionEffect.translate({ x: 0, y: 10 })
            .animation({ duration: MotionTokens.NORMAL, curve: Curve.FastOutSlowIn })))
      } else {
        SearchResultList({
          results: this.results,
          onAddToPlaylist: (song: MusicItem, event: ClickEvent) => { this.addToPlaylist(song, event) }
        })
        .layoutWeight(1)
        .width('100%')
        .transition(TransitionEffect.OPACITY.animation({ duration: MotionTokens.PAGE, curve: Curve.EaseOut })
          .combine(TransitionEffect.translate({ x: 0, y: 14 })
            .animation({ duration: MotionTokens.PAGE, curve: Curve.FastOutSlowIn })))
      }
    }
    .width('100%').height('100%')
    .clip(true)
  }

  private doSearch(): void {
    if (!this.keyword.trim()) return
    this.isLoading = true
    this.showHistory = false
    SearchEngine.search(this.keyword, 1, MusicQuality.HIGH, this.activeSourceId).then((r: MusicItem[]) => {
      this.results = r; this.isLoading = false
    }).catch(() => { this.results = []; this.isLoading = false })
  }

  private addToPlaylist(song: MusicItem, event: ClickEvent): void {
    const playlists = PlaylistManager.getInstance().getAll()
    const height = Math.min(500, 120 + (playlists.length + 1) * 52)
    const pos = DialogPosUtils.fromClickForDialog(event, 300, height)
    this.playlistPickerController = new CustomDialogController({
      builder: PlaylistPickerDialog({
        song: song,
        playlists: playlists,
        onPick: (playlistId: string, pickEvent: ClickEvent) => {
          if (playlistId === 'new') {
            setTimeout(() => { this.openNewPlaylistDialog(song, pickEvent) }, 200)
            return
          }
          const playlist = playlists.find((item: LocalPlaylist) => item.id === playlistId)
          PlaylistManager.getInstance().addSongs(playlistId, [song]).then((ok: boolean) => {
            this.showToast(ok ? `已添加到「${playlist?.name ?? '歌单'}」` : '添加失败')
          })
        }
      }),
      autoCancel: true,
      alignment: DialogAlignment.TopStart,
      offset: { dx: pos.x, dy: pos.y },
      customStyle: true
    })
    this.playlistPickerController.open()
  }

  private openNewPlaylistDialog(song: MusicItem, event: ClickEvent): void {
    const pos = DialogPosUtils.fromClickForDialog(event, 300, 220)
    this.newPlaylistDialogController = new CustomDialogController({
      builder: PlaylistNameDialog({
        title: '新建歌单并添加',
        confirmText: '创建并添加',
        placeholder: '请输入歌单名称',
        onConfirm: (name: string) => {
          PlaylistManager.getInstance().create(name, '').then((playlist: LocalPlaylist) => {
            PlaylistManager.getInstance().addSongs(playlist.id, [song])
            this.showToast(`已创建「${name}」并添加歌曲`)
          })
        }
      }),
      autoCancel: true,
      alignment: DialogAlignment.TopStart,
      offset: { dx: pos.x, dy: pos.y },
      customStyle: true
    })
    this.newPlaylistDialogController.open()
  }

  private showToast(msg: string): void {
    this.getUIContext().getPromptAction().showToast({ message: msg, duration: 1500 })
  }
}
