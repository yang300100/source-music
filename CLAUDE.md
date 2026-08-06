# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## 项目概述

洛雪音乐鸿蒙版 — 基于 HarmonyOS 的原生音乐播放器，遵循"壳与音源分离"架构。播放器不含任何内置版权音源，音乐数据来自用户导入的 JS 脚本（兼容 lx-music 社区生态）或 ArkTS 原生音源模块。

**三阶段推进**：MVP（核心链路）→ 功能补齐（原版全覆盖）→ 鸿蒙深度集成（分布式/元服务）

详见 `docs/superpowers/specs/2026-08-06-lx-harmonyos-design.md`

## 当前进度（2026-08-06 记录）

### ✅ 已完成

| 功能 | 状态 |
|------|------|
| JSVM 音源沙箱（完整执行社区 .js 音源） | ✅ 编译通过 + 实测不崩溃 |
| 搜索（酷狗/网易/QQ 三个内置搜索源） | ✅ 实测出真实结果 |
| 播放（URL 解析 → AVPlayer） | ✅ 实测出声 |
| 音源持久化（重启自动恢复 JS 音源） | ✅ |
| 本地音乐导入（文件选择器多选） | ✅ |
| 歌单 CRUD + .lxmc 导入导出 + 备份恢复 | ✅ |
| 媒体会话（通知栏/锁屏控制） | ✅ |
| 主题切换、搜索历史 | ✅ |
| 播放队列（整列表入队切歌） | ✅ |
| 进度条/seek（timeUpdate 驱动） | ✅ |
| 搜索页搜索源选择器（全部/酷狗/网易/QQ） | ✅ |

### ⚠️ 已知限制
- JS 音源多为**解析型**（如野花/野草只支持 musicUrl，不支持搜索；部分服务已失效 404）
- 搜索依赖内置源（酷狗/网易/QQ），其中网易/QQ 播放 VIP 歌曲需换源解析
- 均衡器/音效、通知栏下一首队列等未实现

## 构建与运行

```bash
devecocli build --modules entry            # 构建 debug HAP
devecocli build --modules entry --build-mode release  # 发布构建
devecocli build clean                     # 清理
devecocli run                             # 构建并安装到设备
devecocli log --level E                   # 查看错误日志
devecocli log --level I | grep -i lxmusic # 应用日志（TAG=LxMusic）
devecocli docs search "关键词"            # 搜索本地 HarmonyOS 文档
```

**调试设备**：HUAWEI MatePad Pro（hdc 路径 `D:/DevEco Studio/sdk/default/openharmony/toolchains/hdc.exe`）

**注意**：签名密钥（`build-profile.json5` 中的 signingConfigs）绑定 `com.yuki.source_music`，换 bundleName 需在 DevEco Studio 中 File → Project Structure → Signing Configs → Fix 重新生成。

## 架构：HSP 模块划分

```
entry/              # HAP 主模块（壳）— 唯一可安装入口
  └── pages/Index.ets   # SideBarContainer + Navigation(NavPathStack) 导航框架
common/             # HSP 公共层 — 类型定义(MusicTypes, SourceTypes) + 工具(Log/Storage/Net)
hsp-source/         # HSP 音源引擎 — BaseSource 抽象基类 + SourceManager + JSVM 沙箱
hsp-player/         # HSP 播放器 — AVPlayer 封装 + PlayQueue + MediaSession
hsp-search/         # HSP 搜索 — SearchEngine 聚合搜索 + 去重合并
hsp-playlist/       # HSP 歌单 — PlaylistManager CRUD + preferences 持久化
```

**层级依赖**：entry → hsp-search/hsp-player/hsp-playlist/hsp-source → common（所有 HSP 单向依赖 common）

## 核心设计决策

### 音源系统（壳与源分离）
- **内置搜索源**（ArkTS 原生，随应用发布，受保护不可禁用/删除）：
  - `KugouSource`（酷狗）：搜索 + 播放解析 + 歌词（`mobilecdn.kugou.com` 公开接口）
  - `NeteaseSource`（网易云）：搜索 + 歌词（VIP 播放抛错换源）
  - `QQSource`（QQ 音乐）：仅搜索（播放需签名）
- **JS 音源**（用户导入，JSVM 沙箱执行，单选互斥）：
  - 解析型（野花/野草/六音）：只支持 musicUrl action
  - 搜索型：部分社区源支持 search action（参数需传 text/keyword/name/query 等全字段）
- **换源解析**：`getMusicInfoWithFallback` 优先原始音源 → 失败换其他启用音源
- 音源管理页只显示 JS 音源/本地/演示；搜索源选择在搜索页

