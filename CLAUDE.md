# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## 项目概述

洛雪音乐鸿蒙版 — 基于 HarmonyOS 的原生音乐播放器，遵循"壳与音源分离"架构。播放器不含任何内置版权音源，音乐数据来自用户导入的 JS 脚本（兼容 lx-music 社区生态）或 ArkTS 原生音源模块。

**三阶段推进**：MVP（核心链路）→ 功能补齐（原版全覆盖）→ 鸿蒙深度集成（分布式/元服务）

详见 `docs/superpowers/specs/2026-08-06-lx-harmonyos-design.md`

## 构建与运行

```bash
devecocli build --modules entry            # 构建 debug HAP
devecocli build --modules entry --build-mode release  # 发布构建
devecocli build clean                     # 清理
devecocli run                             # 构建并安装到设备
devecocli log --level E                   # 查看错误日志
devecocli docs search "关键词"            # 搜索本地 HarmonyOS 文档
```

**注意**：签名密钥（`build-profile.json5` 中的 signingConfigs）绑定 `com.yuki.source_music`，换 bundleName 需在 DevEco Studio 中 File → Project Structure → Signing Configs → Fix 重新生成。

## 架构：HSP 模块划分

```
entry/              # HAP 主模块（壳）— 唯一可安装入口
  └── pages/Index.ets   # SideBarContainer + Navigation(NavPathStack) 导航框架
common/             # HSP 公共层 — 类型定义(MusicTypes, SourceTypes) + 工具(Log/Storage/Net)
hsp-source/         # HSP 音源引擎 — BaseSource 抽象基类 + SourceManager 多音源管理 + JSSandbox
hsp-player/         # HSP 播放器 — AVPlayer 封装 + PlayQueue 播放队列
hsp-search/         # HSP 搜索 — SearchEngine 聚合搜索 + 去重合并
hsp-playlist/       # HSP 歌单 — PlaylistManager CRUD + preferences 持久化
```

**层级依赖**：entry → hsp-search/hsp-player/hsp-playlist/hsp-source → common（所有 HSP 单向依赖 common）

## 核心设计决策

- **导航**：Index.ets 使用 `SideBarContainer` + `Navigation(NavPathStack)`，子页面为 `@Component` struct 包裹在 `NavDestination()` 中（不是 `@Entry`），侧边栏切换页面不销毁导航状态
- **状态管理**：纯 ArkUI 原生（`@State`/`@Prop`/`AppStorage`），无第三方状态库。`PlayerEngine` 和 `PlaylistManager` 为单例，`AppStorage` 用于跨页面数据传递（如 `selectedPlaylistId`）
- **播放器**：`PlayerEngine` 封装 AVPlayer，状态机 `IDLE → LOADING → BUFFERING → PLAYING ⇄ PAUSED`，支持 URL 失效后自动换源重试
- **音源**：双轨 — ArkTS 原生（`BaseSource` 抽象类）+ JS 兼容（`JSSandbox`/`JSBridge`，MVP 占位待第二阶段实现）
- **搜索**：并发请求所有启用音源，按 `(歌名+歌手)` 去重，不同音源的同名歌曲合并到 `_types` 字段，按音源优先级排序

## ArkTS 严格模式注意事项

项目启用 ArkTS 严格模式（`build-profile.json5` 中的 `strictMode`），编译时会强制执行：

- **禁止 `@Observed` 类有 `static` 方法**：运行时报 `ReferenceError: Observed is not defined`。若需要单例模式，去掉 `@Observed` 装饰器
- **禁止对象展开 `{ ...obj }`**：用 `Object.assign({}, obj)` 替代
- **禁止 `Array<{ k: v }>` 内联类型**：必须用命名的 `interface`
- **禁止 `this` 在静态方法中调用其他静态方法**：用 `ClassName.method()` 替代 `this.method()`
- **`@Builder` 函数中禁止 `return`**：用 `if/else` 链代替 `if + return`
- **异常必须显式处理**：带 `throws` 标记的方法调用需要 try-catch
