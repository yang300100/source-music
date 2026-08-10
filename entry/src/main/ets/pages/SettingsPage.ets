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
import { EqDialog } from '../components/common/EqDialog'
import { DialogPosition, DialogPosUtils } from '../utils/DialogPosUtils'
import { ThemeColors } from '../theme/ThemeColors'
import { MotionTokens } from '../theme/MotionTokens'

const BACKUP_TYPE = 'sourceMusicBackup'

/** 分类项定义 */
interface SettingCategory {
  id: string
  name: string
  summary: string
}

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
  @State eqEnabled: boolean = false
  @State eqSupported: boolean = false
  @State eqPresetText: string = '默认'
  @State cacheSizeText: string = '计算中...'
  @State customBgEnabled: boolean = false
  @State cropUri: string = ''
  @StorageLink('lyricShowTranslation') lyricShowTranslation: boolean = true
  @StorageLink('lyricFontSize') lyricFontSize: number = 14
  /** 当前选中的分类 id（空 = 未展开，仅显示分类列表） */
  @State selectedCategory: string = ''
  /** 面板方向 */
  @Prop panelSide: string = 'left'
  /** 选中状态变化回调（通知外部调整面板宽度） */
  onSelectionChange: (hasSelection: boolean) => void = (hasSelection: boolean) => {}
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
  private eqDialogController: CustomDialogController | null = null
  private actionDialogController: CustomDialogController | null = null
  private dialogPosition: DialogPosition = new DialogPosition()

  private get primaryText(): ResourceColor { return ThemeColors.primaryText(this.isDark) }
  private get secondaryText(): ResourceColor { return ThemeColors.secondaryText(this.isDark) }
  private get accentColor(): ResourceColor { return ThemeColors.accentColor() }
  private get sidebarBg(): ResourceColor { return ThemeColors.sidebarBg(this.isDark) }
  private get borderFaint(): ResourceColor { return ThemeColors.borderFaint(this.isDark) }
  private get cardBg(): ResourceColor { return ThemeColors.cardBg(this.isDark) }

  private categories: SettingCategory[] = [
    { id: 'musicImport', name: '音乐导入', summary: '' },
    { id: 'source', name: '音源管理', summary: '' },
    { id: 'appearance', name: '外观', summary: '' },
    { id: 'audio', name: '音质', summary: '' },
    { id: 'play', name: '播放', summary: '' },
    { id: 'lyric', name: '歌词', summary: '' },
    { id: 'data', name: '数据', summary: '' },
    { id: 'about', name: '关于', summary: '源音乐 v0.1.0' }
  ]

  // 更新分类摘要
  private getCategorySummary(id: string): string {
    switch (id) {
      case 'musicImport': return `${this.localSongCount} 首`
      case 'source': return `${this.sources.length} 个`
      case 'appearance': return this.themeMode === 'dark' ? '深色' : '浅色'
      case 'audio': return this.eqEnabled ? this.eqPresetText : this.defaultQualityText
      case 'play': return this.sleepRemainText !== '关闭' ? `定时${this.sleepRemainText}` : ''
      case 'lyric': return `${this.lyricFontSize}`
      case 'data': return this.cacheSizeText
      case 'about': return '源音乐 v0.1.0'
      default: return ''
    }
  }

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
    this.eqEnabled = this.player.eqEnabled
    this.eqSupported = this.player.eqSupported
    this.eqPresetText = this.getEqPresetLabel(this.player.eqPreset)
    this.refreshCacheSize()
    this.sources = [...this.sourceManager.getManageSources()]
  }

  private applyQualityToPlayer(quality: string): void {
    if (quality === '128k') { this.player.defaultQuality = MusicQuality.LOW }
    else if (quality === 'flac') { this.player.defaultQuality = MusicQuality.LOSSLESS }
    else { this.player.defaultQuality = MusicQuality.HIGH }
  }

  private refreshCacheSize(): void {
    this.sourceManager.getCacheSize().then((size: number) => {
      if (size <= 0) { this.cacheSizeText = '0 KB' }
      else if (size < 1024 * 1024) { this.cacheSizeText = `${(size / 1024).toFixed(0)} KB` }
      else { this.cacheSizeText = `${(size / 1024 / 1024).toFixed(1)} MB` }
    }).catch(() => { this.cacheSizeText = '0 KB' })
  }

  build() {
    if (this.panelSide === 'right') {
      // 右侧面板：侧栏贴右缘，详情在左展开
      Stack({ alignContent: Alignment.End }) {
        if (this.selectedCategory) {
          Column() {
            this.DetailTitle()
            Scroll() { this.DetailContent() }
              .width('100%').layoutWeight(1).scrollBar(BarState.Auto)
          }
          .width('100%').height('100%')
          .padding({ left: 12, right: 12 })
          .padding({ right: 160 })
          .alignItems(HorizontalAlign.Start)
          .transition(TransitionEffect.OPACITY.animation({ duration: 350, curve: Curve.FastOutSlowIn })
            .combine(TransitionEffect.translate({ x: 16, y: 0 })
              .animation({ duration: 350, curve: Curve.FastOutSlowIn })))
        }

        this.Sidebar(true)
      }
      .width('100%').height('100%').clip(true)
    } else {
      // 左侧面板：侧栏贴左缘，详情在右展开
      Stack({ alignContent: Alignment.Start }) {
        if (this.selectedCategory) {
          Column() {
            this.DetailTitle()
            Scroll() { this.DetailContent() }
              .width('100%').layoutWeight(1).scrollBar(BarState.Auto)
          }
          .width('100%').height('100%')
          .padding({ left: 12, right: 12 })
          .padding({ left: 160 })
          .alignItems(HorizontalAlign.Start)
          .transition(TransitionEffect.OPACITY.animation({ duration: 350, curve: Curve.FastOutSlowIn })
            .combine(TransitionEffect.translate({ x: -16, y: 0 })
              .animation({ duration: 350, curve: Curve.FastOutSlowIn })))
        }

        this.Sidebar(false)
      }
      .width('100%').height('100%').clip(true)
    }
  }

  @Builder
  DetailTitle() {
    Text(this.getCategoryName(this.selectedCategory))
      .fontSize(20).fontWeight(FontWeight.Bold).fontColor(this.primaryText)
      .padding({ left: 8, top: 16, bottom: 12 })
      .width('100%')
  }

  @Builder
  DetailContent() {
    Column({ space: 4 }) {
      if (this.selectedCategory === 'musicImport') {
        SettingsRow({ title: '导入本地音乐', value: '选择音频文件', showArrow: true,
          onRowClick: (event: ClickEvent) => { void event; this.importLocalMusic() } })
        SettingsRow({ title: '扫描文件夹导入',
          subtitle: '选择文件夹，自动解析封面/歌手等信息', showArrow: true,
          onRowClick: (event: ClickEvent) => { void event; this.importLocalFolder() } })
      } else if (this.selectedCategory === 'source') {
        SourceManagePanel({
          sources: this.sources, importStatus: this.sourceImportStatus,
          onToggleSource: (srcId: string, enabled: boolean) => { this.toggleSource(srcId, enabled) },
          onRemoveSource: (srcId: string) => {
            this.sourceManager.removeSource(srcId).then(() => { this.sources = [...this.sourceManager.getManageSources()] })
          },
          showImportDialog: (event: ClickEvent) => { this.showImportSourceDialog(event) }
        })
        SettingsRow({ title: '扩展音源搜索',
          subtitle: this.extendedSearchEnabled ? '允许声明 search 的源参与搜索' : '标准解析：自定义源只解析播放',
          showToggle: true, isOn: this.extendedSearchEnabled,
          onToggle: (checked: boolean) => { this.toggleExtendedSearch(checked) } })
      } else if (this.selectedCategory === 'appearance') {
        SettingsRow({ title: '自动跟随系统主题', showToggle: true, isOn: this.autoThemeEnabled,
          onToggle: (checked: boolean) => { this.toggleAutoTheme(checked) } })
        SettingsRow({ title: '主题', value: this.themeMode === 'dark' ? '深色' : '浅色',
          onRowClick: (event: ClickEvent) => { this.showThemeDialog(event) } })
        SettingsRow({ title: '自定义背景',
          subtitle: this.customBgEnabled ? '已启用（点击更换）' : '从相册选择图片作为背景',
          value: this.customBgEnabled ? '更换' : '',
          onRowClick: (event: ClickEvent) => { void event; this.importCustomBg() } })
        if (this.customBgEnabled) {
          SettingsRow({ title: '恢复默认背景',
            onRowClick: (event: ClickEvent) => { void event; this.resetCustomBg() } })
        }
      } else if (this.selectedCategory === 'audio') {
        SettingsRow({ title: '默认音质', value: this.defaultQualityText,
          onRowClick: (event: ClickEvent) => { this.showQualityDialog(event) } })
        SettingsRow({ title: '十段均衡器',
          subtitle: this.eqSupported ? '31Hz—16kHz，支持预设与自定义调节' : '当前设备系统版本不支持',
          value: this.eqSupported ? (this.eqEnabled ? this.eqPresetText : '关闭') : '不支持',
          showArrow: this.eqSupported, onRowClick: (event: ClickEvent) => { this.showEqDialog(event) } })
      } else if (this.selectedCategory === 'play') {
        SettingsRow({ title: '定时关闭', value: this.sleepRemainText,
          onRowClick: (event: ClickEvent) => { this.showSleepTimerDialog(event) } })
        SettingsRow({ title: '保存播放进度', subtitle: '下次播放时从断点继续',
          showToggle: true, isOn: this.saveProgressEnabled,
          onToggle: (checked: boolean) => { this.toggleSaveProgress(checked) } })
        SettingsRow({ title: '自动清理已播列表', subtitle: '播放完成自动移除该曲',
          showToggle: true, isOn: this.autoCleanPlayedEnabled,
          onToggle: (checked: boolean) => { this.toggleAutoCleanPlayed(checked) } })
        SettingsRow({ title: '启动时自动播放上次歌曲',
          showToggle: true, isOn: this.autoPlayEnabled,
          onToggle: (checked: boolean) => { this.toggleAutoPlay(checked) } })
      } else if (this.selectedCategory === 'lyric') {
        SettingsRow({ title: '歌词翻译', showToggle: true, isOn: this.lyricShowTranslation,
          onToggle: (checked: boolean) => { this.toggleLyricTranslation(checked) } })
        SettingsRow({ title: '歌词字号', value: `${this.lyricFontSize}`,
          onRowClick: (event: ClickEvent) => { this.showLyricFontDialog(event) } })
      } else if (this.selectedCategory === 'data') {
        SettingsRow({ title: '备份与恢复', showArrow: true,
          onRowClick: (event: ClickEvent) => { this.showBackupDialog(event) } })
        SettingsRow({ title: '清除缓存', value: this.cacheSizeText,
          onRowClick: (event: ClickEvent) => { this.clearCaches(event) } })
      } else if (this.selectedCategory === 'about') {
        Column({ space: 4 }) {
          Text('源音乐').fontSize(24).fontWeight(FontWeight.Bold).fontColor(this.primaryText)
          Text('HarmonyOS 原生音乐播放器').fontSize(14).fontColor(this.secondaryText)
          Text('壳与音源分离架构，兼容 LX Music 社区音源生态').fontSize(12).fontColor(this.secondaryText)
          Text('Version 0.2.2').fontSize(14).fontColor(this.accentColor).margin({ top: 8 })
        }.width('100%').alignItems(HorizontalAlign.Start).padding(4)
      }
    }
    .width('100%').alignItems(HorizontalAlign.Start)
  }

  @Builder
  Sidebar(borderOnLeft: boolean) {
    Column() {
      Text('设置')
        .fontSize(16).fontWeight(FontWeight.Bold).fontColor(this.primaryText)
        .padding({ left: 12, right: 12, top: 16, bottom: 10 })

      List({ space: 2 }) {
        ForEach(this.categories, (cat: SettingCategory) => {
          ListItem() { this.CategoryRow(cat) }
        })
      }
      .width('100%').layoutWeight(1).scrollBar(BarState.Off)
    }
    .width(160).height('100%')
    .backgroundColor(this.sidebarBg).backdropBlur(20)
    .border(borderOnLeft
      ? { width: { left: this.selectedCategory ? 0.5 : 0 }, color: this.borderFaint }
      : { width: { right: this.selectedCategory ? 0.5 : 0 }, color: this.borderFaint })
  }

  @Builder
  CategoryRow(cat: SettingCategory) {
    Row() {
      Column({ space: 2 }) {
        Text(cat.name)
          .fontSize(13)
          .fontColor(this.selectedCategory === cat.id ? this.accentColor : this.primaryText)
          .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
        if (this.getCategorySummary(cat.id)) {
          Text(this.getCategorySummary(cat.id))
            .fontSize(10).fontColor(this.secondaryText)
            .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
        }
      }
      .layoutWeight(1)
    }
    .width('100%')
    .padding({ left: 12, right: 12, top: 10, bottom: 10 })
    .borderRadius(8)
    .backgroundColor(this.selectedCategory === cat.id ? (this.isDark ? '#15b388ff' : '#10b388ff') : Color.Transparent)
    .scale({ x: this.selectedCategory === cat.id ? 1.02 : 1, y: this.selectedCategory === cat.id ? 1.02 : 1 })
    .animation({ duration: MotionTokens.NORMAL, curve: Curve.FastOutSlowIn })
    .onClick(() => {
      const newId = (this.selectedCategory === cat.id) ? '' : cat.id
      this.selectedCategory = newId
      this.onSelectionChange(newId !== '')
    })
  }

  private getCategoryName(id: string): string {
    const found = this.categories.find((c: SettingCategory) => c.id === id)
    return found ? found.name : ''
  }

  // ===== toggle 辅助方法 =====
  private toggleExtendedSearch(checked: boolean): void {
    const previous = this.extendedSearchEnabled
    this.extendedSearchEnabled = checked
    this.sourceManager.setExtendedSearchEnabled(checked).then(() => {
      this.showSourceImportFeedback(checked ? '扩展音源搜索已开启' : '已恢复标准解析模式')
    }).catch((err: Error) => {
      this.extendedSearchEnabled = previous
      this.showSourceImportFeedback('设置保存失败，请重试')
    })
  }

  private toggleAutoTheme(checked: boolean): void {
    this.autoThemeEnabled = checked
    AppStorage.setOrCreate('autoTheme', checked)
    StorageUtils.putString('auto_theme', checked ? 'true' : 'false')
    this.applyAutoTheme(checked)
  }

  private toggleSaveProgress(checked: boolean): void {
    this.saveProgressEnabled = checked
    this.player.savePlayProgress = checked
    StorageUtils.putString('save_play_progress', checked ? 'true' : 'false')
  }

  private toggleAutoCleanPlayed(checked: boolean): void {
    this.autoCleanPlayedEnabled = checked
    this.player.autoCleanPlayed = checked
    StorageUtils.putString('auto_clean_played', checked ? 'true' : 'false')
  }

  private toggleAutoPlay(checked: boolean): void {
    this.autoPlayEnabled = checked
    StorageUtils.putString('auto_play_enabled', checked ? 'true' : 'false')
  }

  private toggleLyricTranslation(checked: boolean): void {
    this.lyricShowTranslation = checked
    AppStorage.setOrCreate('lyricShowTranslation', checked)
    StorageUtils.putString('lyric_show_translation', checked ? 'true' : 'false')
  }

  // ===== 弹窗/操作逻辑 =====
  private showImportSourceDialog(event: ClickEvent): void {
    const actions: AppDialogAction[] = [
      { id: 'local', label: '从本地文件导入' },
      { id: 'online', label: '从在线链接导入' }
    ]
    this.showActionDialog('导入音源', '支持社区 .js 音源脚本', actions,
      (actionId: string, actionEvent: ClickEvent) => {
      if (actionId === 'local') { this.importSourceFromLocal() }
      else if (actionId === 'online') { this.importSourceFromOnline(actionEvent) }
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

  private async importLocalFolder(): Promise<void> {
    try {
      const documentPicker = new picker.DocumentViewPicker()
      const result = await documentPicker.select({ selectMode: picker.DocumentSelectMode.FOLDER })
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
      const result = await documentPicker.select({ fileSuffixFilters: ['.js'], maxSelectNumber: 1 })
      if (!result || result.length === 0) { this.showSourceImportFeedback('已取消导入音源'); return }
      this.showSourceImportFeedback('正在导入音源...')
      const ret = await this.sourceManager.importSource(SourceImportMethod.LOCAL_FILE, result[0])
      const message = ret.success ? `导入成功：${ret.source?.info.name ?? '未知音源'}（请手动启用）` :
        `导入失败：${ret.error ?? '未知错误'}`
      this.showSourceImportFeedback(message)
    } catch (err) {
      const error = err as BusinessError
      this.showSourceImportFeedback(`导入失败：${error.message || JSON.stringify(err)}`)
    } finally {
      this.sources = [...this.sourceManager.getManageSources()]
    }
  }

  private onlineSourceDialog: CustomDialogController | null = null

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
          if (!trimmed.startsWith('http')) { this.showToast('请输入有效的 http(s) 链接'); return }
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

  private async importSourceFromUrl(url: string): Promise<void> {
    this.showSourceImportFeedback('正在导入音源...')
    try {
      const ret = await this.sourceManager.importSource(SourceImportMethod.ONLINE_URL, url)
      const message = ret.success ? `导入成功：${ret.source?.info.name ?? '未知音源'}（请手动启用）` :
        `导入失败：${ret.error ?? '未知错误'}`
      this.showSourceImportFeedback(message)
    } catch (err) {
      const error = err as BusinessError
      this.showSourceImportFeedback(`导入失败：${error.message || JSON.stringify(err)}`)
    } finally { this.sources = [...this.sourceManager.getManageSources()] }
  }

  private showSourceImportFeedback(message: string): void {
    this.sourceImportStatus = message
    try { this.showToast(message) } catch (err) {}
  }

  private async toggleSource(id: string, enabled: boolean): Promise<void> {
    this.showSourceImportFeedback(enabled ? '正在初始化音源...' : '正在禁用音源...')
    try {
      const result = await this.sourceManager.toggleSource(id, enabled)
      this.showSourceImportFeedback(`${result.success ? (enabled ? '启用成功' : '禁用成功') : '启用失败'}：${result.message}`)
    } catch (err) {
      this.showSourceImportFeedback(`操作失败：${JSON.stringify(err)}`)
    } finally { this.sources = [...this.sourceManager.getManageSources()] }
  }

  private showQualityDialog(event: ClickEvent): void {
    const pos = DialogPosUtils.fromClickForDialog(event, 300, 300)
    this.qualityDialogController = new CustomDialogController({
      builder: QualityDialog({
        currentQuality: this.defaultQualityText,
        onSelect: (quality: string) => { this.applyQuality(quality) }
      }),
      autoCancel: true, alignment: DialogAlignment.TopStart,
      offset: { dx: pos.x, dy: pos.y }, customStyle: true
    })
    this.qualityDialogController.open()
  }

  private getEqPresetLabel(preset: string): string {
    if (preset === 'ballad') return '民谣'
    if (preset === 'chinese') return '中国风'
    if (preset === 'classical') return '古典'
    if (preset === 'dance') return '舞曲'
    if (preset === 'jazz') return '爵士'
    if (preset === 'pop') return '流行'
    if (preset === 'rb') return 'R&B'
    if (preset === 'rock') return '摇滚'
    if (preset === 'custom') return '自定义'
    return '默认'
  }

  private showEqDialog(event: ClickEvent): void {
    if (!this.eqSupported) { this.showToast('当前设备系统版本不支持十段均衡器'); return }
    const pos = DialogPosUtils.fromClickForDialog(event, 540, 430)
    this.eqDialogController = new CustomDialogController({
      builder: EqDialog({
        eqEnabled: this.player.eqEnabled,
        supported: this.player.eqSupported,
        preset: this.player.eqPreset,
        gains: [...this.player.eqGains],
        onEnabledChange: (enabled: boolean) => {
          this.player.setEqEnabled(enabled).then((success: boolean) => {
            if (success) { this.eqEnabled = enabled; this.showToast(enabled ? '均衡器已开启' : '均衡器已关闭') }
            else { this.showToast('均衡器开关失败') }
          })
        },
        onPresetChange: (preset: string) => {
          this.player.setEqPreset(preset).then((success: boolean) => {
            if (success) { this.eqPresetText = this.getEqPresetLabel(preset) }
            else { this.showToast('预设应用失败') }
          })
        },
        onGainsChange: (gains: number[]) => {
          this.player.setEqGains(gains).then((success: boolean) => {
            if (success) { this.eqPresetText = '自定义' }
          })
        }
      }),
      autoCancel: true, alignment: DialogAlignment.TopStart,
      offset: { dx: pos.x, dy: pos.y }, customStyle: true
    })
    this.eqDialogController.open()
  }

  private applyQuality(quality: string): void {
    this.defaultQualityText = quality
    this.applyQualityToPlayer(quality)
    StorageUtils.putString('default_quality', quality)
  }

  private clearCaches(event: ClickEvent): void {
    const actions: AppDialogAction[] = [{ id: 'clear', label: '确认清除', danger: true }]
    this.showActionDialog('清除缓存',
      `将清除播放地址、歌词、换源等缓存（约 ${this.cacheSizeText}），不影响歌单与收藏`,
      actions, (actionId: string, actionEvent: ClickEvent) => {
        void actionEvent
        if (actionId !== 'clear') return
        this.sourceManager.clearAllCaches().then((ok: boolean) => {
          this.showToast(ok ? '缓存已清除' : '清除失败')
          this.refreshCacheSize()
        })
      }, event)
  }

  private showLyricFontDialog(event: ClickEvent): void {
    const pos = DialogPosUtils.fromClickForDialog(event, 300, 300)
    this.fontDialogController = new CustomDialogController({
      builder: FontSizeDialog({
        currentSize: this.lyricFontSize,
        onSelect: (size: number) => { this.applyLyricFontSize(size) }
      }),
      autoCancel: true, alignment: DialogAlignment.TopStart,
      offset: { dx: pos.x, dy: pos.y }, customStyle: true
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
      autoCancel: true, alignment: DialogAlignment.TopStart,
      offset: { dx: pos.x, dy: pos.y }, customStyle: true
    })
    this.sleepDialogController.open()
  }

  private applySleepTimer(minutes: number): void {
    this.player.setSleepTimer(minutes)
    if (minutes <= 0) { this.sleepRemainText = '关闭' }
    else { this.sleepRemainText = `${minutes}分钟` }
    this.showToast(minutes <= 0 ? '已取消定时关闭' : `定时关闭：${minutes} 分钟后暂停`)
  }

  private async importCustomBg(): Promise<void> {
    try {
      const photoSelectOptions = new picker.PhotoSelectOptions()
      photoSelectOptions.MIMEType = picker.PhotoViewMIMETypes.IMAGE_TYPE
      photoSelectOptions.maxSelectNumber = 1
      const photoPicker = new picker.PhotoViewPicker()
      const result = await photoPicker.select(photoSelectOptions)
      if (!result || result.photoUris.length === 0) return
      this.cropUri = result.photoUris[0]
      this.cropDialogController = new CustomDialogController({
        builder: ImageCropper({
          srcUri: this.cropUri, frameRatio: 16 / 9,
          onCropDone: (filePath: string) => { this.applyCustomBg(filePath) }
        }),
        autoCancel: false, alignment: DialogAlignment.Center, customStyle: true
      })
      this.cropDialogController.open()
    } catch (err) { LogUtils.warn(`[背景] 选择图片失败: ${JSON.stringify(err)}`) }
  }

  private applyCustomBg(filePath: string): void {
    StorageUtils.putString('custom_bg_path', filePath)
    this.customBgEnabled = true
    AppStorage.setOrCreate('customBgUpdated', Date.now())
    this.showToast('已应用自定义背景')
  }

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
      this.autoThemeEnabled = false
      AppStorage.setOrCreate('autoTheme', false)
      StorageUtils.putString('auto_theme', 'false')
      if (actionId === 'dark') {
        this.themeMode = 'dark'
        AppStorage.setOrCreate('themeIsDark', true)
        StorageUtils.putString('theme_mode', 'dark')
        this.applyTheme('dark')
      } else if (actionId === 'light') {
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

  private applyAutoTheme(enabled: boolean): void {
    const appContext = getContext(this)
    if (enabled) {
      appContext.getApplicationContext().setColorMode(ConfigurationConstant.ColorMode.COLOR_MODE_NOT_SET)
      const sysMode = AppStorage.get<number>('systemColorMode') ?? ConfigurationConstant.ColorMode.COLOR_MODE_DARK
      const isDark = sysMode !== ConfigurationConstant.ColorMode.COLOR_MODE_LIGHT
      this.themeMode = isDark ? 'dark' : 'light'
      AppStorage.setOrCreate('themeIsDark', isDark)
    } else {
      appContext.getApplicationContext().setColorMode(
        this.themeMode === 'light'
          ? ConfigurationConstant.ColorMode.COLOR_MODE_LIGHT
          : ConfigurationConstant.ColorMode.COLOR_MODE_DARK)
    }
  }

  private showBackupDialog(event: ClickEvent): void {
    const actions: AppDialogAction[] = [
      { id: 'export', label: '导出备份' },
      { id: 'import', label: '恢复备份' }
    ]
    const estimatedHeight = 100 + actions.length * 52
    this.dialogPosition = DialogPosUtils.fromClickForDialog(event, 320, estimatedHeight)
    if (this.dialogPosition.x < 10 && this.dialogPosition.y < 30) {
      this.dialogPosition.x = Math.max(8, DialogPosUtils.screenWidth() / 2 - 160)
      this.dialogPosition.y = DialogPosUtils.screenHeight() / 3
    }
    this.actionDialogController = new CustomDialogController({
      builder: AppActionDialog({
        title: '备份与恢复',
        message: '导出或导入应用数据（歌单、本地音乐列表）',
        actions: actions,
        onAction: (actionId: string, actionEvent: ClickEvent) => {
          void actionEvent
          if (actionId === 'export') { this.exportBackup() }
          else if (actionId === 'import') { this.importBackup() }
        }
      }),
      autoCancel: true, alignment: DialogAlignment.TopStart,
      offset: { dx: this.dialogPosition.x, dy: this.dialogPosition.y }, customStyle: true
    })
    this.actionDialogController.open()
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
        const encoder = new util.TextEncoder()
        const buffer = encoder.encodeInto(JSON.stringify(backupData))
        fileIo.writeSync(file.fd, buffer)
        fileIo.closeSync(file)
        this.showToast(`已导出 ${plList.length} 个歌单`)
      }
    } catch (err) { this.showInfoDialog('备份失败', JSON.stringify(err)) }
  }

  private async importBackup(): Promise<void> {
    try {
      const documentPicker = new picker.DocumentViewPicker()
      const result = await documentPicker.select({ fileSuffixFilters: ['.json'], maxSelectNumber: 1 })
      if (!result || result.length === 0) return
      const file = fileIo.openSync(result[0], fileIo.OpenMode.READ_ONLY)
      const stat = fileIo.statSync(result[0])
      const buf = new ArrayBuffer(stat.size)
      fileIo.readSync(file.fd, buf)
      fileIo.closeSync(file)
      const decoder = util.TextDecoder.create('utf-8')
      const content = decoder.decodeToString(new Uint8Array(buf))
      const parsed = JSON.parse(content) as Record<string, Object>
      if (parsed['type'] !== BACKUP_TYPE) {
        this.showInfoDialog('格式不支持', '仅支持 JSON 格式的源音乐备份文件'); return
      }
      const plList = parsed['playlists'] as Array<Record<string, Object>>
      if (plList && plList.length > 0) {
        let count = 0
        for (const pl of plList) {
          const created = await PlaylistManager.getInstance().importArchive(JSON.stringify(pl))
          if (created) count++
        }
        this.showToast(`已恢复 ${count} 个歌单`)
      } else { this.showToast('备份中没有歌单数据') }
    } catch (err) {
      const e = err as BusinessError
      this.showInfoDialog('恢复失败', `解析失败: ${e.code} ${e.message}`)
    }
  }

  private showToast(msg: string): void {
    this.getUIContext().getPromptAction().showToast({ message: msg, duration: 1500 })
  }

  private showActionDialog(
    title: string, message: string, actions: AppDialogAction[],
    onAction: (actionId: string, event: ClickEvent) => void, event?: ClickEvent
  ): void {
    if (event) {
      const estimatedHeight = 100 + actions.length * 52
      this.dialogPosition = DialogPosUtils.fromClickForDialog(event, 320, estimatedHeight)
    }
    this.actionDialogController = new CustomDialogController({
      builder: AppActionDialog({ title: title, message: message, actions: actions, onAction: onAction }),
      autoCancel: true, alignment: DialogAlignment.TopStart,
      offset: { dx: this.dialogPosition.x, dy: this.dialogPosition.y }, customStyle: true
    })
    this.actionDialogController.open()
  }

  private showInfoDialog(title: string, message: string): void {
    const actions: AppDialogAction[] = [{ id: 'ok', label: '知道了' }]
    this.showActionDialog(title, message, actions, (actionId: string, event: ClickEvent) => {
      void actionId; void event
    })
  }
}
