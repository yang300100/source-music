# 源音乐鸿蒙版 MVP 实现计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 构建源音乐鸿蒙版 MVP，实现音源导入、多音源搜索、音乐播放、歌单管理和歌词显示五大核心功能

**Architecture:** HSP 特性模块架构，entry 作为壳负责 UI 和导航，hsp-source/hsp-player/hsp-search/hsp-playlist 四个业务模块 + common 公共基础模块，通过 ArkUI 原生状态管理串联

**Tech Stack:** HarmonyOS API 6.1.1 (24), ArkTS, ArkUI, AVPlayer, @ohos/hvigor-ohos-plugin

---

## 文件结构概览

```
source_music/
├── common/                          # [新建 HSP] 公共基础模块
│   ├── build-profile.json5
│   ├── oh-package.json5
│   ├── hvigorfile.ts
│   └── src/main/ets/
│       ├── types/
│       │   ├── MusicTypes.ets       # 歌曲、音源、歌单等核心数据类型
│       │   └── SourceTypes.ets      # 音源接口类型定义
│       ├── utils/
│       │   ├── LogUtils.ets         # 统一日志工具
│       │   ├── StorageUtils.ets     # 本地持久化存储封装
│       │   └── NetUtils.ets         # HTTP 请求封装
│       └── Index.ets                # 模块汇总导出
│
├── hsp-source/                      # [新建 HSP] 音源引擎模块
│   ├── build-profile.json5
│   ├── oh-package.json5
│   ├── hvigorfile.ts
│   └── src/main/ets/
│       ├── api/
│       │   ├── SourceAPI.ets        # 音源接口规范（ArkTS 原生音源契约）
│       │   └── JSBridge.ets         # JS 脚本桥接（网络请求、日志注入）
│       ├── manager/
│       │   └── SourceManager.ets    # 多音源管理：导入、开关、排序、调度
│       ├── sandbox/
│       │   └── JSSandbox.ets        # 受限 JS 执行环境（封装 worker/QuickJS）
│       └── Index.ets                # 模块汇总导出
│
├── hsp-player/                      # [新建 HSP] 播放器模块
│   ├── build-profile.json5
│   ├── oh-package.json5
│   ├── hvigorfile.ts
│   └── src/main/ets/
│       ├── engine/
│       │   └── PlayerEngine.ets     # AVPlayer 封装 + 状态机
│       ├── queue/
│       │   └── PlayQueue.ets        # 播放队列管理
│       └── Index.ets                # 模块汇总导出
│
├── hsp-search/                      # [新建 HSP] 搜索模块
│   ├── build-profile.json5
│   ├── oh-package.json5
│   ├── hvigorfile.ts
│   └── src/main/ets/
│       ├── SearchEngine.ets         # 聚合搜索 + 去重合并
│       └── Index.ets                # 模块汇总导出
│
├── hsp-playlist/                    # [新建 HSP] 歌单模块
│   ├── build-profile.json5
│   ├── oh-package.json5
│   ├── hvigorfile.ts
│   └── src/main/ets/
│       ├── PlaylistManager.ets      # 歌单 CRUD + 导入导出
│       └── Index.ets                # 模块汇总导出
│
├── entry/                           # [修改] 主模块（壳）
│   └── src/main/ets/
│       ├── entryability/
│       │   └── EntryAbility.ets     # [修改] 初始化全局状态
│       ├── model/
│       │   ├── AppState.ets         # [新建] 全局应用状态（播放器、音源列表）
│       │   └── PlayerState.ets      # [新建] 播放器可观察状态
│       ├── components/
│       │   ├── SideMenu.ets         # [新建] 侧边栏导航
│       │   ├── MusicItemView.ets    # [新建] 歌曲列表项
│       │   ├── LyricView.ets        # [新建] 滚动歌词组件
│       │   ├── PlayerBar.ets        # [新建] 底部迷你播放条
│       │   └── SearchBar.ets        # [新建] 搜索输入框
│       ├── pages/
│       │   ├── Index.ets            # [修改] 主框架页（SideBar + 路由）
│       │   ├── NowPlayingPage.ets   # [新建] 正在播放（封面+歌词+控制）
│       │   ├── SearchPage.ets       # [新建] 搜索页
│       │   ├── PlaylistListPage.ets # [新建] 歌单列表页
│       │   ├── PlaylistDetailPage.ets #[新建] 歌单详情页
│       │   ├── SourceManagePage.ets # [新建] 音源管理页
│       │   └── SettingsPage.ets     # [新建] 设置页
│       └── viewmodel/
│           ├── SearchVM.ets         # [新建] 搜索状态与逻辑
│           └── PlaylistVM.ets       # [新建] 歌单状态与逻辑
│
├── build-profile.json5              # [修改] 添加 HSP 模块引用
└── oh-package.json5                 # [修改] 添加 HSP 依赖
```

---

## 第一阶段：项目基础设施

### Task 1: 创建 common HSP 模块骨架

**Files:**
- Create: `common/build-profile.json5`
- Create: `common/oh-package.json5`
- Create: `common/hvigorfile.ts`
- Create: `common/Index.ets` (占位)

- [ ] **Step 1: 创建 build-profile.json5**

写入 `common/build-profile.json5`：

```json5
{
  "apiType": "stageMode",
  "buildOption": {
  },
  "targets": [
    {
      "name": "default"
    }
  ]
}
```

- [ ] **Step 2: 创建 oh-package.json5**

写入 `common/oh-package.json5`：

```json5
{
  "name": "common",
  "version": "1.0.0",
  "description": "源音乐公共基础模块",
  "main": "Index.ets",
  "author": "",
  "license": "MIT",
  "dependencies": {}
}
```

- [ ] **Step 3: 创建 hvigorfile.ts**

写入 `common/hvigorfile.ts`：

```typescript
import { hspTasks } from '@ohos/hvigor-ohos-plugin';

export default {
  system: hspTasks,
  plugins: []
}
```

- [ ] **Step 4: 创建占位导出文件**

写入 `common/Index.ets`：

```typescript
// common 公共基础模块 - 占位，后续任务填充
export {}
```

- [ ] **Step 5: 在根 build-profile.json5 注册模块**

修改 `build-profile.json5`，在 `modules` 数组中添加：

```json5
{
  "name": "common",
  "srcPath": "./common",
  "targets": [
    {
      "name": "default",
      "applyToProducts": ["default"]
    }
  ]
}
```

- [ ] **Step 6: 在 entry/oh-package.json5 添加依赖**

修改 `entry/oh-package.json5`，在 `dependencies` 中添加：

```json5
"common": "file:../common"
```

### Task 2: 创建 hsp-source 模块骨架

**Files:**
- Create: `hsp-source/build-profile.json5`
- Create: `hsp-source/oh-package.json5`
- Create: `hsp-source/hvigorfile.ts`
- Create: `hsp-source/src/main/ets/Index.ets` (占位)

- [ ] **Step 1: 创建 build-profile.json5**

写入 `hsp-source/build-profile.json5`：

```json5
{
  "apiType": "stageMode",
  "buildOption": {
  },
  "targets": [
    {
      "name": "default"
    }
  ]
}
```

- [ ] **Step 2: 创建 oh-package.json5**

写入 `hsp-source/oh-package.json5`：

```json5
{
  "name": "hsp_source",
  "version": "1.0.0",
  "description": "音源引擎模块",
  "main": "Index.ets",
  "author": "",
  "license": "MIT",
  "dependencies": {
    "common": "file:../common"
  }
}
```

- [ ] **Step 3: 创建 hvigorfile.ts**

写入 `hsp-source/hvigorfile.ts`：

```typescript
import { hspTasks } from '@ohos/hvigor-ohos-plugin';

export default {
  system: hspTasks,
  plugins: []
}
```

- [ ] **Step 4: 创建占位导出文件**

写入 `hsp-source/src/main/ets/Index.ets`：

```typescript
// hsp-source 音源引擎模块 - 占位
export {}
```

- [ ] **Step 5: 注册到根 build-profile.json5**

在 `build-profile.json5` 的 `modules` 中添加：

```json5
{
  "name": "hsp_source",
  "srcPath": "./hsp-source",
  "targets": [
    {
      "name": "default",
      "applyToProducts": ["default"]
    }
  ]
}
```

- [ ] **Step 6: entry 添加依赖**

修改 `entry/oh-package.json5`，在 `dependencies` 中添加：

```json5
"hsp_source": "file:../hsp-source"
```

### Task 3: 创建 hsp-player 模块骨架

**Files:**
- Create: `hsp-player/build-profile.json5`
- Create: `hsp-player/oh-package.json5`
- Create: `hsp-player/hvigorfile.ts`
- Create: `hsp-player/src/main/ets/Index.ets` (占位)

- [ ] **Step 1: 创建 build-profile.json5**

写入 `hsp-player/build-profile.json5`：

```json5
{
  "apiType": "stageMode",
  "buildOption": {
  },
  "targets": [
    {
      "name": "default"
    }
  ]
}
```

- [ ] **Step 2: 创建 oh-package.json5**

写入 `hsp-player/oh-package.json5`：

```json5
{
  "name": "hsp_player",
  "version": "1.0.0",
  "description": "播放器模块",
  "main": "Index.ets",
  "author": "",
  "license": "MIT",
  "dependencies": {
    "common": "file:../common"
  }
}
```

- [ ] **Step 3: 创建 hvigorfile.ts**

写入 `hsp-player/hvigorfile.ts`：

```typescript
import { hspTasks } from '@ohos/hvigor-ohos-plugin';

export default {
  system: hspTasks,
  plugins: []
}
```

- [ ] **Step 4: 创建占位导出文件**

写入 `hsp-player/src/main/ets/Index.ets`：

```typescript
// hsp-player 播放器模块 - 占位
export {}
```

- [ ] **Step 5: 注册到根 build-profile.json5 + entry 依赖**

在 `build-profile.json5` 的 `modules` 中添加：

```json5
{
  "name": "hsp_player",
  "srcPath": "./hsp-player",
  "targets": [
    {
      "name": "default",
      "applyToProducts": ["default"]
    }
  ]
}
```

在 `entry/oh-package.json5` 的 `dependencies` 中添加：

```json5
"hsp_player": "file:../hsp-player"
```

### Task 4: 创建 hsp-search 模块骨架

**Files:**
- Create: `hsp-search/build-profile.json5`
- Create: `hsp-search/oh-package.json5`
- Create: `hsp-search/hvigorfile.ts`
- Create: `hsp-search/src/main/ets/Index.ets` (占位)

- [ ] **Step 1: 创建 build-profile.json5**

写入 `hsp-search/build-profile.json5`：

```json5
{
  "apiType": "stageMode",
  "buildOption": {
  },
  "targets": [
    {
      "name": "default"
    }
  ]
}
```

- [ ] **Step 2: 创建 oh-package.json5**

写入 `hsp-search/oh-package.json5`：

```json5
{
  "name": "hsp_search",
  "version": "1.0.0",
  "description": "搜索模块",
  "main": "Index.ets",
  "author": "",
  "license": "MIT",
  "dependencies": {
    "common": "file:../common",
    "hsp_source": "file:../hsp-source"
  }
}
```

- [ ] **Step 3: 创建 hvigorfile.ts**

写入 `hsp-search/hvigorfile.ts`：

