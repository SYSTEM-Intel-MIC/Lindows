# ElevenDE Lindows Windows 11 Icon Overlay

`icon-map.tsv` 是 Lindows 对 ElevenDE 所集成组件的**专属图标映射**。大多数映射条目指向用户指定的 [HaydenReeve/WindowsIcons](https://github.com/HaydenReeve/WindowsIcons) `Icons/` 目录；`scripts/import-lindows-win11-icons.py` 将这些 ICO，以及明确以 `@local/` 标记的仓库内审计资源，确定性转换为本目录 `icons/` 覆盖层中的 16–128px PNG。该目录仅保存 Lindows 实际使用的转换输出，而不镜像完整第三方图标库。

这些 PNG 用于 Linux PC Manager、Registry Editor、Lindows Store、Copilot、PeaZip、Defender、Widgets 及其他 Lindows 集成组件。`patch-elevende-lindows-component-icons.py` 将窗口类和启动命令映射到相同别名，因此桌面、开始菜单、任务栏和 ElevenDE 绘制的窗口标题栏解析同一图标。

## 注册表编辑器资源

原先的 `objects/keys.ico` 是钥匙图标，不能代表 Windows 11 Registry Editor，现已移除。`linux-regedit` 改为引用 `@local/registry-editor-windows-11.png`。此文件来自 [Wikimedia Commons 的 Windows 11 registry editor icon](https://commons.wikimedia.org/wiki/File:Windows_11_registry_editor_icon.svg) 的 960px PNG 派生文件；该页面说明该 SVG 是从 `regedit.exe` 的 `regedit_100.ico` 重绘，并在页面上以公有领域资源发布。保存的 PNG SHA-256 为：

```text
a86e856acbd107224b9117b1dc9b99d038289b933e0b45bd8f747d466cb539ac
```

该图标不来自用户上传的低分辨率参考图。Windows、Windows 11 和相关商标归其各自权利人所有；Lindows 不主张这些商标或源资源的所有权。若来源页面、权利状态或再分发条件变更，应在发布前重新审计此单一资源。

## 重新生成

在已有 WindowsIcons `Icons/` 目录的工作站运行：

```sh
python3 scripts/import-lindows-win11-icons.py \
  --map packages/elevende/icon-map.tsv \
  --icons-root /path/to/WindowsIcons/Icons \
  --local-icons-root packages/elevende/local-icon-sources \
  --destination packages/elevende/icons
```

上游 WindowsIcons 仓库未在本次审计的顶层树中提供许可证文件。Lindows 不因 ICO/PNG 的确定性转换改变任何原始权利状态；如上游补充、变更或撤回再分发条款，应优先按上游条款处理并更新此覆盖层。
