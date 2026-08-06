import { SearchVM } from '../viewmodel/SearchVM'
import { MusicItemView } from '../components/MusicItemView'
import { MusicItem } from 'common'

/**
 * 搜索页面 — 搜索框 + 历史记录 + 搜索结果列表
 */
@Entry
@Component
struct SearchPage {
  @State viewModel: SearchVM = new SearchVM()
  @State showHistory: boolean = true

  aboutToAppear(): void {
    this.viewModel.loadHistory()
  }

  build() {
    Column() {
      // 搜索框
      Row({ space: 8 }) {
        TextInput({ placeholder: '搜索歌曲、歌手...' })
          .layoutWeight(1)
          .fontSize(15)
          .onChange((value: string) => {
            this.viewModel.keyword = value
            this.showHistory = !value
          })
          .onSubmit(() => {
            this.viewModel.search(this.viewModel.keyword)
            this.showHistory = false
          })

        Button('搜索')
          .fontSize(14)
          .onClick(() => {
            this.viewModel.search(this.viewModel.keyword)
            this.showHistory = false
          })
      }
      .padding({ left: 16, right: 16, top: 12, bottom: 12 })

      if (this.showHistory) {
        this.HistoryView()
      } else if (this.viewModel.isLoading) {
        LoadingProgress().color('#89b4fa').width(40).height(40)
      } else {
        this.ResultView()
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor('#1e1e2e')
  }

  @Builder
  HistoryView() {
    Column() {
      Row() {
        Text('搜索历史').fontSize(14).fontColor('#6c7086')
        Blank()
        Text('清除').fontSize(12).fontColor('#f38ba8')
          .onClick(() => this.viewModel.clearHistory())
      }
      .width('100%').padding(16)

      ForEach(this.viewModel.history, (keyword: string) => {
        Row() {
          Text(keyword).fontSize(14).fontColor('#a6adc8')
        }
        .width('100%')
        .padding({ left: 16, top: 10, bottom: 10 })
        .onClick(() => {
          this.viewModel.keyword = keyword
          this.viewModel.search(keyword)
          this.showHistory = false
        })
      })
    }
  }

  @Builder
  ResultView() {
    if (this.viewModel.results.length === 0) {
      Column() {
        Text('未找到相关歌曲').fontSize(15).fontColor('#6c7086')
      }
      .width('100%').height('100%').justifyContent(FlexAlign.Center)
    } else {
      List() {
        ForEach(this.viewModel.results, (song: MusicItem) => {
          ListItem() {
            MusicItemView({ song: song })
          }
        })
      }
      .width('100%')
      .layoutWeight(1)
      .scrollBar(BarState.Off)
    }
  }
}