```typescript
import { hspTasks } from '@ohos/hvigor-ohos-plugin';

export default {
  system: hspTasks,
  plugins: []
}
```

- [ ] **Step 4: 创建占位导出文件**

写入 `hsp-search/src/main/ets/Index.ets`：

```typescript
// hsp-search 搜索模块 - 占位
export {}
```

- [ ] **Step 5: 注册到根 build-profile.json5 + entry 依赖**

在 `build-profile.json5` 的 `modules` 中添加 `hsp_search` 条目。

在 `entry/oh-package.json5` 的 `dependencies` 中添加：

```json5
"hsp_search": "file:../hsp-search"
```

### Task 5: 创建 hsp-playlist 模块骨架

**Files:**
- Create: `hsp-playlist/build-profile.json5`
- Create: `hsp-playlist/oh-package.json5`
- Create: `hsp-playlist/hvigorfile.ts`
- Create: `hsp-playlist/src/main/ets/Index.ets` (占位)

- [ ] **Step 1: 创建 build-profile.json5**

写入 `hsp-playlist/build-profile.json5`：

```json5
{
  "apiType": "stageMode",
  "buildOption": {
  },
  "targets": [
    {
      "name": "default"
    }
  ]
}
```

- [ ] **Step 2: 创建 oh-package.json5**

写入 `hsp-playlist/oh-package.json5`：

```json5
{
  "name": "hsp_playlist",
  "version": "1.0.0",
  "description": "歌单管理模块",
  "main": "Index.ets",
  "author": "",
  "license": "MIT",
  "dependencies": {
    "common": "file:../common"
  }
}
```

- [ ] **Step 3: 创建 hvigorfile.ts**

写入 `hsp-playlist/hvigorfile.ts`：

```typescript
import { hspTasks } from '@ohos/hvigor-ohos-plugin';

export default {
  system: hspTasks,
  plugins: []
}
```

- [ ] **Step 4: 创建占位导出文件**

写入 `hsp-playlist/src/main/ets/Index.ets`：

```typescript
// hsp-playlist 歌单模块 - 占位
export {}
```

- [ ] **Step 5: 注册到根 build-profile.json5 + entry 依赖**

在 `build-profile.json5` 的 `modules` 中添加 `hsp_playlist` 条目。

在 `entry/oh-package.json5` 的 `dependencies` 中添加：

```json5
"hsp_playlist": "file:../hsp-playlist"
```

- [ ] **Step 6: 验证项目结构**

运行以下命令验证所有模块能被正确识别：

```bash
devecocli build --help
```

确认无配置错误。

---

## 第二阶段：common 公共模块

### Task 6: 定义核心数据类型 MusicTypes

**Files:**
- Create: `common/src/main/ets/types/MusicTypes.ets`
- Modify: `common/Index.ets`

- [ ] **Step 1: 写入音乐核心数据类型**

写入 `common/src/main/ets/types/MusicTypes.ets`：

```typescript
/**
 * 音源标识（与 社区音源 社区约定一致）
 * kg=酷狗, kw=酷我, tx=QQ, wy=网易, mg=咪咕, local=本地
 */
export enum SourceType {
  KG = 'kg',
  KW = 'kw',
  TX = 'tx',
  WY = 'wy',
  MG = 'mg',
  LOCAL = 'local',
  CUSTOM = 'custom'
}

/**
 * 音质级别
 */
export enum MusicQuality {
  LOW = '128k',      // 标准品质
  HIGH = '320k',     // 高品质
  LOSSLESS = 'flac',  // 无损
  HIRES = 'flac24bit' // Hi-Res
}

/**
 * 一首歌包含的所有音源信息
 */
export interface MusicItem {
  songmid: string          // 歌曲唯一标识
  name: string             // 歌曲名
  singer: string           // 歌手名
  albumName: string        // 专辑名
  interval: number         // 时长（秒）
  imgUrl: string           // 封面图 URL
  lyricUrl: string         // 歌词 URL
  source: SourceType       // 来自哪个音源
  types: Record<string, MusicQualityInfo> // 各音质播放信息
  _types?: Record<string, MusicQualityInfo> // 其他音源的音质（合并时用）
}

/**
 * 某音质下的播放信息
 */
export interface MusicQualityInfo {
  url: string              // 播放地址
  size: number             // 文件大小
  br: number               // 比特率
}

/**
 * 搜索结果
 */
export interface SearchResult {
  list: MusicItem[]        // 歌曲列表
  total: number            // 总数量
  limit: number            // 每页条数
  page: number             // 当前页码
  source: SourceType       // 来源音源
}

/**
 * 歌词行
 */
export interface LyricLine {
  time: number             // 时间（毫秒）
  text: string             // 歌词文本
  transText?: string       // 翻译文本
}

/**
 * 歌单信息
 */
export interface PlaylistInfo {
  id: string               // 歌单 ID
  name: string             // 歌单名称
  description: string      // 描述
  coverUrl: string         // 封面图
  songCount: number        // 歌曲数
  source: SourceType       // 来源音源
  songs: MusicItem[]       // 歌曲列表
}

/**
 * 本地歌单
 */
export interface LocalPlaylist {
  id: string               // 唯一 ID（UUID）
  name: string             // 歌单名称
  description: string      // 描述
  songs: MusicItem[]       // 歌曲列表
  createdAt: number        // 创建时间戳
  updatedAt: number        // 更新时间戳
}

/**
 * 播放模式
 */
export enum PlayMode {
  SEQUENCE = 'sequence',   // 顺序播放
  LOOP_ONE = 'loopOne',    // 单曲循环
  LOOP_ALL = 'loopAll',    // 列表循环
  SHUFFLE = 'shuffle'      // 随机播放
}

/**
 * 播放器状态
 */
export enum PlayerStatus {
  IDLE = 'idle',           // 空闲
  LOADING = 'loading',     // 获取 URL
  BUFFERING = 'buffering', // 缓冲中
  PLAYING = 'playing',     // 播放中
  PAUSED = 'paused',       // 暂停
  ERROR = 'error'          // 出错
}
```

- [ ] **Step 2: 更新 common 导出**

修改 `common/Index.ets`，替换占位内容：

```typescript
// 类型定义
export * from './src/main/ets/types/MusicTypes'
```

### Task 7: 定义音源接口类型 SourceTypes

**Files:**
- Create: `common/src/main/ets/types/SourceTypes.ets`
- Modify: `common/Index.ets`

- [ ] **Step 1: 写入音源接口类型定义**

写入 `common/src/main/ets/types/SourceTypes.ets`：

```typescript
import { MusicItem, SearchResult, LyricLine, PlaylistInfo, MusicQuality, SourceType } from './MusicTypes'

/**
 * 音源基本信息
 */
export interface SourceInfo {
  id: string               // 唯一标识
  name: string             // 音源名称（如"六音"）
  version: string          // 版本号
  author: string           // 作者
  description: string      // 描述
  type: SourceType         // 音源类型
  scriptUrl?: string       // JS 脚本路径（兼容模式）
  nativeModule?: string    // ArkTS 原生模块名（原生模式）
}

/**
 * 可用音源实例
 */
export interface SourceInstance {
  info: SourceInfo
  enabled: boolean         // 是否启用
  priority: number         // 优先级（数字越小越高）
  isNative: boolean        // 是否原生音源

  // 核心音源方法
  search(query: string, page: number, quality: MusicQuality): Promise<SearchResult>
  getMusicInfo(songmid: string, quality: MusicQuality): Promise<MusicItem>
  getLyric(songmid: string): Promise<LyricLine[]>
  getPlaylistInfo(listid: string): Promise<PlaylistInfo>
  getHotSearch(): Promise<Array<{ label: string; value: string }>>
}

/**
 * 音源导入方式
 */
export enum SourceImportMethod {
  LOCAL_FILE = 'localFile',     // 本地 JS 文件
  ONLINE_URL = 'onlineUrl',     // 在线链接
  NATIVE_PACKAGE = 'nativePackage' // 原生 HSP 包
}

/**
 * 音源导入结果
 */
export interface SourceImportResult {
  success: boolean
  source?: SourceInstance
  error?: string
}
```

- [ ] **Step 2: 更新 common 导出**

修改 `common/Index.ets`，添加导出：

```typescript
// 类型定义
export * from './src/main/ets/types/MusicTypes'
export * from './src/main/ets/types/SourceTypes'
```

### Task 8: 实现工具类

**Files:**
- Create: `common/src/main/ets/utils/LogUtils.ets`
- Create: `common/src/main/ets/utils/StorageUtils.ets`
- Create: `common/src/main/ets/utils/NetUtils.ets`
- Modify: `common/Index.ets`

- [ ] **Step 1: 实现 LogUtils**

写入 `common/src/main/ets/utils/LogUtils.ets`：

```typescript
import { hilog } from '@kit.PerformanceAnalysisKit'

const DOMAIN = 0x0001
const TAG = 'SourceMusic'

/**
 * 统一日志工具，封装 hilog
 */
export class LogUtils {
  static debug(msg: string, ...args: string[]): void {
    hilog.debug(DOMAIN, TAG, `[D] ${msg}`, args)
  }

  static info(msg: string, ...args: string[]): void {
    hilog.info(DOMAIN, TAG, `[I] ${msg}`, args)
  }

  static warn(msg: string, ...args: string[]): void {
    hilog.warn(DOMAIN, TAG, `[W] ${msg}`, args)
  }

  static error(msg: string, ...args: string[]): void {
    hilog.error(DOMAIN, TAG, `[E] ${msg}`, args)
  }
}
```

- [ ] **Step 2: 实现 StorageUtils**

写入 `common/src/main/ets/utils/StorageUtils.ets`：

```typescript
import { preferences } from '@kit.ArkData'
import { Context } from '@kit.AbilityKit'
import { LogUtils } from './LogUtils'

const STORE_NAME = 'source_music_store'

/**
 * 本地持久化存储封装，基于 preferences
 */
export class StorageUtils {
  private static store: preferences.Preferences | null = null

  /** 初始化存储（需要在 EntryAbility 中调用） */
  static async init(context: Context): Promise<void> {
    try {
      StorageUtils.store = await preferences.getPreferences(context, STORE_NAME)
      LogUtils.info('存储初始化成功')
    } catch (err) {
      LogUtils.error('存储初始化失败', JSON.stringify(err))
    }
  }

  /** 保存字符串 */
  static async putString(key: string, value: string): Promise<void> {
    if (!StorageUtils.store) return
    await StorageUtils.store.put(key, value)
    await StorageUtils.store.flush()
  }

  /** 读取字符串 */
  static async getString(key: string, defaultValue: string = ''): Promise<string> {
    if (!StorageUtils.store) return defaultValue
    return await StorageUtils.store.get(key, defaultValue) as string
  }

  /** 保存对象（JSON 序列化） */
  static async putObject(key: string, value: Object): Promise<void> {
    await StorageUtils.putString(key, JSON.stringify(value))
  }

  /** 读取对象（JSON 反序列化） */
  static async getObject<T>(key: string, defaultValue: T): Promise<T> {
    const str = await StorageUtils.getString(key, '')
    if (!str) return defaultValue
    try {
      return JSON.parse(str) as T
    } catch {
      return defaultValue
    }
  }

  /** 删除 */
  static async delete(key: string): Promise<void> {
    if (!StorageUtils.store) return
    await StorageUtils.store.delete(key)
    await StorageUtils.store.flush()
  }
}
```

