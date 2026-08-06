import { MusicItem } from 'common'
import { SearchEngine } from 'hsp_search'

/**
 * 搜索页 ViewModel — 管理搜索状态和搜索历史
 */
@Observed
export class SearchVM {
  keyword: string = ''
  results: MusicItem[] = []
  isLoading: boolean = false
  history: string[] = []

  async search(query: string): Promise<void> {
    if (!query.trim()) return
    this.isLoading = true
    this.keyword = query
    try {
      this.results = await SearchEngine.search(query)
    } catch (err) {
      this.results = []
    } finally {
      this.isLoading = false
    }
  }

  async loadHistory(): Promise<void> {
    this.history = await SearchEngine.getHistory()
  }

  async clearHistory(): Promise<void> {
    await SearchEngine.clearHistory()
    this.history = []
  }
}
