# Chrome 网页长截图

> PinboardShot 0.17.0 起可从设置侧栏直接进入「Chrome 网页长截图」；旧版仍按下文的“设置 → 偏好”路径操作。

PinboardShot Browser Capture 是可选的 Chrome Manifest V3 插件。它按网页的实际滚动坐标采集 PNG 分段图片，通过 Native Messaging 交给本机 PinboardShot 合成，并打开现有编辑窗口。图片不会上传到服务器，也不需要 macOS 屏幕录制权限。其他应用的长截图继续使用原生截图入口。

本地开发版 0.3.0 包含独立 PNG 保存：初始检测无法连接 App 或 App 协议不兼容时，插件在浏览器内拼接并下载图片。面板显示“独立模式”，勾选“保存时选择位置”会打开 Chrome 保存对话框，否则使用浏览器默认下载位置。保留单个主要内部滚动面板的识别与裁切、粘性标题保留、橘色界面和截图动效，结束后清空进度。这些增强目前仅在源码和本地构建中，尚未发布到 Chrome 商店；开发验证请使用下述本地安装方式。

独立模式也支持暂停/继续、停止并保存已截取部分、取消并丢弃。开始时选定保存目标，途中 App 断连不会改道下载或重复保存。页面在保存对话框出现之前恢复；只有 Chrome 确认下载完成才显示成功。保存等待最长两分钟；保存失败或取消后需重新截图。

## 商店安装

