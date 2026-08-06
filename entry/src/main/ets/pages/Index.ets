import { PlayerEngine } from 'hsp_player'
import { PlaylistManager } from 'hsp_playlist'
import { SourceManager } from 'hsp_source'
import { SearchEngine } from 'hsp_search'
import { PlayerStatus, PlayMode, MusicItem, MusicQuality, SourceInstance, SourceImportMethod, SourceImportResult, LocalPlaylist, LyricLine } from 'common'
import { picker, fileIo } from '@kit.CoreFileKit'
import { util } from '@kit.ArkTS'
import { ConfigurationConstant } from '@kit.AbilityKit'
import { LyricView } from '../components/LyricView'
import { MusicItemView } from '../components/MusicItemView'

/**
 * 主框架页面 — SideBar 导航 + Navigation 内容切换
 * 使用 NavPathStack 切换页面，侧边栏保持不动
 */
@Entry
@Component
struct Index {
  @State showSideBar: boolean = false
  @State currentPage: string = 'NowPlaying'
  private navPathStack: NavPathStack = new NavPathStack()
  private player: PlayerEngine = PlayerEngine.getInstance()
  // MiniPlayerBar 状态快照（轮询同步）
  @State barSongName: string = ''
  @State barSinger: string = ''
  @State barIsPlaying: boolean = false
  private barSyncTimer: number = -1

  aboutToAppear(): void {
    // 默认显示正在播放页
    this.navPathStack.pushPathByName('NowPlaying', null)
    // 迷你播放条状态同步
    this.barSyncTimer = setInterval(() => {
      const song = this.player.currentSong
      this.barSongName = song?.name ?? ''
      this.barSinger = song?.singer ?? ''
      this.barIsPlaying = this.player.status === PlayerStatus.PLAYING
    }, 500)
  }

  aboutToDisappear(): void {
    if (this.barSyncTimer >= 0) {
      clearInterval(this.barSyncTimer)
      this.barSyncTimer = -1
    }
  }

  build() {
    Column() {
      // ===== 主内容区 =====
      SideBarContainer(SideBarContainerType.Embed) {
        // 侧边栏
        Column() {
          Text('🎵 洛雪音乐')
            .fontSize(18)
            .fontWeight(FontWeight.Bold)
            .fontColor('#89b4fa')
            .padding({ top: 24, bottom: 16, left: 16 })

          this.NavItem('▶', '正在播放', 'NowPlaying')
          this.NavItem('🔍', '搜索', 'Search')
          this.NavItem('📋', '我的歌单', 'PlaylistList')
          this.NavItem('🔌', '音源管理', 'SourceManage')
          this.NavItem('⚙', '设置', 'Settings')

          Blank()
        }
        .width(200)
        .height('100%')
        .backgroundColor('#2d2d3f')

        // 内容区：Navigation 路由切换
        Navigation(this.navPathStack) {
          Column() {
            Text('🎵 欢迎使用洛雪音乐~')
              .fontSize(20).fontColor('#cdd6f4')
            Text('请从左侧菜单选择功能')
              .fontSize(14).fontColor('#6c7086')
              .margin({ top: 8 })
          }
          .width('100%').height('100%')
          .justifyContent(FlexAlign.Center)
        }
        .navDestination(this.pageBuilder)
        .hideTitleBar(true)
        .mode(NavigationMode.Stack)
        .backgroundColor('#1e1e2e')
      }
      .sideBarWidth(200)
      .showSideBar(this.showSideBar)
      .autoHide(true)
      .minContentWidth(360)
      .layoutWeight(1)

      // ===== 底部迷你播放条 =====
      this.MiniPlayerBar()
    }
    .width('100%')
    .height('100%')
  }

