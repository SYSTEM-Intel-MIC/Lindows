# Lindows 2.0 第三方组件与许可证声明

Copyright © 2026 **SYSTEM-Intel-MIC**。除文件另有说明外，Lindows 自有的构建脚本、配置、打包元数据、品牌资源、文档和集成代码均按 **GNU GPL-3.0-or-later** 发布，完整文本见 [`LICENSE`](LICENSE)。Lindows 是聚合发行项目；根目录 GPL **不会**改变第三方组件的原始许可证、版权或分发条件。

> 对于上游明确提供许可证文件的每个本地 DEB，构建会安装许可证副本至 `/usr/share/doc/<package>/copyright`。仓库同时在 [`LICENSES/`](LICENSES/) 保留审计时取得的许可证原文；LinuxPCManager 与 linux-regedit 的上游快照未提供许可证文件，Lindows 仅记录其状态而不伪造授权。

## 固定组件与分发边界

| 组件 | 固定来源 | 许可证 | Lindows 2.0 分发与启用边界 |
|---|---|---|---|
| ElevenDE 3.5.1 | `b4b97ca4fa0ac46235dd8a20b508ff5c9bdf1026` [1] | GPL-3.0-or-later（ElevenDE 自有部分） | 从公开固定提交构建。SAS、Explorer 与 runbox 的原始上游部分保留独立许可证；ElevenDE 对 Explorer 的重大修改和集成按其 GPL 声明处理。 |
| LinuxPCManager、linux-regedit | 见 [`packages/sources.lock.tsv`](packages/sources.lock.tsv) | 上游当前未提供可执行的明确许可证 | 不重新标注为 GPL；保留来源和固定提交。单独再分发前应取得明确授权。 |
| bsod、Device Manager | 固定上游提交 | MIT | 蓝屏仅以 `--restore` 演示模式按需启动；不注册守护进程或自动触发。 |
| Lindows Store | `264b3821b1f180201226e02003fa48d81ffee214` [15] | GPL-3.0-only | 独立 `lindows-store` DEB；仅使用系统 APT/polkit 路径，未内置第三方源或凭据。 |
| Copilot for Linux、PeaZip | 固定 Release DEB | GPL-3.0；LGPL-3.0 | 二进制 URL 和 SHA-256 位于 `packages/binaries.lock.tsv`。Copilot 不预置 API 密钥。 |
| activate-linux | `203ee66e8e2a614266d59921d5493ea681b11a74` [2] | GPL-3.0 | 仅作为“Activate Lindows”视觉水印工具，不规避或声明第三方软件许可。 |
| Lindows-Troubleshooting | 固定提交 [3] | MIT | 以独立 DEB 提供疑难解答入口。 |
| Linux_uac | `288ac83acfe5a2cc0f2a3ac02cfd5d03dc92e62e` [4] | MIT | 仅打包**非授权预览界面**；不安装上游 PAM 模块，不编辑 PAM 配置，并移除独立模式的超时自动接受。 |
| LinuxDefender、Linux-Sticky-keys | 固定提交 [5] [6] | MIT | 用户显式启动的桌面工具；不在安装时写入 root、PAM 或自动启动配置。 |
| WindowsWidget-for-Linux | `5b92311174dfe3236b995ced6aeae73487ef313c` [7] | MIT | 用户会话组件，不在 Live 会话默认自动启动。 |
| windowshit | `5eac6c1d8e3d126bbbc03c76d11edd9e2badc718` [8] | MIT | 命令以 `lindows-` 前缀安装，避免覆盖 Debian 原生命令；涉及电源的命令仍受系统权限与确认限制。 |
| WinSAT | `dc292e6c34d089f9b5718d44744d54a40dbb818e` [9] | WTFPL | 按需运行的基准测试，不自动启动。 |
| windows_update_in_linux | `c82ad6005f0756ec1013f1e1acd798711db03291` [10] | MIT | 仅提供无破坏性预览入口，固定 `--no-reboot`；系统实际更新仍由 Debian apt 和显式用户授权处理。 |
| linux-winver、FeedbackHub | 固定提交 [11] [12] | GPL-3.0 | 作为“About Lindows”和反馈中心独立 DEB 构建，并保留 GPL 源码与许可证。 |
| windowsuninstaller/mmclinux | 用户指定地址在审查时不可获取 | 未知 | GitHub API 返回 404，且未找到可验证替代公开来源，因此**未被集成**。提供可审计 URL 与许可证后才可加入。 |

