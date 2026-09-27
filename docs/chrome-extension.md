# Chrome 网页长截图

PinboardShot Browser Capture 是可选的 Chrome Manifest V3 插件。它按网页的实际滚动坐标采集 PNG 分段图片，通过 Native Messaging 交给本机 PinboardShot 合成，并打开现有编辑窗口。图片不会上传到服务器，也不需要 macOS 屏幕录制权限。其他应用的长截图继续使用原生截图入口。

## 本地安装

当前开发版尚未上架 Chrome Web Store，不能随 App 静默启用。

1. 更新并启动 `/Applications/PinboardShot.app`。
2. 在 PinboardShot 的“设置 → 通用 → Chrome 网页长截图”点击“设置 Chrome 插件”。确认连接后，App 注册只允许本插件访问的本机通道，将插件导出到“下载”文件夹并复制路径。
3. 在 Chrome 打开 `chrome://extensions`，开启开发者模式，点击“加载已解压的扩展程序”。
4. 在选目录窗口直接从“下载”选择 `PinboardShot-Chrome-` 开头的文件夹；也可以按 `⌘⇧G` 并粘贴 App 已复制的路径。请保留该文件夹，Chrome 会从中运行插件。
5. 在网页点击 PinboardShot 插件按钮开始长截图，或使用 `⌘⇧Y`。采集期间不要切换该 Chrome 窗口的标签页；插件完成后回到原始滚动位置，App 打开编辑窗口。

更新 App 后重新导出插件；若导出路径变化，移除旧扩展并加载新文件夹。相同内容重复导出会复用同一路径，不会覆盖用户改过的文件。正式上架后应改用商店安装，并同步商店分配的扩展 ID 与本机通道白名单。

## 范围和限制

- 使用 `activeTab`、`scripting` 和 `nativeMessaging` 权限，只在用户通过插件按钮或快捷键发起时采集当前页面。没有常驻的所有网站访问权限。
- 支持以整个文档为滚动容器的网页；独立嵌套滚动区域暂不支持。
- 固定或粘性元素只在首段保留，后续采集暂时隐藏，结束后恢复。图片与字体有加载等待，但网络无限加载、网页结构变化或视口改变可能导致捕获失败。
- 动态高度会继续采集，达到时间、分段数量或像素上限时会明确停止，不将缺少内容的结果标记为完整。
- 只支持 Chrome 普通网页；受浏览器限制的页面不能注入采集脚本。其他浏览器的安装与本机通道配置暂未实现。
- 图片按实际坐标合成；发现坐标缺口或尺寸不一致时拒绝导入，不填补未捕获内容。

## 本机接收

App 确认连接后写入：

`~/Library/Application Support/Google/Chrome/NativeMessagingHosts/com.ryanwang.pinboardshot.browser_capture.json`

该文件仅允许开发版扩展 `olghjpagobkdfmiphmabpapcfgjfdeaf`，宿主是 App 内的 `Contents/MacOS/PinboardShotBrowserHost`。扩展按受限长度分块传输，宿主接收 PNG 分段并验证格式、尺寸、顺序和会话 ID。临时图片位于仅当前用户可访问的 `~/Library/Application Support/PinboardShot/BrowserCaptures/` UUID 子目录；导入或取消时清理，过期未完成会话在后续启动宿主时清理。

浏览器回传 URL 只包含随机 UUID，不包含文件路径、网页地址或标题。App 只读取完成的受控目录，拒绝符号链接和任意外部文件路径。

卸载插件请在 Chrome 扩展页移除 PinboardShot Browser Capture。如不再使用本机通道，可删除上述唯一注册 JSON；不要删除其他应用的 Native Messaging 注册文件。

## 开发验证

运行 `node --test browser-extension/tests/*.test.mjs`、`swift test --filter 'BrowserCaptureBridgeTests|BrowserCaptureImportTests|CaptureAutomationTests'`，然后用 `scripts/build-app.sh` 构建含插件资源和签名宿主的 App。宿主协议测试使用受控临时目录，不启动用户的 Chrome 或 App，不修改真实 Chrome 配置。

## 从 App 发起采集

先在 Chrome 当前标签页选好网页，然后在 PinboardShot 菜单栏面板点击“Chrome 网页长截图”，或在设置 → 通用 → Chrome 网页长截图中点击“启动 Chrome 网页长截图”。首次需要允许 macOS 辅助功能权限。App 会切回 Chrome 并触发插件命令；采集完成后回到 App 编辑。Chrome 的插件快捷键须保持为 ⌘⇧Y，且插件须已启用。如果更改了该快捷键，请使用 Chrome 插件按钮。

滚动截图选区所属窗口为 Chrome 时，预览面板会显示“已识别 Chrome”和“开始自动截屏”。该按钮调用插件截取目标窗口当前标签页的整页内容，范围不限于选区。其他应用继续使用原生滚动截图；其他浏览器目前不走 Chrome 插件。
