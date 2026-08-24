# Lindows 2.0

**Lindows 2.0** 是由 **SYSTEM-Intel-MIC** 维护的 Debian Bookworm AMD64 Live 发行版集成层。它以 **ElevenDE 3.5.1** 为核心 X11 桌面，提供 Windows 风格的开始菜单、任务栏、统一标题栏、资源管理器、设置、任务管理器、运行对话框、中文输入、Calamares 安装器和一组受控集成的 Windows 风格工具。

> `main` 始终保持正式发布基线。所有 Lindows 2.0 工作均位于隔离的 `lindows-2.0-integration` 分支；该分支可以运行持续集成并上传构建工件，但**不会创建 GitHub Release**，也不会改动 `main`。

## 发行版集成架构

Lindows 不把所有上游项目做成长期完整 fork，也不让 `live-build` 直接面对 GitHub。仓库只维护“如何把固定上游软件变成 Lindows 一部分”的 package layer、patch layer 与 desktop integration layer；每个正式构建先产出可验证 DEB，再由 `live-build` 只消费已验证包集。

| 层 | 仓库位置 | 职责 | 不做什么 |
| --- | --- | --- | --- |
| **来源锁** | `packages/sources.lock.tsv`、`packages/binaries.lock.tsv` | 固定每个 Git 项目的 URL/提交，或固定预构建 DEB 的 URL/SHA-256。 | 不记录浮动分支或“最新版”标签。 |
| **源码缓存** | `artifacts/source-cache/` 与 CI 缓存 | 将锁定提交缓存到一次性构建工作树，允许同一来源在核心/附加 recipe 间复用。 | 不提交完整第三方 Git 历史或工作副本。 |
| **包 recipe** | `scripts/build-lindows-components.sh`、`scripts/build-lindows2-extra-components.sh` | 在独立 Bookworm 容器中获取锁定来源、应用受控适配、构建 DEB 并写入哈希。 | 不执行上游 `install.sh`，不让 Live ISO 直接拉取源码。 |
| **补丁层** | `packages/elevende/patches/` 与受审计补丁脚本 | 对构建副本应用显示重排、桌面入口、会话策略和图标解析改造。 | 不修改或推送 ElevenDE 上游仓库。 |
| **桌面集成层** | `config/includes.chroot/`、`config/hooks/normal/` | 统一 ElevenDE 会话变量、标题栏、启动入口、Windows 11 图标和 GTK 控件主题。 | 不替代第三方工具的业务逻辑。 |
| **Live 输入层** | `scripts/stage-lindows-live-inputs.sh` | 只向 Live chroot 放入已校验 DEB、SHA256、清单和执行钩子。 | 不重新下载组件。 |

这种结构将上游更新、Lindows 适配、包构建和 ISO 组装明确分离。`LINDOWS-2.0-BUILD-MANIFEST.json` 同时记录 Lindows 提交、包哈希、来源锁、二进制锁、ElevenDE 图标映射及每个覆盖图标的 SHA-256，便于复核最终 ISO 的输入。

## 桌面、会话与安装体验

| 范围 | Lindows 2.0 实现 |
| --- | --- |
| **核心桌面** | ElevenDE 3.5.1、Openbox、picom、Xorg、NetworkManager 与 Fcitx5 中文输入。ElevenDE 负责开始菜单、任务栏、窗口标题栏、窗口操作和其自身的 Win11 风格登录/锁屏界面。 |
| **LiveCD** | `lindows-elevende-display.service` 使用 Xorg/xinit 直接启动一次性的 `user` 桌面会话。Live 用户不需要、也不公开密码；该临时用户只由系统服务通过 `runuser` 启动。 |
| **已安装系统** | Calamares 后安装步骤写入实际创建的用户至 `/etc/lindows/session-user`。同一个 ElevenDE 原生显示服务以该用户启动会话，ElevenDE 自己的 `elevende-lock --login` 显示并验证密码。**不使用 LightDM 或其 Greeter。** |
| **安全边界** | Live 初始化不会设置 `user:live`、不会创建 `nopasswdlogin` 组，也不会更改安装时设置的密码。已安装系统保留用户密码并仅将用户加入 Debian `sudo` 组。 |
| **安装器** | Calamares 使用 Lindows 标识、中文欢迎页和专属幻灯片；Live 桌面与开始菜单提供“安装 Lindows”。目标系统清理 Live 安装器入口、Live 初始化服务和临时用户策略。 |
| **启动链路** | ISO 使用统一的 `boot=live config components splash` BIOS/UEFI 参数。ISOLINUX 运行模块来自同一 syslinux 包；EFI System Partition 由双启动重打包脚本注入。安装后 GRUB 主题仅在主题和壁纸均存在时启用，避免悬空主题路径报错。 |

