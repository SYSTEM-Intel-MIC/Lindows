# Lindows 2.0 本地验证记录

## 2026-08-22：ISO 完整性回归与新增门控

本地早期 XZ SquashFS ISO 曾通过目录列表和有限 QEMU 存活检查，但实际图形虚拟机中出现以下读取错误：

```text
SQUASHFS error: xz decompression failed, data probably corrupt
SQUASHFS error: Failed to read block ... -5
```

这证明仅检查 ISO 内文件名或 QEMU 进程仍在运行不足以证明 Live 系统可用。Lindows 已将 `scripts/validate-lindows-live-image.sh` 改为先完整 `unsquashfs` 解压最终 `/live/filesystem.squashfs`，再检查 Calamares、原生 ElevenDE 服务、无 LightDM、组件适配器、Lindows Store 和 20 个图标别名。旧 XZ 映像因此不再可能被误判为有效产物。

随后一次使用 gzip SquashFS 的本地重建已通过完整 SquashFS 展开，但图形虚拟机在选择默认 Live 启动项后于早期启动阶段报出：

```text
Kernel panic - not syncing: No working init found.
```

对该 ISO 的 `/live/initrd.img` 运行 `lsinitramfs` 得到 `cpio: premature end of archive`，证明该 initrd 同样损坏或截断。因此该 gzip ISO 也**不是**可交付成果；它不能用作 ElevenDE Live 桌面、组件或 Calamares 的通过证据。

为防止再次发生同类漏检，最终 ISO 验证现已同时抽取并完整枚举 `/live/initrd.img`，且要求其中存在顶层 `init`。BIOS/UEFI 冒烟脚本也已改为通过 QEMU monitor 主动按下默认 Live 启动项、保存启动后的帧，避免把静止的启动菜单误报为成功。

下一项验证将在 GitHub Actions 的干净托管构建器中从锁定 package layer 重新生成 ISO，并由新的完整 SquashFS 与 initrd 门控先行验证。只有下载该可信 ISO 回本地虚拟机，确认 Live 免登录进入 ElevenDE、组件入口与 Calamares 安装路径后，才可以把 Lindows 2.0 视为本地回归通过。当前状态：**仍在验证，不可交付。**

## 2026-08-24：CI 构建与视觉门控

GitHub Actions 运行 `32686179382`（提交 `023b6b9`，分支 `lindows-2.0-integration`）已完成并以 `success` 结束。该运行的唯一构建作业 `Build Lindows LiveCD and installer image` 也已成功完成；构建器发布了 LiveCD/安装器映像、组件包和 QEMU 视觉诊断工件。

视觉诊断工件 `Lindows-2.0-qemu-visual-diagnostics-217` 同时包含 BIOS 与 UEFI 的 1280×800 帧。两帧均显示真实的 ElevenDE 浅色桌面、任务栏和原生浅色壁纸，不是黑屏或均匀灰屏；桌面上可见“此电脑”“主目录”“Registry Editor”“Microsoft Edge”“Lindows Terminal”和“Install Lindows”入口。该结果证明 BIOS/UEFI 图形启动门控通过，并确认 Edge、注册表编辑器、终端和安装器桌面快捷方式已被渲染出来。

这组截图**不等同于完整交互回归**。由于当前主机的 EXT4 文件系统错误仍使大文件下载和本地虚拟机结果不可信，本轮没有把约 1.7 GB 的 LiveCD 工件下载到本机，也没有虚构 Calamares 真正落盘安装、安装后原生登录、Edge/BSOD/Task Scheduler/WinSAT/Store/Control Panel 的交互结果。因此当前状态更新为：**CI 构建与 BIOS/UEFI 视觉验证通过；健康环境中的安装和应用交互回归仍待完成，不宣称完整交付通过。**

## 2026-08-24：启动滚屏、设备管理器浅色主题与 sudo/UAC 修复

提交 `ca2b77e` 已推送到 `lindows-2.0-integration`，GitHub Actions 运行 `32696164185` 成功完成。BIOS 与 UEFI 视觉诊断帧均显示真实 ElevenDE 桌面、浅色壁纸、中文桌面入口和 Microsoft Edge 官方图标；没有出现黑屏或均匀灰屏。新的启动参数已从正常 BIOS/UEFI Live 项中移除 `splash`，保留安全图形项的 `nomodeset`，因此内核/systemd 启动过程可恢复可见滚屏；诊断帧只证明最终图形桌面可达，不能替代启动过程录像或串口日志验证。

