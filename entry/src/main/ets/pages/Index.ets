import { PlayerEngine } from 'hsp_player'
import { PlaylistManager } from 'hsp_playlist'
import { SourceManager, JsExecutorRegistry } from 'hsp_source'
import { PlayerStatus, MusicItem, StorageUtils, SourceType, LogUtils, PlayCacheUtils } from 'common'
import { webview } from '@kit.ArkWeb'
import { window, display } from '@kit.ArkUI'
import { SearchContent } from './SearchPage'
import { PlaylistListContent } from './PlaylistListPage'
import { SettingsContent } from './SettingsPage'
import { AppBackground } from '../components/common/AppBackground'
import { NavCapsule, NavTab } from '../components/common/NavCapsule'
import { PortraitPage } from '../components/portrait/PortraitPage'
import { WebJsExecutor } from '../executor/WebJsExecutor'
import { NowPlayingPanel } from '../components/player/NowPlayingPanel'
import { QueuePanel } from '../components/player/QueuePanel'
import { DownloadPanel } from '../components/download/DownloadPanel'
import { SongActionMenu } from '../components/common/SongActionMenu'
import { DialogPosUtils } from '../utils/DialogPosUtils'
import { ThemeColors } from '../theme/ThemeColors'
import { pasteboard } from '@kit.BasicServicesKit'

/**
 * 面板名称：queue=播放列表（默认），search/playlist/settings/downloads 为替换内容
 */
type PanelName = 'queue' | 'search' | 'playlist' | 'settings' | 'downloads'

@Entry
@Component
struct Index {
  @StorageLink('themeMode') @Watch('onThemeChange') themeMode: string = 'dark'
  @StorageLink('systemColorMode') @Watch('onSystemColorModeChange') systemColorMode: number = 0
  @State activePanel: PanelName = 'queue'
  /** 侧边页面是否展开 */
  @State capsuleExpanded: boolean = true
  /** 页面切换悬浮导航是否显示；与侧边页面展开状态相互独立 */
  @State capsuleVisible: boolean = true
  @State queueSongs: MusicItem[] = []
  @State queueIndex: number = -1
  @State playerStatus: PlayerStatus = PlayerStatus.IDLE
  @State playlistHasSelection: boolean = false
  @State settingsHasSelection: boolean = false
  @State panelWidth: string = '29%'
  @State panelSide: string = 'left'
  /** 竖屏检测（宽 < 高） */
  @State isPortrait: boolean = false
  private mainWindow: window.Window | null = null
  /** 导航悬浮球锚定侧（全局手势触发）：'left'/'right'/''（自由拖拽） */
  @State capsuleDockSide: string = ''
  /** 全局横滑手势累计偏移（控制导航悬浮球展开/收起） */
  private swipeX: number = 0
  /** 隐藏 Web 执行器（JS 音源脚本执行，绕开 JSVM ACL 限制） */
  private webController: webview.WebviewController = new webview.WebviewController()
  private webExecutor: WebJsExecutor = new WebJsExecutor()

  /** JavaScriptProxy：Web 页面音源请求桥接到原生网络（由 WebJsExecutor 实现） */
  private player: PlayerEngine = PlayerEngine.getInstance()
  private syncTimer: number = -1
  private lastQueueFingerprint: string = ''
  private queueSongActionController: CustomDialogController | null = null

  private readonly tabs: NavTab[] = [
    { icon: $r('app.media.ic_search'), label: '搜索', pageName: 'Search' },
    { icon: $r('app.media.ic_nav_playlist'), label: '歌单', pageName: 'Playlist' },
    { icon: $r('app.media.ic_download'), label: '下载', pageName: 'Downloads' },
    { icon: $r('app.media.ic_play'), label: '播放', pageName: 'NowPlaying' },
    { icon: $r('app.media.ic_more'), label: '设置', pageName: 'Settings' }
  ]

  private get isDark(): boolean {
    return this.themeMode !== 'light'
  }