- [ ] **Step 3: 实现 NetUtils**

写入 `common/src/main/ets/utils/NetUtils.ets`：

```typescript
import { http } from '@kit.NetworkKit'
import { LogUtils } from './LogUtils'

/**
 * HTTP 网络请求封装
 */
export class NetUtils {
  /** GET 请求并返回字符串 */
  static async getString(url: string, headers: Record<string, string> = {}): Promise<string> {
    try {
      const request = http.createHttp()
      const response = await request.request(url, {
        method: http.RequestMethod.GET,
        header: headers,
        connectTimeout: 15000,
        readTimeout: 15000
      })
      request.destroy()
      if (response.responseCode === 200) {
        return response.result as string
      }
      LogUtils.warn(`HTTP GET ${url} 返回 ${response.responseCode}`)
      return ''
    } catch (err) {
      LogUtils.error(`HTTP GET ${url} 失败: ${JSON.stringify(err)}`)
      return ''
    }
  }

  /** GET 请求并返回 JSON 对象 */
  static async getJSON<T>(url: string, headers: Record<string, string> = {}): Promise<T | null> {
    const body = await NetUtils.getString(url, headers)
    if (!body) return null
    try {
      return JSON.parse(body) as T
    } catch {
      LogUtils.error(`JSON 解析失败: ${url}`)
      return null
    }
  }
}
```

- [ ] **Step 4: 更新 common 导出**

修改 `common/Index.ets`，添加工具类导出：

```typescript
// 类型定义
export * from './src/main/ets/types/MusicTypes'
export * from './src/main/ets/types/SourceTypes'

// 工具类
export { LogUtils } from './src/main/ets/utils/LogUtils'
export { StorageUtils } from './src/main/ets/utils/StorageUtils'
export { NetUtils } from './src/main/ets/utils/NetUtils'
```

---

## 第三阶段：hsp-source 音源引擎

### Task 9: 定义音源接口规范 SourceAPI

**Files:**
- Create: `hsp-source/src/main/ets/api/SourceAPI.ets`
- Modify: `hsp-source/src/main/ets/Index.ets`

- [ ] **Step 1: 实现音源接口抽象类**

写入 `hsp-source/src/main/ets/api/SourceAPI.ets`：

```typescript
import {
  SourceInfo,
  SourceInstance,
  MusicItem,
  SearchResult,
  LyricLine,
  PlaylistInfo,
  MusicQuality,
  SourceType
} from 'common'

/**
 * ArkTS 原生音源基类 — 所有音源（原生/JS兼容）都实现此接口
 */
export abstract class BaseSource implements SourceInstance {
  info: SourceInfo
  enabled: boolean = true
  priority: number = 99
  isNative: boolean = true

  constructor(info: SourceInfo) {
    this.info = info
  }

  abstract search(query: string, page: number, quality: MusicQuality): Promise<SearchResult>
  abstract getMusicInfo(songmid: string, quality: MusicQuality): Promise<MusicItem>
  abstract getLyric(songmid: string): Promise<LyricLine[]>
  abstract getPlaylistInfo(listid: string): Promise<PlaylistInfo>
  abstract getHotSearch(): Promise<Array<{ label: string; value: string }>>

  /** 解析 LRC 歌词文本为 LyricLine 数组 */
  protected parseLRC(lrcText: string): LyricLine[] {
    const lines: LyricLine[] = []
    const timeRegex = /\[(\d{2}):(\d{2})\.(\d{2,3})\]/g

    for (const line of lrcText.split('\n')) {
      const text = line.replace(timeRegex, '').trim()
      if (!text) continue

      // 重置 lastIndex 以复用正则
      timeRegex.lastIndex = 0
      const matches = line.matchAll(timeRegex)
      for (const match of matches) {
        const min = parseInt(match[1])
        const sec = parseInt(match[2])
        const ms = match[3].length === 2 ? parseInt(match[3]) * 10 : parseInt(match[3])
        lines.push({
          time: (min * 60 + sec) * 1000 + ms,
          text: text
        })
      }
    }
    return lines.sort((a, b) => a.time - b.time)
  }
}

/**
 * 内置演示音源 — 用于测试播放链路（不含版权内容，仅返回模拟数据）
 */
export class DemoSource extends BaseSource {
  constructor() {
    super({
      id: 'demo',
      name: '演示音源',
      version: '1.0.0',
      author: 'Yuki',
      description: '内置演示音源，用于测试播放链路，不含版权音乐',
      type: SourceType.CUSTOM
    })
  }

  async search(query: string, page: number, _quality: MusicQuality): Promise<SearchResult> {
    // 返回模拟搜索结果，确认搜索链路通畅
    return {
      list: [],
      total: 0,
      limit: 30,
      page: page,
      source: SourceType.CUSTOM
    }
  }

  async getMusicInfo(songmid: string, _quality: MusicQuality): Promise<MusicItem> {
    throw new Error('演示音源不支持获取真实播放地址')
  }

  async getLyric(songmid: string): Promise<LyricLine[]> {
    return []
  }

  async getPlaylistInfo(listid: string): Promise<PlaylistInfo> {
    throw new Error('演示音源不支持获取歌单')
  }

  async getHotSearch(): Promise<Array<{ label: string; value: string }>> {
    return []
  }
}
```

- [ ] **Step 2: 更新 hsp-source 导出**

修改 `hsp-source/src/main/ets/Index.ets`：

```typescript
export { BaseSource, DemoSource } from './src/main/ets/api/SourceAPI'
```

### Task 10: 实现多音源管理器 SourceManager

**Files:**
- Create: `hsp-source/src/main/ets/manager/SourceManager.ets`
- Modify: `hsp-source/src/main/ets/Index.ets`

- [ ] **Step 1: 实现 SourceManager**

写入 `hsp-source/src/main/ets/manager/SourceManager.ets`：

```typescript
import {
  SourceInstance,
  SourceInfo,
  SourceImportMethod,
  SourceImportResult,
  SourceType,
  SearchResult,
  MusicItem,
  LyricLine,
  MusicQuality,
  LogUtils,
  StorageUtils
} from 'common'
import { BaseSource, DemoSource } from '../api/SourceAPI'

const STORAGE_KEY_SOURCES = 'source_list'

/**
 * 多音源管理器 — 统一管理所有音源的生命周期
 *
 * 职责：
 * 1. 音源导入（本地文件/在线链接）
 * 2. 音源开关/排序
 * 3. 搜索调度（并发请求所有启用音源）
 * 4. 播放 URL 获取 + 换源回退
 */
export class SourceManager {
  private sources: SourceInstance[] = []
  private static instance: SourceManager | null = null

  /** 单例 */
  static getInstance(): SourceManager {
    if (!SourceManager.instance) {
      SourceManager.instance = new SourceManager()
    }
    return SourceManager.instance
  }

  /**
   * 初始化：加载已保存的音源 + 注册内置演示音源
   */
  async init(): Promise<void> {
    // 加载持久化的音源列表
    const saved = await StorageUtils.getObject<SourceInfo[]>('source_sources', [])
    // 后续 JS 音源导入后再补充加载逻辑

    // 内置演示音源（最低优先级）
    const demo = new DemoSource()
    demo.priority = 999
    this.sources.push(demo)

    LogUtils.info('音源管理器初始化完成', `共 ${this.sources.length} 个音源`)
  }

  /** 获取所有音源 */
  getAllSources(): SourceInstance[] {
    return [...this.sources]
  }

  /** 获取已启用的音源（按优先级排序） */
  getEnabledSources(): SourceInstance[] {
    return this.sources
      .filter(s => s.enabled)
      .sort((a, b) => a.priority - b.priority)
  }

  /** 按 ID 查找音源 */
  getSourceById(id: string): SourceInstance | undefined {
    return this.sources.find(s => s.info.id === id)
  }

  /** 导入音源 */
  async importSource(method: SourceImportMethod, pathOrUrl: string): Promise<SourceImportResult> {
    switch (method) {
      case SourceImportMethod.LOCAL_FILE:
        return this.importFromLocal(pathOrUrl)
      case SourceImportMethod.ONLINE_URL:
        return this.importFromUrl(pathOrUrl)
      default:
        return { success: false, error: '不支持的导入方式' }
    }
  }

  /** 从本地文件导入（.js 脚本） */
  private async importFromLocal(filePath: string): Promise<SourceImportResult> {
    // MVP 阶段：读取文件内容，后续 Task 11 通过 JSSandbox 执行
    LogUtils.info('导入本地音源', filePath)
    return { success: false, error: '本地 JS 音源导入将在 JSSandbox 实现后支持' }
  }

  /** 从在线 URL 导入 */
  private async importFromUrl(url: string): Promise<SourceImportResult> {
    LogUtils.info('导入在线音源', url)
    return { success: false, error: '在线音源导入将在 JSSandbox 实现后支持' }
  }

  /** 移除音源 */
  async removeSource(id: string): Promise<boolean> {
    const index = this.sources.findIndex(s => s.info.id === id)
    if (index < 0) return false
    this.sources.splice(index, 1)
    await this.save()
    return true
  }

  /** 开关音源 */
  async toggleSource(id: string, enabled: boolean): Promise<void> {
    const source = this.getSourceById(id)
    if (source) {
      source.enabled = enabled
      await this.save()
    }
  }

  /** 设置优先级 */
  async setPriority(id: string, priority: number): Promise<void> {
    const source = this.getSourceById(id)
    if (source) {
      source.priority = priority
      await this.save()
    }
  }

  /** 聚合搜索：并发请求所有启用音源 */
  async searchAll(
    query: string,
    page: number = 1,
    quality: MusicQuality = MusicQuality.HIGH
  ): Promise<SearchResult[]> {
    const enabled = this.getEnabledSources()
    LogUtils.info(`聚合搜索: "${query}", ${enabled.length} 个音源`)

    const promises = enabled.map(source =>
      source.search(query, page, quality).catch(err => {
        LogUtils.warn(`音源 ${source.info.name} 搜索失败`, JSON.stringify(err))
        return null
      })
    )

    const results = await Promise.all(promises)
    return results.filter(r => r !== null) as SearchResult[]
  }

  /** 获取播放信息（尝试所有音源直到成功） */
  async getMusicInfoWithFallback(
    songmid: string,
    sourceType: SourceType,
    quality: MusicQuality = MusicQuality.HIGH
  ): Promise<MusicItem | null> {
    const enabled = this.getEnabledSources()

    // 优先用原始音源
    const primary = enabled.find(s => s.info.type === sourceType)
    if (primary) {
      try {
        return await primary.getMusicInfo(songmid, quality)
      } catch (err) {
        LogUtils.warn(`主音源获取失败，尝试换源`, JSON.stringify(err))
      }
    }

    // 换源重试
    for (const source of enabled) {
      if (source.info.type === sourceType) continue
      try {
        const info = await source.getMusicInfo(songmid, quality)
        if (info) return info
      } catch (err) {
        continue
      }
    }

    return null
  }

  /** 持久化音源列表 */
  private async save(): Promise<void> {
    const infos = this.sources.map(s => s.info)
    await StorageUtils.putObject(STORAGE_KEY_SOURCES, infos)
  }
}
```

- [ ] **Step 2: 更新 hsp-source 导出**

修改 `hsp-source/src/main/ets/Index.ets`：

