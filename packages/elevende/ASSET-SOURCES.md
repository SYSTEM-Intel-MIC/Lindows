# ElevenDE Lindows Windows 11 Icon Overlay

`icon-map.tsv` 是 Lindows 对 ElevenDE 所集成组件的**专属图标映射**。构建时，`scripts/import-lindows-win11-icons.py` 从用户指定的 [HaydenReeve/WindowsIcons](https://github.com/HaydenReeve/WindowsIcons) `Icons/` 目录中转换映射表列出的 ICO，并将 16–128px PNG 写入本目录下的 `icons/` 覆盖层。该目录仅保存 Lindows 实际使用的 18 组多尺寸应用图标，而不复制整个上游图标仓库。

这些 PNG 由 Windows 11 风格 ICO 资源转换而来，分别用于 Linux PC Manager、Registry Editor、Lindows Store、Copilot、PeaZip、Defender、Widgets、Feedback Hub 及其他 Lindows 集成组件。`patch-elevende-lindows-component-icons.py` 会把窗口类和启动命令映射到相同别名，因此桌面、开始菜单、任务栏和 ElevenDE 绘制的窗口标题栏使用同一图标。

上游仓库未在本次审计的顶层树中提供许可证文件。Lindows 不主张这些资产或 Windows 相关商标的所有权，也不因 ICO 到 PNG 的确定性转换改变原始权利状态。发行边界与现有 ElevenDE `WINDOWSICONS-NOTICE.md` 一致；如上游补充、变更或撤回再分发条款，应优先按上游条款处理并更新此覆盖层。
