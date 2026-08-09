import { PlayerEngine } from 'hsp_player'
import { SourceManager } from 'hsp_source'
import { PlaylistManager } from 'hsp_playlist'
import { LogUtils } from 'common'

export class AppState {
  async init(): Promise<void> {
    LogUtils.info('应用初始化开始...')
    await SourceManager.getInstance().init()
    await PlaylistManager.getInstance().init()
    LogUtils.info('应用初始化完成')
  }
}