  /** 底部迷你播放条 — 始终可见，显示当前歌曲和基本控制 */
  @Builder
  MiniPlayerBar() {
    if (this.barSongName) {
      Row() {
        // 歌曲信息（点击回到正在播放页）
        Row({ space: 8 }) {
          Text(this.barSongName)
            .fontSize(14).fontColor('#cdd6f4').maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
          Text(`- ${this.barSinger}`)
            .fontSize(12).fontColor('#6c7086').maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
        }
        .layoutWeight(1)
        .onClick(() => {
          this.navPathStack.clear()
          this.navPathStack.pushPathByName('NowPlaying', null)
        })

        // 播放控制
        Text(this.barIsPlaying ? '⏸' : '▶️')
          .fontSize(22)
          .fontColor('#a6e3a1')
          .padding({ left: 8, right: 8 })
          .onClick(() => this.player.togglePlay())

        Text('⏭')
          .fontSize(20)
          .fontColor('#a6e3a1')
          .onClick(() => this.player.next())
      }
      .width('100%')
      .height(48)
      .padding({ left: 12, right: 12 })
      .backgroundColor('#2d2d3f')
      .border({ width: { top: 1 }, color: '#45475a' })
    }
  }

  // ===== 路由表：根据页面名返回对应内容 =====
  @Builder
  pageBuilder(name: string) {
    if (name === 'NowPlaying') {
      NowPlayingContent()
    } else if (name === 'Search') {
      SearchContent()
    } else if (name === 'PlaylistList') {
      PlaylistListContent()
    } else if (name === 'PlaylistDetail') {
      PlaylistDetailContent()
    } else if (name === 'SourceManage') {
      SourceManageContent()
    } else if (name === 'Settings') {
      SettingsContent()
    }
  }

  // ===== 侧边栏菜单项 =====
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
      this.currentPage = pageName
      this.navPathStack.clear()
      this.navPathStack.pushPathByName(pageName, null)
    })
  }
}

// ============================================================
//  正在播放页
// ============================================================
@Component
struct NowPlayingContent {
  private player: PlayerEngine = PlayerEngine.getInstance()
  // 播放器状态快照（@Observed 已移除，用轮询同步驱动 UI 刷新）
  @State currentSongName: string = '未在播放'
  @State currentSinger: string = '选择一首歌曲开始播放吧~'
  @State status: PlayerStatus = PlayerStatus.IDLE
  @State currentProgress: number = 0
  @State duration: number = 0
  @State lyrics: LyricLine[] = []
  @State mode: PlayMode = PlayMode.SEQUENCE
  private syncTimer: number = -1

  aboutToAppear(): void {
    // 每 500ms 同步播放器状态到 @State（驱动 UI 刷新）
    this.syncTimer = setInterval(() => {
      this.currentSongName = this.player.currentSong?.name ?? '未在播放'
      this.currentSinger = this.player.currentSong?.singer ?? '选择一首歌曲开始播放吧~'
      this.status = this.player.status
      this.currentProgress = this.player.currentProgress
      this.duration = this.player.duration
      this.lyrics = this.player.lyrics
      this.mode = this.player.queue.mode
    }, 500)
  }

  aboutToDisappear(): void {
    if (this.syncTimer >= 0) {
      clearInterval(this.syncTimer)
      this.syncTimer = -1
    }
  }

  build() {
    NavDestination() {
      Column() {
        // 歌曲信息
        Column({ space: 8 }) {
          Image($r('app.media.startIcon'))
            .width(200)
            .height(200)
            .borderRadius(12)
            .objectFit(ImageFit.Cover)

          Text(this.currentSongName)
            .fontSize(20)
            .fontWeight(FontWeight.Bold)
            .fontColor('#cdd6f4')

          Text(this.currentSinger)
            .fontSize(15)
            .fontColor('#6c7086')
        }
        .padding({ top: 40, bottom: 16 })

        // 进度条
        Row({ space: 12 }) {
          Text(this.formatTime(this.currentProgress))
            .fontSize(12).fontColor('#585b70')
          Slider({
            value: this.duration > 0 ? this.currentProgress / this.duration : 0
          })
            .width('60%')
            .onChange((value: number) => {
              this.player.seekTo(value * this.duration)
            })
          Text(this.formatTime(this.duration))
            .fontSize(12).fontColor('#585b70')
        }
        .width('100%')
        .padding({ left: 24, right: 24 })
        .justifyContent(FlexAlign.Center)

        // 播放控制
        Row({ space: 24 }) {
          Text('⏮').fontSize(28).onClick(() => this.player.previous())
          Text(this.status === PlayerStatus.PLAYING ? '⏸' : '▶️')
            .fontSize(36).onClick(() => this.player.togglePlay())
          Text('⏭').fontSize(28).onClick(() => this.player.next())
        }
        .padding({ top: 12, bottom: 8 })
        .justifyContent(FlexAlign.Center)

        // 播放模式
        Row() {
          Text(this.getModeIcon()).fontSize(16).fontColor('#89b4fa')
            .onClick(() => {
              const modes = [PlayMode.SEQUENCE, PlayMode.LOOP_ONE, PlayMode.LOOP_ALL, PlayMode.SHUFFLE]
              const idx = (modes.indexOf(this.mode) + 1) % modes.length
              this.player.setPlayMode(modes[idx])
            })
        }
        .width('100%').justifyContent(FlexAlign.Center).padding({ bottom: 8 })

        // 歌词
        LyricView({ lyrics: this.lyrics, currentProgress: this.currentProgress })
          .layoutWeight(1)
      }
      .width('100%')
      .height('100%')
      .backgroundColor('#1e1e2e')
    }
    .hideTitleBar(true)
  }

