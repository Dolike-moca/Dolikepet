# Dolikepet

Dolike 桌宠的 Windows 64 位精简游玩版。本仓库只提供游玩包、使用说明和更新信息。

## 下载与启动

[下载 beta0.1.0](https://github.com/DavidGump-070660/Dolikepet/releases/tag/beta0.1.0)。在 Release 的 Assets 中下载 `Dolikepet-beta0.1.0-windows-x64.zip`，完整解压后双击 `Dolikepet/DolikePet.exe`。自动生成的 Source code 压缩包不是游戏。

无需安装 Godot、Python 或 Live2D 编辑器。EXE、PCK、DLL 必须放在一起。右键猫咪或系统托盘可打开设置；猫咪和坩埚共用托盘图标。

## 饭盆与接猫挑战

拖动猫咪、滚轮缩放；显示饭盆后可双击锅打开文件夹，或将文件拖入锅。**投喂会移动文件：吃完移入“猫的胃袋”，到达消化时间后永久删除，不进入回收站。** 请只投喂确认不再需要的文件。容量、消化时间、自动开锅均在设置中调整。

把猫抛向上、左、右边框并接住，自动开始接猫挑战。一次抛出碰边 n 次得 n² 分；连续接住每逢 10、20、30……次分别额外加 10、20、30……分。接住后 3 秒未再抛出或没有接住，本轮清零，最高分保留。倒计时剩 1 秒开始渐隐，归零后再过 1 秒完全透明并关闭计分窗。

## 更新

右键 → 桌宠设置 → 版本与更新 → 检查更新。检测到新版本时打开对应发布页下载。退出旧桌宠，再用新版程序文件替换旧文件；**保留原目录的“猫的饭盆”“猫的胃袋”及其中数据**。设置与最高分保存在 `%APPDATA%\Godot\app_userdata\Dolike 桌宠`。

公开 beta 更新接口：[updates/beta.json](updates/beta.json)。客户端手动请求；不含账号凭据、不静默安装。接口结构见 [updates/README.md](updates/README.md)。

第三方许可随包放在 `licenses` 中；本发布仓库不另行授予角色素材或第三方组件的额外授权。
