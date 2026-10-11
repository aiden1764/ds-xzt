# tools

维护 ds-xzt 桌面封装时用到的小工具。

## ds-xzt-launch.ps1

用户侧的一键安装脚本本体：下载便携包 → 校验 SHA-256 → 解压到
`%LOCALAPPDATA%\Programs\ds-xzt` → 建桌面快捷方式 → 启动。

不需要管理员权限、不写注册表，删除安装目录即卸载。可覆盖的环境变量：

| 变量 | 作用 |
| --- | --- |
| `DSXZT_DEST` | 安装目录，默认 `%LOCALAPPDATA%\Programs\ds-xzt` |
| `DSXZT_ZIP` | 用本地已有的 zip，跳过下载 |
| `DSXZT_NO_LAUNCH` | 设为 `1` 只安装不启动 |
| `DSXZT_NO_SHORTCUT` | 设为 `1` 不创建桌面快捷方式 |

解压优先用 Windows 自带的 `System32\tar.exe`（bsdtar，37k 个文件约 40 秒），
没有时回退到 .NET 逐条解压。

## make-oneclick-cmd.ps1

把 `ds-xzt-launch.ps1` 嵌进一个自包含的 `.cmd`，发给别人只需一个文件。

```powershell
powershell -ExecutionPolicy Bypass -File tools\make-oneclick-cmd.ps1 `
  -LaunchScript tools\ds-xzt-launch.ps1 `
  -OutFile      ds-xzt-oneclick-setup.cmd
```

为什么不直接把脚本 base64 编码后用 `-EncodedCommand` 传：那会在命令行上放约 24 KB，
而 Windows 命令行上限是 32767 字符，脚本一长就炸。改成把脚本原文追加在
`#:PAYLOAD` 标记之后，由一行 PowerShell 命令把标记之后的内容写进临时 `.ps1` 再执行。

三条编码规则让这个方案成立：

1. `.cmd` 本身是 **UTF-8 无 BOM**，且批处理部分**全 ASCII**——cmd.exe 用 OEM 代码页
   （中文系统是 936）解码文件，中文写在批处理段里必然乱码
2. cmd **永远不会解析** payload：批处理段在标记之前就以 `endlocal & exit /b %RC%` 结束，
   所以 payload 里不会发生 `%VAR%` 展开或命令解释
3. payload 用 `[Text.Encoding]::UTF8` 取出（能正确解码无 BOM 的 UTF-8），
   再**带 BOM** 写回 `.ps1`——Windows PowerShell 5.1 需要 BOM 才能正确读取非 ASCII 脚本

所有面向用户的中文都放在 payload 里，因此能正常显示。

改完 `ds-xzt-launch.ps1` 后记得重新生成 `.cmd`，并同步更新 `SHA256SUMS.txt`。

## pack-asar.js

把目录重新打包成 Electron 的 `app.asar`，无需安装 `asar` / `@electron/asar`。

```powershell
node tools\pack-asar.js <源目录> <输出.asar>
```

asar 布局（本实现直接按此写出，不压缩、不加密）：

```
[UInt32 4][UInt32 headerBufLength][UInt32 payloadSize][UInt32 jsonLength][json][padding][文件数据...]
```

文件数据按 header 中的 `offset` 顺序依次追加，`offset` 相对于数据区起点。
打包完成后建议做往返校验：解包回来逐文件比 SHA-256，确认 0 处不一致。

## ds-xzt-apply.ps1

把 repack 出来的 `app.asar` 装回**已安装**的目录。

它会在应用退出后依次做四件事：

1. 把 `resources\app.asar` 改名为 `app.asar.bak`，再复制新 asar 到位（比对 SHA-256）
2. 把主程序 exe 改名为 `ds-xzt.exe`
3. 更新开始菜单 / 桌面 / 任务栏固定项快捷方式的名称与目标
4. 更新卸载注册表项的 `DisplayName` 与 `DisplayIcon`

脚本刻意写成 **ASCII only**：Windows PowerShell 5.1 会把无 BOM 的 UTF-8 当 ANSI 读，
中文会乱码，所以中文 exe 名和快捷方式路径都在运行时按模式匹配发现，不写死在脚本里。

使用前需要改脚本顶部的 `$root`（默认 `D:\DSH\dsh-desktop-baiyun`），
然后让它在应用**退出后**运行——它会循环等待文件锁释放（最长 1 小时）：

```powershell
# 应用仍在运行时启动，脚本会等它退出
Start-Process powershell -ArgumentList '-NoProfile','-ExecutionPolicy','Bypass','-File','.\tools\ds-xzt-apply.ps1' -WindowStyle Hidden
```

回滚：把 `app.asar.bak` 改名回 `app.asar`，并把 `ds-xzt.exe` 改回原 exe 名。