  private get accentColor(): ResourceColor { return ThemeColors.accentColor() }
  private get secondaryText(): ResourceColor { return ThemeColors.secondaryText(this.isDark) }
  private get glassBg(): ResourceColor { return ThemeColors.glassBg(this.isDark) }
  private get borderFaint(): ResourceColor { return ThemeColors.borderFaint(this.isDark) }

  /**
   * 更新左侧面板宽度：
   * - 歌单页：未选中歌单时很窄（仅显示歌单列表），选中后适度扩展以显示歌曲名
   * - 其他面板（搜索/设置）：标准宽度，不受歌单状态影响
   * 用显式 @State 驱动（@Builder 中 getter 间接访问无法触发重绘）
   */
  private updatePanelWidth(): void {
    let width = '29%'
    if (this.activePanel === 'playlist') {
      // 歌单：未选中时 160vp（与固定侧栏等宽，歌单名不动），选中后扩展显示详情
      width = this.playlistHasSelection ? '34%' : '160vp'
    } else if (this.activePanel === 'settings') {
      // 设置：未选中分类时 160vp，选中后 30%
      width = this.settingsHasSelection ? '30%' : '160vp'
    }
    this.panelWidth = width
  }

  onThemeChange(): void {
    AppStorage.setOrCreate('themeIsDark', this.themeMode !== 'light')
    this.updateSystemBarColor()
  }

  /** 系统颜色模式变化（自动主题开启时立即跟随，无需进入设置页） */
  onSystemColorModeChange(): void {
    try {
      const isAuto = AppStorage.get<boolean>('autoTheme') ?? false
      if (!isAuto) return
      const isDark = this.systemColorMode !== 0
      const newMode = isDark ? 'dark' : 'light'
      if (newMode !== this.themeMode) {
        this.themeMode = newMode
        AppStorage.setOrCreate('themeIsDark', isDark)
        this.updateSystemBarColor()
      }
    } catch (err) {
      LogUtils.warn(`[主题] 自动主题响应异常: ${JSON.stringify(err)}`)
    }
  }

  /** 根据当前主题更新状态栏/导航栏文字颜色（浅色主题用深色文字） */
  private updateSystemBarColor(): void {
    try {
      const barContentColor = this.themeMode !== 'light' ? '#e8e0f8' : '#1a1525'
      window.getLastWindow(getContext(this)).then((mainWindow: window.Window) => {
        mainWindow.setWindowSystemBarProperties({
          statusBarColor: '#00000000',
          statusBarContentColor: barContentColor,
          navigationBarColor: '#00000000',
          navigationBarContentColor: barContentColor
        })
      }).catch((err: Error) => {
        LogUtils.warn(`[主题] 更新系统栏颜色失败: ${JSON.stringify(err)}`)
      })
    } catch (err) {
      LogUtils.warn(`[主题] 更新系统栏颜色异常: ${JSON.stringify(err)}`)
    }
  }

