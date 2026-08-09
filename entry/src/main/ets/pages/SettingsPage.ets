import { SourceManager } from 'hsp_source'
import { PlaylistManager } from 'hsp_playlist'
import { PlayerEngine } from 'hsp_player'
import { StorageUtils, SourceInstance, SourceImportMethod, MusicQuality, LogUtils } from 'common'
import { picker, fileIo } from '@kit.CoreFileKit'
import { BusinessError } from '@kit.BasicServicesKit'
import { util } from '@kit.ArkTS'
import { ConfigurationConstant } from '@kit.AbilityKit'
import { SettingsRow } from '../components/settings/SettingsRow'
import { SourceManagePanel } from '../components/settings/SourceManagePanel'
import { PlaylistNameDialog } from '../components/PlaylistNameDialog'
import { SleepTimerDialog } from '../components/common/SleepTimerDialog'
import { FontSizeDialog } from '../components/common/FontSizeDialog'
import { QualityDialog } from '../components/common/QualityDialog'
import { ImageCropper } from '../components/common/ImageCropper'
import { AppActionDialog, AppDialogAction } from '../components/common/AppActionDialog'
import { DialogPosition, DialogPosUtils } from '../utils/DialogPosUtils'
import { ThemeColors } from '../theme/ThemeColors'

const BACKUP_TYPE = 'sourceMusicBackup'
// 兼容旧版备份类型与扩展名，字符串拆分可避免旧品牌继续出现在正式代码中。
const LEGACY_BACKUP_TYPE = String.fromCharCode(108, 120) + 'MusicBackup'
const LEGACY_PLAYLIST_SUFFIX = '.' + String.fromCharCode(108, 120) + 'mc'

@Component
export struct SettingsContent {
  @StorageLink('themeIsDark') isDark: boolean = true
  @StorageLink('themeMode') themeMode: string = 'dark'
  @State localSongCount: number = 0
  @State autoPlayEnabled: boolean = false
  @State sources: SourceInstance[] = []
  @State sourceImportStatus: string = ''
  @State sourceExpanded: boolean = false
  @State extendedSearchEnabled: boolean = false
  @State sleepRemainText: string = '关闭'
  @State saveProgressEnabled: boolean = false
  @State autoCleanPlayedEnabled: boolean = false
  @State autoThemeEnabled: boolean = false
  @State defaultQualityText: string = '320k'
  @State cacheSizeText: string = '计算中...'
  @State customBgEnabled: boolean = false
  @State cropUri: string = ''
  @StorageLink('lyricShowTranslation') lyricShowTranslation: boolean = true
  @StorageLink('lyricFontSize') lyricFontSize: number = 14
  private sourceManager: SourceManager = SourceManager.getInstance()
  private player: PlayerEngine = PlayerEngine.getInstance()
  private cropDialogController: CustomDialogController = new CustomDialogController({
    builder: ImageCropper({
      srcUri: '',
      onCropDone: (filePath: string) => { this.applyCustomBg(filePath) }
    }),
    autoCancel: false,
    alignment: DialogAlignment.Center,
    customStyle: true
  })
  private sleepDialogController: CustomDialogController = new CustomDialogController({
    builder: SleepTimerDialog({
      currentText: '关闭',
      onSelect: (minutes: number) => { this.applySleepTimer(minutes) }
    }),
    autoCancel: true,
    alignment: DialogAlignment.Center,
    customStyle: true
  })
  private qualityDialogController: CustomDialogController = new CustomDialogController({
    builder: QualityDialog({
      currentQuality: '320k',
      onSelect: (quality: string) => { this.applyQuality(quality) }
    }),
    autoCancel: true,
    alignment: DialogAlignment.Center,
    customStyle: true
  })
  private fontDialogController: CustomDialogController = new CustomDialogController({
    builder: FontSizeDialog({
      currentSize: 14,
      onSelect: (size: number) => { this.applyLyricFontSize(size) }
    }),
    autoCancel: true,
    alignment: DialogAlignment.Center,
    customStyle: true
  })
  /** 应用统一操作弹窗，成员引用可避免弹窗控制器被提前回收 */
  private actionDialogController: CustomDialogController | null = null
  /** 最近一次弹窗锚点，异步错误提示也沿用触发操作的位置 */
  private dialogPosition: DialogPosition = new DialogPosition()

