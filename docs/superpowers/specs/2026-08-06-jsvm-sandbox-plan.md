# JS 音源完整沙箱方案 — JSVM-API 集成计划

> 日期：2026-08-06 | 状态：调研完成，待实施

## 一、背景

社区音源 社区音源脚本（新版事件驱动格式）需要**真实执行 JS 代码**才能工作：
- 脚本通过 `globalThis.sourceApi.on(sourceApi.EVENT_NAMES.request, handler)` 注册请求处理器
- 处理器内部做加密签名、参数构造、响应解析（无法用正则模拟）
- 当前 `JSSourceAdapter` 只能正则提取 URL 模式，无法运行复杂脚本

## 二、调研结论：鸿蒙官方 JSVM-API

**鸿蒙系统自带完整的 JavaScript 引擎能力（JSVM-API）**，无需集成 QuickJS：

| 项目 | 详情 |
|------|------|
| 库文件 | `libjsvm.so`（系统内置） |
| 头文件 | `ark_runtime/jsvm.h`（SDK 提供） |
| 起始版本 | API 11 |
| 平台 | arm64 |
| 能力 | 引擎生命周期管理、JS context、代码执行、JS/C++ 互操作、快照、code cache |
| 对标 | 相当于 QuickJS/V8 的官方替代品 |

**优势**：
- 系统自带，无需编译第三方引擎
- JIT 编译加速，性能优于 QuickJS 解释执行
- 严格遵守 ECMAScript 规范

**参考**：
- [JSVM-API 使用指导（官方）](https://developer.huawei.com/consumer/cn/doc/harmonyos-guides/jsvm-guidelines)
- [jsvm.h 接口定义](https://developer.huawei.com/consumer/cn/doc/harmonyos-references/capi-jsvm-h)

## 三、架构设计

```
ArkTS 层（hsp-source）
┌─────────────────────────────────────────┐
│ JSSandbox（完整实现）                     │
│  - evalScript(script, bridge) → exports  │
│  - callHandler(handler, args) → result   │
│  - requestQueue 管理                     │
└──────────────┬──────────────────────────┘
               │ NAPI 调用
┌──────────────▼──────────────────────────┐
│ Native 层（hsp-source/src/main/cpp/）     │
│  JsvmBridge (C++)                        │
│  - OH_JSVM_CreateVM / CreateEnv          │
│  - OH_JSVM_RunScript 执行脚本            │
│  - 注入 sourceApi 全局对象（request 桥接）       │
│  - 回调 ArkTS（napi 线程安全函数）         │
└──────────────┬──────────────────────────┘
               │ libjsvm.so
┌──────────────▼──────────────────────────┐
│ 系统 JSVM 引擎（ECMAScript 标准）         │
└─────────────────────────────────────────┘
```

## 四、实施步骤（预估）

1. **Native 骨架**（hsp-source 加 native 目录）
   - `hsp-source/src/main/cpp/CMakeLists.txt`
   - `hsp-source/src/main/cpp/napi_init.cpp` — NAPI 模块注册
   - `hsp-source/src/main/cpp/jsvm_bridge.cpp` — JSVM 封装
   - `hsp-source/oh-package.json5` 配置 `externalNativeOptions`

2. **核心 API**（暴露给 ArkTS）
   - `createVM()` → VM 句柄
   - `evalScript(script)` → 执行脚本
   - `callFunction(fnName, argsJson)` → 调用脚本内函数
   - `registerNativeFunction(name, napiRef)` → 注入 `sourceApi.request` 等原生能力
   - `destroyVM()`

3. **sourceApi 运行环境注入**（对齐原版 user-api-preload.js）
   - `globalThis.sourceApi = { EVENT_NAMES, request, send, on, utils, version, env }`
   - `request` → NAPI 回调 ArkTS → NetUtils 发请求 → 回调 JS Promise
   - `send(EVENT_NAMES.inited, { sources })` → 上报支持的音源/音质
   - `on(EVENT_NAMES.request, handler)` → 注册请求处理器
   - 安全限制：禁 eval/Function 构造器、冻结全局对象（对齐原版）

4. **JSSandbox 完整化**
   - 导入脚本 → 创建 VM → 注入 sourceApi 环境 → 执行脚本 → 等待 inited 事件
   - 包装为 `JSScriptSource implements SourceInstance`
   - search/getMusicInfo/getLyric 内部：构造 request → 调 JS handler → 解析结果

5. **验证**
   - 导入社区真实音源（六音 latest.js）实测搜索/播放/歌词

## 五、风险与对策

| 风险 | 对策 |
|------|------|
| JSVM C API 学习成本 | 官方有完整使用指导 + 示例代码 |
| 线程模型（JSVM 单线程） | 所有 JS 操作串行化，request 异步回调经线程安全函数 |
| 脚本兼容性（ES 特性） | JSVM 遵守 ECMAScript 规范，兼容性优于 QuickJS |
| 调试困难 | 分层测试：先跑通 evalScript 简单脚本，再逐步注入 sourceApi 环境 |

## 六、前置依赖

- DevEco Studio NDK（native 编译）
- API 11+（当前项目 API 24，满足）