  aboutToAppear(): void {
    AppStorage.setOrCreate('themeIsDark', this.themeMode !== 'light')
    this.updateSystemBarColor()
    // 竖屏检测：监听窗口尺寸变化
    window.getLastWindow(getContext(this)).then((mainWindow: window.Window) => {
      this.mainWindow = mainWindow
      this.updateOrientation()
      mainWindow.on('windowSizeChange', (size: window.Size) => {
        this.isPortrait = size.height > size.width
      })
    }).catch((err: Error) => {
      LogUtils.warn(`[方向] 获取窗口失败: ${JSON.stringify(err)}`)
    })
    // 处理桌面快捷方式跳转（短cutKey → 面板）
    const shortCutKey = AppStorage.get<string>('shortCutKey')
    if (shortCutKey === 'search' || shortCutKey === 'recent') {
      this.activePanel = 'search'
    } else if (shortCutKey === 'favorites') {
      this.activePanel = 'playlist'
    }
    AppStorage.delete('shortCutKey')
    this.updatePanelWidth()
    this.player.onPlayError = (message: string) => {
      this.getUIContext().getPromptAction().showToast({ message: message, duration: 2000 })
    }
    // 清理过期播放缓存：不在任何歌单且超过 7 天未播放的删除；在歌单中的永不删除
    PlayCacheUtils.cleanup((songmid: string, source: string): boolean => {
      const playlists = PlaylistManager.getInstance().getAll()
      for (const pl of playlists) {
        for (const s of pl.songs) {
          if (s.songmid === songmid && s.source === source) {
            return true
          }
        }
      }
      return false
    })
    StorageUtils.getString('theme_mode', 'dark').then((val: string) => {
      if (val === 'light' || val === 'dark') {
        const isAuto = AppStorage.get<boolean>('autoTheme') ?? false
        if (isAuto) {
          // 自动主题：按系统模式（systemColorMode），忽略存储的手动选择
          const isDark = this.systemColorMode !== 0
          this.themeMode = isDark ? 'dark' : 'light'
        } else {
          this.themeMode = val
        }
        AppStorage.setOrCreate('themeIsDark', this.themeMode !== 'light')
        this.updateSystemBarColor()
      }
    })

    this.syncTimer = setInterval(() => {
      this.queueSongs = this.player.queue.list
      this.queueIndex = this.player.queue.currentIndex
      this.playerStatus = this.player.status
      // 检测队列变化（长度/索引/首曲指纹）→ 持久化，重启后恢复
      const q = this.player.queue
      const fingerprint = `${q.list.length}_${q.currentIndex}_${q.list.length > 0 ? q.list[0].songmid : ''}`
      if (fingerprint !== this.lastQueueFingerprint) {
        this.lastQueueFingerprint = fingerprint
        this.player.saveQueueState()
      }
    }, 500)

    StorageUtils.getString('auto_play_enabled', 'false').then((enabled: string) => {
      LogUtils.info(`[自动播放] auto_play_enabled 设置值: "${enabled}"`)
      if (enabled !== 'true') return
      StorageUtils.getObject<Record<string, string | number>>('last_played_song', { 'songmid': '' })
        .then((saved: Record<string, string | number>) => {
          const songmid = saved['songmid'] as string
          LogUtils.info(`[自动播放] 读取上次播放: songmid="${songmid}", name="${saved['name']}", source="${saved['source']}"`)
          if (!songmid) return
          const sourceStr = saved['source'] as string
          let source: SourceType = SourceType.KG
          if (sourceStr === 'wy') source = SourceType.WY
          else if (sourceStr === 'tx') source = SourceType.TX
          else if (sourceStr === 'custom') source = SourceType.CUSTOM
          else if (sourceStr === 'kg') source = SourceType.KG
          const song: MusicItem = {
            songmid: songmid,
            name: (saved['name'] as string) ?? '未知歌曲',
            singer: (saved['singer'] as string) ?? '',
            albumName: (saved['albumName'] as string) ?? '',
            interval: (saved['interval'] as number) ?? 0,
            imgUrl: (saved['imgUrl'] as string) ?? '',
            source: source,
            lyricUrl: '',
            types: {}
          }
          LogUtils.info('[自动播放] 开始自动播放...')
          this.player.play(song)
        })
        .catch((err: Error) => {
          LogUtils.error(`[自动播放] 读取失败: ${JSON.stringify(err)}`)
        })
    })
  }

  aboutToDisappear(): void {
    if (this.mainWindow) {
      this.mainWindow.off('windowSizeChange')
      this.mainWindow = null
    }
    if (this.syncTimer >= 0) {
      clearInterval(this.syncTimer)
      this.syncTimer = -1
    }
  }

  /** 根据当前显示方向更新竖屏状态 */
  private updateOrientation(): void {
    try {
      const d = display.getDefaultDisplaySync()
      const w = d.width / d.densityPixels
      const h = d.height / d.densityPixels
      this.isPortrait = h > w
    } catch (err) {
      LogUtils.warn(`[方向] 读取显示属性失败: ${JSON.stringify(err)}`)
    }
  }