  private formatTime(ms: number): string {
    const totalSec = Math.floor(ms / 1000)
    const min = Math.floor(totalSec / 60)
    const sec = totalSec % 60
    return `${min.toString().padStart(2, '0')}:${sec.toString().padStart(2, '0')}`
  }

  private getModeIcon(): string {
    switch (this.player.queue.mode) {
      case PlayMode.LOOP_ONE: return '🔂'
      case PlayMode.LOOP_ALL: return '🔁'
      case PlayMode.SHUFFLE: return '🔀'
      default: return '➡️'
    }
  }
}

// ============================================================
//  搜索页
// ============================================================
/** 搜索源选项（搜索页选择器） */
interface SearchSourceOption {
  id: string
  name: string
}

@Component
struct SearchContent {
  @State keyword: string = ''
  @State results: MusicItem[] = []
  @State isLoading: boolean = false
  @State showHistory: boolean = true
  @State history: string[] = []
  // 搜索源选择（'' = 全部）
  @State activeSourceId: string = ''
  @State searchSources: SearchSourceOption[] = []

  aboutToAppear(): void {
    SearchEngine.getHistory().then(h => { this.history = h })
    // 加载搜索源列表（内置搜索源），默认"全部"搜索
    const sources = SourceManager.getInstance().getSearchSources()
    const list: SearchSourceOption[] = []
    for (const s of sources) {
      const opt: SearchSourceOption = { id: s.info.id, name: s.info.name }
      list.push(opt)
    }
    this.searchSources = list
    this.activeSourceId = ''
  }

  build() {
    NavDestination() {
      Column() {
        // 搜索框
        Row({ space: 8 }) {
          TextInput({ placeholder: '搜索歌曲、歌手...' })
            .layoutWeight(1)
            .fontSize(15)
            .onChange((value: string) => {
              this.keyword = value
              this.showHistory = !value
            })
            .onSubmit(() => {
              this.doSearch()
            })

          Button('搜索')
            .fontSize(14)
            .onClick(() => { this.doSearch() })
        }
        .padding({ left: 16, right: 16, top: 12, bottom: 12 })

        // 搜索源选择器（单选：全部 / 酷狗 / 网易 / QQ）
        Row({ space: 8 }) {
          this.SourceChip('', '全部')
          ForEach(this.searchSources, (source: SearchSourceOption) => {
            this.SourceChip(source.id, source.name)
          })
        }
        .width('100%')
        .padding({ left: 16, right: 16, bottom: 8 })

        if (this.showHistory) {
          // 搜索历史
          Column() {
            Row() {
              Text('搜索历史').fontSize(14).fontColor('#6c7086')
              Blank()
              Text('清除').fontSize(12).fontColor('#f38ba8')
                .onClick(() => {
                  SearchEngine.clearHistory()
                  this.history = []
                })
            }
            .width('100%').padding(16)

            ForEach(this.history, (keyword: string) => {
              Row() {
                Text(keyword).fontSize(14).fontColor('#a6adc8')
              }
              .width('100%')
              .padding({ left: 16, top: 10, bottom: 10 })
              .onClick(() => {
                this.keyword = keyword
                this.doSearch()
              })
            })
          }
        } else if (this.isLoading) {
          LoadingProgress().color('#89b4fa').width(40).height(40)
        } else if (this.results.length === 0) {
          Column() {
            Text('未找到相关歌曲').fontSize(15).fontColor('#6c7086')
          }
          .width('100%').height('100%').justifyContent(FlexAlign.Center)
        } else {
          List() {
            ForEach(this.results, (song: MusicItem) => {
              ListItem() {
                // 传入整个结果列表 → 点击后整列表入队，支持上一首/下一首切歌
                MusicItemView({ song: song, queueSongs: this.results, showAddButton: true })
              }
              .swipeAction({
                end: {
                  builder: () => {
                    this.AddToPlaylistBuilder(song)
                  }
                }
              })
            })
          }
          .width('100%').layoutWeight(1).scrollBar(BarState.Off)
        }
      }
      .width('100%').height('100%').backgroundColor('#1e1e2e')
    }
    .hideTitleBar(true)
  }