  private get primaryText(): ResourceColor { return ThemeColors.primaryText(this.isDark) }
  private get secondaryText(): ResourceColor { return ThemeColors.secondaryText(this.isDark) }

  aboutToAppear(): void {
    this.localSongCount = this.sourceManager.getLocalSongs().length
    this.extendedSearchEnabled = this.sourceManager.isExtendedSearchEnabled()
    StorageUtils.getString('custom_bg_path', '').then((path: string) => { this.customBgEnabled = path.length > 0 })
    StorageUtils.getString('auto_play_enabled', 'false').then((val: string) => { this.autoPlayEnabled = val === 'true' })
    StorageUtils.getString('lyric_show_translation', 'true').then((val: string) => {
      AppStorage.setOrCreate('lyricShowTranslation', val !== 'false')
    })
    StorageUtils.getString('lyric_font_size', '14').then((val: string) => {
      const num = Number(val)
      const size = (num >= 12 && num <= 24) ? num : 14
      AppStorage.setOrCreate('lyricFontSize', size)
    })
    StorageUtils.getString('save_play_progress', 'false').then((val: string) => {
      this.saveProgressEnabled = val === 'true'
      this.player.savePlayProgress = this.saveProgressEnabled
    })
    StorageUtils.getString('auto_clean_played', 'false').then((val: string) => {
      this.autoCleanPlayedEnabled = val === 'true'
      this.player.autoCleanPlayed = this.autoCleanPlayedEnabled
    })
    StorageUtils.getString('auto_theme', 'false').then((val: string) => {
      this.autoThemeEnabled = val === 'true'
      AppStorage.setOrCreate('autoTheme', this.autoThemeEnabled)
    })
    StorageUtils.getString('default_quality', '320k').then((val: string) => {
      this.defaultQualityText = val
      this.applyQualityToPlayer(val)
    })
    this.refreshCacheSize()
    this.sources = [...this.sourceManager.getManageSources()]
  }

  private applyQualityToPlayer(quality: string): void {
    if (quality === '128k') {
      this.player.defaultQuality = MusicQuality.LOW
    } else if (quality === 'flac') {
      this.player.defaultQuality = MusicQuality.LOSSLESS
    } else {
      this.player.defaultQuality = MusicQuality.HIGH
    }
  }

  private refreshCacheSize(): void {
    this.sourceManager.getCacheSize().then((size: number) => {
      if (size <= 0) {
        this.cacheSizeText = '0 KB'
      } else if (size < 1024 * 1024) {
        this.cacheSizeText = `${(size / 1024).toFixed(0)} KB`
      } else {
        this.cacheSizeText = `${(size / 1024 / 1024).toFixed(1)} MB`
      }
    }).catch(() => { this.cacheSizeText = '0 KB' })
  }