  build() {
    Stack() {
      if (this.isPortrait) {
        // 竖屏布局：负一屏 | 播放 | 歌词 三页横滑
        PortraitPage()
      } else {
        // 横屏布局：双面板 + 导航悬浮球
        Stack() {
          AppBackground()

          Column() {
            Row({ space: 8 }) {
              if (this.panelSide === 'left') {
                this.LeftPanel()
              }

              NowPlayingPanel({ onNavigateSearch: (keyword: string) => { this.navigateToSearch(keyword) } })
                .layoutWeight(1)

              if (this.panelSide === 'right') {
                this.RightPanel()
              }
            }
            .width('100%')
            .height('100%')
            .padding({ left: 12, right: 12, top: 8, bottom: 8 })
            .alignItems(VerticalAlign.Center)
          }
          .width('100%')
          .height('100%')
          .expandSafeArea([SafeAreaType.SYSTEM, SafeAreaType.CUTOUT], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
          .backgroundColor(Color.Transparent)

          NavCapsule({
            tabs: this.tabs,
            activePage: this.getActiveTabName(),
            capsuleVisible: this.capsuleVisible,
            dockSide: this.capsuleDockSide,
            onSelect: (pageName: string) => { this.handleTabSelect(pageName) },
            onExpand: (isLeft: boolean) => { this.panelSide = isLeft ? 'left' : 'right' },
            onSideChange: (isLeft: boolean) => { this.panelSide = isLeft ? 'left' : 'right' }
          })
        }
        .width('100%')
        .height('100%')
        .backgroundColor(Color.Transparent)
        .gesture(
          PanGesture({ direction: PanDirection.Horizontal })
            .onActionUpdate((event: GestureEvent) => {
              this.swipeX = event.offsetX
            })
            .onActionEnd(() => {
              this.handleGlobalSwipe()
            })
        )
      }

      // 隐藏 Web 执行器（JS 音源脚本执行环境，屏幕外不可见；横竖屏共用）
      Web({ src: $rawfile('executor.html'), controller: this.webController })
        .width(1)
        .height(1)
        .position({ x: -200, y: -200 })
        .opacity(0)
        .mixedMode(MixedMode.All)
        .domStorageAccess(true)
        .javaScriptProxy({
          object: this.webExecutor,
          name: 'sourceNative',
          methodList: ['nativeRequest'],
          controller: this.webController
        })
        .onPageEnd(() => {
          this.webExecutor.attach(this.webController)
          this.webExecutor.markReady()
          JsExecutorRegistry.register(this.webExecutor)
          // 验证原生桥注入状态
          this.webExecutor.evalScript(`JSON.stringify({ native: typeof globalThis.sourceNative, reqMethod: typeof (globalThis.sourceNative && globalThis.sourceNative.nativeRequest), keys: globalThis.sourceNative ? Object.keys(globalThis.sourceNative) : [] })`)
            .then((v: string) => { LogUtils.info(`[Web执行器] 注入验证: ${v}`) })
            .catch((e: Error) => { LogUtils.warn(`[Web执行器] 注入验证失败: ${e.message}`) })
          // 原生桥自检：直接调用 sourceNative.nativeRequest 并捕获调用错误
          this.webExecutor.evalScript(
            `try { globalThis.sourceNative.nativeRequest('https://www.baidu.com', '{}', 'basetest1'); globalThis.__bridgeTest__ = 'called' } catch(e) { globalThis.__bridgeTest__ = 'callerr:' + String(e) }`)
            .then((r: string) => {
              setTimeout(() => {
                this.webExecutor.evalScript(`JSON.stringify({ test: globalThis.__bridgeTest__, errs: globalThis.__source_errors__ || [] })`)
                  .then((v: string) => { LogUtils.info(`[Web执行器] 桥自检结果: ${v}`) })
                  .catch((e: Error) => { LogUtils.warn(`[Web执行器] 桥自检读取失败: ${e.message}`) })
              }, 4000)
              LogUtils.info(`[Web执行器] 桥自检发起返回: ${r ? r.substring(0, 100) : '(空)'}`)
            })
            .catch((e: Error) => { LogUtils.warn(`[Web执行器] 桥自检发起失败: ${e.message}`) })
          LogUtils.info('[Web执行器] 就绪，重新加载 JS 音源')
          SourceManager.getInstance().reloadJSSources()
        })
        .onRenderExited((event) => {
          this.webExecutor.markNotReady()
          LogUtils.error(`[Web执行器] ArkWeb 渲染进程异常退出: ${JSON.stringify(event)}`)
          try {
            // HarmonyOS 官方建议在 onRenderExited 中通过 refresh/loadUrl 恢复页面。
            this.webController.refresh()
          } catch (err) {
            LogUtils.warn(`[Web执行器] 渲染进程恢复失败: ${JSON.stringify(err)}`)
          }
        })
    }
    .width('100%')
    .height('100%')
    .backgroundColor(Color.Transparent)
  }

  /**
   * 全局横滑控制导航悬浮球：
   * - 侧边页面展开时：向所在屏幕外侧滑动可收起页面
   * - 悬浮导航隐藏但页面仍展开时：向屏幕内侧滑动可恢复悬浮导航
   * - 侧边页面收起时：左滑从右侧展开，右滑从左侧展开，不受上一次所在侧限制
   */
  private handleGlobalSwipe(): void {
    if (this.capsuleExpanded) {
      if (this.panelSide === 'left' && this.swipeX < -80) {
        this.capsuleExpanded = false
        this.capsuleVisible = false
      } else if (this.panelSide === 'right' && this.swipeX > 80) {
        this.capsuleExpanded = false
        this.capsuleVisible = false
      } else if (!this.capsuleVisible) {
        if (this.panelSide === 'left' && this.swipeX > 80) {
          this.capsuleVisible = true
        } else if (this.panelSide === 'right' && this.swipeX < -80) {
          this.capsuleVisible = true
        }
      }
    } else {
      if (this.swipeX < -80) {
        this.panelSide = 'right'
        this.capsuleDockSide = 'right'
        this.capsuleExpanded = true
        this.capsuleVisible = true
      } else if (this.swipeX > 80) {
        this.panelSide = 'left'
        this.capsuleDockSide = 'left'
        this.capsuleExpanded = true
        this.capsuleVisible = true
      }
    }
    this.swipeX = 0
  }

  /** 左侧毛玻璃面板：内容随 activePanel 替换；宽度变化动画（详情展开），侧栏贴左缘不参与位移 */
  @Builder
  LeftPanel() {
    Column() {
      this.PanelContent()
    }
    .width(this.capsuleExpanded ? this.panelWidth : '0%')
    .height('96%')
    .opacity(this.capsuleExpanded ? 1 : 0)
    .margin({ right: this.capsuleExpanded ? 4 : 0 })
    .animation({ duration: 350, curve: Curve.FastOutSlowIn })
    .transition(TransitionEffect.OPACITY.animation({ duration: 300, curve: Curve.FastOutSlowIn })
      .combine(TransitionEffect.translate({ x: -20, y: 0 }).animation({ duration: 300, curve: Curve.FastOutSlowIn })))
    .backgroundColor(this.glassBg)
    .backdropBlur(this.capsuleExpanded ? 40 : 0)
    .borderRadius(20)
    .clip(true)
    .border({ width: 0.5, color: this.borderFaint })
    .shadow({ radius: 30, color: '#a0b388ff', offsetX: 0, offsetY: 4 })
    .shadow({ radius: 60, color: '#60b388ff', offsetX: 0, offsetY: 0 })
  }

  /** 右侧毛玻璃面板：从右向左展开，左推播放页 */
  @Builder
  RightPanel() {
    Column() {
      this.PanelContent()
    }
    .width(this.capsuleExpanded ? this.panelWidth : '0%')
    .height('96%')
    .opacity(this.capsuleExpanded ? 1 : 0)
    .margin({ left: this.capsuleExpanded ? 4 : 0 })
    .animation({ duration: 350, curve: Curve.FastOutSlowIn })
    .transition(TransitionEffect.OPACITY.animation({ duration: 300, curve: Curve.FastOutSlowIn })
      .combine(TransitionEffect.translate({ x: 20, y: 0 }).animation({ duration: 300, curve: Curve.FastOutSlowIn })))
    .backgroundColor(this.glassBg)
    .backdropBlur(this.capsuleExpanded ? 40 : 0)
    .borderRadius(20)
    .clip(true)
    .border({ width: 0.5, color: this.borderFaint })
    .shadow({ radius: 30, color: '#a0b388ff', offsetX: 0, offsetY: 4 })
    .shadow({ radius: 60, color: '#60b388ff', offsetX: 0, offsetY: 0 })
  }

  /** 面板内容（左右侧共用，直接引用 @State 保证响应式更新） */
  @Builder
  PanelContent() {
    if (this.activePanel === 'queue') {
      QueuePanel({
        queueSongs: this.queueSongs,
        queueIndex: this.queueIndex,
        status: this.playerStatus,
        onClear: () => { this.player.queue.clear() },
        onRemoveAt: (index: number) => { this.player.queue.removeAt(index) },
        onPlayAt: (index: number) => {
          const target = this.player.queue.skipTo(index)
          if (target) { this.player.play(target) }
        },
        onMoveItem: (from: number, to: number) => { this.player.queue.move(from, to) },
        onLongPressSong: (song: MusicItem, index: number, event: GestureEvent) => {
          this.handleQueueLongPress(song, index, event)
        }
      })
      .transition(TransitionEffect.OPACITY.animation({ duration: 280, curve: Curve.FastOutSlowIn })
        .combine(TransitionEffect.translate({ x: this.panelSide === 'left' ? -16 : 16, y: 0 })
          .animation({ duration: 280, curve: Curve.FastOutSlowIn })))
    } else if (this.activePanel === 'search') {
      SearchContent()
        .transition(TransitionEffect.OPACITY.animation({ duration: 280, curve: Curve.FastOutSlowIn })
          .combine(TransitionEffect.translate({ x: this.panelSide === 'left' ? -16 : 16, y: 0 })
            .animation({ duration: 280, curve: Curve.FastOutSlowIn })))
    } else if (this.activePanel === 'playlist') {
      PlaylistListContent({
        panelSide: this.panelSide,
        onSelectionChange: (hasSelection: boolean) => {
          this.playlistHasSelection = hasSelection
          this.updatePanelWidth()
        },
        onNavigateSearch: (keyword: string) => { this.navigateToSearch(keyword) }
      })
      .transition(TransitionEffect.OPACITY.animation({ duration: 280, curve: Curve.FastOutSlowIn }))
    } else if (this.activePanel === 'downloads') {
      DownloadPanel({
        onPlay: (song: MusicItem) => { this.player.play(song) }
      })
      .transition(TransitionEffect.OPACITY.animation({ duration: 280, curve: Curve.FastOutSlowIn })
        .combine(TransitionEffect.translate({ x: this.panelSide === 'left' ? -16 : 16, y: 0 })
          .animation({ duration: 280, curve: Curve.FastOutSlowIn })))
    } else if (this.activePanel === 'settings') {
      SettingsContent({
        panelSide: this.panelSide,
        onSelectionChange: (hasSelection: boolean) => {
          this.settingsHasSelection = hasSelection
          this.updatePanelWidth()
        }
      })
        .transition(TransitionEffect.OPACITY.animation({ duration: 280, curve: Curve.FastOutSlowIn })
          .combine(TransitionEffect.translate({ x: this.panelSide === 'left' ? -16 : 16, y: 0 })
            .animation({ duration: 280, curve: Curve.FastOutSlowIn })))
    }
  }

  /** 胶囊点击：替换左侧面板内容（queue=播放列表 对应"播放"tab） */
  private handleTabSelect(pageName: string): void {
    if (pageName === 'Search') {
      this.activePanel = 'search'
    } else if (pageName === 'Playlist') {
      this.activePanel = 'playlist'
    } else if (pageName === 'Downloads') {
      this.activePanel = 'downloads'
    } else if (pageName === 'Settings') {
      this.activePanel = 'settings'
    } else {
      this.activePanel = 'queue'
    }
    this.updatePanelWidth()
  }

  private switchPanel(panel: PanelName): void {
    this.activePanel = panel
    this.updatePanelWidth()
  }

  /** 导航到搜索页面并填入关键词 */
  private navigateToSearch(keyword: string): void {
    AppStorage.setOrCreate('searchKeyword', keyword)
    this.activePanel = 'search'
    this.updatePanelWidth()
  }

  /** 播放队列长按歌曲弹出操作菜单 */
  private handleQueueLongPress(song: MusicItem, index: number, event: GestureEvent): void {
    const pos = DialogPosUtils.fit(DialogPosUtils.fromGesture(event), 300, 480)
    const contextIndex = index
    const contextSong = song
    this.queueSongActionController = new CustomDialogController({
      builder: SongActionMenu({
        song: song,
        isFavorited: false,
        actions: ['playlist', 'nextPlay', 'favorite', 'download',
          'sourceSwitch', 'searchSinger', 'searchSong', 'copyName', 'remove'],
        onAction: (action: string, clickEvent: ClickEvent) => {
          void clickEvent
          if (action === 'playlist') {
            this.activePanel = 'playlist'
            this.updatePanelWidth()
          } else if (action === 'nextPlay') {
            this.player.queue.insertAt(contextSong, this.player.queue.currentIndex + 1)
            this.getUIContext().getPromptAction().showToast({ message: '已设为下一首播放', duration: 1200 })
          } else if (action === 'favorite') {
            PlaylistManager.getInstance().toggleFavorite(contextSong)
            this.getUIContext().getPromptAction().showToast({ message: '已切换收藏', duration: 1200 })
          } else if (action === 'remove') {
            this.player.queue.removeAt(contextIndex)
            this.getUIContext().getPromptAction().showToast({ message: '已从队列移除', duration: 1200 })
          } else if (action === 'searchSinger') {
            this.navigateToSearch(contextSong.singer)
          } else if (action === 'searchSong') {
            this.navigateToSearch(contextSong.name)
          } else if (action === 'copyName') {
            try {
              const data = pasteboard.createData(pasteboard.MIMETYPE_TEXT_PLAIN,
                `${contextSong.name} - ${contextSong.singer}`)
              pasteboard.getSystemPasteboard().setData(data)
              this.getUIContext().getPromptAction().showToast({ message: '已复制歌曲名', duration: 1200 })
            } catch (err) {
              this.getUIContext().getPromptAction().showToast({ message: '复制失败', duration: 1200 })
            }
          } else if (action === 'download') {
            this.getUIContext().getPromptAction().showToast({ message: '下载功能请在歌单中使用', duration: 1500 })
          } else if (action === 'sourceSwitch') {
            this.getUIContext().getPromptAction().showToast({ message: '换源功能请在歌单中使用', duration: 1500 })
          }
        }
      }),
      autoCancel: true,
      alignment: DialogAlignment.TopStart,
      offset: { dx: pos.x, dy: pos.y },
      customStyle: true
    })
    this.queueSongActionController.open()
  }

  /** 胶囊高亮：activePanel 映射回 tab 名 */
  private getActiveTabName(): string {
    if (this.activePanel === 'search') return 'Search'
    if (this.activePanel === 'playlist') return 'Playlist'
    if (this.activePanel === 'downloads') return 'Downloads'
    if (this.activePanel === 'settings') return 'Settings'
    return 'NowPlaying'
  }
}
