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

## 2026-08-24：会话稳定性、中文文字与动态重排修复

提交 `6bb7606` 已推送到 `lindows-2.0-integration`，GitHub Actions 运行 `32716877911` 已以 `success` 完成。该运行的 ISO 完整性验证、BIOS/UEFI QEMU 冒烟启动、QEMU 视觉诊断上传、ISO/验证工件上传及组件包上传均已成功；发布步骤按分支策略跳过，未创建 Release。

本轮从构建输入中移除了 Lindows Control Panel 和 Task Scheduler，包括来源锁、构建配方、桌面入口、图标覆盖层、许可证副本、CI 断言、最终 ISO 校验和公开组件声明。镜像新增 `zh_CN.UTF-8` 生成、Noto CJK Fontconfig 优先级及 ElevenDE 会话启动的 Xresources，以修复截图中开始菜单、SAS 和终端可能出现的中文方框/乱码；开始菜单过滤同时覆盖 Exec、desktop 文件名及中英文显示名，避免遗留关机、重启、睡眠、注销、锁屏条目出现在“所有应用”。Copilot 入口统一经过 `lindows-copilot` 包装器，避免开始菜单路径绕过兼容启动参数。

ElevenDE 会话增加受控 Shell 重启循环；显示服务对正常 Openbox 退出也会重启完整会话，因此 SAS“注销”不再应停在仅有左上角光标的黑屏。会话内启动标准 polkit 代理，电源操作仍走 loginctl 的正常授权路径而不降低权限控制。锁屏补丁监听根窗口 ConfigureNotify 与 RandR 屏幕变化，重建全屏窗口、壁纸和离屏帧；Widgets 补丁则监听每个 QScreen 的 geometryChanged 与屏幕增删，延迟合并变更并重新贴合面板与右侧边缘热区。

`32716877911` 的 BIOS 与 UEFI 1280×800 视觉帧均显示真实浅色 ElevenDE 桌面、任务栏、中文“终端”“注册表编辑器”标签以及 Microsoft Edge 图标，没有黑屏或均匀灰屏。这只证明最终桌面启动与基础文字/图标渲染没有回归；它不能替代健康 VM 中的开机滚屏录像、开始菜单实际列表、Copilot 首次点击、设备管理器界面、锁屏动态分辨率、Widgets 热区、SAS 电源操作、注销后登录页或完整 Calamares 安装交互回归。当前主机的 EXT4 问题仍使这些本地交互测试不可信，因此不将其表述为已完成。
