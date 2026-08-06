/**
 * 设置页面 — 主题、音质、缓存、关于等选项（MVP 阶段为静态占位）
 */
@Entry
@Component
struct SettingsPage {
  build() {
    Column() {
      Text('设置')
        .fontSize(18)
        .fontWeight(FontWeight.Bold)
        .fontColor('#cdd6f4')
        .padding({ left: 16, top: 16, bottom: 12 })

      List() {
        ListItem() {
          Row() {
            Text('主题').fontSize(15).fontColor('#cdd6f4')
            Blank()
            Text('深色').fontSize(13).fontColor('#6c7086')
          }.width('100%').padding(16)
        }

        ListItem() {
          Row() {
            Text('默认音质').fontSize(15).fontColor('#cdd6f4')
            Blank()
            Text('320k').fontSize(13).fontColor('#6c7086')
          }.width('100%').padding(16)
        }

        ListItem() {
          Row() {
            Text('清除缓存').fontSize(15).fontColor('#cdd6f4')
            Blank()
            Text('0 MB').fontSize(13).fontColor('#6c7086')
          }.width('100%').padding(16)
          .onClick(() => {
            AlertDialog.show({ title: '提示', message: '缓存已清除', autoCancel: true })
          })
        }

        ListItem() {
          Row() {
            Text('关于').fontSize(15).fontColor('#cdd6f4')
            Blank()
            Text('洛雪音乐鸿蒙版 v0.1.0').fontSize(13).fontColor('#6c7086')
          }.width('100%').padding(16)
        }
      }
      .width('100%')
    }
    .width('100%').height('100%').backgroundColor('#1e1e2e')
  }
}