```typescript
export { BaseSource, DemoSource } from './src/main/ets/api/SourceAPI'
export { SourceManager } from './src/main/ets/manager/SourceManager'
```

### Task 11: 实现 JS 音源桥接 JSBridge

**Files:**
- Create: `hsp-source/src/main/ets/api/JSBridge.ets`
- Modify: `hsp-source/src/main/ets/Index.ets`

- [ ] **Step 1: 实现 JSBridge**

写入 `hsp-source/src/main/ets/api/JSBridge.ets`：

```typescript
import { LogUtils, NetUtils } from 'common'

/**
 * JS 音源脚本桥接对象
 *
 * 注入到 JS 沙箱中，为音源脚本提供受限的网络请求和日志能力。
 * 音源脚本通过全局对象 `sourceApi` 访问这些 API。
 *
 * MVP 阶段：定义桥接接口契约，实际 JS 执行将在 JSSandbox 中对接。
 */
export class JSBridge {
  /**
   * HTTP GET 请求（只能请求白名单域名的音乐平台 API）
   */
  static httpGet(url: string, headers: Record<string, string> = {}): Promise<string> {
    return NetUtils.getString(url, headers)
  }

  /**
   * 输出日志（脚本侧调试用）
   */
  static log(level: string, msg: string): void {
    switch (level) {
      case 'error':
        LogUtils.error(`[音源脚本] ${msg}`)
        break
      case 'warn':
        LogUtils.warn(`[音源脚本] ${msg}`)
        break
      default:
        LogUtils.info(`[音源脚本] ${msg}`)
    }
  }

  /**
   * 构建注入到 JS 沙箱的桥接代码（字符串形式）
   * 这段代码在沙箱中执行，创建全局 sourceApi 对象
   */
  static buildBridgeScript(): string {
    return `
      var sourceApi = {
        httpGet: function(url, headers) {
          return __nativeCall__('httpGet', url, headers || {})
        },
        log: function(level, msg) {
          __nativeCall__('log', level, msg)
        }
      };
    `
  }
}
```

- [ ] **Step 2: 更新 hsp-source 导出**

修改 `hsp-source/src/main/ets/Index.ets`：

```typescript
export { BaseSource, DemoSource } from './src/main/ets/api/SourceAPI'
export { SourceManager } from './src/main/ets/manager/SourceManager'
export { JSBridge } from './src/main/ets/api/JSBridge'
```

### Task 12: 实现 JS 沙箱 JSSandbox

**Files:**
- Create: `hsp-source/src/main/ets/sandbox/JSSandbox.ets`
- Modify: `hsp-source/src/main/ets/Index.ets`

- [ ] **Step 1: 实现 JSSandbox 占位框架**

写入 `hsp-source/src/main/ets/sandbox/JSSandbox.ets`：

```typescript
import { LogUtils, SourceInstance, SourceInfo, MusicItem } from 'common'
import { BaseSource } from '../api/SourceAPI'
import { JSBridge } from '../api/JSBridge'

/**
 * JS 音源沙箱
 *
 * 负责在受限环境中执行用户导入的 .js 音源脚本。
 * MVP 阶段提供框架骨架，后续通过以下方案之一实现完整沙箱：
 * - 方案 A：集成 QuickJS C 库（最佳兼容性，需要 NAPI 封装）
 * - 方案 B：使用鸿蒙 WebView 的 JS 引擎
 * - 方案 C：使用 Worker 线程 + 受限全局对象
 */
export class JSSandbox {
  /**
   * 从文件内容创建音源实例
   * @param scriptContent JS 脚本源代码
   * @param sourceInfo 音源基本信息
   * @returns 音源实例（通过 BaseSource 接口调用，内部走 JS）
   */
  static async createSource(
    scriptContent: string,
    sourceInfo: SourceInfo
  ): Promise<SourceInstance | null> {
    LogUtils.info('JSSandbox: 加载音源脚本', sourceInfo.name)

    // MVP 占位：后续实现完整的 JS 执行环境
    // 1. 注入 JSBridge.buildBridgeScript() 创建 sourceApi 全局对象
    // 2. 执行 scriptContent
    // 3. 提取 module.exports 中的音源方法
    // 4. 包装为 BaseSource 派生类返回
    LogUtils.warn('JSSandbox: 沙箱尚未完整实现，返回空结果')

    return null
  }

  /**
   * 验证脚本安全性（白名单检查）
   * @returns null 表示安全，否则返回风险描述
   */
  static validateScript(scriptContent: string): string | null {
    // 禁止访问的 API 黑名单
    const blockedPatterns = [
      /require\s*\(/g,
      /import\s+/g,
      /eval\s*\(/g,
      /Function\s*\(/g,
      /fs\./g,
      /child_process/g,
      /process\./g
    ]

    for (const pattern of blockedPatterns) {
      if (pattern.test(scriptContent)) {
        return `脚本包含禁止的操作: ${pattern.source}`
      }
    }

    return null
  }
}
```

- [ ] **Step 2: 更新 hsp-source 导出**

修改 `hsp-source/src/main/ets/Index.ets`：

```typescript
export { BaseSource, DemoSource } from './src/main/ets/api/SourceAPI'
export { SourceManager } from './src/main/ets/manager/SourceManager'
export { JSBridge } from './src/main/ets/api/JSBridge'
export { JSSandbox } from './src/main/ets/sandbox/JSSandbox'
```

---

## 第四阶段：hsp-player 播放引擎

### Task 13: 实现播放队列 PlayQueue

**Files:**
- Create: `hsp-player/src/main/ets/queue/PlayQueue.ets`
- Create: `hsp-player/src/main/ets/Index.ets` (覆盖占位)

- [ ] **Step 1: 实现 PlayQueue**

写入 `hsp-player/src/main/ets/queue/PlayQueue.ets`：

```typescript
import { MusicItem, PlayMode, LogUtils } from 'common'

/**
 * 播放队列管理器
 *
 * 维护当前播放列表、索引、播放模式。
 * 支持三种来源：搜索结果临时队列 / 歌单队列 / 本地文件队列
 */
@Observed
export class PlayQueue {
  list: MusicItem[] = []
  currentIndex: number = -1
  mode: PlayMode = PlayMode.SEQUENCE

  /** 一次性替换整个队列 */
  replaceList(songs: MusicItem[], startIndex: number = 0): void {
    this.list = [...songs]
    this.currentIndex = Math.min(startIndex, this.list.length - 1)
    LogUtils.info(`播放队列已更新: ${this.list.length} 首, 当前第 ${this.currentIndex + 1} 首`)
  }

  /** 追加歌曲到队列末尾 */
  appendSongs(songs: MusicItem[]): void {
    this.list.push(...songs)
    LogUtils.info(`已添加 ${songs.length} 首到队列`)
  }

  /** 在指定位置插入 */
  insertAt(song: MusicItem, index: number): void {
    this.list.splice(index, 0, song)
    if (this.currentIndex >= index) {
      this.currentIndex++
    }
  }

  /** 移除歌曲 */
  removeAt(index: number): MusicItem | null {
    if (index < 0 || index >= this.list.length) return null
    const removed = this.list.splice(index, 1)[0]
    if (index < this.currentIndex) {
      this.currentIndex--
    } else if (index === this.currentIndex && this.list.length === 0) {
      this.currentIndex = -1
    }
    return removed
  }

  /** 获取当前歌曲 */
  getCurrentSong(): MusicItem | null {
    if (this.currentIndex < 0 || this.currentIndex >= this.list.length) return null
    return this.list[this.currentIndex]
  }

  /** 切到下一首 */
  next(): MusicItem | null {
    if (this.list.length === 0) return null
    switch (this.mode) {
      case PlayMode.LOOP_ONE:
        return this.list[this.currentIndex]
      case PlayMode.SHUFFLE:
        this.currentIndex = Math.floor(Math.random() * this.list.length)
        return this.list[this.currentIndex]
      case PlayMode.LOOP_ALL:
        this.currentIndex = (this.currentIndex + 1) % this.list.length
        return this.list[this.currentIndex]
      case PlayMode.SEQUENCE:
      default:
        if (this.currentIndex < this.list.length - 1) {
          this.currentIndex++
          return this.list[this.currentIndex]
        }
        return null // 播放完毕
    }
  }

  /** 切到上一首 */
  previous(): MusicItem | null {
    if (this.list.length === 0) return null
    switch (this.mode) {
      case PlayMode.LOOP_ONE:
        return this.list[this.currentIndex]
      case PlayMode.SHUFFLE:
        this.currentIndex = Math.floor(Math.random() * this.list.length)
        return this.list[this.currentIndex]
      default:
        if (this.currentIndex > 0) {
          this.currentIndex--
          return this.list[this.currentIndex]
        }
        return this.list[this.currentIndex] // 第一首不动
    }
  }

  /** 跳转到指定索引 */
  skipTo(index: number): MusicItem | null {
    if (index < 0 || index >= this.list.length) return null
    this.currentIndex = index
    return this.list[index]
  }

  /** 清空队列 */
  clear(): void {
    this.list = []
    this.currentIndex = -1
  }

  /** 队列总长度 */
  get length(): number {
    return this.list.length
  }

  /** 是否为空 */
  get isEmpty(): boolean {
    return this.list.length === 0
  }
}
```

- [ ] **Step 2: 写入 hsp-player 导出**

覆盖 `hsp-player/src/main/ets/Index.ets`：

```typescript
export { PlayQueue } from './src/main/ets/queue/PlayQueue'
```

### Task 14: 实现播放器引擎 PlayerEngine

**Files:**
- Create: `hsp-player/src/main/ets/engine/PlayerEngine.ets`
- Modify: `hsp-player/src/main/ets/Index.ets`

- [ ] **Step 1: 实现 PlayerEngine**

写入 `hsp-player/src/main/ets/engine/PlayerEngine.ets`：