## ElevenDE 上游边界

ElevenDE 自有代码的 GPL-3.0-or-later 文本保存在 [`LICENSES/GPL-3.0-ElevenDE.txt`](LICENSES/GPL-3.0-ElevenDE.txt)。其内嵌 Explorer-for-Linux 并非未修改镜像：上游原始代码继续受 MIT 条款约束，而 ElevenDE 对其重构、构建整合与增量实现遵循 ElevenDE 的 GPL 声明。Lindows 不声称能够以根目录 GPL 重新授权任何独立上游项目。[1]

## Debian 与运行时依赖

Firefox ESR、VLC、Calamares、Fcitx5、Xorg、Openbox、NetworkManager、GTK、Qt、Python、Rust、Go 及其他依赖均由 Debian Bookworm 或固定构建容器提供，且各自保留其版权与许可证。已安装系统以 `/usr/share/doc/<package>/copyright` 为准。Lindows 不为 Debian 软件包重新授权。

## 对应源码与构建可追溯性

Lindows 自有源码、配置和构建脚本在本仓库公开。`packages/sources.lock.tsv`、`packages/binaries.lock.tsv`、构建期 Git 缓存和 package recipe 共同定义可复现输入；构建时使用的提交、DEB SHA-256、来源锁、二进制锁、ElevenDE 图标映射与图标覆盖层哈希会写入 `LINDOWS-2.0-BUILD-MANIFEST.json`，并随 GitHub Actions 工件上传。上游许可证文本位于 [`LICENSES/`](LICENSES/)，构建逻辑位于 [`scripts/build-lindows-components.sh`](scripts/build-lindows-components.sh) 与 [`scripts/build-lindows2-extra-components.sh`](scripts/build-lindows2-extra-components.sh)。

## 商标

“Windows”、“Windows 11”、“Microsoft”、“Copilot”和 WindowsIcons 等名称、标志及相关品牌可能属于各自权利人。Lindows 对 `packages/elevende/icons/` 中由 [WindowsIcons][16] 转换的精选 PNG 不主张所有权；图标转换不会改变上游资产的权利状态。Lindows 是独立 Linux 发行版项目，不代表也未获 Microsoft 授权。

## 参考

[1]: https://github.com/SYSTEM-Intel-MIC/ElevenDE/tree/b4b97ca4fa0ac46235dd8a20b508ff5c9bdf1026 "ElevenDE 3.5.1 fixed source"
[2]: https://github.com/MrGlockenspiel/activate-linux "activate-linux"
[3]: https://github.com/BobbyChengCN0518/Lindows-Troubleshooting "Lindows Troubleshooting"
[4]: https://github.com/WenAnrong/Linux_uac "Linux UAC"
[5]: https://github.com/xusk1234/LinuxDefender "LinuxDefender"
[6]: https://github.com/xusk1234/Linux-Sticky-keys "Linux Sticky Keys"
[7]: https://github.com/phillin-liu/WindowsWidget-for-Linux "WindowsWidget for Linux"
[8]: https://github.com/HelloAIXIAOJI/windowshit "windowshit"
[9]: https://github.com/WhatDamon/WinSAT "WinSAT"
[10]: https://github.com/WenAnrong/windows_update_in_linux "windows update in linux"
[11]: https://github.com/DeepslateQAQ/linux-winver "linux-winver"
[12]: https://github.com/com-in/FeedbackHub-For-Linux "FeedbackHub for Linux"
[15]: https://github.com/SYSTEM-Intel-MIC/linux-store "linux-store"
[16]: https://github.com/HaydenReeve/WindowsIcons "WindowsIcons"
