# PinboardShot Website

PinboardShot 的中英双语产品页与公开下载入口。网站基于
[vinext](https://github.com/cloudflare/vinext)，部署目标为 Cloudflare
Workers + Static Assets。

## Prerequisites

- Node.js `>=22.13.0`
- pnpm `10.22.0`

## Quick Start

```bash
pnpm install
pnpm run dev
pnpm run build
```

部署配置位于 `wrangler.jsonc`。当前站点不使用 D1、R2、Cloudflare
Images 或其他远程绑定。

## Cloudflare 部署准备

```bash
pnpm run lint
pnpm test
pnpm run check:cloudflare
pnpm run deploy:dry-run
```

确认 dry-run 产物无误后，登录 Cloudflare，再显式执行：

```bash
pnpm run deploy
```

## GitHub Actions 自动部署

仓库包含 `.github/workflows/deploy-website.yml`。当 `main` 分支上的
`website/**` 或 workflow 自身更新时，会自动安装依赖、执行 lint、测试、
Cloudflare 兼容检查、部署 dry-run，并在成功后部署到 Cloudflare Workers。

GitHub 仓库需要配置以下 Actions secrets：

- `CLOUDFLARE_ACCOUNT_ID`
- `CLOUDFLARE_API_TOKEN`

不要把这些值写入仓库。`website/scripts/check-app-version.mjs` 依赖未公开的
应用 `Resources/Info.plist`，因此它只适合本地发布前检查，不在公开仓库 CI 中运行。

## Google 收录

网站会输出可索引的页面 metadata、`/robots.txt` 和 `/sitemap.xml`。
`robots.txt` 声明 sitemap 地址；sitemap 只列出适合进入 Google 搜索结果的
规范页面，并为中英文页面声明 alternate 关系。

Search Console 验证码不要写入仓库。需要使用 HTML meta 验证时，在
Cloudflare/GitHub Actions 环境中设置：

- `NEXT_PUBLIC_GOOGLE_SITE_VERIFICATION`

网站已添加 Google tag（`G-WDBY7TDB0R`）用于 Google 设置和基础访问衡量。
脚本默认拒绝广告存储和广告个性化，分析存储默认开启；访客选择“关闭分析”
后会把 analytics storage 更新为拒绝。

部署后，在 Google Search Console 添加 `https://pinboardshot.agentclub.dev/`
属性，并提交 `https://pinboardshot.agentclub.dev/sitemap.xml`。

## Workspace Auth Headers

OpenAI workspace sites can read the current user's email from
`oai-authenticated-user-email`.

SIWC-authenticated workspace sites may also receive
`oai-authenticated-user-full-name` when the user's SIWC profile has a non-empty
`name` claim. The full-name value is percent-encoded UTF-8 and is accompanied by
`oai-authenticated-user-full-name-encoding: percent-encoded-utf-8`.

Treat the full name as optional and fall back to email when it is absent:

```tsx
import { headers } from "next/headers";

export default async function Home() {
  const requestHeaders = await headers();
  const email = requestHeaders.get("oai-authenticated-user-email");
  const encodedFullName = requestHeaders.get("oai-authenticated-user-full-name");
  const fullName =
    encodedFullName &&
    requestHeaders.get("oai-authenticated-user-full-name-encoding") ===
      "percent-encoded-utf-8"
      ? decodeURIComponent(encodedFullName)
      : null;

  const displayName = fullName ?? email;
  // ...
}
```

## Optional Dispatch-Owned ChatGPT Sign-In

Import the ready-to-use helpers from `app/chatgpt-auth.ts` when the site needs
optional or required ChatGPT sign-in:

- Use `getChatGPTUser()` for optional signed-in UI.
- Use `requireChatGPTUser(returnTo)` for server-rendered pages that should send
  anonymous visitors through Sign in with ChatGPT.
- Use `chatGPTSignInPath(returnTo)` and `chatGPTSignOutPath(returnTo)` for
  browser links or actions.
- Pass a same-origin relative `returnTo` path for the destination after sign-in
  or sign-out. The helper validates and safely encodes it.
- Mark protected pages with `export const dynamic = "force-dynamic"` because
  they depend on per-request identity headers.

Dispatch owns `/signin-with-chatgpt`, `/signout-with-chatgpt`, `/callback`, the
OAuth cookies, and identity header injection. Do not implement app routes for
those reserved paths. Routes that do not import and call the helper remain
anonymous-compatible.

SIWC establishes identity only; it does not prove workspace membership. Use the
Sites hosting platform's access policy controls for workspace-wide restrictions,
or enforce explicit server-side membership or allowlist checks.

Use SIWC for account pages, user-specific dashboards, saved records, and write
actions tied to the current ChatGPT user. Leave public content anonymous.

## Useful Commands

- `pnpm run dev`: start local development
- `pnpm run build`: verify the vinext build output
- `pnpm test`: 构建网站并验证服务端渲染的下载页
- `pnpm run check:cloudflare`: 检查 vinext 与 Cloudflare Workers 的兼容性
- `pnpm run deploy:dry-run`: 生成部署包但不上传
- `pnpm run deploy`: 构建并部署到 Cloudflare Workers
- `pnpm run db:generate`: generate Drizzle migrations after schema changes

## Learn More

- [vinext Documentation](https://github.com/cloudflare/vinext)
- [Drizzle D1 Guide](https://orm.drizzle.team/docs/get-started/d1-new)
