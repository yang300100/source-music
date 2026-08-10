# 源音乐 (Source Music)

HarmonyOS 原生音乐播放器，遵循"壳与音源分离"架构。播放器不含任何内置版权音源，音乐数据来自用户导入的 JS 脚本（兼容 LX Music 社区音源生态）或 ArkTS 原生音源模块。

## 平台要求

- HarmonyOS 6.1.1(24) / API 24+
- DevEco Studio 5.0+
- 设备类型：手机 / 平板 / 2in1

## 功能特性

### 核心播放
- 基于 AVPlayer 的原生音频播放引擎
- 播放队列管理（整列表入队 / 切歌 / 顺序播放）
- 进度条拖动（seek）与实时进度同步
- 媒体会话集成（通知栏 / 锁屏控制）
- 后台音频播放

### 音源系统
- 内置搜索源（ArkTS 原生，随应用发布）：
  - 酷狗音乐（搜索 + 播放解析 + 歌词）
  - 网易云音乐（搜索 + 歌词，VIP 歌曲换源解析）
  - QQ 音乐（搜索）
- JS 音源沙箱（JSVM 引擎）：用户可导入社区 .js 音源脚本，兼容 LX Music 生态
- 换源解析：播放失败时自动切换其他可用音源

### 搜索
- 聚合搜索（多源并发，按歌名+歌手去重合并）
- 搜索源选择器（全部 / 酷狗 / 网易 / QQ）
- 搜索历史记录

### 歌单
- 歌单 CRUD（创建 / 重命名 / 删除）
- JSON 格式导入导出
- 备份与恢复

### 本地音乐
- 文件选择器多选导入本地音频文件

### 其他
- 明暗主题切换
- 歌词显示
- 本地音乐下载

## 架构概览

项目采用 HarmonyOS HSP（HarmonyOS Shared Package）模块化架构：

```
entry/              HAP 主模块（壳）-- 唯一可安装入口
common/             HSP 公共层 -- 类型定义 + 工具函数
hsp-source/         HSP 音源引擎 -- BaseSource 抽象基类 + SourceManager + JSVM 沙箱
hsp-player/         HSP 播放器 -- AVPlayer 封装 + PlayQueue + MediaSession
hsp-search/         HSP 搜索 -- SearchEngine 聚合搜索 + 去重合并
hsp-playlist/       HSP 歌单 -- PlaylistManager CRUD + preferences 持久化
```

层级依赖：`entry -> hsp-search / hsp-player / hsp-playlist / hsp-source -> common`

## 音源引擎设计

### 内置搜索源
内置搜索源为 ArkTS 原生实现，随应用发布，受保护不可禁用或删除。使用各平台公开 API 接口。

### JSVM 沙箱（JS 音源）
用户导入的社区 .js 音源脚本运行在 JSVM（JavaScript Virtual Machine）沙箱中，通过 C++ Native 模块（`hsp-source/src/main/cpp/`）实现脚本隔离执行。

关键设计：
- 脚本侧零原生回调：sourceApi.request 仅入队，ArkTS 主动轮询取请求
- `__source_tick__` 驱动脚本内 setTimeout
- 支持搜索型与解析型音源（musicUrl action）

### 换源解析
`getMusicInfoWithFallback` 优先使用原始音源，失败时自动尝试其他已启用音源。

## 构建与运行

### 环境准备

1. 安装 DevEco Studio 5.0+
2. 配置 HarmonyOS SDK（API 24+）
3. 配置签名证书（用于真机调试 / 发布）

### 签名配置

复制 `build-profile.json5.template` 为 `build-profile.json5`，填入你的 HarmonyOS 签名信息：

```bash
cp build-profile.json5.template build-profile.json5
```

然后编辑 `build-profile.json5`，将 `<...>` 占位符替换为你的实际签名文件路径和密码。签名证书可在 DevEco Studio 中通过 File -> Project Structure -> Signing Configs 自动生成。

### 构建命令

```bash
# Debug 构建
devecocli build --modules entry

# Release 构建
devecocli build --modules entry --build-mode release

# 清理构建产物
devecocli build clean

# 构建并安装到已连接设备
devecocli run
```

### 调试

```bash
# 查看错误日志
devecocli log --level E

# 查看应用日志
devecocli log --level I | grep -i source_music
```

播放链路日志前缀 `[播放]`，沙箱日志前缀 `[沙箱]`。

## 项目结构

```
source_music/
  AppScope/                   # 应用全局配置
  entry/                      # HAP 主模块
    src/main/
      ets/
        components/           # UI 组件
        entryability/         # 应用入口
        model/                # 状态模型
        pages/                # 页面
        theme/                # 主题
        utils/                # 工具函数
      resources/              # 资源文件
  common/                     # 公共 HSP
    src/main/ets/
      types/                  # 类型定义 (MusicTypes, SourceTypes)
      utils/                  # 工具 (Log, Storage, Net)
  hsp-source/                 # 音源引擎 HSP
    src/main/
      cpp/                    # JSVM Native 模块 (CMake)
      ets/
        manager/              # SourceManager
        sources/              # 内置音源 + JS 适配器
  hsp-player/                 # 播放器 HSP
  hsp-search/                 # 搜索 HSP
  hsp-playlist/               # 歌单 HSP
  docs/                       # 设计文档
```

## 技术要点

- 状态管理：纯 ArkUI 原生（@State / @Prop / AppStorage），无第三方状态库
- 导航框架：SideBarContainer + Navigation(NavPathStack)
- 网络安全：允许明文 HTTP（AVPlayer 播 http 源需要）
- 进度条：由 AVPlayer `timeUpdate` 事件驱动，不使用定时器模拟
- 构建模式：ArkTS 严格模式（strictMode）

## 注意

- 内置搜索源的公开 API 接口可能随各平台策略变化而失效，需适时维护更新
- JS 音源脚本兼容 LX Music 社区生态，但部分老旧音源可能已停止维护
- 本项目不含任何版权音乐内容，仅提供播放器框架与音源对接能力

## 开源协议

MIT License
