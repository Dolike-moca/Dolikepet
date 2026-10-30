# 方案 C：今后的开发与发布标准

用户于 2026-10-24 确认采用方案 C，整理后的视觉效果必须与已经验收的正式版保持一致。

## 目录职责

| 目录 | 用途 |
| --- | --- |
| `assets/library` | 唯一正式 PNG/SVG 素材库，包含普通/进食等有效变体 |
| `assets/manifest.json` | 最新素材 SHA-256、运行副本、PSD 图层位置和变体清单 |
| `assets/imports.json` | 已确认的 Godot 贴图导入选项与资源 ID；保持缩小采样和透明边缘效果 |
| `assets/licenses.json` | 素材逐文件署名、许可与第三方例外 |
| `DesktopPet.Psd` | 从正式清单生成的 2048×2048 分层总素材；隐藏组保存动作变体 |
| `model/source` | 可编辑 Cubism 工程及由清单生成的基础 PSD |
| `model/runtime` | Cubism 正式导出，保持 ArtMesh ID、网格顶点、参数接口 |
| `Godot` | Godot 开发工程、动作代码、原生文件辅助器、必要回归 |
| `Runtime` | 可发布 EXE、PCK、原生插件；由发布脚本生成 |
| `../_tools` | Godot、导出模板、SDK 构建依赖、PSD 和视频工具 |
| `../_work` | 临时帧、日志、测试文件、发布暂存；不属于发布内容 |
| `../_archive` | 整理前可恢复基线与历史方案；当前构建不可引用 |

`猫的饭盆` 和 `猫的胃袋` 是用户数据，任何清理、打包或回归脚本都不得处理这两个目录。

## 修改顺序

1. 在素材库编辑最新已确认素材。正常远手与进食反手是两种有效变体，不能合并。
2. 对应更新清单中的图层位置和变体；运行 `tools/manage.py register` 登记经审核的源文件哈希。
   Godot 导入选项有意调整时同时更新 `assets/imports.json`；新增素材补全 `assets/licenses.json`。公开仓库须保留素材原始字节，避免 Git 换行转换导致清单哈希失效。
3. 运行 `tools/manage.py sync` 与 `tools/manage.py psd`。不要手改 Godot 的生成副本。
4. 基础模型改动需要在 Cubism 更新 `model/source/DesktopPet.cmo3`，重新导出到 `model/runtime`，再登记和同步。保留已有 ArtMesh、顶点顺序及参数绑定；Godot 的全臂覆盖图、坐姿和表情层是正式混合模型的一部分。
5. 执行相关回归以及 `tools/build-release.ps1`，候选版只输出到 `../_work/release`。用相同脚本渲染基线与候选；`tools/review-release.py` 传入 `--pack` 绑定候选哈希。全部通过后才用 `tools/build-release.ps1 -Publish` 发布已核验的同一份文件，发布步骤不再次编译。

## 不改变已有效果

固定随机种子、时间点、窗口大小和渲染器，以 `Godot/tools/review_effects.gd` 对基线与候选 PCK 输出 720 帧；站立、行走/镜像、坐姿、拖拽、下落/落地、连续进食、举锅大喊、吃饱睁眼都必须核对。若需要改变视觉表现，必须是用户的新要求，不能夹带在整理和优化中。

动画模块保持当前职责分工，不为重构而改写运动公式。开发演示菜单通过 `--dev` 开启；发布菜单保留实际使用功能。

清理先查引用、登记清单，再将不可再生成的旧源文件归档一次。可重新生成的缓存、过期发布暂存和重复预览帧可清理；用户文件、许可和必要安全回归必须保留。
