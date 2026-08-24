# Lindows 2.0 发行版架构

## 目标与范围

Lindows 2.0 是面向 AMD64 的 Debian Bookworm 轻量级 X11 Live 发行版。它以 ElevenDE 3.5.1 为默认桌面会话，提供 Windows 风格桌面、系统工具、中文输入和图形化安装入口，同时避免引入 GNOME、KDE 或完整桌面元包。镜像标识、`/etc/os-release`、启动菜单、Calamares 品牌、桌面与已安装系统的 GRUB 主题统一为 **Lindows 2.0**。

> Lindows 使用 **Calamares** 作为唯一图形安装器。仓库和 ISO 不再构建或暴露 Debian Installer Live；桌面与开始菜单的“安装 Lindows”入口均启动 `lindows-installer`。

## 运行时分层

| 层次 | 方案 | 目的 |
|---|---|---|
| 基础 | Debian Bookworm、live-boot、systemd、Xorg 与固件 | 提供可启动的 Live ISO 与硬件兼容性。 |
| 桌面与会话 | ElevenDE 3.5.1、Openbox、picom、Xorg、`lindows-elevende-display.service` | LiveCD 直接启动临时用户的 ElevenDE 桌面；已安装系统由 ElevenDE 原生 Win11 风格登录界面验证 Calamares 创建的用户。系统不安装 LightDM。 |
| 安装器 | Calamares、`lindows-installer` 与 `lindows-target-postinstall` | 以 Lindows 品牌安装系统，并清理目标系统中的 Live 安装器入口。 |
| 输入 | Fcitx5、中文扩展、拼音、Noto CJK | 通过 GTK、Qt 与 XIM 环境变量统一提供中文输入。 |
| 工具 | 固定提交的系统工具和独立 DEB | 组件不在 ISO 构建阶段运行上游安装脚本；每项都有许可证副本与桌面入口。 |

## 组件构建边界

构建流程以 package layer 将运行时软件与发行集成严格分离。`packages/sources.lock.tsv` 固定 Git 来源和提交，`packages/binaries.lock.tsv` 固定预构建 DEB 与 SHA-256，构建缓存仅用于复用锁定来源。核心 ElevenDE、C、Qt 与 Go 组件在 `golang:1.24-bookworm` 中构建；需现代 Cargo.lock 的 Rust 工具在 `rust:1.95-bookworm` 中构建。两阶段产生的 `.deb` 必须通过 SHA-256、包元数据、许可证与桌面入口验证，并写入包含来源锁和图标覆盖哈希的 JSON manifest，之后才会进入 Live chroot。

| 组件类别 | 示例 | 固定与安全边界 |
|---|---|---|
| 桌面核心 | ElevenDE 3.5.1，提交 `b4b97ca4fa0ac46235dd8a20b508ff5c9bdf1026` | 从公开固定提交构建；保持 ElevenDE GPL 与其上游 SAS、Explorer、runbox 的独立许可证边界。[1] |
| 普通桌面工具 | Lindows Store、Troubleshooting、Defender、Sticky Keys、Widgets、Feedback Hub | 独立 DEB、XDG 入口与许可证副本；所有入口经 ElevenDE 会话适配器并映射为精选 Windows 11 图标，不写入用户配置或自动启动项。 |
| 命令兼容工具 | Windows 命令兼容工具 | 所有命令使用 `lindows-*` 前缀，避免覆盖 Linux 命令；系统操作继续通过标准系统授权路径执行。 |
| 安全预览工具 | UAC Preview、Windows Update Preview | 不安装 PAM 模块、不自动接受、不执行自动 apt 升级或重启。 |
| 阻塞项 | `windowsuninstaller/mmclinux` | 请求的公开地址无法取得且许可证未知，不进入 ISO。 |

完整组件锁定、许可证和桌面入口设计见 [`LINDOWS-2.0-COMPONENT-INTEGRATION.md`](LINDOWS-2.0-COMPONENT-INTEGRATION.md)；版权与分发说明见 [`../THIRD-PARTY-NOTICES.md`](../THIRD-PARTY-NOTICES.md)。

## 启动与安装一致性

BIOS 使用 Isolinux 与同一套 `boot=live components` 内核参数，保留内核和 systemd 的可见滚屏，避免图形服务启动前出现无反馈黑屏。UEFI 在 ISO 重打包阶段使用同样的 Live 参数与 GRUB standalone 引导项，安全图形项另加 `nomodeset`。已安装系统仅在主题描述符和壁纸均存在时写入 `GRUB_THEME`；主题资源以相对路径引用，防止目标路径差异或缺失资源造成 GRUB 主题加载警告。

Calamares 后安装脚本会将 Lindows 主题与壁纸复制到目标系统，再写入 `/etc/default/grub.d/00-lindows.cfg`。若资源缺失，脚本移除该主题 drop-in，而非留下悬空的主题引用。

## 可追溯性与 ISO 验收

设备管理器在 Lindows 构建副本中固定使用 Fyne `VariantLight`，不继承暗色系统偏好。交互终端中的 `sudo` 仍指向未修改的系统认证和 PAM；Lindows 仅通过 `lindows-sudo` 先执行原生密码验证、再显示 UAC 确认，取消或 UI 失败时不执行目标命令。

每个 Actions 构建会生成以下审计材料：组件 DEB 的 `SHA256SUMS`、`LINDOWS-2.0-COMPONENTS.txt`、包含来源/二进制锁及图标覆盖哈希的 `LINDOWS-2.0-BUILD-MANIFEST.json`、ISO 校验值与 El Torito 报告。工作流还会从最终 ISO 解出 BIOS syslinux 模块、EFI 镜像和 squashfs，验证 Calamares、最小 Live sudoers、无 LightDM、ElevenDE 原生显示服务、组件适配器、Lindows Store 和 20 个 Windows 11 图标；随后在 QEMU 的 BIOS 与 OVMF UEFI 模式下进行有界启动冒烟测试。

这类检查证明映像能进入引导窗口和保留关键结构，但不替代真实硬件、完整 Calamares 分区安装或图形桌面手工验收。发布前仍应保留 ISO、manifest、工作流日志和对应提交。

## 许可证与商标

Lindows 自有代码、配置、品牌与文档按 GPL-3.0-or-later 发布。聚合 ISO 不会使所有第三方代码自动成为 GPL；已安装系统应以 `/usr/share/doc/<package>/copyright` 和本仓库 [`LICENSES/`](../LICENSES/) 中的上游文本为准。Windows、Microsoft、Copilot 等标记可能属于相应权利人；Lindows 不代表或获其授权。

## 参考

[1]: https://github.com/SYSTEM-Intel-MIC/ElevenDE/tree/b4b97ca4fa0ac46235dd8a20b508ff5c9bdf1026 "ElevenDE 3.5.1 fixed source"