## ElevenDE Windows 11 图标与 UI 适配

Lindows 对每个集成组件提供明确的 ElevenDE 图标别名，而不是依赖 Linux 主题的随机回退。`packages/elevende/icon-map.tsv` 将组件入口映射到用户指定的 [WindowsIcons](https://github.com/HaydenReeve/WindowsIcons) ICO 路径；`scripts/import-lindows-win11-icons.py` 将**实际使用的 20 组**资产转换为 16–128px PNG 覆盖层。仓库保存被使用的确定性输出和来源说明，不镜像整个第三方图标库。完整资产边界见 [`packages/elevende/ASSET-SOURCES.md`](packages/elevende/ASSET-SOURCES.md)。

构建时，`patch-elevende-lindows-component-icons.py` 向 ElevenDE 的窗口/应用解析表注入命令与窗口类别名，`patch-elevende-icon-overlay-staging.py` 确保上游图标生成步骤后重新放入覆盖资源。因此桌面、开始菜单、任务栏和 ElevenDE 绘制的窗口标题栏都解析同一 Windows 11 图标。最终 ISO 验证会检查全部 20 个 64px 图标存在，不允许构建时丢失。

第三方入口统一经由 `/usr/local/libexec/lindows-component-launch` 运行。该适配器设置 ElevenDE/X11 会话变量、关闭 GTK 客户端标题栏并使用统一图标搜索路径；`/usr/share/themes/ElevenDE/gtk-3.0/gtk.css` 为 GTK 的按钮、输入框、列表、进度条和焦点状态提供浅色、圆角和蓝色强调。Qt/GTK/Tk 应用仍保留各自上游业务界面，但窗口外框、标题栏、启动入口、图标和基本控件行为遵循 ElevenDE 环境。

## 集成组件、上游与 Lindows 修改

下表是 Lindows 2.0 的完整第三方组件声明。实际 URL 与不可变提交位于 `packages/sources.lock.tsv`；Copilot 和 PeaZip 的发布 DEB 与 SHA-256 位于 `packages/binaries.lock.tsv`。其中“入口/图标”均表示经过 ElevenDE 启动适配与 Windows 11 图标映射。

| 组件 | 上游 | Lindows 包与技术实现 | 入口/图标与安全边界 |
| --- | --- | --- | --- |
| **ElevenDE 3.5.1** | [SYSTEM-Intel-MIC/ElevenDE](https://github.com/SYSTEM-Intel-MIC/ElevenDE) | 固定 `b4b97ca`；构建副本应用桌面启动、显示重排、图标解析、图标覆盖和会话策略补丁。 | 核心 Shell；Live 绕过登录，安装系统使用其原生登录界面。 |
| Linux PC Manager | [SYSTEM-Intel-MIC/LinuxPCManager](https://github.com/SYSTEM-Intel-MIC/LinuxPCManager) | Python 源码打包为 `linux-pcmanager`。 | `linux-pcmanager` / 控制面板图标。 |
| Registry Editor | [heyManNice/regedit](https://github.com/heyManNice/regedit) | Meson/C 构建为 `linux-regedit`，并提供 `regedit` 命令别名。 | `linux-regedit` / Windows 键图标。 |
| Blue Screen Demo | [heyManNice/bsod](https://github.com/heyManNice/bsod) | Meson/C 构建为 `lindows-bsod`。 | 经 `--restore` 包装器启动，演示结束恢复桌面，**不重启**。 |
| Device Manager | [daimile2/Device-Manager-But-Linux](https://github.com/daimile2/Device-Manager-But-Linux) | Go 构建；上游缺少 `go.sum`，Lindows 使用 `vendor/lindows-device-manager.go.sum` 并强制 `-mod=readonly`。 | `devmgr` / 设备图标。 |
| **Lindows Store** | [SYSTEM-Intel-MIC/linux-store](https://github.com/SYSTEM-Intel-MIC/linux-store) | 锁定源码打包为 `lindows-store`；沿用 APT 与 polkit 的软件安装模型。 | `lindows-store` / Microsoft Store 风格图标。 |
| Copilot for Linux | [com-in/Copilot-For-Linux](https://github.com/com-in/Copilot-For-Linux) | 仅获取 SHA-256 校验的 v1.0.0 AMD64 发布 DEB；Live 环境使用受控 Electron 沙箱兼容包装器。 | `lindows-copilot` / package 图标；不包含 API 密钥。 |
| PeaZip | [PeaZip](https://github.com/peazip/PeaZip) | 仅获取 SHA-256 校验的 11.2.0 Qt6 AMD64 发布 DEB。 | `peazip` / ZIP 文件夹图标。 |
| **Microsoft Edge** | [Microsoft Edge for Linux](https://packages.microsoft.com/repos/edge/) | 使用 `packages/binaries.lock.tsv` 中固定版本、URL 和 SHA-256 的官方 amd64 DEB；不在 Live 构建中查询漂移的 latest。 | `microsoft-edge` 官方包图标；桌面提供 Microsoft Edge 快捷方式。该专有二进制不重新许可为 GPL。 |
| Activate Lindows | [MrGlockenspiel/activate-linux](https://github.com/MrGlockenspiel/activate-linux) | C 源码构建为激活水印视觉组件。 | `lindows-activation-watermark` / package 图标；不改变许可或系统激活状态。 |
| Lindows Control | [BobbyChengCN0518/Lindows_Control](https://github.com/BobbyChengCN0518/Lindows_Control) | Rust 1.95、锁定 Cargo.lock 构建。 | `lindows-control` / 控制面板图标。 |
| Troubleshooting | [BobbyChengCN0518/Lindows-Troubleshooting](https://github.com/BobbyChengCN0518/Lindows-Troubleshooting) | PySide6 导入适配为 Debian 可用的 PyQt5 绑定。 | `lindows-troubleshooting` / 信息图标。 |
| UAC Preview | [WenAnrong/Linux_uac](https://github.com/WenAnrong/Linux_uac) | 仅构建 UI；打包期补丁强制 `--timeout 0`。 | `lindows-uac-preview` / 安全图标；**不安装 PAM 模块、不修改 sudo、不自动批准操作**。 |
| Lindows Defender | [xusk1234/LinuxDefender](https://github.com/xusk1234/LinuxDefender) | Python/Tk 入口打包。 | `lindows-defender` / Defender 图标。 |
| Sticky Keys | [xusk1234/Linux-Sticky-keys](https://github.com/xusk1234/Linux-Sticky-keys) | Python 入口打包，并由 Lindows 覆盖错误的上游桌面 Exec。 | `lindows-sticky-keys` / Sticky Notes 图标。 |
| Task Scheduler | [1ctrl-cv/taskschd4Linux](https://github.com/1ctrl-cv/taskschd4Linux) | 保留上游 Qt6 图形路径，使用 Debian `python3-pyqt6`、`croniter` 和 polkit 依赖。 | `taskschd` / 任务图标。 |
| Windows Widgets | [phillin-liu/WindowsWidget-for-Linux](https://github.com/phillin-liu/WindowsWidget-for-Linux) | Python/PyQt5 包装。 | `lindows-widgets` / Widgets 图标。 |
| Windows Commands | [HelloAIXIAOJI/windowshit](https://github.com/HelloAIXIAOJI/windowshit) | Rust 1.95 构建；所有命令以 `lindows-*` 命名空间暴露，避免覆盖 Linux 命令。 | `lindows-windowshit` / Terminal 图标；电源命令仍受权限控制。 |
| WinSAT | [WhatDamon/WinSAT](https://github.com/WhatDamon/WinSAT) | Python 模块打包。 | `winsat` / 芯片图标。 |
| Windows Update Preview | [WenAnrong/windows_update_in_linux](https://github.com/WenAnrong/windows_update_in_linux) | CMake 构建；Lindows 包装器恢复上游 TTY/DRM 预览并固定 `--no-reboot`。 | `lindows-update-preview` / 刷新图标；不运行 `apt upgrade`、不重启。 |
| About Lindows | [DeepslateQAQ/linux-winver](https://github.com/DeepslateQAQ/linux-winver) | GTK4/C 构建。 | `winver` / 系统版本图标。 |
| Feedback Hub | [com-in/FeedbackHub-For-Linux](https://github.com/com-in/FeedbackHub-For-Linux) | Python/GTK 包装。 | `feedbackhub` / Feedback 图标。 |
| mmclinux | `windowsuninstaller/mmclinux` | 用户提供的公开地址在审计时无法确认，未进入来源锁、构建、ISO 或菜单。 | **未集成。** 提供可审计来源与许可后才可能评估。 |

## 构建、验证与发布

本地完整回归要求 Debian/Ubuntu 主机具备 Docker、`live-build`、`xorriso`、`qemu-system-x86_64`、OVMF 与 `sudo`。核心 recipe 在 `golang:1.24-bookworm` 容器中构建；含 Rust 依赖的附加组件在 `rust:1.95-bookworm` 容器中构建。

```sh
git clone https://github.com/SYSTEM-Intel-MIC/Lindows.git lindows
cd lindows
git switch lindows-2.0-integration
bash scripts/local-test.sh
```

构建顺序为：来源锁与缓存 → 核心/附加 DEB → SHA-256 与包元数据校验 → 构建清单 → Live staging → Bookworm ISO → BIOS/UEFI 重打包 → squashfs 内容校验 → QEMU BIOS/UEFI 冒烟。`scripts/validate-lindows-live-image.sh` 必须确认 Calamares 后安装模块、最小 Live sudoers、无 LightDM、原生 ElevenDE 服务、20 个图标别名、Lindows Store 和关键组件入口均在最终 squashfs 中。

GitHub Actions 在开发分支上传 ISO、ISO SHA-256、启动报告、构建日志、组件包集和 manifest 作为 Artifacts。工作流仅在 `main` 条件满足时创建 GitHub Release；当前开发分支**绝不发布正式 Release**。

## 许可证与安全边界

Lindows 自有集成代码、构建 recipe、补丁、配置、品牌资源和文档按 **GPL-3.0-or-later** 发布，全文见 [`LICENSE`](LICENSE)。根目录 GPL 不会重新授权 MIT、LGPL、WTFPL、Debian 软件包、二进制发布包或未明确许可的上游代码。逐组件来源、固定提交、许可证文本和分发状态见 [`THIRD-PARTY-NOTICES.md`](THIRD-PARTY-NOTICES.md)。

ElevenDE 自有代码按 GPL-3.0-or-later 发布；其 SAS-for-Linux、Explorer-for-Linux 和 runbox-linux 来源仍保留各自边界。Explorer 在 ElevenDE 内经过大幅修改和重构，因此原始上游部分与 ElevenDE 的 GPL 增量必须被区分。[1]

Lindows 不自动执行系统清理、驱动卸载、驱动下载、系统任务创建、系统升级、UAC/PAM 改写或重启。蓝屏演示固定恢复桌面；UAC 仅为视觉预览；Windows Update 为无破坏预览；Copilot 凭据必须由用户自行配置。

## 维护者

**SYSTEM-Intel-MIC**

项目主页：<https://github.com/SYSTEM-Intel-MIC/Lindows>

问题反馈：<https://github.com/SYSTEM-Intel-MIC/Lindows/issues>

## 参考

[1]: https://github.com/SYSTEM-Intel-MIC/ElevenDE "ElevenDE source and license boundary"

## 第二轮体验修复补充

在 `lindows-2.0-integration` 的后续集成中，Firefox ESR 已替换为固定版本的 Microsoft Edge for Linux amd64 DEB；其官方下载 URL、版本和 SHA-256 位于 `packages/binaries.lock.tsv`。Edge 是 Microsoft 专有二进制，不属于 Lindows GPL 源码。Lindows 还为 Edge、Lindows 终端和注册表编辑器提供桌面快捷方式，并继续使用锁定的 WindowsIcons 资源映射 Lindows 自有工具图标，不使用用户上传的低清截图作为图标。

BlueScreen Demo 恢复调用上游真实 TTY/DRM 渲染器，但 Lindows 包装器固定使用 `--restore`，因此演示完成后回到桌面且不执行默认重启路径。分辨率补丁改为读取 X11 根窗口的实时几何属性，配合 ElevenDE 原生 RandR 事件和轮询，使任务栏、桌面图标和工作区跟随分辨率变化重新布局。
