# ElevenDE Lindows Patch Layer

Lindows **不维护 ElevenDE 的完整 fork**。`packages/sources.lock.tsv` 固定 ElevenDE 上游提交；构建时该提交被放入一次性工作树，然后才应用本目录所定义的 Lindows 集成修改。

当前补丁层由可审计的确定性脚本组成，原因是补丁同时需要检查上游标记并在不同 ElevenDE 源文件中插入受控生成内容。脚本位于仓库根目录 `scripts/`，其输入、目的和边界如下：

| 脚本 | 目标 | 修改边界 |
| --- | --- | --- |
| `patch-elevende-desktop-launcher.py` | `shell/main.c` | 修复桌面 `.desktop` 启动语义。 |
| `patch-elevende-shell-display.py` | `shell/main.c` | 在分辨率变化时重新布局 Shell。 |
| `patch-elevende-settings-display.py` | `apps/settings/main.cpp` | 同步设置应用的显示设置体验。 |
| `patch-elevende-lindows-component-icons.py` | `shell/main.c` | 为 Lindows 集成组件的窗口类、启动命令建立 Windows 11 图标解析别名。 |

`../icon-map.tsv` 与 `../icons/` 是独立的视觉资产覆盖层。它们只在构建副本中覆盖对应图标别名，不修改上游源码仓库，不影响 ElevenDE 上游的其它图标和许可证说明。
