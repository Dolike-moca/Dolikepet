# Dolike 桌宠工程 · 0.4.0「奸奇的赐福」

这是公开的 Godot 源码工程。项目希望制作一个更有陪伴感的实用小桌宠，结合日常陪伴、文件投喂和互动小游戏。

- 玩家功能与下载见[项目介绍](../README.md)，构建环境和步骤见[构建说明](../docs/BUILD.md)。
- 本版加入 DeepSeek / OpenAI API 与 ChatGPT 登录、气泡聊天、人设和分层记忆、主动问候、语速滑条，以及坐姿睡眠和作息；详见 [AI 陪伴](docs/AI_COMPANION.md)与[版本说明](docs/public/0.4.0.md)。
- `Godot/scripts` 管理桌宠行为与界面，`Godot/native` 提供 Windows 辅助功能，`Godot/tests` 为维护中的回归。
- `assets/library` 是正式素材唯一来源，`assets/manifest.json` 记录哈希；`Godot/assets`、`Godot/model` 是同步工具生成的副本。
- 运行 `python Game/tools/manage.py check` 核对素材；用仓库根目录 `tools/build.ps1` 构建，结果位于 `_work/release`。
- 自有代码采用 MIT，项目美术采用 CC BY 4.0；第三方内容保留原许可。源码不包含 SDK、PSD、Cubism 编辑工程、私有历史或玩家数据。

饭盆与胃袋是玩家数据。文件吃入胃袋后达到消化时间会永久删除，不进入回收站。构建、打包和回归只使用独立临时目录，不复制或处理玩家食物；AI 也不读取这些文件的名称或内容。

工程版与游玩版使用同一套自动更新逻辑；发现新版后后台下载并校验，猫咪提示完成，安装仍由玩家手动进行。验证摘要见[版本验证](../docs/VERIFICATION.md)。