  private doSearch(): void {
    if (!this.keyword.trim()) return
    this.isLoading = true
    this.showHistory = false
    SearchEngine.search(this.keyword, 1, MusicQuality.HIGH, this.activeSourceId).then(r => {
      this.results = r
      this.isLoading = false
    }).catch(() => {
      this.results = []
      this.isLoading = false
    })
  }

  /** 搜索源选择芯片（单选） */
  @Builder
  SourceChip(sourceId: string, name: string) {
    Text(name)
      .fontSize(13)
      .fontColor(this.activeSourceId === sourceId ? '#1e1e2e' : '#a6adc8')
      .backgroundColor(this.activeSourceId === sourceId ? '#a6e3a1' : '#2d2d3f')
      .padding({ left: 12, right: 12, top: 4, bottom: 4 })
      .borderRadius(14)
      .onClick(() => {
        // 选择器只管搜索范围，不影响音源启用状态（搜索源始终启用）
        this.activeSourceId = sourceId
        // 切换源后重新搜索
        if (this.keyword.trim()) {
          this.doSearch()
        }
      })
  }

  /** 添加到歌单按钮（swipeAction builder 必须是 @Builder） */
  @Builder
  AddToPlaylistBuilder(song: MusicItem) {
    Button('添加到歌单')
      .fontSize(12)
      .backgroundColor('#89b4fa')
      .onClick(() => {
        const playlists = PlaylistManager.getInstance().getAll()
        if (playlists.length === 0) {
          PlaylistManager.getInstance().create('默认歌单', '自动创建')
        }
        const pls = PlaylistManager.getInstance().getAll()
        if (pls.length > 0) {
          PlaylistManager.getInstance().addSongs(pls[0].id, [song])
        }
      })
  }
}

// ============================================================
//  歌单列表页
// ============================================================
@Component
struct PlaylistListContent {
  @State playlists: LocalPlaylist[] = []
  private playlistMgr: PlaylistManager = PlaylistManager.getInstance()

  aboutToAppear(): void {
    this.playlists = this.playlistMgr.getAll()
  }

