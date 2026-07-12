# PinboardShot

> 原生、轻量、本地优先的 macOS 截图、标注与贴图工具。  
> A native, lightweight, local-first screenshot, annotation, and pinboard tool for macOS.

[中文](#中文) · [English](#english) · [最新版本 / Latest Release](https://github.com/agent-club/PinboardShot/releases/latest)

> [!IMPORTANT]
> 这是 PinboardShot 的公开发布仓库，仅提供应用安装包和签名更新清单，不包含项目源码。  
> This is PinboardShot’s public release repository. It contains application packages and the signed update feed, but not the project source code.

## 中文

### 功能概览

- 区域、当前屏幕、光标所在窗口和延时截图
- 马赛克、画笔、矩形、高亮、箭头和可编辑文字标注
- 多张贴图、等比缩放、透明度、鼠标穿透和阴影控制
- 最近 50 张截图的本地历史记录
- 可自定义的多组全局快捷键
- 简体中文、繁体中文和英文界面
- 基于 Sparkle 的签名应用内更新

### 下载与安装

当前公开版本要求：

- macOS 14 或更高版本
- Apple Silicon Mac

安装步骤：

1. 前往[最新版本页面](https://github.com/agent-club/PinboardShot/releases/latest)。
2. 下载以 `PinboardShot-` 开头的 ZIP 安装包。
3. 解压后将 PinboardShot 移入“应用程序”文件夹。
4. 启动应用，并按系统提示授予屏幕录制权限。

### 软件更新

PinboardShot 可从菜单栏选择“检查更新…”。用户同意后，应用可以定期检查并在后台下载新版本；安装更新时会安全重启应用。

更新包通过 Sparkle EdDSA 签名验证，稳定更新清单位于：

- [appcast.xml](https://github.com/agent-club/PinboardShot/releases/latest/download/appcast.xml)

应用的网络访问仅用于检查和下载软件更新。截图、标注、历史和偏好设置均在本机处理，不包含遥测或分析服务。

### Release 资产

| 文件 | 用途 |
| --- | --- |
| `PinboardShot-<version>-<build>.zip` | 面向用户的应用安装包 |
| `appcast.xml` | Sparkle 使用的签名更新清单，不需要手动安装 |

每个 Release 的说明均同时提供中文和英文。问题反馈可通过本仓库的 [Issues](https://github.com/agent-club/PinboardShot/issues) 提交。

---

## English

### Features

- Region, current-display, pointer-window, and delayed captures
- Mosaic, pen, rectangle, highlight, arrow, and editable text annotations
- Multiple pinned images with proportional resizing, opacity, click-through, and shadow controls
- Local history for the latest 50 captures
- Customizable multiple global shortcuts
- Simplified Chinese, Traditional Chinese, and English interfaces
- Signed in-app updates powered by Sparkle

### Download and installation

The current public release requires:

- macOS 14 or later
- An Apple Silicon Mac

Installation:

1. Open the [latest release](https://github.com/agent-club/PinboardShot/releases/latest).
2. Download the ZIP package whose name starts with `PinboardShot-`.
3. Extract it and move PinboardShot to the Applications folder.
4. Launch the app and grant Screen Recording permission when macOS requests it.

### Software updates

Choose “Check for Updates…” from the PinboardShot menu. After the user opts in, the app can check periodically and download new versions in the background. The app restarts safely when an update is installed.

Update archives are verified with Sparkle EdDSA signatures. The stable update feed is available at:

- [appcast.xml](https://github.com/agent-club/PinboardShot/releases/latest/download/appcast.xml)

Network access is used only to check for and download software updates. Captures, annotations, history, and preferences stay on-device, with no telemetry or analytics.

### Release assets

| File | Purpose |
| --- | --- |
| `PinboardShot-<version>-<build>.zip` | Application package for end users |
| `appcast.xml` | Signed update feed consumed by Sparkle; no manual installation is needed |

Every Release includes complete Chinese and English notes. Report problems through this repository’s [Issues](https://github.com/agent-club/PinboardShot/issues).