插件已发布到 [Chrome 应用商店](https://chromewebstore.google.com/detail/pinboardshot-browser-capt/kjpleeeibdicdoljjhoahhnkggncglac)。需要 Chrome 116 或更新版本、macOS 14 或更新版本，以及支持商店版插件的 PinboardShot。

1. 更新并启动 `/Applications/PinboardShot.app`。
2. 在 PinboardShot 的“设置 → 偏好 → Chrome 网页长截图”点击“从 Chrome 商店安装”，在商店中安装并启用插件。
3. App 启动时自动注册本机通道；插件面板会自动握手检测，连接成功后即可截图。设置中会显示近期连接状态，“连接本机应用”可用于手动修复注册。
4. 在网页点击 PinboardShot 插件按钮开始长截图，或使用 `⌘⇧Y`。采集期间不要切换该 Chrome 窗口的标签页；插件完成后回到原始滚动位置，App 打开编辑窗口。

无需开启开发者模式或加载已解压的扩展程序。Chrome 管理插件更新，Mac 应用独立更新；不再需要随 App 更新重新导出插件。

## 本地安装（无需访问商店）

1. 在 App 的“设置 → 偏好 → Chrome 网页长截图”点击“下载到本地”。App 将内置插件导出到“下载”目录的 `PinboardShot-Chrome-<内容摘要>` 文件夹，并在 Finder 中选中它；此过程不访问网络。
2. 在 Chrome 打开 `chrome://extensions`，开启“开发者模式”，点击“加载已解压的扩展程序”，选择导出的文件夹。[Chrome 官方本地加载步骤](https://developer.chrome.com/docs/extensions/get-started/tutorial/hello-world#load-unpacked)。
3. 保留该文件夹。加载并启用后，插件会自动检测本机连接；通过插件按钮或 `⌘⇧Y` 开始截图。
4. 本地插件随 App 更新。App 更新后再次点击“下载到本地”，加载新导出的文件夹；旧文件夹不会被覆盖，以保护已加载内容和用户修改。

正式发布的 App 和本地构建都允许商店版 ID `kjpleeeibdicdoljjhoahhnkggncglac` 与内置本地版 ID `olghjpagobkdfmiphmabpapcfgjfdeaf`。本地版保留固定公钥；商店上传 ZIP 按现有打包脚本移除此开发用途字段，并上传到已有商店条目。此前仓库开发版使用同一个本地 ID，无需更换身份。

两种插件可以保留在 Chrome 中。它们共用快捷键时，Chrome 可能只将快捷键分配给其中一个；请用各自工具栏按钮启动。

插件打开面板时自动检测本机协议，每 5 秒重试；后台每分钟通过 `alarms` 做一次握手。检测只发送协议版本，不查询网页、不截图，也不上传数据。App 使用仅包含固定插件 ID 与时间的短期握手记录显示近期连接；记录 150 秒后过期，所以“未检测到”不等同于“未安装”。

## 范围和限制

- 使用 `activeTab`、`scripting` 和 `nativeMessaging` 权限，只在用户通过插件按钮或快捷键发起时采集当前页面。0.3.0 增加 `downloads`，仅用于插件自己的 PNG 下载、结果确认和取消。没有常驻的所有网站访问权限，不上传图片、不将图片写入插件持久存储。
- 独立模式的 PNG 单边最多 32767 个物理像素、总计最多 3200 万物理像素；超出时明确停止，不缩放或截断为“完整”图片。较大的页面可缩小浏览器窗口，或连接 App 后重试。
- 支持整个文档滚动，以及外层页面不滚动时单个主要、完整可见的内部滚动面板。内部面板只输出其内容，不把外围工具栏或侧栏反复拼入图片；多个主要滚动区域、被裁切或缩放变换的面板会明确拒绝采集。
- 粘性元素临时回到正常文档流，保留首屏之外的章节标题；固定元素在首段保留，后续暂时隐藏。根据首段底部固定元素的遮挡高度增加重叠，减少大悬浮页脚遮住的内容遗漏。结束后恢复样式与原始滚动位置。
- 可见图片与字体有加载等待；可见资源加载失败或超时时明确停止，不将可能缺少内容的截图提交为成功。网络无限加载、网页结构变化或视口改变仍可能导致捕获失败。
- 动态高度会继续采集，达到时间、分段数量或像素上限时会明确停止，不将缺少内容的结果标记为完整。
- 只支持 Chrome 普通网页；受浏览器限制的页面不能注入采集脚本。其他浏览器的安装与本机通道配置暂未实现。
- 图片按实际坐标合成；发现坐标缺口或尺寸不一致时拒绝导入，不填补未捕获内容。
- iframe 内部滚动、Shadow DOM 内部面板、虚拟化列表和持续变化的动画内容没有完整性保证，不应把采集完成理解为所有网站数据都已截取。

## 本机接收

App 启动或执行“连接本机应用”后写入：

`~/Library/Application Support/Google/Chrome/NativeMessagingHosts/com.ryanwang.pinboardshot.browser_capture.json`

正式构建和本地构建都只允许上述两个固定插件 ID；宿主是 App 内的 `Contents/MacOS/PinboardShotBrowserHost`。扩展按受限长度分块传输，宿主接收 PNG 分段并验证格式、尺寸、顺序和会话 ID。临时图片位于仅当前用户可访问的 `~/Library/Application Support/PinboardShot/BrowserCaptures/` UUID 子目录；导入或取消时清理，过期未完成会话在后续启动宿主时清理。

浏览器回传 URL 只包含随机 UUID，不包含文件路径、网页地址或标题。App 只读取完成的受控目录，拒绝符号链接和任意外部文件路径。

卸载插件请在 Chrome 扩展页移除 PinboardShot Browser Capture。如不再使用本机通道，可删除上述唯一注册 JSON；不要删除其他应用的 Native Messaging 注册文件。

## 开发验证

运行 `node --test browser-extension/tests/*.test.mjs`、`swift test --filter 'BrowserCaptureBridgeTests|BrowserCaptureImportTests|CaptureAutomationTests'`，然后用 `scripts/build-app.sh` 构建含插件资源和签名宿主的 App。宿主协议测试使用受控临时目录，不启动用户的 Chrome 或 App，不修改真实 Chrome 配置。

安装 Playwright 并确保本机 Chrome 可用时，可单独运行 `node --test browser-extension/tests/capture.browser.mjs`。该测试使用隔离、未登录的临时 Chrome，验证合成网页的内部面板、Retina 裁切、粘性标题、较高固定页脚和拒绝不明确的范围；不读取用户网页。

## 从 App 发起采集

先在 Chrome 当前标签页选好网页，然后在 PinboardShot 菜单栏面板点击“Chrome 网页长截图”，或在设置 → 偏好 → Chrome 网页长截图中点击“启动 Chrome 网页长截图”。首次需要允许 macOS 辅助功能权限。App 会切回 Chrome 并触发插件命令；采集完成后回到 App 编辑。Chrome 的插件快捷键须保持为 ⌘⇧Y，且插件须已启用。如果更改了该快捷键，请使用 Chrome 插件按钮。

滚动截图选区所属窗口为 Chrome 时，预览面板会显示“已识别 Chrome”和“开始自动截屏”。该按钮调用插件截取目标窗口当前标签页的整页内容，范围不限于选区。其他应用继续使用原生滚动截图；其他浏览器目前不走 Chrome 插件。
