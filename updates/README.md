# Dolikepet 发布与更新接口

当前版本为 **0.2.0 · 纳垢的赐福**，Windows x64。公开仓库 https://github.com/Dolike-moca/Dolikepet 只存游玩包、说明与更新信息；开发工程不在公开仓库中。

## 0.2.0 及后续版本

设置页手动、异步读取 https://raw.githubusercontent.com/Dolike-moca/Dolikepet/main/updates/latest.json 。版本为三段数字，如 `0.2.0`；界面另显示版本名称。

接口字段：`schema: 1`、`channel: "stable"`、`platform: "windows-x86_64"`、`version`、`release_url`、`download_url`、`size_bytes`、`sha256`。只接受指定仓库中与版本一致的发布页、下载路径、有效 SHA-256 和正整数大小。版本按三段数字比较，不提示降级。`beta0.2.0` 与 `0.2.0` 在版本比较时视为同一版本，避免兼容入口形成重复升级。

客户端只提示并打开发布页，不启动远程程序、不自动安装，也不在启动时联网。请求超时 15 秒、响应上限 64 KiB；失败可重试，不阻塞猫咪动作或设置草稿。

## beta0.1.0 兼容入口

旧客户端仅接受 `beta主.次.修订` 格式，并严格校验旧仓库地址和匹配的标签、ZIP 名称。为保持它的「检查更新」可用，继续维护原 `updates/beta.json`，字段为 `channel: "beta"`、`version: "beta0.2.0"`，链接保留旧地址 `https://github.com/DavidGump-070660/Dolikepet`（GitHub 重定向至当前公开仓库）。

`beta0.2.0` 是同一 0.2.0 程序的旧版兼容发布入口，不是另一套构建。其 ZIP 与主发布页的 ZIP 字节完全相同，只有下载文件名不同；兼容页明确链接主发布页及完整更新说明。主发布页、程序内版本和 README 均使用 **0.2.0 · 纳垢的赐福**。

## 发布顺序

1. 更新程序版本、Windows 数字版本、版本名称、游玩说明与本次更新内容。
2. 构建候选版，完成相关回归、720 帧原有效果核对和隔离启动检查。将已核验的同一份文件发布至 Runtime，再从正式文件生成全新精简包。
3. ZIP 仅收录明确列出的运行文件、游玩说明与许可，不遍历玩家的饭盆、胃袋或 AppData。
4. 上传主发布和必要的旧客户端兼容入口，每页附独立 update.json 与 SHA256SUMS.txt。匿名下载核验 ZIP 后，最后以同一次提交更新 README 与两个更新接口。
5. 用原 beta0.1.0 客户端和新客户端分别实测在线检查；保留历史发布及其校验值。

玩家更新前退出桌宠，仅覆盖程序文件，保留原目录的「猫的饭盆」「猫的胃袋」，以及 AppData 中的设置和游戏记录。