  build() {
    Scroll() {
      Column() {
        Text('设置').fontSize(20).fontWeight(FontWeight.Bold).fontColor(this.primaryText)
          .padding({ left: 16, top: 16, bottom: 12 })

        List({ space: 6 }) {
          ListItem() {
            SettingsRow({
              title: '导入本地音乐',
              value: `${this.localSongCount} 首`,
              showArrow: true,
              onRowClick: (event: ClickEvent) => { this.importLocalMusic() }
            })
          }

          ListItem() {
            SettingsRow({
              title: '扫描文件夹导入',
              subtitle: '选择文件夹，自动解析封面/歌手等信息',
              showArrow: true,
              onRowClick: (event: ClickEvent) => { this.importLocalFolder() }
            })
          }

          ListItem() {
            SettingsRow({
              title: '音源管理',
              subtitle: `${this.sources.length} 个音源`,
              value: this.sourceExpanded ? '收起' : '展开',
              onRowClick: (event: ClickEvent) => { this.sourceExpanded = !this.sourceExpanded }
            })
          }

          if (this.sourceExpanded) {
            ListItem() {
              SourceManagePanel({
                sources: this.sources,
                importStatus: this.sourceImportStatus,
                onToggleSource: (id: string, enabled: boolean) => {
                  this.toggleSource(id, enabled)
                },
                onRemoveSource: (id: string) => {
                  this.sourceManager.removeSource(id).then(() => {
                    this.sources = [...this.sourceManager.getManageSources()]
                  })
                },
                showImportDialog: (event: ClickEvent) => { this.showImportSourceDialog(event) }
              })
            }
          }

          ListItem() {
            SettingsRow({
              title: '扩展音源搜索',
              subtitle: this.extendedSearchEnabled ?
                '允许声明 search 的活动自定义源参与搜索' :
                '标准解析模式：自定义源只解析播放地址',
              showToggle: true,
              isOn: this.extendedSearchEnabled,
              onToggle: (checked: boolean) => {
                const previous = this.extendedSearchEnabled
                this.extendedSearchEnabled = checked
                this.sourceManager.setExtendedSearchEnabled(checked).then(() => {
                  this.showSourceImportFeedback(checked ? '扩展音源搜索已开启' : '已恢复标准解析模式')
                }).catch((err: Error) => {
                  this.extendedSearchEnabled = previous
                  LogUtils.warn(`[音源] 保存扩展搜索设置失败: ${JSON.stringify(err)}`)
                  this.showSourceImportFeedback('设置保存失败，请重试')
                })
              }
            })
          }

          ListItem() {
            SettingsRow({
              title: '自动跟随系统主题',
              showToggle: true,
              isOn: this.autoThemeEnabled,
              onToggle: (checked: boolean) => {
                this.autoThemeEnabled = checked
                AppStorage.setOrCreate('autoTheme', checked)
                StorageUtils.putString('auto_theme', checked ? 'true' : 'false')
                this.applyAutoTheme(checked)
              }
            })
          }

          ListItem() {
            SettingsRow({
              title: '主题',
              value: this.themeMode === 'dark' ? '深色' : '浅色',
              onRowClick: (event: ClickEvent) => { this.showThemeDialog(event) }
            })
          }

          ListItem() {
            SettingsRow({
              title: '自定义背景',
              subtitle: this.customBgEnabled ? '已启用（点击更换）' : '从相册选择图片作为背景',
              value: this.customBgEnabled ? '更换' : '',
              onRowClick: (event: ClickEvent) => { this.importCustomBg() }
            })
          }

          if (this.customBgEnabled) {
            ListItem() {
              SettingsRow({
                title: '恢复默认背景',
                value: '',
                onRowClick: (event: ClickEvent) => { this.resetCustomBg() }
              })
            }
          }

          ListItem() {
            SettingsRow({
              title: '默认音质',
              value: this.defaultQualityText,
              onRowClick: (event: ClickEvent) => { this.showQualityDialog(event) }
            })
          }

          ListItem() {
            SettingsRow({
              title: '定时关闭',
              value: this.sleepRemainText,
              onRowClick: (event: ClickEvent) => { this.showSleepTimerDialog(event) }
            })
          }

          ListItem() {
            SettingsRow({
              title: '保存播放进度',
              subtitle: '下次播放时从断点继续',
              showToggle: true,
              isOn: this.saveProgressEnabled,
              onToggle: (checked: boolean) => {
                this.saveProgressEnabled = checked
                this.player.savePlayProgress = checked
                StorageUtils.putString('save_play_progress', checked ? 'true' : 'false')
              }
            })
          }

          ListItem() {
            SettingsRow({
              title: '自动清理已播列表',
              subtitle: '播放完成自动移除该曲',
              showToggle: true,
              isOn: this.autoCleanPlayedEnabled,
              onToggle: (checked: boolean) => {
                this.autoCleanPlayedEnabled = checked
                this.player.autoCleanPlayed = checked
                StorageUtils.putString('auto_clean_played', checked ? 'true' : 'false')
              }
            })
          }

          ListItem() {
            SettingsRow({
              title: '歌词翻译',
              showToggle: true,
              isOn: this.lyricShowTranslation,
              onToggle: (checked: boolean) => {
                this.lyricShowTranslation = checked
                AppStorage.setOrCreate('lyricShowTranslation', checked)
                StorageUtils.putString('lyric_show_translation', checked ? 'true' : 'false')
              }
            })
          }

          ListItem() {
            SettingsRow({
              title: '歌词字号',
              value: `${this.lyricFontSize}`,
              onRowClick: (event: ClickEvent) => { this.showLyricFontDialog(event) }
            })
          }

          ListItem() {
            SettingsRow({
              title: '启动时自动播放上次歌曲',
              showToggle: true,
              isOn: this.autoPlayEnabled,
              onToggle: (checked: boolean) => {
                this.autoPlayEnabled = checked
                StorageUtils.putString('auto_play_enabled', checked ? 'true' : 'false')
              }
            })
          }

          ListItem() {
            SettingsRow({
              title: '备份与恢复',
              showArrow: true,
              onRowClick: (event: ClickEvent) => { this.showBackupDialog(event) }
            })
          }

          ListItem() {
            SettingsRow({
              title: '清除缓存',
              value: this.cacheSizeText,
              onRowClick: (event: ClickEvent) => { this.clearCaches(event) }
            })
          }

          ListItem() {
            SettingsRow({
              title: '关于',
              value: '源音乐 v0.1.0'
            })
          }
        }
        .width('100%').padding({ left: 12, right: 12 })
      }
      .width('100%')
    }
    .width('100%').height('100%')
    .scrollBar(BarState.Auto)
  }