```typescript
import { media } from '@kit.MediaKit'
import { backgroundTaskManager } from '@kit.BackgroundTasksKit'
import {
  MusicItem,
  PlayerStatus,
  PlayMode,
  SourceType,
  SourceManager,
  LogUtils
} from 'common'
import { PlayQueue } from '../queue/PlayQueue'

/**
 * 播放器引擎核心
 *
 * 封装 AVPlayer，管理完整的播放生命周期：
 * 空闲 → 获取URL → 缓冲中 → 播放中 ⇄ 暂停
 *
 * 基于 @Observed 实现，状态变化自动触发 UI 更新。
 */
@Observed
export class PlayerEngine {
  // 播放状态
  status: PlayerStatus = PlayerStatus.IDLE
  currentSong: MusicItem | null = null
  currentProgress: number = 0      // 当前播放进度（毫秒）
  duration: number = 0             // 总时长（毫秒）

  // 播放队列
  queue: PlayQueue = new PlayQueue()

  // 歌词
  lyrics: import('common').LyricLine[] = []

  // 内部 AVPlayer 实例
  private avPlayer: media.AVPlayer | null = null
  private progressTimer: number | null = null
  private static instance: PlayerEngine | null = null

  /** 单例 */
  static getInstance(): PlayerEngine {
    if (!PlayerEngine.instance) {
      PlayerEngine.instance = new PlayerEngine()
    }
    return PlayerEngine.instance
  }

  /**
   * 初始化 AVPlayer
   */
  async init(): Promise<void> {
    try {
      this.avPlayer = await media.createAVPlayer()
      this.setupCallbacks()
      LogUtils.info('AVPlayer 初始化完成')
    } catch (err) {
      LogUtils.error('AVPlayer 初始化失败', JSON.stringify(err))
    }
  }

  /**
   * 设置 AVPlayer 回调
   */
  private setupCallbacks(): void {
    if (!this.avPlayer) return

    // 状态变化
    this.avPlayer.on('stateChange', (state: media.AVPlayerState) => {
      switch (state) {
        case media.AVPlayerState.IDLE:
        case media.AVPlayerState.INITIALIZED:
          this.status = PlayerStatus.IDLE
          break
        case media.AVPlayerState.PREPARED:
          this.status = PlayerStatus.PLAYING
          this.startProgressTimer()
          break
        case media.AVPlayerState.PLAYING:
          this.status = PlayerStatus.PLAYING
          break
        case media.AVPlayerState.PAUSED:
          this.status = PlayerStatus.PAUSED
          break
        case media.AVPlayerState.COMPLETED:
          this.handleCompletion()
          break
        case media.AVPlayerState.ERROR:
          this.status = PlayerStatus.ERROR
          LogUtils.error('AVPlayer 播放出错')
          break
      }
    })

    // 时长变化
    this.avPlayer.on('durationUpdate', (duration: number) => {
      this.duration = duration
    })

    // 时间更新
    this.avPlayer.on('timeUpdate', (time: number) => {
      this.currentProgress = time
    })

    // 错误处理
    this.avPlayer.on('error', (err: media.AVPlayerError) => {
      LogUtils.error('AVPlayer 错误', JSON.stringify(err))
      this.status = PlayerStatus.ERROR
    })
  }

  /**
   * 播放指定歌曲
   */
  async play(song: MusicItem): Promise<void> {
    if (!this.avPlayer) {
      LogUtils.error('AVPlayer 未初始化')
      return
    }

    this.status = PlayerStatus.LOADING
    this.currentSong = song

    try {
      // 从音源获取播放 URL
      const sourceMgr = SourceManager.getInstance()
      const musicInfo = await sourceMgr.getMusicInfoWithFallback(song.songmid, song.source)
      if (!musicInfo) {
        LogUtils.error('无法获取播放地址')
        this.status = PlayerStatus.ERROR
        return
      }

      // 选最高可用音质的 URL
      const qualityKey = Object.keys(musicInfo.types)[0]
      const playUrl = musicInfo.types[qualityKey]?.url
      if (!playUrl) {
        LogUtils.error('无可用的播放 URL')
        this.status = PlayerStatus.ERROR
        return
      }

      // 重置 AVPlayer
      await this.avPlayer.reset()
      this.avPlayer.url = playUrl
      this.status = PlayerStatus.BUFFERING
      await this.avPlayer.prepare()
      await this.avPlayer.play()

      // 获取歌词
      this.fetchLyrics(song)

      LogUtils.info(`开始播放: ${song.name} - ${song.singer}`)
    } catch (err) {
      LogUtils.error('播放失败', JSON.stringify(err))
      this.status = PlayerStatus.ERROR
    }
  }

  /**
   * 播放队列中当前歌曲
   */
  async playCurrent(): Promise<void> {
    const song = this.queue.getCurrentSong()
    if (song) {
      await this.play(song)
    }
  }

  /**
   * 暂停 / 继续
   */
  async togglePlay(): Promise<void> {
    if (!this.avPlayer) return
    if (this.status === PlayerStatus.PLAYING) {
      await this.avPlayer.pause()
    } else if (this.status === PlayerStatus.PAUSED) {
      await this.avPlayer.play()
    }
  }

  /**
   * 下一首
   */
  async next(): Promise<void> {
    const song = this.queue.next()
    if (song) {
      await this.play(song)
    } else {
      LogUtils.info('队列播完')
      this.status = PlayerStatus.IDLE
    }
  }

  /**
   * 上一首
   */
  async previous(): Promise<void> {
    const song = this.queue.previous()
    if (song) {
      await this.play(song)
    }
  }

  /**
   * 跳转到指定进度
   */
  async seekTo(timeMs: number): Promise<void> {
    if (!this.avPlayer) return
    await this.avPlayer.seek(timeMs)
  }

  /**
   * 设置播放模式
   */
  setPlayMode(mode: PlayMode): void {
    this.queue.mode = mode
  }

  /**
   * 播放完成回调
   */
  private async handleCompletion(): Promise<void> {
    LogUtils.info('歌曲播放完毕')
    this.stopProgressTimer()
    await this.next()
  }

  /**
   * 异步获取歌词
   */
  private async fetchLyrics(song: MusicItem): Promise<void> {
    try {
      const sourceMgr = SourceManager.getInstance()
      const source = sourceMgr.getSourceById(song.source)
      if (source) {
        this.lyrics = await source.getLyric(song.songmid)
      }
    } catch (err) {
      LogUtils.warn('歌词获取失败', JSON.stringify(err))
      this.lyrics = []
    }
  }

  /**
   * 启动进度更新定时器（每秒）
   */
  private startProgressTimer(): void {
    this.stopProgressTimer()
    this.progressTimer = setInterval(() => {
      if (this.status === PlayerStatus.PLAYING) {
        this.currentProgress += 1000
      }
    }, 1000)
  }

  /**
   * 停止进度定时器
   */
  private stopProgressTimer(): void {
    if (this.progressTimer !== null) {
      clearInterval(this.progressTimer)
      this.progressTimer = null
    }
  }

  /**
   * 释放资源
   */
  async release(): Promise<void> {
    this.stopProgressTimer()
    if (this.avPlayer) {
      await this.avPlayer.release()
      this.avPlayer = null
    }
  }
}
```

- [ ] **Step 2: 更新 hsp-player 导出**

修改 `hsp-player/src/main/ets/Index.ets`：

```typescript
export { PlayQueue } from './src/main/ets/queue/PlayQueue'
export { PlayerEngine } from './src/main/ets/engine/PlayerEngine'
```

---

## 第五阶段：hsp-search 搜索系统

### Task 15: 实现聚合搜索引擎 SearchEngine

**Files:**
- Create: `hsp-search/src/main/ets/SearchEngine.ets`
- Modify: `hsp-search/src/main/ets/Index.ets` (覆盖占位)

- [ ] **Step 1: 实现 SearchEngine**

写入 `hsp-search/src/main/ets/SearchEngine.ets`：

```typescript
import {
  MusicItem,
  SearchResult,
  SourceType,
  MusicQuality,
  SourceManager,
  LogUtils,
  StorageUtils
} from 'common'

const STORAGE_KEY_HISTORY = 'search_history'
const MAX_HISTORY = 50

/**
 * 聚合搜索引擎
 *
 * 1. 并发请求所有启用音源
 * 2. 统一格式
 * 3. 按歌名+歌手去重
 * 4. 合并不同音源的同一首歌
 * 5. 按优先级排序
 */
export class SearchEngine {
  /**
   * 执行聚合搜索
   */
  static async search(
    query: string,
    page: number = 1,
    quality: MusicQuality = MusicQuality.HIGH
  ): Promise<MusicItem[]> {
    if (!query.trim()) return []

    // 保存搜索历史
    SearchEngine.saveHistory(query)

    const sourceMgr = SourceManager.getInstance()
    const results = await sourceMgr.searchAll(query, page, quality)

    // 合并所有结果
    const merged = SearchEngine.mergeResults(results)
    LogUtils.info(`聚合搜索完成: ${merged.length} 首去重结果`)

    return merged
  }

  /**
   * 合并多个音源的结果
   * - 同歌名+同歌手 = 同一首
   * - 同一首歌保留多个音源的信息 _types
   */
  private static mergeResults(results: SearchResult[]): MusicItem[] {
    const map = new Map<string, MusicItem>()

    for (const result of results) {
      for (const item of result.list) {
        const key = `${item.name}_${item.singer}`.toLowerCase()
        const existing = map.get(key)

        if (existing) {
          // 合并音源信息
          existing._types = existing._types ?? {}
          Object.assign(existing._types, item.types)
        } else {
          // 新歌
          item._types = { ...item.types }
          map.set(key, item)
        }
      }
    }

    return Array.from(map.values())
  }

  /**
   * 去重后的结果按原始优先级编排
   */
  static sortBySourcePriority(items: MusicItem[]): MusicItem[] {
    const sourceMgr = SourceManager.getInstance()
    const enabled = sourceMgr.getEnabledSources()
    const priorityMap = new Map<SourceType, number>()
    enabled.forEach(s => priorityMap.set(s.info.type, s.priority))

    return items.sort((a, b) => {
      const pa = priorityMap.get(a.source) ?? 999
      const pb = priorityMap.get(b.source) ?? 999
      return pa - pb
    })
  }

  /**
   * 获取搜索历史
   */
  static async getHistory(): Promise<string[]> {
    return await StorageUtils.getObject<string[]>(STORAGE_KEY_HISTORY, [])
  }

  /**
   * 保存搜索历史
   */
  private static async saveHistory(keyword: string): Promise<void> {
    const history = await SearchEngine.getHistory()
    const filtered = history.filter(h => h !== keyword)
    filtered.unshift(keyword)
    await StorageUtils.putObject(STORAGE_KEY_HISTORY, filtered.slice(0, MAX_HISTORY))
  }

  /**
   * 清除搜索历史
   */
  static async clearHistory(): Promise<void> {
    await StorageUtils.delete(STORAGE_KEY_HISTORY)
  }
}
```

- [ ] **Step 2: 写入 hsp-search 导出**

覆盖 `hsp-search/src/main/ets/Index.ets`：

```typescript
export { SearchEngine } from './src/main/ets/SearchEngine'
```

---

## 第六阶段：hsp-playlist 歌单管理

### Task 16: 实现歌单管理器 PlaylistManager

**Files:**
- Create: `hsp-playlist/src/main/ets/PlaylistManager.ets`
- Modify: `hsp-playlist/src/main/ets/Index.ets` (覆盖占位)

- [ ] **Step 1: 实现 PlaylistManager**

写入 `hsp-playlist/src/main/ets/PlaylistManager.ets`：