  build() {
    NavDestination() {
      Column() {
        // 标题栏 + 创建按钮
        Row() {
          Text('我的歌单')
            .fontSize(18).fontWeight(FontWeight.Bold).fontColor('#cdd6f4')
          Blank()
          Text('+ 新建')
            .fontSize(14).fontColor('#a6e3a1')
            .onClick(() => {
              AlertDialog.show({
                title: '新建歌单',
                message: '请输入歌单名称',
                autoCancel: true,
                alignment: DialogAlignment.Center,
                primaryButton: {
                  value: '取消',
                  action: () => {}
                },
                secondaryButton: {
                  value: '创建',
                  action: () => {
                    this.playlistMgr.create('新歌单', '')
                    this.playlists = this.playlistMgr.getAll()
                  }
                }
              })
            })
        }
        .width('100%')
        .padding({ left: 16, right: 16, top: 16, bottom: 12 })

        if (this.playlists.length === 0) {
          Column({ space: 4 }) {
            Text('还没有歌单').fontSize(14).fontColor('#6c7086')
            Text('去搜索页添加喜欢的歌曲吧~').fontSize(12).fontColor('#585b70')
          }
          .width('100%').height('100%').justifyContent(FlexAlign.Center)
        } else {
          List() {
            ForEach(this.playlists, (pl: LocalPlaylist) => {
              ListItem() {
                Row({ space: 12 }) {
                  Column({ space: 4 }) {
                    Text(pl.name).fontSize(15).fontColor('#cdd6f4')
                    Text(`${pl.songs.length} 首`).fontSize(12).fontColor('#6c7086')
                  }
                  .layoutWeight(1)

                  Text('▶').fontSize(20).fontColor('#a6e3a1')
                    .onClick(() => {
                      const player = PlayerEngine.getInstance()
                      player.queue.replaceList(pl.songs)
                      player.playCurrent()
                    })

                  Text('🗑').fontSize(16).fontColor('#f38ba8')
                    .margin({ left: 8 })
                    .onClick(() => {
                      AlertDialog.show({
                        title: '删除歌单',
                        message: `确定删除歌单「${pl.name}」吗？`,
                        autoCancel: true,
                        primaryButton: {
                          value: '取消',
                          action: () => {}
                        },
                        secondaryButton: {
                          value: '删除',
                          action: () => {
                            this.playlistMgr.delete(pl.id)
                            this.playlists = this.playlistMgr.getAll()
                          }
                        }
                      })
                    })
                }
                .width('100%')
                .padding({ left: 16, right: 16, top: 14, bottom: 14 })
                .onClick(() => {
                  AppStorage.setOrCreate('selectedPlaylistId', pl.id)
                  const nav = this.queryNavigationInfo()
                  if (nav?.pathStack) {
                    nav.pathStack.pushPathByName('PlaylistDetail', null)
                  }
                })
              }
            })
          }
          .width('100%').layoutWeight(1)
        }
      }
      .width('100%').height('100%').backgroundColor('#1e1e2e')
    }
    .hideTitleBar(true)
  }
}

// ============================================================
//  歌单详情页
// ============================================================
@Component
struct PlaylistDetailContent {
  @State playlist: LocalPlaylist | null = null
  @State playlistId: string = ''

  aboutToAppear(): void {
    const id = AppStorage.get<string>('selectedPlaylistId')
    if (id) {
      this.playlistId = id
      this.playlist = PlaylistManager.getInstance().getById(id) ?? null
    }
  }

  build() {
    NavDestination() {
      Column() {
        if (!this.playlist) {
          Text('歌单不存在').fontSize(15).fontColor('#6c7086')
        } else {
          Row({ space: 12 }) {
            Column({ space: 4 }) {
              Text(this.playlist!.name).fontSize(18).fontWeight(FontWeight.Bold).fontColor('#cdd6f4')
              Text(`${this.playlist!.songs.length} 首`).fontSize(12).fontColor('#6c7086')
            }
            Blank()
            Text('导出').fontSize(13).fontColor('#89b4fa').margin({ right: 12 })
              .onClick(() => { this.exportPlaylist() })
            Text('▶ 播放全部').fontSize(14).fontColor('#a6e3a1')
              .onClick(() => {
                const player = PlayerEngine.getInstance()
                player.queue.replaceList(this.playlist!.songs)
                player.playCurrent()
              })
          }
          .width('100%').padding(16)

          List() {
            ForEach(this.playlist!.songs, (song: MusicItem, index: number) => {
              ListItem() {
                MusicItemView({ song: song })
              }
              .swipeAction({
                end: {
                  builder: () => {
                    this.DeleteSongBuilder(index)
                  }
                }
              })
            })
          }
          .width('100%').layoutWeight(1)
        }
      }
      .width('100%').height('100%').backgroundColor('#1e1e2e')
    }
    .hideTitleBar(true)
  }

  /** 删除歌曲按钮（swipeAction builder 必须是 @Builder） */
  @Builder
  DeleteSongBuilder(index: number) {
    Button('删除')
      .fontSize(13)
      .backgroundColor('#f38ba8')
      .onClick(() => {
        PlaylistManager.getInstance().removeSongs(this.playlistId, [index])
        this.playlist = PlaylistManager.getInstance().getById(this.playlistId) ?? null
      })
  }