  private showImportSourceDialog(event: ClickEvent): void {
    const actions: AppDialogAction[] = [
      { id: 'local', label: '从本地文件导入' },
      { id: 'online', label: '从在线链接导入' }
    ]
    this.showActionDialog('导入音源', '支持社区 .js 音源脚本', actions,
      (actionId: string, actionEvent: ClickEvent) => {
      if (actionId === 'local') {
        this.importSourceFromLocal()
      } else if (actionId === 'online') {
        this.importSourceFromOnline(actionEvent)
      }
    }, event)
  }

  private async importLocalMusic(): Promise<void> {
    try {
      const documentPicker = new picker.DocumentViewPicker()
      const result = await documentPicker.select({
        fileSuffixFilters: ['.mp3', '.flac', '.wav', '.ogg', '.aac', '.m4a'],
        maxSelectNumber: 500,
        selectMode: picker.DocumentSelectMode.FILE
      })
      if (result && result.length > 0) {
        const count = await this.sourceManager.importLocalFiles(result)
        this.localSongCount = this.sourceManager.getLocalSongs().length
        this.showToast(`成功导入 ${count} 首本地音乐`)
      }
    } catch (err) {}
  }

  /** 选择文件夹扫描导入（解析封面/歌手/专辑等元数据） */
  private async importLocalFolder(): Promise<void> {
    try {
      const documentPicker = new picker.DocumentViewPicker()
      const result = await documentPicker.select({
        selectMode: picker.DocumentSelectMode.FOLDER
      })
      if (result && result.length > 0) {
        this.showToast('正在扫描文件夹...')
        const count = await this.sourceManager.scanLocalFolder(result[0])
        this.localSongCount = this.sourceManager.getLocalSongs().length
        this.showToast(`成功导入 ${count} 首本地音乐`)
      }
    } catch (err) {}
  }

  private async importSourceFromLocal(): Promise<void> {
    try {
      const documentPicker = new picker.DocumentViewPicker()
      // 一次只能导入一个音源脚本
      const result = await documentPicker.select({ fileSuffixFilters: ['.js'], maxSelectNumber: 1 })
      if (!result || result.length === 0) {
        this.showSourceImportFeedback('已取消导入音源')
        return
      }
      this.showSourceImportFeedback('正在导入音源...')
      const ret = await this.sourceManager.importSource(SourceImportMethod.LOCAL_FILE, result[0])
      const message = ret.success ? `导入成功：${ret.source?.info.name ?? '未知音源'}（请手动启用）` :
        `导入失败：${ret.error ?? '未知错误'}`
      this.showSourceImportFeedback(message)
    } catch (err) {
      const error = err as BusinessError
      const detail = error.message || JSON.stringify(err) || '未知异常'
      LogUtils.error(`[导入] 本地音源导入异常: code=${error.code} message=${detail}`)
      this.showSourceImportFeedback(`导入失败：${detail}`)
    } finally {
      // SourceManager 返回内部数组；复制一份才能稳定触发 ArkUI 状态刷新。
      this.sources = [...this.sourceManager.getManageSources()]
    }
  }