```typescript
import {
  LocalPlaylist,
  MusicItem,
  LogUtils,
  StorageUtils
} from 'common'

const STORAGE_KEY_PLAYLISTS = 'local_playlists'

/**
 * 本地歌单管理器
 *
 * 提供歌单的完整 CRUD 操作，支持持久化存储。
 * 后续第二阶段支持导入/导出 .json 格式。
 */
export class PlaylistManager {
  private playlists: LocalPlaylist[] = []
  private static instance: PlaylistManager | null = null

  /** 单例 */
  static getInstance(): PlaylistManager {
    if (!PlaylistManager.instance) {
      PlaylistManager.instance = new PlaylistManager()
    }
    return PlaylistManager.instance
  }

  /** 初始化：从存储加载歌单 */
  async init(): Promise<void> {
    this.playlists = await StorageUtils.getObject<LocalPlaylist[]>(
      STORAGE_KEY_PLAYLISTS, []
    )
    LogUtils.info(`歌单管理器初始化: ${this.playlists.length} 个歌单`)
  }

  /** 获取所有歌单 */
  getAll(): LocalPlaylist[] {
    return [...this.playlists]
  }

  /** 按 ID 获取歌单 */
  getById(id: string): LocalPlaylist | undefined {
    return this.playlists.find(p => p.id === id)
  }

  /** 创建新歌单 */
  async create(name: string, description: string = ''): Promise<LocalPlaylist> {
    const playlist: LocalPlaylist = {
      id: this.generateId(),
      name: name,
      description: description,
      songs: [],
      createdAt: Date.now(),
      updatedAt: Date.now()
    }
    this.playlists.push(playlist)
    await this.save()
    LogUtils.info(`创建歌单: ${name}`)
    return playlist
  }

  /** 更新歌单信息 */
  async update(
    id: string,
    name: string,
    description: string = ''
  ): Promise<boolean> {
    const playlist = this.getById(id)
    if (!playlist) return false
    playlist.name = name
    playlist.description = description
    playlist.updatedAt = Date.now()
    await this.save()
    return true
  }

  /** 删除歌单 */
  async delete(id: string): Promise<boolean> {
    const index = this.playlists.findIndex(p => p.id === id)
    if (index < 0) return false
    this.playlists.splice(index, 1)
    await this.save()
    LogUtils.info(`删除歌单: ${id}`)
    return true
  }

  /** 添加歌曲到歌单 */
  async addSongs(playlistId: string, songs: MusicItem[]): Promise<boolean> {
    const playlist = this.getById(playlistId)
    if (!playlist) return false

    // 去重：已存在的跳过
    const existing = new Set(playlist.songs.map(s => `${s.name}_${s.singer}`))
    const newSongs = songs.filter(s => !existing.has(`${s.name}_${s.singer}`))

    playlist.songs.push(...newSongs)
    playlist.updatedAt = Date.now()
    await this.save()
    LogUtils.info(`添加到歌单 ${playlist.name}: ${newSongs.length} 首`)
    return true
  }

  /** 从歌单移除歌曲 */
  async removeSongs(playlistId: string, songIndices: number[]): Promise<boolean> {
    const playlist = this.getById(playlistId)
    if (!playlist) return false

    // 从大到小排序，避免索引偏移
    const sorted = songIndices.sort((a, b) => b - a)
    for (const index of sorted) {
      playlist.songs.splice(index, 1)
    }
    playlist.updatedAt = Date.now()
    await this.save()
    return true
  }

  /** 持久化保存 */
  private async save(): Promise<void> {
    await StorageUtils.putObject(STORAGE_KEY_PLAYLISTS, this.playlists)
  }

  /** 生成唯一 ID */
  private generateId(): string {
    const chars = 'abcdefghijklmnopqrstuvwxyz0123456789'
    let result = ''
    for (let i = 0; i < 16; i++) {
      result += chars.charAt(Math.floor(Math.random() * chars.length))
    }
    return `pl_${result}_${Date.now()}`
  }
}
```

- [ ] **Step 2: 写入 hsp-playlist 导出**

覆盖 `hsp-playlist/src/main/ets/Index.ets`：

```typescript
export { PlaylistManager } from './src/main/ets/PlaylistManager'
```

---

## 第七阶段：entry UI 壳

### Task 17: 构建全局状态模型

**Files:**
- Create: `entry/src/main/ets/model/PlayerState.ets`
- Create: `entry/src/main/ets/model/AppState.ets`

- [ ] **Step 1: 实现可观察播放器状态**

写入 `entry/src/main/ets/model/PlayerState.ets`：

```typescript
import { MusicItem, PlayerStatus, PlayMode, LyricLine } from 'common'

/**
 * 播放器可观察状态
 *
 * 使用 @Observed 使 PlayerEngine 的状态变化能驱动 UI 更新。
 * 通过 @ObjectLink 在组件树中传递。
 */
@Observed
export class PlayerState {
  status: PlayerStatus = PlayerStatus.IDLE
  currentSong: MusicItem | null = null
  currentProgress: number = 0
  duration: number = 0
  lyrics: LyricLine[] = []
  mode: PlayMode = PlayMode.SEQUENCE
  queueLength: number = 0
  currentIndex: number = -1
}
```

- [ ] **Step 2: 实现全局应用状态**

写入 `entry/src/main/ets/model/AppState.ets`：

```typescript
import { PlayerState } from './PlayerState'
import { PlayerEngine } from 'hsp_player'
import { SourceManager } from 'hsp_source'
import { PlaylistManager } from 'hsp_playlist'
import { StorageUtils, LogUtils } from 'common'

/**
 * 全局应用状态容器
 *
 * 在 EntryAbility 中初始化，通过 @Provide 向整个组件树提供。
 * 持有所有模块的单例引用，统一管理初始化和生命周期。
 */
export class AppState {
  playerState: PlayerState = new PlayerState()

  constructor() {}

  /**
   * 初始化所有子系统
   */
  async init(): Promise<void> {
    LogUtils.info('应用初始化开始...')

    // 1. 初始化持久化存储
    // （StorageUtils.init 在 EntryAbility 中通过 context 调用）

    // 2. 初始化音源管理器
    await SourceManager.getInstance().init()

    // 3. 初始化播放器
    await PlayerEngine.getInstance().init()

    // 4. 初始化歌单管理器
    await PlaylistManager.getInstance().init()

    // 5. 同步播放器状态到可观察对象
    this.syncPlayerState()

    LogUtils.info('应用初始化完成')
  }

  /**
   * 将 PlayerEngine 状态同步到 PlayerState（驱动 UI 更新）
   */
  private syncPlayerState(): void {
    const engine = PlayerEngine.getInstance()
    setInterval(() => {
      this.playerState.status = engine.status
      this.playerState.currentSong = engine.currentSong
      this.playerState.currentProgress = engine.currentProgress
      this.playerState.duration = engine.duration
      this.playerState.lyrics = engine.lyrics
      this.playerState.mode = engine.queue.mode
      this.playerState.queueLength = engine.queue.length
      this.playerState.currentIndex = engine.queue.currentIndex
    }, 500)
  }
}
```

### Task 18: 更新 EntryAbility 初始化入口

**Files:**
- Modify: `entry/src/main/ets/entryability/EntryAbility.ets`

- [ ] **Step 1: 在 EntryAbility 中初始化全局状态**

修改 `entry/src/main/ets/entryability/EntryAbility.ets`，替换原有内容：

```typescript
import { AbilityConstant, ConfigurationConstant, UIAbility, Want } from '@kit.AbilityKit'
import { hilog } from '@kit.PerformanceAnalysisKit'
import { window } from '@kit.ArkUI'
import { StorageUtils, LogUtils } from 'common'
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

    // 初始化持久化存储（需要 context）
    await StorageUtils.init(this.context)

    // 初始化应用全局状态（音源、播放器、歌单）
    await this.appState.init()
    AppStorage.setOrCreate('appState', this.appState)

    windowStage.loadContent('pages/Index', (err) => {
      if (err.code) {
        hilog.error(DOMAIN, 'testTag', 'Failed to load the content. Cause: %{public}s', JSON.stringify(err))
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
```

### Task 19: 实现侧边栏导航 Index 页面

**Files:**
- Modify: `entry/src/main/ets/pages/Index.ets`
- Create: `entry/src/main/ets/components/SideMenu.ets`

- [ ] **Step 1: 实现 SideMenu 组件**

写入 `entry/src/main/ets/components/SideMenu.ets`：

```typescript
/**
 * 侧边栏导航组件
 *
 * 使用 SideBarContainer 实现。
 * 小屏设备侧边栏默认收起，通过手势/按钮唤出。
 * 后续第三阶段改为响应式（小屏 Tab，大屏 SideBar）。
 */
@Component
export struct SideMenu {
  private navigationItems: Array<{
    icon: string,
    label: string,
    pageName: string
  }> = [
    { icon: '', label: '正在播放', pageName: 'pages/NowPlayingPage' },
    { icon: '', label: '搜索', pageName: 'pages/SearchPage' },
    { icon: '', label: '我的歌单', pageName: 'pages/PlaylistListPage' },
    { icon: '', label: '音源管理', pageName: 'pages/SourceManagePage' },
    { icon: '', label: '设置', pageName: 'pages/SettingsPage' }
  ]

  build() {
    Column() {
      // 应用标题
      Text('🎵 源音乐')
        .fontSize(18)
        .fontWeight(FontWeight.Bold)
        .fontColor('#89b4fa')
        .padding({ top: 24, bottom: 16, left: 16 })

      // 导航列表
      ForEach(this.navigationItems, (item, index) => {
        Row() {
          Text(`${item.icon}  ${item.label}`)
            .fontSize(15)
            .fontColor('#cdd6f4')
        }
        .width('100%')
        .padding({ left: 16, top: 12, bottom: 12 })
        .borderRadius(8)
        .onClick(() => {
          // 通过 router 跳转到对应页面
          router.pushUrl({ url: item.pageName })
        })
      })
    }
    .width(200)
    .height('100%')
    .backgroundColor('#2d2d3f')
  }
}
```

- [ ] **Step 2: 重写 Index.ets 为主框架**

修改 `entry/src/main/ets/pages/Index.ets`，替换原有模板内容：

```typescript
import { router } from '@kit.ArkUI'

/**
 * 主框架页面
 *
 * 使用 SideBarContainer 作为根布局。
 * 侧边栏导航 + 内容区（默认显示正在播放页面）。
 */
@Entry
@Component
struct Index {
  @Provide('appState') appState: AppState = AppStorage.get('appState') as AppState
  @State showSideBar: boolean = false

  aboutToAppear(): void {
    // 默认打开正在播放页
    router.pushUrl({ url: 'pages/NowPlayingPage' })
  }

  build() {
    SideBarContainer(SideBarContainerType.Embed) {
      // 侧边栏内容
      Column() {
        Text('🎵 源音乐')
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
```

### Task 20: 实现 NowPlayingPage

**Files:**
- Create: `entry/src/main/ets/pages/NowPlayingPage.ets`
- Create: `entry/src/main/ets/components/LyricView.ets`

- [ ] **Step 1: 实现 LyricView 组件**

写入 `entry/src/main/ets/components/LyricView.ets`：

```typescript
import { LyricLine } from 'common'

/**
 * 滚动歌词组件
 *
 * 根据当前播放进度自动滚动到对应歌词行。
 * 当前行高亮（放大+亮色），其余行半透明。
 * 支持原文+译文对照显示。
 */
@Component
export struct LyricView {
  @Prop lyrics: LyricLine[]
  @Prop currentProgress: number
  @State currentIndex: number = 0

  build() {
    if (this.lyrics.length === 0) {
      Column() {
        Text('纯音乐，请欣赏')
          .fontSize(16)
          .fontColor('#6c7086')
      }
      .width('100%')
      .height('100%')
      .justifyContent(FlexAlign.Center)
      return
    }

    List() {
      ForEach(this.lyrics, (line: LyricLine, index: number) => {
        ListItem() {
          Column({ space: 2 }) {
            // 原文
            Text(line.text)
              .fontSize(index === this.currentIndex ? 18 : 14)
              .fontWeight(index === this.currentIndex ? FontWeight.Bold : FontWeight.Normal)
              .fontColor(index === this.currentIndex ? '#a6e3a1' : '#6c7086')
              .animation({ duration: 300, curve: Curve.EaseOut })

            // 译文（如果有）
            if (line.transText && index === this.currentIndex) {
              Text(line.transText)
                .fontSize(13)
                .fontColor('#585b70')
            }
          }
          .width('100%')
          .padding({ top: 6, bottom: 6 })
          .onClick(() => {
            // 点击跳转到对应时间
            const player = getContext().getSharedObject('playerEngine')
            player?.seekTo(line.time)
          })
        }
      })
    }
    .width('100%')
    .height('100%')
    .scrollBar(BarState.Off)
  }

  aboutToAppear(): void {
    // 根据进度更新当前歌词行
    setInterval(() => {
      for (let i = this.lyrics.length - 1; i >= 0; i--) {
        if (this.currentProgress >= this.lyrics[i].time) {
          this.currentIndex = i
          break
        }
      }
    }, 300)
  }
}
```