设备管理器在 Lindows 构建副本中将 Fyne 主题颜色固定到 `theme.VariantLight`，并继续通过统一组件适配器使用浅色 GTK/Qt 环境。sudo/UAC 采用不修改系统 `/usr/bin/sudo`、PAM 或 sudoers 的安全方案：交互终端的 `sudo` 别名调用 `lindows-sudo`，先执行原生 `/usr/bin/sudo -v` 校验当前用户密码，再显示 UAC 确认；用户取消、关闭窗口或 UI 失败时不会执行目标命令，确认后才调用未修改的 `/usr/bin/sudo`。

当前主机仍未完成健康 VM 的真实落盘安装、安装后登录、设备管理器手工打开验证和 sudo/UAC 鼠标交互回归，因此不把这些项目虚构为已通过。当前可确认结论为：**代码静态检查通过，CI 构建通过，BIOS/UEFI 最终图形桌面视觉门控通过；完整健康 VM 交互验证仍待执行。**

## 2026-08-24：稳定性恢复与安装后动作路径重构

提交 `df73c54` 与后续 CI 权限补充 `94d952d` 已推送到 `lindows-2.0-integration`。运行 `32730634610` 已以 `success` 完成；其包含组件 DEB 重建、成品 squashfs 完整性校验、最终 ISO 路径断言，以及 BIOS/UEFI QEMU 启动冒烟。开发分支未创建 Release。

本轮继续移除了 Lindows Control Panel 和 Task Scheduler 的构建输入与入口。中文修复不再请求 Bookworm 中不存在的 `Noto Sans Mono CJK SC`，而使用镜像实际含有并经 Fontconfig 确认的 `Noto Sans CJK SC`；`zh_CN.UTF-8`、Fontconfig 与 Xresources 共同为开始菜单、SAS 和终端提供 CJK 回退。Start“所有应用”改为在最终安装钩子中物理删除系统关机、重启、注销、睡眠与锁屏 `.desktop` 文件，并由最终 squashfs 的负向断言复核。注册表编辑器不再使用错误的钥匙图标，改为独立记录来源、由 `regedit_100.ico` 重绘的 Windows 11 图标资源；设备管理器构建副本优先识别并显示 Lindows。

严重的稳定性回归已从源头撤回：ElevenDE Shell 恢复为单一长生命周期进程，不再在 RandR 期间循环重建；显示服务从 `Restart=always` 改回 `Restart=on-failure`。SAS 注销改为专用 `lindows-logout` 在 Openbox 退出前写入标记，显示启动器仅对该标记执行同一 Xorg 内的新会话；无标记退出即使状态码为 0 也交给 systemd 失败恢复。Widgets 保持每个屏幕的边缘热区窗口，只在 geometryChanged 时原地重定位，避免销毁/新建热区导致静止鼠标反复触发中间 Widgets。

BSOD、Windows Update Preview 和 Start 电源改为经由固定功能的 `lindows-privileged-action` 请求单一 polkit 动作。该调度器只允许 `bsod`、`update-preview`、`suspend`、`poweroff`、`reboot`；BSOD 硬编码 `--restore`，更新预览硬编码 `--no-reboot`，并且没有任意参数传递。Live 用户仅对此单一动作免密，安装系统保留 active-user `auth_self` 的可见认证提示，替代此前只在 Live 工作的宽泛 `pkexec` 例外和安装后裸 `loginctl` 无反馈路径。

真实运行时结论仍受限：我下载运行 `32730512489` 的 ISO 工件时，ZIP 自检通过但解压后 ISO 的 SHA-256 与 CI 附带值不一致；随后宿主内核记录了 `vda` I/O 错误与 EXT4 错误。损坏 ISO 已被删除，未用于 QEMU 或安装验证。因此本轮只能确认最终 CI 构建、成品内容校验和 BIOS/UEFI 启动冒烟通过；**尚未宣称**分辨率热重排、Widgets 热区、SAS 注销/电源、安装后 BSOD/更新、Copilot 首次启动或 Calamares 落盘安装已在健康虚拟机中交互通过。