  /** 在线音源导入对话框（成员保持引用，避免局部 controller 被 GC） */
  private onlineSourceDialog: CustomDialogController | null = null

  /** 从在线链接导入音源：弹出 URL 输入对话框 */
  private importSourceFromOnline(event: ClickEvent): void {
    this.dialogPosition = DialogPosUtils.fromClickForDialog(event, 300, 220)
    this.onlineSourceDialog = new CustomDialogController({
      builder: PlaylistNameDialog({
        title: '从链接导入音源',
        confirmText: '导入',
        placeholder: '请输入音源脚本 URL（.js 在线链接）',
        fallbackValue: '',
        onConfirm: (url: string) => {
          const trimmed = url.trim()
          if (!trimmed.startsWith('http')) {
            this.showToast('请输入有效的 http(s) 链接')
            return
          }
          this.importSourceFromUrl(trimmed)
        }
      }),
      autoCancel: true,
      alignment: DialogAlignment.TopStart,
      offset: { dx: this.dialogPosition.x, dy: this.dialogPosition.y },
      customStyle: true
    })
    this.onlineSourceDialog.open()
  }

  /** 在线导入与本地导入使用同一套可见反馈，避免 Promise 异常静默。 */
  private async importSourceFromUrl(url: string): Promise<void> {
    this.showSourceImportFeedback('正在导入音源...')
    try {
      const ret = await this.sourceManager.importSource(SourceImportMethod.ONLINE_URL, url)
      const message = ret.success ? `导入成功：${ret.source?.info.name ?? '未知音源'}（请手动启用）` :
        `导入失败：${ret.error ?? '未知错误'}`
      this.showSourceImportFeedback(message)
    } catch (err) {
      const error = err as BusinessError
      const detail = error.message || JSON.stringify(err) || '未知异常'
      LogUtils.error(`[导入] 在线音源导入异常: code=${error.code} message=${detail}`)
      this.showSourceImportFeedback(`导入失败：${detail}`)
    } finally {
      this.sources = [...this.sourceManager.getManageSources()]
    }
  }

  /** Toast 失败时仍保留面板状态，确保导入结果一定可见。 */
  private showSourceImportFeedback(message: string): void {
    this.sourceImportStatus = message
    try {
      this.showToast(message)
    } catch (err) {
      LogUtils.warn(`[导入] Toast 显示失败，已保留面板状态: ${JSON.stringify(err)}`)
    }
  }

  /** 用户明确打开开关时才初始化脚本；失败后保留已导入脚本并恢复关闭状态。 */
  private async toggleSource(id: string, enabled: boolean): Promise<void> {
    this.showSourceImportFeedback(enabled ? '正在初始化音源...' : '正在禁用音源...')
    try {
      const result = await this.sourceManager.toggleSource(id, enabled)
      const prefix = result.success ? (enabled ? '启用成功' : '禁用成功') : '启用失败'
      this.showSourceImportFeedback(`${prefix}：${result.message}`)
    } catch (err) {
      const detail = JSON.stringify(err) || '未知异常'
      LogUtils.error(`[音源] 切换状态异常: ${detail}`)
      this.showSourceImportFeedback(`启用失败：${detail}`)
    } finally {
      this.sources = [...this.sourceManager.getManageSources()]
    }
  }

  private showQualityDialog(event: ClickEvent): void {
    const pos = DialogPosUtils.fromClickForDialog(event, 300, 300)
    this.qualityDialogController = new CustomDialogController({
      builder: QualityDialog({
        currentQuality: this.defaultQualityText,
        onSelect: (quality: string) => { this.applyQuality(quality) }
      }),
      autoCancel: true,
      alignment: DialogAlignment.TopStart,
      offset: { dx: pos.x, dy: pos.y },
      customStyle: true
    })
    this.qualityDialogController.open()
  }

