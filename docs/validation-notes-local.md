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
