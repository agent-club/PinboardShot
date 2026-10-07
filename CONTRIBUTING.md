# Contributing to PinboardShot

[English](#english) · [中文](#中文) · [Product overview / 产品介绍](README.md)

## English

Contributions to code, documentation, translations, and bug reports are welcome. This guide covers local development and verification; see the [README](README.md) for installation and everyday use.

### Start contributing

1. For bug fixes, describe the reproduction steps, macOS version, PinboardShot version, and expected behavior. Discuss the scope of new features or larger changes in [Issues](https://github.com/agent-club/PinboardShot/issues) first.
2. Work on your own branch and keep changes focused, without unrelated refactoring or formatting.
3. Run checks relevant to the change. Describe the problem, resulting behavior, verification, and known limits in the Pull Request. Include redacted screenshots for UI changes when useful.

Report vulnerabilities according to [SECURITY.md](SECURITY.md). Do not expose vulnerability details or sensitive data in public issues.

### Development environment

- macOS 14 or later.
- Swift 6.2 and Xcode Command Line Tools.
- A stable Apple Development or Developer ID Application signing identity is recommended to reduce Screen Recording permission resets after rebuilds.
- Browser extension changes need Node.js; website changes need Node.js ≥ 22.13.0 and pnpm 10.22.0.

From the repository root, run:

```bash
swift test --no-parallel
./scripts/build-app.sh
```

`build-app.sh` builds the app, then removes the old bundle and recreates `.build/app/PinboardShot.app`. It includes both `arm64` and `x86_64` by default. To build only for Apple Silicon:

```bash
PINBOARDSHOT_ARCHS=arm64 ./scripts/build-app.sh
```

The script tries Developer ID Application and Apple Development identities in order. If neither is available and no identity was explicitly requested, it falls back to ad-hoc signing with a warning. Set `PINBOARDSHOT_CODE_SIGN_IDENTITY` to select an identity. On macOS 26, ad-hoc rebuilds may require Screen Recording permission again.

For local runtime verification, quit PinboardShot, completely replace `/Applications/PinboardShot.app` with the new build, and launch from that path to check the change. Do not copy incrementally into an old bundle or launch additional copies from build or download folders. Remove temporary backups and installers afterward, keeping only the latest build and the Applications installation.

### Code and documentation

| Path | Contents |
| --- | --- |
| `Sources/PinboardShot/` | Menu-bar app, capture, annotation, pins, history, and settings |
| `Sources/BrowserCaptureBridge/` | Local browser-capture protocol and controlled data handling |
| `Sources/PinboardShotBrowserHost/` | Chrome Native Messaging host |
| `Resources/` | Info.plist, icons, and localizations |
| `Tests/` | Swift tests |
| `browser-extension/` | Optional Chrome capture extension and tests |
| `website/` | Bilingual website and Cloudflare deployment configuration |
| `scripts/` | App builds, preview packaging, and release scripts |

Further guides:

- [Extension development and tests](browser-extension/README.md) and [local integration](docs/chrome-extension.md).
- [Website development and Cloudflare deployment](website/README.md). Use the existing Cloudflare workflow for website publishing.
- [Declarative OCR plugin format and security limits](docs/ocr-plugins.md).
- [Public privacy and security signals](docs/privacy-security-signals.md).

### Verify changes

Use relevant Swift tests for app code; `swift test --filter <TestName>` runs selected tests. For changes to app behavior, resources, or configuration, run `scripts/build-app.sh` after verification and complete the local installation and runtime checks above.

Run extension unit and protocol tests with:

```bash
node --test browser-extension/tests/*.test.mjs
```

See the [extension guide](browser-extension/README.md#tests) for prerequisites and commands for real Chrome rendering checks, and [website/README.md](website/README.md) for website checks. Documentation-only changes need content, link, and Markdown checks.

Keep captures and history local by default. Remote OCR applies only to regions actively selected by the user; history indexing and smart redaction always remain on-device. Preserve these privacy boundaries and verify cancellation, failure, and cleanup paths for new behavior.

### Signing and releases

Official distribution requires Developer ID Application signing and Apple notarization. Ad-hoc and Apple Development builds are for development and preview only. Store notarization credentials interactively in Keychain rather than in the repository:

```bash
xcrun notarytool store-credentials "PinboardShot-notary"
```

Maintainers should follow the [release process](docs/release-process.md) and prefer `scripts/release-artifacts.sh <version> <build>`, which invokes the update-package workflow and produces the ZIP, DMG, and appcast. Use `scripts/prepare-update.sh <version> <build>` for update-package generation alone, or `scripts/package-preview.sh` for internal previews. Preview packages are not Apple notarized and must not be published as official updates.

Before publishing, verify the version and build, nested code signatures, notarization, Sparkle signatures, ZIP contents, and SHA-256 of anonymous downloads. GitHub Releases and user-visible update notes must provide matching Chinese and English sections, with Chinese first. Do not overwrite or delete existing public releases.

Review the diff and staging area before committing. Never commit authentication or session material, private keys, signing certificates, environment files, local configuration, logs, or user data. Sparkle private keys must remain in protected Keychain or release-system secret storage. Redact screenshots and logs before sharing. See [LICENSE](LICENSE) and [NOTICE.md](NOTICE.md) for licensing and third-party notices.

## 中文

欢迎参与 PinboardShot 的代码、文档、翻译和问题反馈。以下是本地开发与验证的入口；下载安装和日常使用见 [README](README.md)。

### 开始贡献

1. 修复问题时，先说明复现步骤、macOS 版本、PinboardShot 版本和预期行为。新功能或较大调整建议先在 [Issues](https://github.com/agent-club/PinboardShot/issues) 中讨论范围。
2. 在自己的分支中完成改动，保持提交聚焦，避免混入无关重构或格式化。
3. 执行与改动相关的验证，在 Pull Request 中说明问题、改动效果、验证结果与已知限制。界面变化可附脱敏截图。

安全漏洞请按 [SECURITY.md](SECURITY.md) 报告，不要在公开 Issue 中暴露漏洞细节或敏感数据。

### 开发环境

- macOS 14 或更高版本。
- Swift 6.2 工具链与 Xcode Command Line Tools。
- 推荐使用稳定的 Apple Development 或 Developer ID Application 签名身份，减少本地重建后屏幕录制权限重置。
- 修改浏览器插件需要 Node.js；修改官网需要 Node.js ≥ 22.13.0 和 pnpm 10.22.0。

在仓库根目录执行：

```bash
swift test --no-parallel
./scripts/build-app.sh
```

`build-app.sh` 先构建，再清理并重新生成 `.build/app/PinboardShot.app`，默认包含 `arm64` 与 `x86_64`。仅构建 Apple Silicon 架构时可执行：

```bash
PINBOARDSHOT_ARCHS=arm64 ./scripts/build-app.sh
```

脚本依次尝试 Developer ID Application 和 Apple Development 身份；未显式指定身份且两者均不可用时，回退到 ad-hoc 签名并提示警告。可通过 `PINBOARDSHOT_CODE_SIGN_IDENTITY` 指定签名身份。macOS 26 上 ad-hoc 重建可能需要重新授权屏幕录制。

本机运行验证时，先退出 PinboardShot，再用新构建完整替换 `/Applications/PinboardShot.app`，从该路径启动并确认改动。不要增量复制进旧应用包，也不要从构建目录或下载目录启动其他副本；完成后清理临时备份与安装包，只保留最新构建和 Applications 中的安装。

### 代码与文档入口

| 路径 | 内容 |
| --- | --- |
| `Sources/PinboardShot/` | 菜单栏应用、截图、标注、贴图、历史与设置 |
| `Sources/BrowserCaptureBridge/` | 浏览器截图的本机协议与受控数据处理 |
| `Sources/PinboardShotBrowserHost/` | Chrome Native Messaging 宿主 |
| `Resources/` | Info.plist、图标和本地化资源 |
| `Tests/` | Swift 测试 |
| `browser-extension/` | 可选的 Chrome 网页截图插件与测试 |
| `website/` | 中英双语官网与 Cloudflare 部署配置 |
| `scripts/` | 应用构建、预览打包和正式发布脚本 |

专项说明：

- [浏览器插件开发与测试](browser-extension/README.md)及[本机集成说明](docs/chrome-extension.md)。
- [官网开发与 Cloudflare 部署](website/README.md)。网站发布使用现有 Cloudflare 流程。
- [声明式 OCR 插件格式与安全限制](docs/ocr-plugins.md)。
- [隐私与安全公开佐证维护](docs/privacy-security-signals.md)。

### 验证改动

应用代码使用相关 Swift 测试验证；可用 `swift test --filter <TestName>` 运行目标测试。涉及应用行为、资源或配置时，验证后运行 `scripts/build-app.sh`，并完成上述本机安装与运行检查。

浏览器插件的单元与协议测试：

```bash
node --test browser-extension/tests/*.test.mjs
```

真实 Chrome 渲染验证的前置条件与命令见[插件说明](browser-extension/README.md#tests)。官网改动的检查命令见 [website/README.md](website/README.md)。只修改文档时，核对内容、链接与 Markdown 格式即可。

保持截图与历史默认在本机处理。远程 OCR 仅用于用户主动框选的区域，历史索引和智能脱敏始终在本机执行。新增行为应保持这些隐私边界，并验证相关取消、失败和清理路径。

### 签名与发布

正式分发使用 Developer ID Application 签名和 Apple 公证；ad-hoc 或 Apple Development 构建仅用于开发和预览。公证凭据通过交互式命令存入钥匙串，不写入仓库：

```bash
xcrun notarytool store-credentials "PinboardShot-notary"
```

维护者按[发布流程](docs/release-process.md)执行，优先使用 `scripts/release-artifacts.sh <version> <build>`；该脚本调用更新包流程并生成 ZIP、DMG 和 appcast。独立更新包入口为 `scripts/prepare-update.sh <version> <build>`，内部预览入口为 `scripts/package-preview.sh`。预览包未经 Apple 公证，不应作为正式更新发布。

发布必须核对版本与 build、嵌套代码签名、公证、Sparkle 签名、ZIP 内容及匿名下载的 SHA-256。GitHub Release 和用户可见的更新说明须中文在前、英文在后，内容一致。不要覆盖或删除已有公开 Release。

提交前检查 diff 与暂存区。不得提交认证或会话材料、私钥、签名证书、环境变量文件、本机配置、日志或用户数据。Sparkle 私钥只保存在受保护的钥匙串或发布系统密钥存储中；截图与日志须先脱敏。项目许可证与第三方声明见 [LICENSE](LICENSE) 和 [NOTICE.md](NOTICE.md)。