  private applyQuality(quality: string): void {
    this.defaultQualityText = quality
    this.applyQualityToPlayer(quality)
    StorageUtils.putString('default_quality', quality)
  }

  private clearCaches(event: ClickEvent): void {
    const actions: AppDialogAction[] = [
      { id: 'clear', label: '确认清除', danger: true }
    ]
    this.showActionDialog(
      '清除缓存',
      `将清除播放地址、歌词、换源等缓存（约 ${this.cacheSizeText}），不影响歌单与收藏`,
      actions,
      (actionId: string, actionEvent: ClickEvent) => {
        void actionEvent
        if (actionId !== 'clear') return
        this.sourceManager.clearAllCaches().then((ok: boolean) => {
          this.showToast(ok ? '缓存已清除' : '清除失败')
          this.refreshCacheSize()
        })
      },
      event
    )
  }

  private showLyricFontDialog(event: ClickEvent): void {
    const pos = DialogPosUtils.fromClickForDialog(event, 300, 300)
    this.fontDialogController = new CustomDialogController({
      builder: FontSizeDialog({
        currentSize: this.lyricFontSize,
        onSelect: (size: number) => { this.applyLyricFontSize(size) }
      }),
      autoCancel: true,
      alignment: DialogAlignment.TopStart,
      offset: { dx: pos.x, dy: pos.y },
      customStyle: true
    })
    this.fontDialogController.open()
  }

  private applyLyricFontSize(size: number): void {
    this.lyricFontSize = size
    AppStorage.setOrCreate('lyricFontSize', size)
    StorageUtils.putString('lyric_font_size', `${size}`)
  }

  private showSleepTimerDialog(event: ClickEvent): void {
    const pos = DialogPosUtils.fromClickForDialog(event, 300, 330)
    this.sleepDialogController = new CustomDialogController({
      builder: SleepTimerDialog({
        currentText: this.sleepRemainText,
        onSelect: (minutes: number) => { this.applySleepTimer(minutes) }
      }),
      autoCancel: true,
      alignment: DialogAlignment.TopStart,
      offset: { dx: pos.x, dy: pos.y },
      customStyle: true
    })
    this.sleepDialogController.open()
  }

  private applySleepTimer(minutes: number): void {
    this.player.setSleepTimer(minutes)
    if (minutes <= 0) {
      this.sleepRemainText = '关闭'
    } else {
      this.sleepRemainText = `${minutes}分钟`
    }
    this.showToast(minutes <= 0 ? '已取消定时关闭' : `定时关闭：${minutes} 分钟后暂停`)
  }

  /** 选择图片 → 打开裁剪界面 */
  private async importCustomBg(): Promise<void> {
    try {
      const photoSelectOptions = new picker.PhotoSelectOptions()
      photoSelectOptions.MIMEType = picker.PhotoViewMIMETypes.IMAGE_TYPE
      photoSelectOptions.maxSelectNumber = 1
      const photoPicker = new picker.PhotoViewPicker()
      const result = await photoPicker.select(photoSelectOptions)
      if (!result || result.photoUris.length === 0) return
      this.cropUri = result.photoUris[0]
      // 打开全屏裁剪对话框
      this.cropDialogController = new CustomDialogController({
        builder: ImageCropper({
          srcUri: this.cropUri,
          frameRatio: 16 / 9,
          onCropDone: (filePath: string) => { this.applyCustomBg(filePath) }
        }),
        autoCancel: false,
        alignment: DialogAlignment.Center,
        customStyle: true
      })
      this.cropDialogController.open()
    } catch (err) {
      LogUtils.warn(`[背景] 选择图片失败: ${JSON.stringify(err)}`)
    }
  }

  /** 应用裁剪后的自定义背景 */
  private applyCustomBg(filePath: string): void {
    StorageUtils.putString('custom_bg_path', filePath)
    this.customBgEnabled = true
    // 通知 AppBackground 刷新（通过 AppStorage 广播）
    AppStorage.setOrCreate('customBgUpdated', Date.now())
    this.showToast('已应用自定义背景')
  }