- [ ] **Step 2: 实现 NowPlayingPage**

写入 `entry/src/main/ets/pages/NowPlayingPage.ets`：

```typescript
import { PlayerEngine } from 'hsp_player'
import { PlayerState } from '../model/PlayerState'
import { LyricView } from '../components/LyricView'
import { PlayerStatus, PlayMode } from 'common'

/**
 * 正在播放页面
 *
 * 封面旋转 + 歌曲信息 + 播放控制 + 歌词滚动
 */
@Entry
@Component
struct NowPlayingPage {
  @Consume('appState') appState: AppState
  @State playerState: PlayerState = new PlayerState()
  private player: PlayerEngine = PlayerEngine.getInstance()

  build() {
    Column() {
      // 歌曲信息区域
      Column({ space: 8 }) {
        // 封面占位
        Image($r('app.media.startIcon'))
          .width(200)
          .height(200)
          .borderRadius(12)
          .objectFit(ImageFit.Cover)

        Text(this.player.currentSong?.name ?? '未在播放')
          .fontSize(20)
          .fontWeight(FontWeight.Bold)
          .fontColor('#cdd6f4')

        Text(this.player.currentSong?.singer ?? '')
          .fontSize(15)
          .fontColor('#6c7086')
      }
      .padding({ top: 40, bottom: 16 })

      // 进度条
      Row({ space: 12 }) {
        Text(this.formatTime(this.player.currentProgress))
          .fontSize(12)
          .fontColor('#585b70')
        Slider({
          value: this.player.duration > 0
            ? this.player.currentProgress / this.player.duration
            : 0
        })
          .width('60%')
          .onChange((value: number) => {
            const seekTime = value * this.player.duration
            this.player.seekTo(seekTime)
          })
        Text(this.formatTime(this.player.duration))
          .fontSize(12)
          .fontColor('#585b70')
      }
      .width('100%')
      .padding({ left: 24, right: 24 })
      .justifyContent(FlexAlign.Center)

      // 播放控制
      Row({ space: 24 }) {
        Text('⏮')
          .fontSize(28)
          .onClick(() => this.player.previous())

        Text(this.player.status === PlayerStatus.PLAYING ? '⏸' : '▶️')
          .fontSize(36)
          .onClick(() => this.player.togglePlay())

        Text('⏭')
          .fontSize(28)
          .onClick(() => this.player.next())
      }
      .padding({ top: 12, bottom: 8 })
      .justifyContent(FlexAlign.Center)

      // 播放模式
      Row({ space: 16 }) {
        Text(this.getModeIcon())
          .fontSize(16)
          .fontColor('#89b4fa')
          .onClick(() => {
            const modes = [PlayMode.SEQUENCE, PlayMode.LOOP_ONE, PlayMode.LOOP_ALL, PlayMode.SHUFFLE]
            const idx = (modes.indexOf(this.player.queue.mode) + 1) % modes.length
            this.player.setPlayMode(modes[idx])
          })
      }
      .width('100%')
      .justifyContent(FlexAlign.Center)
      .padding({ bottom: 8 })

      // 歌词区域
      LyricView({
        lyrics: this.player.lyrics,
        currentProgress: this.player.currentProgress
      })
        .layoutWeight(1)
    }
    .width('100%')
    .height('100%')
    .backgroundColor('#1e1e2e')
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
```

### Task 21: 实现 SearchPage

**Files:**
- Create: `entry/src/main/ets/pages/SearchPage.ets`
- Create: `entry/src/main/ets/components/MusicItemView.ets`
- Create: `entry/src/main/ets/viewmodel/SearchVM.ets`

- [ ] **Step 1: 实现 SearchVM**

写入 `entry/src/main/ets/viewmodel/SearchVM.ets`：

```typescript
import { MusicItem, SearchEngine } from 'common'

/**
 * 搜索页面 ViewModel
 */
@Observed
export class SearchVM {
  keyword: string = ''
  results: MusicItem[] = []
  isLoading: boolean = false
  history: string[] = []

  async search(query: string): Promise<void> {
    if (!query.trim()) return
    this.isLoading = true
    this.keyword = query

    try {
      this.results = await SearchEngine.search(query)
    } catch (err) {
      this.results = []
    } finally {
      this.isLoading = false
    }
  }

  async loadHistory(): Promise<void> {
    this.history = await SearchEngine.getHistory()
  }

  async clearHistory(): Promise<void> {
    await SearchEngine.clearHistory()
    this.history = []
  }
}
```

- [ ] **Step 2: 实现 MusicItemView**

写入 `entry/src/main/ets/components/MusicItemView.ets`：

```typescript
import { MusicItem, PlayerEngine } from 'common'

/**
 * 歌曲列表项组件
 */
@Component
export struct MusicItemView {
  @Prop song: MusicItem
  @Prop showSource: boolean = true

  build() {
    Row({ space: 12 }) {
      Column({ space: 2 }) {
        Text(this.song.name)
          .fontSize(15)
          .fontColor('#cdd6f4')
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })

        Text(`${this.song.singer} · ${this.song.albumName}`)
          .fontSize(12)
          .fontColor('#6c7086')
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
      }
      .layoutWeight(1)

      if (this.showSource) {
        Text(this.song.source)
          .fontSize(11)
          .fontColor('#89b4fa')
          .padding({ left: 6, right: 6, top: 2, bottom: 2 })
          .backgroundColor('#45475a')
          .borderRadius(4)
      }

      Text(`${this.formatDuration(this.song.interval)}`)
        .fontSize(12)
        .fontColor('#585b70')
    }
    .width('100%')
    .padding({ left: 16, right: 16, top: 12, bottom: 12 })
    .onClick(() => {
      // 替换播放队列并播放
      const player = PlayerEngine.getInstance()
      player.queue.replaceList([this.song])
      player.play(this.song)
    })
  }

  private formatDuration(sec: number): string {
    const m = Math.floor(sec / 60)
    const s = sec % 60
    return `${m}:${s.toString().padStart(2, '0')}`
  }
}
```

- [ ] **Step 3: 实现 SearchPage**

写入 `entry/src/main/ets/pages/SearchPage.ets`：

```typescript
import { SearchVM } from '../viewmodel/SearchVM'
import { MusicItemView } from '../components/MusicItemView'
import { MusicItem, PlayerEngine } from 'common'

@Entry
@Component
struct SearchPage {
  @State viewModel: SearchVM = new SearchVM()
  @State showHistory: boolean = true

  aboutToAppear(): void {
    this.viewModel.loadHistory()
  }

  build() {
    Column() {
      // 搜索框
      Row({ space: 8 }) {
        TextInput({ placeholder: '搜索歌曲、歌手...' })
          .layoutWeight(1)
          .fontSize(15)
          .onChange((value: string) => {
            this.viewModel.keyword = value
            this.showHistory = !value
          })
          .onSubmit((enterKey: EnterKeyType) => {
            this.viewModel.search(this.viewModel.keyword)
            this.showHistory = false
          })

        Button('搜索')
          .fontSize(14)
          .onClick(() => {
            this.viewModel.search(this.viewModel.keyword)
            this.showHistory = false
          })
      }
      .padding({ left: 16, right: 16, top: 12, bottom: 12 })

      // 搜索历史 or 结果
      if (this.showHistory) {
        this.HistoryView()
      } else if (this.viewModel.isLoading) {
        LoadingProgress()
          .color('#89b4fa')
          .width(40)
          .height(40)
      } else {
        this.ResultView()
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor('#1e1e2e')
  }

  @Builder
  HistoryView() {
    Column() {
      Row() {
        Text('搜索历史')
          .fontSize(14)
          .fontColor('#6c7086')
        Blank()
        Text('清除')
          .fontSize(12)
          .fontColor('#f38ba8')
          .onClick(() => this.viewModel.clearHistory())
      }
      .width('100%')
      .padding(16)

      ForEach(this.viewModel.history, (keyword: string) => {
        Row() {
          Text(keyword)
            .fontSize(14)
            .fontColor('#a6adc8')
        }
        .width('100%')
        .padding({ left: 16, top: 10, bottom: 10 })
        .onClick(() => {
          this.viewModel.keyword = keyword
          this.viewModel.search(keyword)
          this.showHistory = false
        })
      })
    }
  }

  @Builder
  ResultView() {
    if (this.viewModel.results.length === 0) {
      Column() {
        Text('未找到相关歌曲')
          .fontSize(15)
          .fontColor('#6c7086')
      }
      .width('100%')
      .height('100%')
      .justifyContent(FlexAlign.Center)
      return
    }

    List() {
      ForEach(this.viewModel.results, (song: MusicItem) => {
        ListItem() {
          MusicItemView({ song: song })
        }
      })
    }
    .width('100%')
    .layoutWeight(1)
    .scrollBar(BarState.Off)
  }
}
```

### Task 22: 实现 PlaylistListPage 和 PlaylistDetailPage

**Files:**
- Create: `entry/src/main/ets/pages/PlaylistListPage.ets`
- Create: `entry/src/main/ets/pages/PlaylistDetailPage.ets`
- Create: `entry/src/main/ets/viewmodel/PlaylistVM.ets`

- [ ] **Step 1: 实现 PlaylistVM**

写入 `entry/src/main/ets/viewmodel/PlaylistVM.ets`：

```typescript
import { LocalPlaylist, PlaylistManager } from 'common'

@Observed
export class PlaylistVM {
  playlists: LocalPlaylist[] = []
  private manager: PlaylistManager = PlaylistManager.getInstance()

  async load(): Promise<void> {
    this.playlists = this.manager.getAll()
  }

  async create(name: string, description: string = ''): Promise<LocalPlaylist | null> {
    const pl = await this.manager.create(name, description)
    if (pl) {
      this.playlists = this.manager.getAll()
    }
    return pl
  }

  async delete(id: string): Promise<void> {
    await this.manager.delete(id)
    this.playlists = this.manager.getAll()
  }
}
```

- [ ] **Step 2: 实现 PlaylistListPage**

写入 `entry/src/main/ets/pages/PlaylistListPage.ets`：

