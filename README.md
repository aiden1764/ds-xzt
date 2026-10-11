# ds-xzt

`ds-xzt` 是 [DeepSeek Harness](https://github.com/deepseek-ai/deepseek-harness)
的社区桌面封装（Windows x64）。

应用内置官方 npm 发布产物和 Node.js 24 运行时，**不依赖本机 Node.js**，也不依赖源码目录。
启动窗口会先显示环境依赖配置面板，DSH 服务就绪后再进入主界面。

## 下载

[![一键下载](https://img.shields.io/badge/%E4%B8%8B%E8%BD%BD-%E4%B8%80%E9%94%AE%E5%AE%89%E8%A3%85%E8%84%9A%E6%9C%AC-blue)](https://github.com/aiden1764/ds-xzt/releases/latest/download/ds-xzt-oneclick-setup.cmd)
[![便携包](https://img.shields.io/badge/%E4%B8%8B%E8%BD%BD-%E4%BE%BF%E6%90%BA%E5%8C%85%20466MB-green)](https://github.com/aiden1764/ds-xzt/releases/download/v0.2.0/ds-xzt-portable-0.2.0.zip)

**方式一：一键脚本（推荐，9 KB）**

点这里直接下载 → **[ds-xzt-oneclick-setup.cmd](https://github.com/aiden1764/ds-xzt/releases/latest/download/ds-xzt-oneclick-setup.cmd)**

下载后**双击运行**，它会自动完成：下载便携包 → 校验 SHA-256 → 解压到
`%LOCALAPPDATA%\Programs\ds-xzt` → 建桌面快捷方式 → 启动。不需要管理员权限。

**方式二：手动下载便携包（466 MB）**

点这里直接下载 → **[ds-xzt-portable-0.2.0.zip](https://github.com/aiden1764/ds-xzt/releases/download/v0.2.0/ds-xzt-portable-0.2.0.zip)**

解压后双击 `ds-xzt/ds-xzt.exe`。

SHA-256 见 `SHA256SUMS.txt`。仓库不直接提交大型便携包（466 MB，超出普通仓库单文件限制）。

> 直接下载链接用的是 GitHub 官方域名。如果所在网络访问 github.com 较慢，请在 Releases
> 页面手动下载，或使用你自己的 GitHub 加速前缀。

## 使用

1. 解压 `ds-xzt-portable-0.2.0.zip`，得到 `ds-xzt/` 文件夹（放在任意路径，例如 `D:\ds-xzt`）。
2. 双击 `ds-xzt/ds-xzt.exe` 启动。
3. 首次启动会停留在**环境依赖配置**面板，逐项检测 Node 运行时、DSH 运行时、DSH 入口、本地服务和
   工作区会话；全部显示「就绪」后自动进入 DSH 主界面。任一项显示「缺失」时，下方启动日志会给出
   具体路径和原因。
4. 进入 DSH 后打开模型设置，配置 DeepSeek API 密钥或其他兼容提供方，再选择工作区。

便携包不需要安装，删除文件夹即可移除。

API 密钥和用户配置只保存在应用用户数据目录
（`%APPDATA%\ds-xzt`），不属于本仓库，也不会随源码公开。
不要把 API 密钥或凭据写入工作区目录，也不要提交到 Git。

## 本地服务

桌面封装只在 `127.0.0.1` 上启动 DSH Web 服务，并拒绝窗口导航到其他本地或远程源。
任何知道本机端口的进程仍可能访问该服务；请不要把 API 密钥或凭据写入公开共享目录。

## 本次改造说明

详见 [`MODIFICATIONS.md`](MODIFICATIONS.md)。相对上游白云打包版，本版本改了两处：

1. **启动动画 → 环境依赖配置面板**：把原来的纯动画启动页换成可诊断的依赖检查面板。
2. **品牌改名**：`DSH 白云版` → `ds-xzt`（窗口标题、应用名、exe 名、快捷方式、卸载项、
   许可证与 NOTICE 版权行）。

## 目录结构

```
main.js             Electron 主进程：解析运行时路径、拉起 DSH 服务、维护启动窗口
preload.js          渲染进程桥（contextBridge 暴露 onStatus / onLog）
loading.html/.js    环境依赖配置面板（启动页）
error.html/.js      启动失败页
assets/             应用图标与便携启动图
licenses/           Electron / electron-builder / Node.js 许可证全文
tools/
  pack-asar.js      把目录打包回 app.asar 的最小实现
  ds-xzt-apply.ps1  把 repack 后的 app.asar 装回已安装目录（含改名、快捷方式、卸载项）
build-portable.ps1  把已安装目录打成便携包 zip
```

## 构建

本仓库只包含桌面封装源码。完整重打包需要 Windows、pnpm、本机 Node.js 24，以及官方
DeepSeek Harness 构建产物。

```powershell
git clone https://github.com/deepseek-ai/deepseek-harness.git
git -C deepseek-harness checkout dsh-v0.1.0-rc.8
cd deepseek-harness
pnpm install --no-audit --no-fund
pnpm run build
```

只改启动页或界面文本时，不必重新构建 DSH，直接改本仓库文件再重打 `app.asar` 即可：

```powershell
# 1) 解包正在运行的 resources\app.asar
# 2) 把本仓库文件同步到解包目录
# 3) 重新打包
node tools\pack-asar.js .\app-dir .\app.asar
# 4) 用 tools\ds-xzt-apply.ps1 在应用退出后替换 resources\app.asar
```

改完后用 `build-portable.ps1` 重新生成便携包：

```powershell
powershell -ExecutionPolicy Bypass -File .\build-portable.ps1 `
  -SourceDir 'D:\DSH\dsh-desktop-baiyun' `
  -OutFile   '.\ds-xzt-portable-0.2.0.zip'
```

## 公开范围

仓库公开桌面封装代码、打包脚本、图标资源、许可证和第三方通知。
以下内容不公开：

- 用户 API Key、凭据、工作区、数据库和本地日志
- `build-resources`、`dist`、`node_modules` 和 `qa`
- 构建机上的个人目录和运行时快照

## 许可证

本桌面封装以 MIT 许可证发布，见 `LICENSE`。

DeepSeek Harness 使用 MIT 许可证。完整第三方通知见 `THIRD_PARTY_NOTICES.md`，
Electron、electron-builder 和 Node.js 的许可证见 `licenses/`。

## 安全报告

请通过 GitHub Issues 报告安全相关缺陷。漏洞报告不要包含真实凭据、
私有工作区数据或个人敏感文件。
