import { SearchEngine } from 'hsp_search'
import { SourceManager } from 'hsp_source'
import { PlaylistManager } from 'hsp_playlist'
import { PlayerEngine } from 'hsp_player'
import { MusicItem, MusicQuality, LocalPlaylist, HotSearchItem } from 'common'
import { SearchBar } from '../components/search/SearchBar'
import { SourceChipBar, SearchSourceOption } from '../components/search/SourceChipBar'
import { SearchResultList } from '../components/search/SearchResultList'
import { MusicItemView } from '../components/MusicItemView'
import { ThemeColors } from '../theme/ThemeColors'

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
    PlayerEngine.getInstance().getPlayHistory().then((h: MusicItem[]) => { this.playHistory = h })
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

              ForEach(this.playHistory, (song: MusicItem) => {
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
      } else if (this.isLoading) {
        LoadingProgress().color('#b388ff').width(40).height(40)
      } else if (this.results.length === 0) {
        Column() {
          Text('未找到相关歌曲').fontSize(15).fontColor(this.secondaryText)
        }
        .width('100%').height('100%').justifyContent(FlexAlign.Center)
      } else {
        SearchResultList({
          results: this.results,
          onAddToPlaylist: (song: MusicItem) => { this.addToPlaylist(song) }
        })
      }
    }
    .width('100%').height('100%')
  }

  private doSearch(): void {
    if (!this.keyword.trim()) return
    this.isLoading = true
    this.showHistory = false
    SearchEngine.search(this.keyword, 1, MusicQuality.HIGH, this.activeSourceId).then((r: MusicItem[]) => {
      this.results = r; this.isLoading = false
    }).catch(() => { this.results = []; this.isLoading = false })
  }

  private addToPlaylist(song: MusicItem): void {
    const playlists = PlaylistManager.getInstance().getAll()
    if (playlists.length === 0) {
      PlaylistManager.getInstance().create('默认歌单', '自动创建').then((pl: LocalPlaylist) => {
        PlaylistManager.getInstance().addSongs(pl.id, [song])
        this.showToast('已添加到默认歌单')
      })
    } else {
      PlaylistManager.getInstance().addSongs(playlists[0].id, [song])
      this.showToast(`已添加到「${playlists[0].name}」`)
    }
  }

  private showToast(msg: string): void {
    this.getUIContext().getPromptAction().showToast({ message: msg, duration: 1500 })
  }
}
