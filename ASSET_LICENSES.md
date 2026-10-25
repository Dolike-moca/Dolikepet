# 素材许可与来源

**程序代码采用 MIT；项目美术素材采用 CC BY 4.0，保留署名与版权。** 第三方素材按下方例外清单保留原作者及原许可，不重新授权为 CC BY 或 MIT。

## 项目美术素材：CC BY 4.0

版权与署名：**© 2026 Dolike-moca，Dolikepet 项目美术素材及制作贡献。**

除下文第三方例外外，`Game/assets/library` 中的图片、图标，以及 `Game/model/runtime` 的模型导出与纹理，作者有权授权的部分采用 **Creative Commons Attribution 4.0 International（CC BY 4.0，署名 4.0 国际版）**。

你可以复制、分享、修改和用于商业用途；请保留版权与署名，提供项目来源和许可证链接，并说明做过的修改，不得暗示作者为你的作品背书。这是摘要，完整条款以 [CC BY 4.0 正文](LICENSES/CC-BY-4.0.txt) 和 [官方许可页面](https://creativecommons.org/licenses/by/4.0/deed.zh-hans) 为准。

可直接使用的署名示例：

> 本作品使用 Dolikepet 美术素材，© 2026 Dolike-moca，按 CC BY 4.0 使用。来源：https://github.com/Dolike-moca/Dolikepet 。许可：https://creativecommons.org/licenses/by/4.0/ 。修改：描述你的修改；未修改则注明未修改。

若同时使用下列第三方表情，还必须保留第三方作者、来源及原许可；上面的项目署名不能替代第三方署名。

## 第三方表情素材

项目导入过 [Coopanion 0.2.3](https://github.com/Pal-AI-Lab/Coopanion) 的 `packages/cortico-world-desktop-pet/web/whale/feat` 表情素材。保留 [AGPL-3.0-or-later 完整许可及附加许可](Game/Godot/licenses/Coopanion-assets.txt)，不改为 MIT。

- `Game/assets/library/runtime/chewing/swallow_mouth.png` 是 `sleep_mouth.png` 的原字节副本，来源 SHA-256 与运行翻转方式记录在同目录 `swallow-reference.json`。
- `Game/assets/library/runtime/drag/drag_eye_near_psd.png`、`drag_eye_far_psd.png`、`drag_mouth_psd.png` 来自项目拖拽 PSD 的表情导出；导入的拖拽表情来源与上述 Coopanion 素材关联。保留其原许可，当前栅格变换和位置见 `psd-reference.json`。这些处理不改变原素材的权利归属。

素材的可编辑像素文件就是这里列出的 PNG；Godot 中的位置、缩放、镜像和遮挡由运行代码处理。不要将这些素材标为项目原创或仅有 MIT 授权。

## 项目美术及模型

项目素材来自角色素材整理、制作与模型处理过程。这里的版权声明针对 Dolike-moca 有权授权的项目美术及制作贡献，不把第三方原作归为项目原创，也不扩大第三方授权范围。Live2D SDK 本体和运行库是软件依赖，不属于这里开放的美术素材。

当前素材的完整文件清单、哈希和运行副本关系在 [manifest.json](Game/assets/manifest.json)，逐文件许可与署名见 [licenses.json](Game/assets/licenses.json)。PSD、Cubism `.cmo3` 编辑工程和历史素材未包含在本仓库。生成的 `Game/Godot/assets` 与 `Game/Godot/model` 副本继承对应源素材的许可范围。

