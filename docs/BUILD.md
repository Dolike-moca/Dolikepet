# 从源码构建 Dolikepet 0.2.1

源码对应 **0.2.1「纳垢的赐福」**。这是可开发的 Godot 工程；只想游玩，请直接下载 [Windows 游玩包](https://github.com/Dolike-moca/Dolikepet/releases/tag/0.2.1)。

## 准备环境

目前支持 Windows 10 / 11 x64。需要：

- Git、Python **3.11 或更新版本**（可运行 `python` 与 `pip`）。
- PowerShell **7**（`pwsh`），用于现有回归脚本；构建入口也可使用 Windows PowerShell。
- Visual Studio Build Tools **2022**，安装「使用 C++ 的桌面开发」、MSVC v143 和 Windows SDK。
- Windows .NET Framework 4.x 的 `csc.exe`，用于文件处理与托盘辅助程序。
- 从 [Live2D 官方网站](https://www.live2d.com/zh-CHS/sdk/download/native/) 自行取得 **Cubism SDK for Native 5-r.5**，阅读并遵守其许可。SDK 不随源码分发，准备脚本不会代替你同意许可。

版本与提交固定在 [dependency-lock.json](../Game/Godot/dependency-lock.json)。不要直接换成其他 Cubism Core / Framework 组合；本项目的兼容补丁针对指定版本。

## 准备依赖并构建

在 PowerShell 中执行：

```powershell
git clone https://github.com/Dolike-moca/Dolikepet.git
cd Dolikepet
python tools/setup.py --sdk-zip "D:\Downloads\CubismSdkForNative-5-r.5.zip"
powershell -NoProfile -ExecutionPolicy Bypass -File tools/build.ps1
```

`setup.py` 获取固定提交的 gd_cubism / godot-cpp、SCons 4.7.0，以及 Godot 4.7.2 和导出模板；引擎下载通过官方 SHA-512 清单验证。首次准备需要下载较大的导出模板包。依赖只放在 `_tools` 中，不进入 Git。

已有解压的 SDK、匹配版本的 Godot 与 Windows 导出模板时，可以复用：

```powershell
python tools/setup.py `
  --sdk-dir "D:\SDK\CubismSdkForNative-5-r.5" `
  --engine-dir "D:\Godot\4.7.2" `
  --templates-dir "D:\Godot\templates\4.7.2.stable"
```

复用目录需要同时包含普通 / console 引擎，以及 `windows_debug_x86_64.exe` / `windows_release_x86_64.exe`。这些本地文件由开发者自行核对来源和版本。

构建会同步素材、编译两个 C# 辅助程序和 debug / release 原生插件、导入 Godot 资源并导出。成功后，程序与许可文件位于 **`_work/release/`**。保留 EXE、PCK、DLL 和许可文件的完整组合再运行。

如果使用非默认 Python，可给 `tools/build.ps1` 传入 `-Python "完整路径\python.exe"`。构建不会替换现有游玩包，不会启动桌宠或读取玩家的饭盆、胃袋。

## 编辑与测试

完成依赖准备和首次构建后，用 `_tools/runtime/godot-build/godot/` 下的 Godot 打开 `Game/Godot/project.godot`。也可使用：

```powershell
powershell -File Game/Godot/tools/launch.ps1 -Editor
python Game/tools/manage.py check
python Game/tools/test-release.py --group logic
python Game/tools/test-release.py --group native
python Game/tools/test-release.py --group render
python Game/tools/test-auto-update.py
```

自动更新测试使用本机 HTTP 服务和独立缓存，覆盖离线重试、完整性校验、缓存修复和取消下载，不请求 GitHub 或访问玩家文件。

渲染测试需要可用的桌面与 OpenGL 图形环境，可能短暂创建窗口。测试数据与日志位于 `_work/tests`，不应使用真实待消化文件。开发运行与游玩版使用相同的 Godot 用户设置名称；如需完全隔离人工测试，请使用独立的 Windows 测试账号。

`Game/Godot/tools/review_effects.gd` 可按固定随机种子和时间点导出 720 帧，用于比较修改前后的视觉效果。执行时传入绝对输出路径：

```powershell
& ./_tools/runtime/godot-build/godot/Godot_v4.7.2-stable_win64_console.exe `
  --path Game/Godot --script res://tools/review_effects.gd -- --out=D:/reviews/dolike
```

## 目录与素材规则

| 目录 | 用途 |
| --- | --- |
| `Game/Godot/scripts` | 桌面交互、动作、饭盆、消化、小游戏、计分板与更新逻辑 |
| `Game/Godot/native` | Windows 文件处理、托盘与鼠标捕获的源码 |
| `Game/Godot/tests` | 行为、图形和文件安全回归 |
| `Game/assets/library` | 唯一正式素材来源 |
| `Game/assets/manifest.json` | 素材哈希、运行副本位置、图层和动作变体清单 |
| `Game/model/runtime` | 当前运行模型导出，包含 moc3 与纹理 |
| `tools` | 公开源码的依赖准备与构建入口 |
| `_tools` / `_work` | 本地依赖、测试与构建输出；不提交 |

`Game/Godot/assets` 和 `Game/Godot/model` 由 `manage.py sync` 生成，不提交重复副本。素材修改经核对后先 `register`，再 `sync` / `check`；不要仅按修改日期替换已确认的素材。普通远手与进食远手是两个有效变体。

`Game/assets/imports.json` 保存已确认的 Godot 贴图导入选项及资源 ID，同步时恢复对应 `.import` 文件。缩小采样、透明边缘等选项也会影响画面，不能在整理素材时丢弃；有意调整导入设置时需同步更新此清单并重新做画面对照。

公开仓库不包含 PSD、Cubism `.cmo3` 编辑工程、私有开发历史或玩家数据。`manage.py psd` 是可选的图层重组工具，需要 Pillow / psd-tools，不参与默认构建，也不能重建 Cubism 的编辑网格与变形器。

`Game/tools/build-release.ps1 -Publish` 是维护者的发布门禁，需要另行准备完整测试与 720 帧视觉审核记录；普通开发使用 `tools/build.ps1` 即可。

## 许可范围

自有程序代码采用 [MIT](../LICENSE)。角色素材、模型和第三方组件分别见 [素材许可说明](../ASSET_LICENSES.md) 与 [第三方声明](../THIRD_PARTY_NOTICES.md)。尤其是 Live2D Core，不因本项目源码公开而变为 MIT 软件。