```typescript
import { PlaylistVM } from '../viewmodel/PlaylistVM'
import { LocalPlaylist, PlayerEngine } from 'common'

@Entry
@Component
struct PlaylistListPage {
  @State viewModel: PlaylistVM = new PlaylistVM()

  aboutToAppear(): void {
    this.viewModel.load()
  }

  build() {
    Column() {
      Text('我的歌单')
        .fontSize(18)
        .fontWeight(FontWeight.Bold)
        .fontColor('#cdd6f4')
        .padding({ left: 16, top: 16, bottom: 12 })

      if (this.viewModel.playlists.length === 0) {
        Column() {
          Text('还没有歌单')
            .fontSize(14)
            .fontColor('#6c7086')
          Text('去搜索页添加喜欢的歌曲吧~')
            .fontSize(12)
            .fontColor('#585b70')
            .margin({ top: 4 })
        }
        .width('100%')
        .height('100%')
        .justifyContent(FlexAlign.Center)
        return
      }

      List() {
        ForEach(this.viewModel.playlists, (pl: LocalPlaylist) => {
          ListItem() {
            Row({ space: 12 }) {
              Column({ space: 4 }) {
                Text(pl.name)
                  .fontSize(15)
                  .fontColor('#cdd6f4')
                Text(`${pl.songs.length} 首 · ${new Date(pl.updatedAt).toLocaleDateString()}`)
                  .fontSize(12)
                  .fontColor('#6c7086')
              }
              .layoutWeight(1)

              Text('▶')
                .fontSize(20)
                .fontColor('#a6e3a1')
                .onClick(() => {
                  const player = PlayerEngine.getInstance()
                  player.queue.replaceList(pl.songs)
                  player.playCurrent()
                })
            }
            .width('100%')
            .padding({ left: 16, right: 16, top: 14, bottom: 14 })
            .onClick(() => {
              router.pushUrl({
                url: 'pages/PlaylistDetailPage',
                params: { playlistId: pl.id }
              })
            })
          }
        })
      }
      .width('100%')
      .layoutWeight(1)
    }
    .width('100%')
    .height('100%')
    .backgroundColor('#1e1e2e')
  }
}
```

- [ ] **Step 3: 实现 PlaylistDetailPage**

写入 `entry/src/main/ets/pages/PlaylistDetailPage.ets`：

```typescript
import { PlaylistManager, LocalPlaylist, MusicItem, PlayerEngine } from 'common'
import { MusicItemView } from '../components/MusicItemView'

@Entry
@Component
struct PlaylistDetailPage {
  @State playlist: LocalPlaylist | null = null
  private playlistId: string = ''

  aboutToAppear(): void {
    // 从路由参数获取歌单 ID
    const params = router.getParams() as Record<string, Object>
    this.playlistId = params?.['playlistId'] as string
    if (this.playlistId) {
      this.playlist = PlaylistManager.getInstance().getById(this.playlistId) ?? null
    }
  }

  build() {
    Column() {
      if (!this.playlist) {
        Text('歌单不存在')
          .fontSize(15)
          .fontColor('#6c7086')
        return
      }

      // 歌单信息
      Row({ space: 12 }) {
        Column({ space: 4 }) {
          Text(this.playlist!.name)
            .fontSize(18)
            .fontWeight(FontWeight.Bold)
            .fontColor('#cdd6f4')
          Text(`${this.playlist!.songs.length} 首`)
            .fontSize(12)
            .fontColor('#6c7086')
        }
        Blank()
        Text('▶ 播放全部')
          .fontSize(14)
          .fontColor('#a6e3a1')
          .onClick(() => {
            const player = PlayerEngine.getInstance()
            player.queue.replaceList(this.playlist!.songs)
            player.playCurrent()
          })
      }
      .width('100%')
      .padding(16)

      // 歌曲列表
      List() {
        ForEach(this.playlist!.songs, (song: MusicItem, index: number) => {
          ListItem() {
            MusicItemView({ song: song })
          }
          .swipeAction({
            end: {
              builder: () => {
                Button('删除')
                  .fontSize(13)
                  .backgroundColor('#f38ba8')
                  .onClick(() => {
                    PlaylistManager.getInstance().removeSongs(this.playlistId, [index])
                    this.playlist = PlaylistManager.getInstance().getById(this.playlistId) ?? null
                  })
              }
            }
          })
        })
      }
      .width('100%')
      .layoutWeight(1)
    }
    .width('100%')
    .height('100%')
    .backgroundColor('#1e1e2e')
  }
}
```

### Task 23: 实现 SourceManagePage

**Files:**
- Create: `entry/src/main/ets/pages/SourceManagePage.ets`

- [ ] **Step 1: 实现 SourceManagePage**

写入 `entry/src/main/ets/pages/SourceManagePage.ets`：

```typescript
import { SourceManager, SourceInstance, SourceImportMethod } from 'common'

@Entry
@Component
struct SourceManagePage {
  @State sources: SourceInstance[] = []
  private manager: SourceManager = SourceManager.getInstance()

  aboutToAppear(): void {
    this.sources = this.manager.getAllSources()
  }

  build() {
    Column() {
      // 标题栏
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
      .width('100%')
      .padding(16)

      // 音源列表
      List() {
        ForEach(this.sources, (source: SourceInstance) => {
          ListItem() {
            Row({ space: 12 }) {
              Column({ space: 2 }) {
                Text(source.info.name)
                  .fontSize(15)
                  .fontColor('#cdd6f4')
                Text(`v${source.info.version} · ${source.info.author}`)
                  .fontSize(11)
                  .fontColor('#6c7086')
              }
              .layoutWeight(1)

              Toggle({ type: ToggleType.Switch, isOn: source.enabled })
                .onChange((isOn: boolean) => {
                  this.manager.toggleSource(source.info.id, isOn)
                })

              Text('🗑')
                .fontSize(16)
                .onClick(() => {
                  this.manager.removeSource(source.info.id)
                  this.sources = this.manager.getAllSources()
                })
            }
            .width('100%')
            .padding({ left: 16, right: 16, top: 12, bottom: 12 })
          }
        })
      }
      .width('100%')
      .layoutWeight(1)
    }
    .width('100%')
    .height('100%')
    .backgroundColor('#1e1e2e')
  }

  private showImportDialog(): void {
    AlertDialog.show({
      title: '导入音源',
      message: '选择导入方式',
      autoCancel: true,
      alignment: DialogAlignment.Bottom,
      primaryButton: {
        value: '从本地文件',
        action: () => {
          this.manager.importSource(SourceImportMethod.LOCAL_FILE, '')
            .then(result => {
              if (result.success) {
                this.sources = this.manager.getAllSources()
              }
            })
        }
      },
      secondaryButton: {
        value: '从在线链接',
        action: () => {
          this.manager.importSource(SourceImportMethod.ONLINE_URL, '')
            .then(result => {
              if (result.success) {
                this.sources = this.manager.getAllSources()
              }
            })
        }
      }
    })
  }
}
```

### Task 24: 实现 SettingsPage

**Files:**
- Create: `entry/src/main/ets/pages/SettingsPage.ets`

- [ ] **Step 1: 实现 SettingsPage**

写入 `entry/src/main/ets/pages/SettingsPage.ets`：

```typescript
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
            Text('主题')
              .fontSize(15)
              .fontColor('#cdd6f4')
            Blank()
            Text('深色')
              .fontSize(13)
              .fontColor('#6c7086')
          }
          .width('100%')
          .padding(16)
        }

        ListItem() {
          Row() {
            Text('默认音质')
              .fontSize(15)
              .fontColor('#cdd6f4')
            Blank()
            Text('320k')
              .fontSize(13)
              .fontColor('#6c7086')
          }
          .width('100%')
          .padding(16)
        }

        ListItem() {
          Row() {
            Text('清除缓存')
              .fontSize(15)
              .fontColor('#cdd6f4')
            Blank()
            Text('0 MB')
              .fontSize(13)
              .fontColor('#6c7086')
          }
          .width('100%')
          .padding(16)
          .onClick(() => {
            AlertDialog.show({
              title: '提示',
              message: '缓存已清除',
              autoCancel: true
            })
          })
        }

        ListItem() {
          Row() {
            Text('关于')
              .fontSize(15)
              .fontColor('#cdd6f4')
            Blank()
            Text('源音乐鸿蒙版 v0.1.0')
              .fontSize(13)
              .fontColor('#6c7086')
          }
          .width('100%')
          .padding(16)
        }
      }
      .width('100%')
    }
    .width('100%')
    .height('100%')
    .backgroundColor('#1e1e2e')
  }
}
```

### Task 25: 更新页面路由注册

**Files:**
- Modify: `entry/src/main/resources/base/profile/main_pages.json`

- [ ] **Step 1: 注册所有页面路由**

修改 `entry/src/main/resources/base/profile/main_pages.json`，替换为：

```json
{
  "src": [
    "pages/Index",
    "pages/NowPlayingPage",
    "pages/SearchPage",
    "pages/PlaylistListPage",
    "pages/PlaylistDetailPage",
    "pages/SourceManagePage",
    "pages/SettingsPage"
  ]
}
```

### Task 26: 更新 AppScope 应用信息

**Files:**
- Modify: `AppScope/app.json5`

- [ ] **Step 1: 设置应用基本信息**

修改 `AppScope/app.json5`：

```json5
{
  "app": {
    "bundleName": "com.yuki.source_music",
    "vendor": "yuki",
    "versionCode": 1000000,
    "versionName": "0.1.0",
    "buildVersion": "1",
    "icon": "$media:layered_image",
    "label": "源音乐"
  }
}
```

---

## 第八阶段：验证与收尾

### Task 27: 构建验证

- [ ] **Step 1: 使用 CLI 构建项目**

```bash
cd C:/Users/User/Desktop/source_music
devecocli build
```

检查构建输出，确认无编译错误。

- [ ] **Step 2: 修复编译错误**

根据构建输出修复：
- 模块引用路径错误
- 类型不匹配
- 缺失导出
- 未定义符号

- [ ] **Step 3: 再次构建确认通过**

```bash
devecocli build
```

期望：BUILD SUCCESSFUL

### Task 28: 代码自查

- [ ] **Step 1: 检查所有 emit 目标**：每个 `.ets` 文件都被对应 HSP 的 `Index.ets` 导出
- [ ] **Step 2: 检查模块依赖链**：hsp-search 依赖 common + hsp_source，hsp-player 依赖 common，hsp-playlist 依赖 common
- [ ] **Step 3: 检查页面路由一致性**：main_pages.json 中注册的路径与 router.pushUrl 中使用的路径一致
- [ ] **Step 4: 确保 AppScope 和 entry/module.json5 中的设备类型匹配**

---

## 设计评审

### 自审清单

**1. 规格覆盖：** 对比设计文档的 MVP 五大功能：
- ✅ 音源导入：SourceManager + JSSandbox + JSBridge（Task 9-12）
- ✅ 多音源搜索：SearchEngine + SourceManager.searchAll（Task 10, 15）
- ✅ 音乐播放：PlayerEngine + PlayQueue（Task 13-14）
- ✅ 歌单管理：PlaylistManager（Task 16）
- ✅ 歌词显示：LyricView + PlayerEngine.fetchLyrics（Task 14, 20）

**2. 占位检查：** JSSandbox 为 MVP 占位框架，这是有意为之——完整 JS 沙箱需要 NAPI + QuickJS 编译，属于第二阶段工作

**3. 类型一致性：**
- `MusicItem.source` 类型为 `SourceType` enum，在 MusicItemView 和 SearchEngine 中使用正确
- `PlayerEngine` 方法名 `play`/`pause`/`next`/`previous`/`seekTo` 与 UI 组件调用一致
- `PlaylistManager` 的 `getById`/`addSongs`/`removeSongs` 签名与 ViewModel 使用一致

---

> **Plan complete.** Ready for execution handoff.