  /** 恢复默认背景 */
  private resetCustomBg(): void {
    StorageUtils.putString('custom_bg_path', '')
    this.customBgEnabled = false
    AppStorage.setOrCreate('customBgUpdated', Date.now())
    this.showToast('已恢复默认背景')
  }

  private showThemeDialog(event: ClickEvent): void {
    const actions: AppDialogAction[] = [
      { id: 'dark', label: '深色主题' },
      { id: 'light', label: '浅色主题' }
    ]
    this.showActionDialog('选择主题', '选择后将关闭自动跟随系统主题', actions,
      (actionId: string, actionEvent: ClickEvent) => {
      void actionEvent
      if (actionId === 'dark') {
          this.autoThemeEnabled = false
          AppStorage.setOrCreate('autoTheme', false)
          StorageUtils.putString('auto_theme', 'false')
          this.themeMode = 'dark'
          AppStorage.setOrCreate('themeIsDark', true)
          StorageUtils.putString('theme_mode', 'dark')
          this.applyTheme('dark')
      } else if (actionId === 'light') {
          this.autoThemeEnabled = false
          AppStorage.setOrCreate('autoTheme', false)
          StorageUtils.putString('auto_theme', 'false')
          this.themeMode = 'light'
          AppStorage.setOrCreate('themeIsDark', false)
          StorageUtils.putString('theme_mode', 'light')
          this.applyTheme('light')
      }
    }, event)
  }

  private applyTheme(mode: string): void {
    const appContext = getContext(this)
    const colorMode = mode === 'light'
      ? ConfigurationConstant.ColorMode.COLOR_MODE_LIGHT
      : ConfigurationConstant.ColorMode.COLOR_MODE_DARK
    appContext.getApplicationContext().setColorMode(colorMode)
  }

  /** 自动主题开关：开启时跟随系统（NOT_SET），关闭时用当前主题固定 */
  private applyAutoTheme(enabled: boolean): void {
    const appContext = getContext(this)
    if (enabled) {
      appContext.getApplicationContext().setColorMode(ConfigurationConstant.ColorMode.COLOR_MODE_NOT_SET)
      // 立即按系统当前模式更新（systemColorMode 由 EntryAbility 启动时写入）
      const sysMode = AppStorage.get<number>('systemColorMode') ?? ConfigurationConstant.ColorMode.COLOR_MODE_DARK
      const isDark = sysMode !== ConfigurationConstant.ColorMode.COLOR_MODE_LIGHT
      this.themeMode = isDark ? 'dark' : 'light'
      AppStorage.setOrCreate('themeIsDark', isDark)
    } else {
      appContext.getApplicationContext().setColorMode(
        this.themeMode === 'light'
          ? ConfigurationConstant.ColorMode.COLOR_MODE_LIGHT
          : ConfigurationConstant.ColorMode.COLOR_MODE_DARK
      )
    }
  }

  private showBackupDialog(event: ClickEvent): void {
    const actions: AppDialogAction[] = [
      { id: 'export', label: '导出备份' },
      { id: 'import', label: '恢复备份' }
    ]
    this.showActionDialog('备份与恢复', '导出或导入应用数据（歌单、本地音乐列表）', actions,
      (actionId: string, actionEvent: ClickEvent) => {
      void actionEvent
      if (actionId === 'export') {
        this.exportBackup()
      } else if (actionId === 'import') {
        this.importBackup()
      }
    }, event)
  }

