# Godot 开发工程

项目采用 Cubism 基础网格与 Godot 叠加素材、变形的组合。当前正式动画中的整臂、坐姿、咀嚼、星星眼和举锅口型均在 Godot 中完成；Cubism 编辑器只展示基础模型，不能用编辑器静态图替代正式动作验收。

`scripts/live2d_pet.gd` 是模型装配与动作合成入口；`arm_rig.gd` 统一处理正常和进食双臂；`desktop_pet.gd` 连接桌面窗口、设置、行为状态；`project_paths.gd` 统一解析开发和发布目录。各动作公式保持已确认版本。

`assets` 和 `model/runtime` 是清单生成副本，使用 `../tools/manage.py sync` 更新。通过 `../tools/build-release.ps1` 构建到暂存区，审核后再发布到 `../Runtime`。开发工具、历史预览和缓存不放在发布目录。

通过 `tools/launch.ps1` 启动带 `--dev` 的开发版。正式版隐藏演示入口，设置中仍可打开饭盆与胃袋。

`tests` 保留有效的动作、遮挡、屏幕边缘和文件安全回归。所有文件夹测试使用上级 `_work/tests`，不操作实际用户食物。统一入口是 `../tools/test-release.py`。

`tools/review_effects.gd` 固定时间、窗口、进食随机数和尾巴随机数，输出 720 帧。用相同脚本分别渲染基线与候选 PCK，再通过 `../tools/review-release.py` 生成对照视频及差异清单。详细维护约定见 `../docs/PROJECT_STANDARD.md`。
