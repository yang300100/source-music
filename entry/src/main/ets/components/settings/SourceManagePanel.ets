import { SourceManager } from 'hsp_source'
import { SourceInstance, SourceTestResult } from 'common'
import { ThemeColors } from '../../theme/ThemeColors'
import { MotionTokens } from '../../theme/MotionTokens'

/**
 * 音源管理面板组件
 *
 * 导入本地音乐、导入音源（本地文件/在线链接）、
 * 音源列表（开关/删除/手动测试）。导入阶段不执行第三方脚本。
 */
@Component
export struct SourceManagePanel {
  @StorageLink('themeIsDark') isDark: boolean = true
  /** 音源列表 */
  @Prop sources: SourceInstance[] = []
  /** 最近一次导入状态：作为 Toast 之外的持久反馈，避免提示被系统文件选择器遮住 */
  @Prop importStatus: string = ''
  /** 切换音源开关 */
  onToggleSource: (id: string, enabled: boolean) => void = (id: string, enabled: boolean) => {}
  /** 删除音源 */
  onRemoveSource: (id: string) => void = (id: string) => {}
  /** 展示导入方式选择弹窗 */
  showImportDialog: (event: ClickEvent) => void = (event: ClickEvent) => {}

  /** 测试结果缓存：id → { success, message } */
  @State testResults: Record<string, string> = {}

  private get primaryText(): ResourceColor { return ThemeColors.primaryText(this.isDark) }
  private get secondaryText(): ResourceColor { return ThemeColors.secondaryText(this.isDark) }
  private get cardBg(): ResourceColor { return ThemeColors.cardBg(this.isDark) }
  private get borderFaint(): ResourceColor { return ThemeColors.borderFaint(this.isDark) }

  /** 测试指定音源并更新状态 */
  private testSource(id: string): void {
    this.testResults[id] = 'testing'
    SourceManager.getInstance().testSource(id).then((result: SourceTestResult) => {
      this.testResults[id] = result.success ? `ok:${result.message}` : `fail:${result.message}`
    }).catch(() => {
      this.testResults[id] = 'fail:测试异常'
    })
  }

  build() {
    Column({ space: 6 }) {
      Row() {
        Text('+ 导入音源').fontSize(14).fontColor('#b388ff')
        Blank()
        Text('支持 .js 音源脚本').fontSize(11).fontColor(this.secondaryText)
      }
      .width('100%').padding({ left: 16, right: 16, top: 12, bottom: 12 })
      .stateStyles({
        normal: { .opacity(1).scale({ x: 1, y: 1 }) },
        pressed: { .opacity(0.75).scale({ x: MotionTokens.PRESSED_SCALE, y: MotionTokens.PRESSED_SCALE }) }
      })
      .onClick((event: ClickEvent) => { this.showImportDialog(event) })

      if (this.importStatus) {
        Text(this.importStatus)
          .fontSize(11)
          .fontColor((this.importStatus.startsWith('导入成功') ||
            this.importStatus.startsWith('启用成功') || this.importStatus.startsWith('禁用成功')) ? '#7ed6a5' :
            (this.importStatus.startsWith('正在') ? '#b388ff' : '#e86090'))
          .width('100%')
          .padding({ left: 16, right: 16, bottom: 8 })
          .transition(TransitionEffect.OPACITY.animation({ duration: MotionTokens.NORMAL, curve: Curve.EaseOut })
            .combine(TransitionEffect.translate({ x: 0, y: -6 })
              .animation({ duration: MotionTokens.NORMAL, curve: Curve.FastOutSlowIn })))
      }

      ForEach(this.sources, (source: SourceInstance, index: number) => {
        Row({ space: 12 }) {
          Column({ space: 2 }) {
            Text(source.info.name).fontSize(14).fontColor(this.primaryText).fontWeight(FontWeight.Medium)
            Text(`v${source.info.version} · ${source.info.author}`)
              .fontSize(10).fontColor(this.secondaryText)
            Text(this.getSourceTypeLabel(source.info.id))
              .fontSize(10).fontColor('#b388ff')
            // 测试状态显示
            if (this.testResults[source.info.id]) {
              Text(this.getTestText(source.info.id))
                .fontSize(10)
                .fontColor(this.testResults[source.info.id].startsWith('ok') ? '#7ed6a5' : '#e86090')
                .onClick(() => { this.testSource(source.info.id) })
            }
          }
          .layoutWeight(1)
          .alignItems(HorizontalAlign.Start)

          // 测试按钮
          Text('测试')
            .fontSize(11)
            .fontColor('#b388ff')
            .padding({ left: 8, right: 8, top: 3, bottom: 3 })
            .backgroundColor('#20b388ff')
            .borderRadius(6)
            .stateStyles({
              normal: { .opacity(1).scale({ x: 1, y: 1 }) },
              pressed: { .opacity(0.72).scale({ x: MotionTokens.CHIP_PRESSED_SCALE,
                y: MotionTokens.CHIP_PRESSED_SCALE }) }
            })
            .onClick(() => { this.testSource(source.info.id) })

          // 内置搜索源始终启用；只有用户导入的解析源采用单选开关。
          if (!this.isProtectedSource(source.info.id)) {
            Toggle({ type: ToggleType.Switch, isOn: source.enabled })
              .selectedColor('#b388ff')
              .scale({ x: source.enabled ? 1.04 : 1, y: source.enabled ? 1.04 : 1 })
              .animation({ duration: MotionTokens.NORMAL, curve: Curve.FastOutSlowIn })
              .onChange((isOn: boolean) => { this.onToggleSource(source.info.id, isOn) })
          }

          if (!this.isProtectedSource(source.info.id)) {
            Text('删除').fontSize(12).fontColor('#e86090')
              .onClick(() => { this.onRemoveSource(source.info.id) })
          }
        }
        .width('100%')
        .padding({ left: 16, right: 16, top: 10, bottom: 10 })
        .transition(TransitionEffect.OPACITY.animation({ duration: MotionTokens.LIST,
          delay: MotionTokens.staggerDelay(index), curve: Curve.EaseOut })
          .combine(TransitionEffect.translate({ x: 0, y: 10 })
            .animation({ duration: MotionTokens.LIST, delay: MotionTokens.staggerDelay(index),
              curve: Curve.FastOutSlowIn })))
      }, (source: SourceInstance) => source.info.id)
    }
    .width('100%')
    .padding({ left: 8, right: 8, top: 4, bottom: 4 })
    .backgroundColor(this.isDark ? '#40141220' : '#60ffffff')
    .borderRadius(10)
    .border({ width: 0.5, color: this.borderFaint })
  }

  private getTestText(id: string): string {
    const raw = this.testResults[id]
    if (raw === 'testing') return '测试中...'
    if (raw.startsWith('ok:')) return `✓ ${raw.substring(3)}（点击重测）`
    if (raw.startsWith('fail:')) return `✗ ${raw.substring(5)}（点击重测）`
    return raw
  }

  private getSourceTypeLabel(id: string): string {
    if (id === 'local_source') return '本地文件源（始终启用）'
    if (id === 'demo') return '演示源（始终启用）'
    if (this.isBuiltInSearchSource(id)) return '内置搜索源（始终启用）'
    return '自定义解析源（单选）'
  }

  private isBuiltInSearchSource(id: string): boolean {
    return id === 'kg' || id === 'wy' || id === 'tx' || id === 'kw' || id === 'mg'
  }

  private isProtectedSource(id: string): boolean {
    return id === 'local_source' || id === 'demo' || this.isBuiltInSearchSource(id)
  }
}
