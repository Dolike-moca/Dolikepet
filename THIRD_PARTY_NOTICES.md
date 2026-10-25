# 许可范围与第三方声明

根目录 `LICENSE` 的 MIT 授权适用于 Dolikepet 自有程序代码、工具、测试及文档。项目有权授权的美术素材采用 CC BY 4.0，署名 © 2026 Dolike-moca，详见 [素材声明](ASSET_LICENSES.md)。这两种授权均不替换以下第三方原许可。

| 内容 | 来源与许可 |
| --- | --- |
| Godot 引擎 | [Godot](https://github.com/godotengine/godot)，MIT；[许可](Game/Godot/licenses/Godot.txt)、[依赖声明](Game/Godot/licenses/Godot-third-party.txt) |
| godot-cpp | [godot-cpp](https://github.com/godotengine/godot-cpp)，MIT；[许可](Game/Godot/licenses/godot-cpp.md) |
| gd_cubism 与 `Game/Godot/addons/gd_cubism/res` 内的上游 shader | [MizunagiKB/gd_cubism](https://github.com/MizunagiKB/gd_cubism)，MIT，Copyright 2023 MizunagiKB；[许可](Game/Godot/licenses/GDCubism.adoc) |
| Live2D Cubism Core | Live2D 专有许可；[原许可入口](Game/Godot/licenses/CubismCore.md)，构建者从官方取得 SDK |
| Live2D Cubism Framework | Live2D Open Software License；[原许可入口](Game/Godot/licenses/CubismFramework.md)，与 Core 使用相同 Native 5-r.5 SDK |
| 来自 Coopanion 的表情素材 | [Pal-AI-Lab/Coopanion](https://github.com/Pal-AI-Lab/Coopanion)，AGPL-3.0-or-later 及原附加许可；[完整许可](Game/Godot/licenses/Coopanion-assets.txt)、[素材范围](ASSET_LICENSES.md) |

依赖源码和 SDK 在本地 `_tools` 准备，未作为本仓库自有源码重新发布。`patch-gdcubism.py` 保留上游文件头，在构建时应用与固定版本匹配的适配；不要剥离上游版权与许可说明。

程序编译后的整体分发还需要遵守其中实际包含的各组件许可。MIT 声明只表示作者对自有代码的授权，不扩大第三方组件或素材的授权范围。

