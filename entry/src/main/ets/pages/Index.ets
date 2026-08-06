import { router } from '@kit.ArkUI'

/**
 * 主框架页面 — SideBar 导航 + 内容区
 */
@Entry
@Component
struct Index {
  @State showSideBar: boolean = false

  aboutToAppear(): void {
    // 默认打开正在播放页
    router.pushUrl({ url: 'pages/NowPlayingPage' })
  }

  build() {
    SideBarContainer(SideBarContainerType.Embed) {
      // 侧边栏
      Column() {
        Text('🎵 洛雪音乐')
          .fontSize(18)
          .fontWeight(FontWeight.Bold)
          .fontColor('#89b4fa')
          .padding({ top: 24, bottom: 16, left: 16 })

        this.NavItem('▶', '正在播放', 'pages/NowPlayingPage')
        this.NavItem('🔍', '搜索', 'pages/SearchPage')
        this.NavItem('📋', '我的歌单', 'pages/PlaylistListPage')
        this.NavItem('🔌', '音源管理', 'pages/SourceManagePage')
        this.NavItem('⚙', '设置', 'pages/SettingsPage')

        Blank()
      }
      .width(200)
      .height('100%')
      .backgroundColor('#2d2d3f')

      // 内容区
      Column() {
        NavigationContent()
      }
      .width('100%')
      .height('100%')
      .backgroundColor('#1e1e2e')
    }
    .sideBarWidth(200)
    .showSideBar(this.showSideBar)
    .autoHide(true)
    .minContentWidth(360)
    .height('100%')
    .width('100%')
  }

  @Builder
  NavItem(icon: string, label: string, pageName: string) {
    Row() {
      Text(`${icon}  ${label}`)
        .fontSize(15)
        .fontColor('#cdd6f4')
    }
    .width('100%')
    .padding({ left: 16, top: 12, bottom: 12 })
    .borderRadius(8)
    .onClick(() => {
      router.replaceUrl({ url: pageName })
    })
  }
}
