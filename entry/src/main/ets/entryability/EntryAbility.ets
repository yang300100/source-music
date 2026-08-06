import { AbilityConstant, ConfigurationConstant, UIAbility, Want } from '@kit.AbilityKit'
import { hilog } from '@kit.PerformanceAnalysisKit'
import { window } from '@kit.ArkUI'
import { StorageUtils, LogUtils } from 'common'
import { PlayerEngine } from 'hsp_player'
import { AppState } from '../model/AppState'

const DOMAIN = 0x0000

export default class EntryAbility extends UIAbility {
  private appState: AppState = new AppState()

  onCreate(want: Want, launchParam: AbilityConstant.LaunchParam): void {
    try {
      this.context.getApplicationContext().setColorMode(
        ConfigurationConstant.ColorMode.COLOR_MODE_NOT_SET
      )
    } catch (err) {
      hilog.error(DOMAIN, 'testTag', 'Failed to set colorMode. Cause: %{public}s', JSON.stringify(err))
    }
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onCreate')
  }

  onDestroy(): void {
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onDestroy')
  }

  async onWindowStageCreate(windowStage: window.WindowStage): Promise<void> {
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onWindowStageCreate')

    try {
      // 初始化持久化存储（需要 context）
      await StorageUtils.init(this.context)
      // 初始化播放器（传入 context 用于创建媒体会话）
      await PlayerEngine.getInstance().init(this.context)
      // 初始化应用全局状态（音源、歌单）
      await this.appState.init()
      AppStorage.setOrCreate('appState', this.appState)
      hilog.info(DOMAIN, 'testTag', '%{public}s', 'AppState 初始化完成')
    } catch (initErr) {
      hilog.error(DOMAIN, 'testTag', '初始化失败: %{public}s', JSON.stringify(initErr))
    }

    windowStage.loadContent('pages/Index', (err) => {
      if (err.code) {
        hilog.error(DOMAIN, 'testTag', 'Failed to load content: %{public}s', JSON.stringify(err))
        return
      }
      hilog.info(DOMAIN, 'testTag', 'Succeeded in loading the content.')
    })
  }

  onWindowStageDestroy(): void {
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onWindowStageDestroy')
  }

  onForeground(): void {
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onForeground')
  }

  onBackground(): void {
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onBackground')
  }
}