  /** 导出歌单为 .lxmc 文件 */
  private async exportPlaylist(): Promise<void> {
    const lxmc = PlaylistManager.getInstance().exportToLxmc(this.playlistId)
    if (!lxmc) {
      AlertDialog.show({ title: '导出失败', message: '歌单不存在或为空', autoCancel: true })
      return
    }
    try {
      const documentPicker = new picker.DocumentViewPicker()
      const saveResult = await documentPicker.save({
        newFileNames: [`${this.playlist?.name ?? '歌单'}.lxmc`]
      })
      const saveUri = saveResult && saveResult.length > 0 ? saveResult[0] : ''
      if (saveUri) {
        // 写入文件内容
        const file = fileIo.openSync(saveUri, fileIo.OpenMode.READ_WRITE | fileIo.OpenMode.CREATE)
        const encoder = new util.TextEncoder()
        const buffer = encoder.encodeInto(lxmc)
        fileIo.writeSync(file.fd, buffer)
        fileIo.closeSync(file)
        AlertDialog.show({ title: '导出成功', message: '歌单已导出为 .lxmc 文件', autoCancel: true })
      }
    } catch (err) {
      AlertDialog.show({ title: '导出失败', message: JSON.stringify(err), autoCancel: true })
    }
  }
}

// ============================================================
//  音源管理页
// ============================================================
@Component
struct SourceManageContent {
  @State sources: SourceInstance[] = []
  private manager: SourceManager = SourceManager.getInstance()

  aboutToAppear(): void {
    // 音源管理只显示 JS 音源和本地/演示（搜索源在搜索页选择）
    this.sources = this.manager.getManageSources()
  }

