# 改造说明

本版本基于上游「DSH 白云版」打包产物（`dsh-desktop-baiyun` 0.2.0，
DeepSeek Harness v0.1.0-rc.8）做了两处修改。

## 1. 启动动画 → 环境依赖配置面板

**改动前**：启动窗口是一段纯动画，用户只能等待，失败时也只能看到一句笼统的错误。

**改动后**：启动窗口变成依赖检查面板，逐项显示真实状态，失败时直接给出路径和原因。

| 检查项 | 说明 |
| --- | --- |
| Node 运行时 | `resources/runtime/node.exe` 是否存在 |
| DSH 运行时 | `resources/dsh/node_modules` 是否存在 |
| DSH 入口 | DSH 的 CLI 入口脚本是否可解析 |
| 本地服务 | `127.0.0.1` 上的 DSH Web 服务是否就绪、端口号 |
| 工作区 / 会话 | 工作区目录是否可写、会话是否初始化完成 |

顶部状态行按阶段推进：`正在准备启动窗口 → 正在解析运行环境路径 → 正在校验环境依赖 →
正在启动 DSH 本地服务 → 本地服务已就绪 → 正在准备工作区与会话 → 环境就绪`。
下方 190px 的启动日志区实时输出主进程日志（保留最后 24000 字符）。

涉及文件：

- `loading.html` — 面板结构（5 行依赖 + 日志区），标题为 `ds-xzt · 环境依赖配置`
- `loading.js` — 渲染逻辑：订阅 `window.dshDesktop.onStatus` / `onLog`，把
  `{ ok: true | false | undefined }` 映射为「就绪 / 缺失 / 检测中」三种徽标
- `preload.js` — 通过 `contextBridge` 暴露 `onStatus` / `onLog` 两个订阅
- `main.js` — 主进程按阶段调用 `reportStatus()` 上报五类依赖状态，并转发服务日志

## 2. 品牌改名 `DSH 白云版` → `ds-xzt`

覆盖范围：

| 位置 | 原值 | 新值 |
| --- | --- | --- |
| `package.json` `productName` | `DSH 白云版` | `ds-xzt` |
| `package.json` `description` | 白云打包版描述 | `ds-xzt —— DeepSeek Harness 社区桌面版` |
| 窗口标题 / 加载页标题 | `DSH 白云版` | `ds-xzt` |
| `error.html` 标题与正文 | `DSH 白云版无法启动` | `ds-xzt 无法启动` |
| 主程序 exe 文件名 | `DSH 白云版.exe` | `ds-xzt.exe` |
| 开始菜单快捷方式与文件夹 | `DSH 白云版.lnk` | `ds-xzt\ds-xzt.lnk` |
| 卸载项 `DisplayName` / `DisplayIcon` | `DSH 白云版` | `ds-xzt` |
| `LICENSE` 版权行 | `DSH 白云版 contributors` | `ds-xzt contributors` |
| `NOTICE` | `DSH Baiyun Desktop` | `ds-xzt` |

`package.json` 的 `name` 字段保留 `dsh-desktop-baiyun`，因为用户数据目录、
单实例锁与 Electron 的 `app.getPath('userData')` 都按它取名；
改掉会让现有会话和 API Key 失效。

## 生效方式

改动以两种方式同时落地，互为保险：

1. `resources/app/` 目录（解包后的源码）
2. `resources/app.asar`（由 `resources/app/` 重新打包，字节级往返校验通过：
   20 个文件、0 处哈希不一致）

> 注意：Electron 优先加载 `resources/app.asar`。`resources/app/` 目录只在 asar 不存在时生效。

原文件保存在 `resources/app.asar.bak` 与 `resources/app.asar.orig`（两者内容相同，
均为上游原始 asar）。便携包中不包含这两个回滚副本。