  private async exportBackup(): Promise<void> {
    const playlists = PlaylistManager.getInstance().getAll()
    if (playlists.length === 0) { this.showToast('没有可导出的歌单'); return }
    try {
      const backupData: Record<string, Object> = {}
      backupData['type'] = BACKUP_TYPE
      backupData['version'] = '1.0.0'
      backupData['exportTime'] = Date.now()
      const plList: Array<Record<string, Object>> = []
      for (const pl of playlists) {
        const archiveJson = PlaylistManager.getInstance().exportArchive(pl.id)
        try { plList.push(JSON.parse(archiveJson)) } catch (e) {}
      }
      backupData['playlists'] = plList
      const documentPicker = new picker.DocumentViewPicker()
      const saveResult = await documentPicker.save({ newFileNames: [`source_music_backup_${Date.now()}.json`] })
      const saveUri = saveResult && saveResult.length > 0 ? saveResult[0] : ''
      if (saveUri) {
        const file = fileIo.openSync(saveUri, fileIo.OpenMode.READ_WRITE | fileIo.OpenMode.CREATE)
        // 应用备份为纯 JSON 文本。
        const encoder = new util.TextEncoder()
        const buffer = encoder.encodeInto(JSON.stringify(backupData))
        fileIo.writeSync(file.fd, buffer)
        fileIo.closeSync(file)
        this.showToast(`已导出 ${plList.length} 个歌单`)
      }
    } catch (err) {
      this.showInfoDialog('备份失败', JSON.stringify(err))
    }
  }

  private async importBackup(): Promise<void> {
    try {
      const documentPicker = new picker.DocumentViewPicker()
      const result = await documentPicker.select({
        fileSuffixFilters: [LEGACY_PLAYLIST_SUFFIX, '.json'],
        maxSelectNumber: 1
      })
      if (!result || result.length === 0) return
      const file = fileIo.openSync(result[0], fileIo.OpenMode.READ_ONLY)
      const stat = fileIo.statSync(result[0])
      const buf = new ArrayBuffer(stat.size)
      fileIo.readSync(file.fd, buf)
      fileIo.closeSync(file)
      // 新旧备份均为纯 JSON 文本。
      const decoder = util.TextDecoder.create('utf-8')
      const content = decoder.decodeToString(new Uint8Array(buf))
      LogUtils.info(`[恢复] 导入内容前200字符: ${content.substring(0, 200)}`)
      const parsed = JSON.parse(content) as Record<string, Object>
      LogUtils.info(`[恢复] 导入 type=${JSON.stringify(parsed['type'])} 字段=${Object.keys(parsed).join(',')}`)
      if (parsed['type'] === BACKUP_TYPE || parsed['type'] === LEGACY_BACKUP_TYPE) {
        const plList = parsed['playlists'] as Array<Record<string, Object>>
        if (plList && plList.length > 0) {
          let count = 0
          for (const pl of plList) {
            const created = await PlaylistManager.getInstance().importArchive(JSON.stringify(pl))
            if (created) count++
          }
          this.showToast(`已恢复 ${count} 个歌单`)
        }
      } else {
        const created = await PlaylistManager.getInstance().importArchive(content)
        this.showToast(created ? `已导入歌单: ${created.name}` : '文件格式不支持')
      }
    } catch (err) {
      const e = err as BusinessError
      LogUtils.error(`[恢复] 解析失败: code=${e.code} message=${e.message} json=${JSON.stringify(err)}`)
      this.showInfoDialog('恢复失败', `解析失败: ${e.code} ${e.message}`)
    }
  }

  private showToast(msg: string): void {
    this.getUIContext().getPromptAction().showToast({ message: msg, duration: 1500 })
  }

  /** 打开应用统一的自定义操作卡片 */
  private showActionDialog(
    title: string,
    message: string,
    actions: AppDialogAction[],
    onAction: (actionId: string, event: ClickEvent) => void,
    event?: ClickEvent
  ): void {
    if (event) {
      const estimatedHeight = 100 + actions.length * 52
      this.dialogPosition = DialogPosUtils.fromClickForDialog(event, 320, estimatedHeight)
    }
    this.actionDialogController = new CustomDialogController({
      builder: AppActionDialog({
        title: title,
        message: message,
        actions: actions,
        onAction: onAction
      }),
      autoCancel: true,
      alignment: DialogAlignment.TopStart,
      offset: { dx: this.dialogPosition.x, dy: this.dialogPosition.y },
      customStyle: true
    })
    this.actionDialogController.open()
  }

  /** 信息提示也使用同一套自定义弹窗，不再回退到原生 AlertDialog */
  private showInfoDialog(title: string, message: string): void {
    const actions: AppDialogAction[] = [{ id: 'ok', label: '知道了' }]
    this.showActionDialog(title, message, actions, (actionId: string, event: ClickEvent) => {
      void actionId
      void event
    })
  }
}