### JSVM 沙箱（关键架构）
- **native 模块**：`hsp-source/src/main/cpp/`（CMake + jsvm_bridge.cpp + napi_init.cpp）
  - 导出 API：`createVM/destroyVM/evalScript/callGlobalFunction/setNativeResult`
  - ArkTS 加载方式：`import jsvmBridgeNative from 'libjsvm_bridge.so'`（**不能用 requireNapi**）
- **脚本执行架构**（重要！踩坑总结）：
  - **脚本侧零原生回调**：lx.request 只入队（pendingRequests），ArkTS 主动轮询 `__lx_takeRequests__` 取请求、`__lx_takeResult__` 取结果
  - `__lx_resolveRequest__` 由 native 在干净栈上调用（setNativeResult）
  - `__lx_tick__` 驱动脚本内 setTimeout（脚本兼容性关键）
  - callAction 等待循环：tick → 取请求 → 发网络 → 取结果（15 秒超时）
- **V8 深坑**（全部已修）：
  - HandleScope/EnvScope/VMScope 三层作用域（最外层调用必须全开）
  - **V8 回调栈内禁止 OpenVMScope**（Isolate::Scope 嵌套崩溃）
  - **禁止 V8 栈内 napi_call_function 跨 VM 调用**（改 TSFN/轮询）
  - CreateStringUtf8 必须传真实长度（传 0 = 空 key）
  - CompileScript 需要 cacheRejected 变量；eagerCompile 用 true
  - CallFunction 参数禁止 nullptr（JsonToValue 失败兜底 null）
  - JSVM 每次 RunScript 全局不共享 → PRELOAD 与用户脚本合并一次执行

### 播放器
- `PlayerEngine` 封装 AVPlayer，状态机 `IDLE → LOADING → BUFFERING → PLAYING ⇄ PAUSED`
- **设置 URL 后必须等待状态变 initialized 再 prepare**（否则挂起）
- 进度条：真实进度由 `timeUpdate` 驱动（**不要用定时器 += 覆盖**）
- seek 后自动恢复播放
- **网络安全配置**：`entry/src/main/resources/base/profile/network_config.json` 允许明文 HTTP（`component-config: { "Media Kit": true }`）——AVPlayer 播 http 源必需
- 媒体会话（AVSession）集成：通知栏/锁屏展示与控制

### UI 状态同步（重要）
- **@Observed 已被移除**（与 static 方法冲突导致崩溃）
- UI 刷新靠**轮询快照**：NowPlayingContent/MiniPlayerBar 用 @State 字段 + setInterval 500ms 从 PlayerEngine 同步
- **swipeAction 的 builder 必须是 @Builder 方法**（普通箭头函数写组件会崩：Cannot read fontSize of undefined）

### 其他
- 导航：Index.ets 使用 `SideBarContainer` + `Navigation(NavPathStack)`，子页面为 `@Component` struct 包裹在 `NavDestination()` 中
- 状态管理：纯 ArkUI 原生（`@State`/`@Prop`/`AppStorage`），无第三方状态库
- 搜索：按 `(歌名+歌手)` 去重，不同音源的同名歌曲合并到 `_types` 字段
- 聚合搜索每源 8 秒超时（`withTimeout`），慢源不拖累整体
- 音源持久化：`source_list`（元信息+enabled+priority）+ `source_scripts`（脚本内容）

## ArkTS 严格模式注意事项

项目启用 ArkTS 严格模式（`build-profile.json5` 中的 `strictMode`），编译时会强制执行：

- **禁止 `@Observed` 类有 `static` 方法**：运行时报 `ReferenceError: Observed is not defined`
- **禁止对象展开 `{ ...obj }`**：用 `Object.assign({}, obj)` 替代
- **禁止 `Array<{ k: v }>` 内联类型**：必须用命名的 `interface`
- **禁止 `this` 在静态方法中调用其他静态方法**：用 `ClassName.method()` 替代 `this.method()`
- **`@Builder` 函数中禁止 `return`**：用 `if/else` 链代替 `if + return`
- **注释里禁止写 `/* ... */` 字样**（会提前终止注释块导致代码被注释）
- **异常必须显式处理**：带 `throws` 标记的方法调用需要 try-catch
- **interface 不能放在装饰器（@Component）后面**

## 调试技巧

- 播放链路日志前缀 `[播放]`（URL 获取/reset/prepare/play/状态变化/时长更新全链路）
- 沙箱日志前缀 `[沙箱]`（action 调用/网络请求/结果）
- 崩溃文件：`hidumper -s 1201 -a "-p Faultlogger -m source_music"`（hdc 执行）
- JS 崩溃：`hidumper -s 1201 -a "-p Faultlogger -f jscrash-xxx.log"` 读取详情
