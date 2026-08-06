import { SourceManager } from 'hsp_source'
import { SourceInstance, SourceImportMethod } from 'common'

/**
 * 音源管理页面 — 展示、开关、导入/删除音源
 */

@Component
struct SourceManagePage {
  @State sources: SourceInstance[] = []
  private manager: SourceManager = SourceManager.getInstance()

  aboutToAppear(): void {
    this.sources = this.manager.getAllSources()
  }

  build() {
    Column() {
      Row() {
        Text('音源管理')
          .fontSize(18)
          .fontWeight(FontWeight.Bold)
          .fontColor('#cdd6f4')
        Blank()
        Text('+ 导入')
          .fontSize(14)
          .fontColor('#a6e3a1')
          .onClick(() => this.showImportDialog())
      }
      .width('100%').padding(16)

      List() {
        ForEach(this.sources, (source: SourceInstance) => {
          ListItem() {
            Row({ space: 12 }) {
              Column({ space: 2 }) {
                Text(source.info.name).fontSize(15).fontColor('#cdd6f4')
                Text(`v${source.info.version} · ${source.info.author}`)
                  .fontSize(11).fontColor('#6c7086')
              }
              .layoutWeight(1)

              Toggle({ type: ToggleType.Switch, isOn: source.enabled })
                .onChange((isOn: boolean) => {
                  this.manager.toggleSource(source.info.id, isOn)
                })

              if (source.info.id !== 'demo') {
                Text('🗑')
                  .fontSize(16)
                  .onClick(() => {
                    this.manager.removeSource(source.info.id)
                    this.sources = this.manager.getAllSources()
                  })
              }
            }
            .width('100%')
            .padding({ left: 16, right: 16, top: 12, bottom: 12 })
          }
        })
      }
      .width('100%').layoutWeight(1)
    }
    .width('100%').height('100%').backgroundColor('#1e1e2e')
  }

  private showImportDialog(): void {
    AlertDialog.show({
      title: '导入音源',
      message: '选择导入方式（MVP 阶段 JS 沙箱尚未完整实现，仅供预览）',
      autoCancel: true,
      alignment: DialogAlignment.Bottom,
      primaryButton: {
        value: '从本地文件',
        action: () => {
          this.manager.importSource(SourceImportMethod.LOCAL_FILE, '')
        }
      },
      secondaryButton: {
        value: '从在线链接',
        action: () => {
          this.manager.importSource(SourceImportMethod.ONLINE_URL, '')
        }
      }
    })
  }
}