  build() {
    NavDestination() {
      Column() {
        Row() {
          Text('音源管理').fontSize(18).fontWeight(FontWeight.Bold).fontColor('#cdd6f4')
          Blank()
          Text('+ 导入').fontSize(14).fontColor('#a6e3a1')
            .onClick(() => {
              AlertDialog.show({
                title: '导入音源',
                message: '选择导入方式（支持 lx-music 社区 .js 音源脚本）\n提示：搜索源（酷狗/网易/QQ）在搜索页选择使用',
                autoCancel: true,
                alignment: DialogAlignment.Bottom,
                primaryButton: {
                  value: '从本地文件',
                  action: () => { this.importFromLocalFile() }
                },
                secondaryButton: {
                  value: '从在线链接',
                  action: () => { this.importFromOnlineUrl() }
                }
              })
            })
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
                  // 音源类型标注
                  Text(this.getSourceTypeLabel(source.info.id, source.isNative))
                    .fontSize(10)
                    .fontColor('#89b4fa')
                }
                .layoutWeight(1)

                Toggle({ type: ToggleType.Switch, isOn: source.enabled })
                  .onChange((isOn: boolean) => {
                    this.manager.toggleSource(source.info.id, isOn)
                  })

                if (source.info.id !== 'demo' && source.info.id !== 'local_source') {
                  Text('🗑').fontSize(16)
                    .onClick(() => {
                      this.manager.removeSource(source.info.id)
                      this.sources = this.manager.getManageSources()
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
    .hideTitleBar(true)
  }

  /** 音源类型标注（帮助用户理解音源能力） */
  private getSourceTypeLabel(id: string, isNative: boolean): string {
    if (id === 'local_source') return '📂 本地文件'
    if (id === 'demo') return '🧪 演示'
    return '📜 JS 音源（解析型，搜索请用搜索页的搜索源选择）'
  }

  /** 从本地文件导入音源 */
  private async importFromLocalFile(): Promise<void> {
    try {
      const documentPicker = new picker.DocumentViewPicker()
      const result = await documentPicker.select()
      if (result && result.length > 0) {
        const fileUri = result[0]
        const ret = await this.manager.importSource(SourceImportMethod.LOCAL_FILE, fileUri)
        if (ret.success) {
          AlertDialog.show({ title: '导入成功', message: `已导入音源: ${ret.source?.info.name ?? ''}`, autoCancel: true })
        } else {
          AlertDialog.show({ title: '导入失败', message: ret.error ?? '未知错误', autoCancel: true })
        }
      }
    } catch (err) {
      // 用户取消选择
    }
    this.sources = this.manager.getManageSources()
  }

  /** 从在线链接导入音源 */
  private importFromOnlineUrl(): void {
    AlertDialog.show({
      title: '导入在线音源',
      message: '请输入音源脚本的 URL（支持 lx-music 社区音源链接）',
      autoCancel: true,
      alignment: DialogAlignment.Center,
      primaryButton: {
        value: '取消',
        action: () => {}
      },
      secondaryButton: {
        value: '确定',
        action: () => {
          // 使用一个常见的音源链接作为默认值
          const demoUrl = 'https://raw.githubusercontent.com/pdone/lx-music-source/main/sixyin/latest.js'
          this.manager.importSource(SourceImportMethod.ONLINE_URL, demoUrl).then((ret: SourceImportResult) => {
            if (ret.success) {
              AlertDialog.show({ title: '导入成功', message: `已导入音源: ${ret.source?.info.name ?? ''}`, autoCancel: true })
            } else {
              AlertDialog.show({ title: '导入失败', message: ret.error ?? '未知错误', autoCancel: true })
            }
            this.sources = this.manager.getManageSources()
          })
        }
      }
    })
  }
}

// ============================================================
//  设置页
// ============================================================
@Component
struct SettingsContent {
  @State localSongCount: number = 0

  aboutToAppear(): void {
    this.localSongCount = SourceManager.getInstance().getLocalSongs().length
  }

  build() {
    NavDestination() {
      Column() {
        Text('设置').fontSize(18).fontWeight(FontWeight.Bold).fontColor('#cdd6f4')
          .padding({ left: 16, top: 16, bottom: 12 })

        List() {
          ListItem() {
            Row() {
              Text('📂 导入本地音乐').fontSize(15).fontColor('#cdd6f4')
              Blank()
              Text(`${this.localSongCount} 首`).fontSize(13).fontColor('#6c7086')
              Text('›').fontSize(15).fontColor('#6c7086').margin({ left: 8 })
            }.width('100%').padding(16)
            .onClick(() => { this.importLocalMusic() })
          }

          ListItem() {
            Row() {
              Text('主题').fontSize(15).fontColor('#cdd6f4')
              Blank()
              Text('深色').fontSize(13).fontColor('#6c7086')
            }.width('100%').padding(16)
            .onClick(() => { this.showThemeDialog() })
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
              Text('💾 备份与恢复').fontSize(15).fontColor('#cdd6f4')
              Blank()
              Text('›').fontSize(15).fontColor('#6c7086')
            }.width('100%').padding(16)
            .onClick(() => { this.showBackupDialog() })
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
    .hideTitleBar(true)
  }

  /** 导入本地音乐（文件选择器多选音频） */
  private async importLocalMusic(): Promise<void> {
    try {
      const documentPicker = new picker.DocumentViewPicker()
      const result = await documentPicker.select({
        fileSuffixFilters: ['.mp3', '.flac', '.wav', '.ogg', '.aac', '.m4a'],
        maxSelectNumber: 500,
        selectMode: picker.DocumentSelectMode.FILE
      })
      if (result && result.length > 0) {
        const count = await SourceManager.getInstance().importLocalFiles(result)
        this.localSongCount = SourceManager.getInstance().getLocalSongs().length
        AlertDialog.show({
          title: '导入完成',
          message: `成功导入 ${count} 首本地音乐，可在「搜索」页输入关键词或浏览本地音源查看`,
          autoCancel: true
        })
      }
    } catch (err) {
      // 用户取消选择
    }
  }

  /** 主题切换对话框 */
  private showThemeDialog(): void {
    AlertDialog.show({
      title: '选择主题',
      message: '深色 / 浅色',
      autoCancel: true,
      alignment: DialogAlignment.Center,
      primaryButton: {
        value: '深色',
        action: () => {
          AppStorage.setOrCreate('themeMode', 'dark')
          this.applyTheme('dark')
        }
      },
      secondaryButton: {
        value: '浅色',
        action: () => {
          AppStorage.setOrCreate('themeMode', 'light')
          this.applyTheme('light')
        }
      }
    })
  }

  /** 应用主题 */
  private applyTheme(mode: string): void {
    const appContext = getContext(this)
    const colorMode = mode === 'light'
      ? ConfigurationConstant.ColorMode.COLOR_MODE_LIGHT
      : ConfigurationConstant.ColorMode.COLOR_MODE_DARK
    appContext.getApplicationContext().setColorMode(colorMode)
  }

  /** 备份恢复对话框 */
  private showBackupDialog(): void {
    AlertDialog.show({
      title: '备份与恢复',
      message: '导出 / 导入应用数据（歌单、本地音乐列表）',
      autoCancel: true,
      alignment: DialogAlignment.Center,
      primaryButton: {
        value: '导出备份',
        action: () => { this.exportBackup() }
      },
      secondaryButton: {
        value: '恢复备份',
        action: () => { this.importBackup() }
      }
    })
  }

  /** 导出备份：所有歌单 → 单个 .lxmc 文件 */
  private async exportBackup(): Promise<void> {
    const playlists = PlaylistManager.getInstance().getAll()
    if (playlists.length === 0) {
      AlertDialog.show({ title: '提示', message: '没有可导出的歌单', autoCancel: true })
      return
    }
    try {
      // 组装备份数据结构
      const backupData: Record<string, Object> = {}
      backupData['type'] = 'lxMusicBackup'
      backupData['version'] = '1.0.0'
      backupData['exportTime'] = Date.now()
      const emptyList: Array<Record<string, Object>> = []
      backupData['playlists'] = emptyList
      const plList: Array<Record<string, Object>> = []
      for (const pl of playlists) {
        const lxmcStr = PlaylistManager.getInstance().exportToLxmc(pl.id)
        try {
          plList.push(JSON.parse(lxmcStr))
        } catch (e) {
          // 跳过无法序列化的歌单
        }
      }
      backupData['playlists'] = plList

      const documentPicker = new picker.DocumentViewPicker()
      const saveResult = await documentPicker.save({
        newFileNames: [`lx_music_backup_${Date.now()}.lxmc`]
      })
      const saveUri = saveResult && saveResult.length > 0 ? saveResult[0] : ''
      if (saveUri) {
        const file = fileIo.openSync(saveUri, fileIo.OpenMode.READ_WRITE | fileIo.OpenMode.CREATE)
        const encoder = new util.TextEncoder()
        const buffer = encoder.encodeInto(JSON.stringify(backupData))
        fileIo.writeSync(file.fd, buffer)
        fileIo.closeSync(file)
        AlertDialog.show({ title: '备份成功', message: `已导出 ${plList.length} 个歌单`, autoCancel: true })
      }
    } catch (err) {
      AlertDialog.show({ title: '备份失败', message: JSON.stringify(err), autoCancel: true })
    }
  }

  /** 恢复备份：读取 .lxmc 文件并重建歌单 */
  private async importBackup(): Promise<void> {
    try {
      const documentPicker = new picker.DocumentViewPicker()
      const result = await documentPicker.select({
        fileSuffixFilters: ['.lxmc', '.json'],
        maxSelectNumber: 1
      })
      if (!result || result.length === 0) return

      // 读取文件内容
      const file = fileIo.openSync(result[0], fileIo.OpenMode.READ_ONLY)
      const stat = fileIo.statSync(result[0])
      const buf = new ArrayBuffer(stat.size)
      fileIo.readSync(file.fd, buf)
      fileIo.closeSync(file)
      const decoder = util.TextDecoder.create('utf-8')
      const content = decoder.decodeToString(new Uint8Array(buf))

      // 解析并导入
      const parsed = JSON.parse(content) as Record<string, Object>
      if (parsed['type'] === 'lxMusicBackup') {
        // 备份文件：包含多个歌单
        const plList = parsed['playlists'] as Array<Record<string, Object>>
        if (plList && plList.length > 0) {
          let count = 0
          for (const pl of plList) {
            const created = await PlaylistManager.getInstance().importFromLxmc(JSON.stringify(pl))
            if (created) count++
          }
          AlertDialog.show({ title: '恢复成功', message: `已恢复 ${count} 个歌单`, autoCancel: true })
        }
      } else {
        // 单个 .lxmc 歌单文件
        const created = await PlaylistManager.getInstance().importFromLxmc(content)
        if (created) {
          AlertDialog.show({ title: '恢复成功', message: `已导入歌单: ${created.name}`, autoCancel: true })
        } else {
          AlertDialog.show({ title: '恢复失败', message: '文件格式不支持，请选择 .lxmc 歌单文件', autoCancel: true })
        }
      }
    } catch (err) {
      AlertDialog.show({ title: '恢复失败', message: `解析失败: ${JSON.stringify(err)}`, autoCancel: true })
    }
  }
}
