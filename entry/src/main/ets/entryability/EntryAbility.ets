import { AbilityConstant, ConfigurationConstant, UIAbility, Want, Configuration } from '@kit.AbilityKit'
import { hilog } from '@kit.PerformanceAnalysisKit'
import { window } from '@kit.ArkUI'
import { StorageUtils, LogUtils } from 'common'
import { PlayerEngine } from 'hsp_player'
import { SearchEngine } from 'hsp_search'
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
    // 处理桌面快捷方式参数（首次启动）
    this.handleShortcutWant(want)
  }

  onDestroy(): void {
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onDestroy')
  }

  onNewWant(want: Want, launchParam: AbilityConstant.LaunchParam): void {
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onNewWant')
    // 处理桌面快捷方式参数（应用已运行时再次拉起）
    this.handleShortcutWant(want)
  }

  /** 解析桌面快捷方式参数并存入 AppStorage（Index 据此切换面板） */
  private handleShortcutWant(want: Want): void {
    try {
      const params = want.parameters
      if (!params) return
      const shortCutKey = params['shortCutKey'] as string
      if (shortCutKey === 'search' || shortCutKey === 'favorites' || shortCutKey === 'recent') {
        AppStorage.setOrCreate('shortCutKey', shortCutKey)
        hilog.info(DOMAIN, 'testTag', '快捷方式触发: %{public}s', shortCutKey)
      }
    } catch (err) {
      hilog.error(DOMAIN, 'testTag', '快捷方式解析失败: %{public}s', JSON.stringify(err))
    }
  }

  async onWindowStageCreate(windowStage: window.WindowStage): Promise<void> {
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onWindowStageCreate')

    try {
      await StorageUtils.init(this.context)
      await PlayerEngine.getInstance().init(this.context)
      await this.appState.init()
      AppStorage.setOrCreate('appState', this.appState)
      hilog.info(DOMAIN, 'testTag', '%{public}s', 'AppState 初始化完成')
    } catch (initErr) {
      hilog.error(DOMAIN, 'testTag', '初始化失败: %{public}s', JSON.stringify(initErr))
    }

    // 在页面加载前应用主题设置（自动主题时跟随系统，否则用存储设置），避免首次渲染先深色后变浅色
    try {
      const autoTheme = await StorageUtils.getString('auto_theme', 'false')
      const isAuto = autoTheme === 'true'
      const savedTheme = await StorageUtils.getString('theme_mode', 'dark')
      if (isAuto) {
        // 自动主题：先设为跟随系统，再读取真实系统颜色模式
        this.context.getApplicationContext().setColorMode(ConfigurationConstant.ColorMode.COLOR_MODE_NOT_SET)
        AppStorage.setOrCreate('autoTheme', true)
      } else {
        AppStorage.setOrCreate('autoTheme', false)
      }
      // 系统当前颜色模式存入 AppStorage（供设置页/Index 读取）
      const sysColorMode = this.context.config.colorMode
      AppStorage.setOrCreate('systemColorMode', sysColorMode)
      let isDark = savedTheme !== 'light'
      if (isAuto) {
        // 跟随系统颜色模式
        isDark = sysColorMode !== ConfigurationConstant.ColorMode.COLOR_MODE_LIGHT
      }
      AppStorage.setOrCreate('themeMode', isDark ? 'dark' : 'light')
      AppStorage.setOrCreate('themeIsDark', isDark)
      // 自动主题时跟随系统（NOT_SET），否则固定模式
      this.context.getApplicationContext().setColorMode(
        isAuto
          ? ConfigurationConstant.ColorMode.COLOR_MODE_NOT_SET
          : (isDark
            ? ConfigurationConstant.ColorMode.COLOR_MODE_DARK
            : ConfigurationConstant.ColorMode.COLOR_MODE_LIGHT)
      )
      hilog.info(DOMAIN, 'testTag', '启动时应用主题: %{public}s (auto=%{public}s)', isDark ? 'dark' : 'light', isAuto ? 'true' : 'false')
    } catch (themeErr) {
      hilog.error(DOMAIN, 'testTag', 'Failed to apply theme. Cause: %{public}s', JSON.stringify(themeErr))
    }

    // 启动时预加载热搜榜（后台异步，不阻塞页面加载；搜索页直接读缓存秒显）
    SearchEngine.getHotSearch().then(() => {
      hilog.info(DOMAIN, 'testTag', '%{public}s', '热搜榜预加载完成')
    }).catch(() => {})

    // 恢复上次播放队列（歌曲列表 + 当前索引），不自动播放（由 auto_play 设置决定）
    PlayerEngine.getInstance().restoreQueueState().then((ok: boolean) => {
      hilog.info(DOMAIN, 'testTag', '播放队列恢复: %{public}s', ok ? '成功' : '无队列')
    }).catch(() => {})

    try {
      const mainWindow = windowStage.getMainWindowSync()
      mainWindow.setWindowBackgroundColor('#00000000')
      mainWindow.setWindowLayoutFullScreen(true)
      const isDark = AppStorage.get<boolean>('themeIsDark') ?? true
      const barContentColor = isDark ? '#e8e0f8' : '#1a1525'
      mainWindow.setWindowSystemBarProperties({
        statusBarColor: '#00000000',
        statusBarContentColor: barContentColor,
        navigationBarColor: '#00000000',
        navigationBarContentColor: barContentColor
      })
      const topAvoid = mainWindow.getWindowAvoidArea(window.AvoidAreaType.TYPE_SYSTEM)
      AppStorage.setOrCreate('topAvoidHeight', topAvoid.topRect.height)
      const bottomAvoid = mainWindow.getWindowAvoidArea(window.AvoidAreaType.TYPE_NAVIGATION_INDICATOR)
      AppStorage.setOrCreate('bottomAvoidHeight', bottomAvoid.bottomRect.height)
    } catch (bgErr) {
      hilog.error(DOMAIN, 'testTag', 'Failed to set window immersive: %{public}s', JSON.stringify(bgErr))
    }

    windowStage.loadContent('pages/Index', (err) => {
      if (err.code) {
        hilog.error(DOMAIN, 'testTag', 'Failed to load content: %{public}s', JSON.stringify(err))
        return
      }
      hilog.info(DOMAIN, 'testTag', 'Succeeded in loading the content.')
    })

    // setColorMode(NOT_SET) 异步生效：延迟重新读取系统颜色模式校正自动主题
    setTimeout(() => {
      try {
        const isAuto = AppStorage.get<boolean>('autoTheme') ?? false
        if (isAuto) {
          const sysMode = this.context.config.colorMode
          AppStorage.setOrCreate('systemColorMode', sysMode)
          const isDark = sysMode !== ConfigurationConstant.ColorMode.COLOR_MODE_LIGHT
          AppStorage.setOrCreate('themeMode', isDark ? 'dark' : 'light')
          AppStorage.setOrCreate('themeIsDark', isDark)
        }
      } catch (err) {
        hilog.error(DOMAIN, 'testTag', '延迟主题校正失败: %{public}s', JSON.stringify(err))
      }
    }, 500)
  }

  onWindowStageDestroy(): void {
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onWindowStageDestroy')
  }

  onForeground(): void {
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onForeground')
    // 主题跟随统一由 onConfigurationUpdate 驱动（系统配置变化时回调）
    // 此处不读 config.colorMode：NOT_SET 模式下该值可能返回应用上次设置，导致误覆盖
  }

  onBackground(): void {
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onBackground')
  }

  /** 系统配置变化（深浅色切换等）：自动主题开启时同步应用 */
  onConfigurationUpdate(newConfig: Configuration): void {
    AppStorage.setOrCreate('systemColorMode', newConfig.colorMode)
    try {
      const isAuto = AppStorage.get<boolean>('autoTheme') ?? false
      if (!isAuto) return
      const isDark = newConfig.colorMode !== ConfigurationConstant.ColorMode.COLOR_MODE_LIGHT
      AppStorage.setOrCreate('themeMode', isDark ? 'dark' : 'light')
      AppStorage.setOrCreate('themeIsDark', isDark)
      hilog.info(DOMAIN, 'testTag', '自动主题跟随系统: %{public}s', isDark ? 'dark' : 'light')
    } catch (err) {
      hilog.error(DOMAIN, 'testTag', '自动主题更新失败: %{public}s', JSON.stringify(err))
    }
  }
}
