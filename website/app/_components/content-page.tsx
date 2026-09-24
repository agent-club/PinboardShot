import Link from "next/link";
import currentRelease from "@/content/current-release.json";
import {
  getContentPageByPath,
  type ContentPageDefinition,
} from "@/content/content-pages";
import { DOWNLOAD_PATH, GITHUB_URL, contentPageStructuredData } from "../seo";

export function ContentPage({ page }: { page: ContentPageDefinition }) {
  const jsonLd = contentPageStructuredData(page);
  const relatedPages = page.relatedPaths.flatMap((path) => {
    const related = getContentPageByPath(path);
    return related ? [related] : [];
  });

  return (
    <main className="content-page" lang="zh-CN">
      <script
        type="application/ld+json"
        dangerouslySetInnerHTML={{ __html: JSON.stringify(jsonLd).replaceAll("<", "\\u003c") }}
      />

      <header className="content-site-header">
        <Link className="brand" href="/" aria-label="返回 PinboardShot 首页">
          <span className="brand-mark" aria-hidden="true"><i /><i /></span>
          <span>PinboardShot</span>
        </Link>
        <nav aria-label="内容页导航">
          <Link href="/#features">功能</Link>
          <Link href="/#workflow">使用方式</Link>
          <Link href="/#compare">对比</Link>
          <Link href="/privacy">隐私</Link>
        </nav>
        <Link className="small-download" href={DOWNLOAD_PATH}>下载</Link>
      </header>

      <article className="content-article">
        <div className="content-breadcrumb" aria-label="面包屑">
          <Link href="/">首页</Link>
          <span aria-hidden="true">/</span>
          <span>{page.categoryLabel}</span>
          <span aria-hidden="true">/</span>
          <span aria-current="page">{page.title}</span>
        </div>

        <header className="content-hero">
          <p className="eyebrow"><span />{page.eyebrow}</p>
          <h1>{page.title}</h1>
          <p className="content-lead">{page.intro}</p>
          <div className="content-hero-meta">
            <span>当前版本 {currentRelease.version}</span>
            <span>事实核对 <time dateTime={page.lastReviewed}>{page.lastReviewed}</time></span>
            <span>macOS 14+</span>
          </div>
          <div className="content-actions">
            <Link className="button button-primary" href={DOWNLOAD_PATH}>下载 PinboardShot<span aria-hidden="true">↓</span></Link>
            <a className="button button-secondary" href={GITHUB_URL} target="_blank" rel="noreferrer">查看源码<span aria-hidden="true">↗</span></a>
          </div>
        </header>

        <section className="content-facts" aria-label="关键事实">
          {page.facts.map((fact) => (
            <div key={fact.label}>
              <span>{fact.label}</span>
              <strong>{fact.value}</strong>
            </div>
          ))}
        </section>

        <div className="content-body">
          {page.sections.map((section) => (
            <section key={section.heading}>
              <h2>{section.heading}</h2>
              {section.paragraphs?.map((paragraph) => <p key={paragraph}>{paragraph}</p>)}
              {section.bullets && (
                <ul>
                  {section.bullets.map((bullet) => <li key={bullet}>{bullet}</li>)}
                </ul>
              )}
            </section>
          ))}
        </div>

        {page.comparison && (
          <section className="content-comparison" aria-labelledby="comparison-table-title">
            <div>
              <p className="content-section-label">FACT TABLE</p>
              <h2 id="comparison-table-title">逐项对比</h2>
              <p>“未知”表示现有官方公开资料不足以支持确定结论，不代表功能一定不存在。</p>
            </div>
            <div className="content-table-wrap">
              <table>
                <thead>
                  <tr>
                    <th scope="col">项目</th>
                    <th scope="col">PinboardShot</th>
                    <th scope="col">{page.comparison.otherProduct}</th>
                  </tr>
                </thead>
                <tbody>
                  {page.comparison.rows.map((row) => (
                    <tr key={row.topic}>
                      <th scope="row">{row.topic}</th>
                      <td>{row.pinboardShot}</td>
                      <td>{row.other}</td>
                    </tr>
                  ))}
                </tbody>
              </table>
            </div>
          </section>
        )}

        <section className="content-cautions" aria-labelledby="content-cautions-title">
          <p className="content-section-label">BOUNDARIES</p>
          <h2 id="content-cautions-title">边界与限制</h2>
          <ul>
            {page.cautions.map((caution) => <li key={caution}>{caution}</li>)}
          </ul>
        </section>

        <section className="content-sources" aria-labelledby="content-sources-title">
          <div>
            <p className="content-section-label">PRIMARY SOURCES</p>
            <h2 id="content-sources-title">来源与核对口径</h2>
            <p>只列项目源码、仓库文档和被比较产品的官方公开页面。</p>
          </div>
          <ol>
            {page.sources.map((source) => (
              <li key={source.href}>
                <a href={source.href} target="_blank" rel="noreferrer">{source.label}<span aria-hidden="true">↗</span></a>
              </li>
            ))}
          </ol>
        </section>

        <section className="content-related" aria-labelledby="content-related-title">
          <p className="content-section-label">KEEP READING</p>
          <h2 id="content-related-title">继续了解</h2>
          <div>
            {relatedPages.map((related) => (
              <Link href={related.path} key={related.path}>
                <span>{related.categoryLabel}</span>
                <strong>{related.title}</strong>
                <small>查看详情 →</small>
              </Link>
            ))}
          </div>
        </section>
      </article>

      <section className="content-download">
        <div>
          <p className="eyebrow light"><span />PINBOARDSHOT FOR MAC</p>
          <h2>把需要核对的画面，留在工作现场。</h2>
          <p>免费、MIT 开源，Developer ID 签名并通过 Apple 公证。</p>
        </div>
        <Link className="button button-primary" href={DOWNLOAD_PATH}>下载 DMG<span aria-hidden="true">↓</span></Link>
      </section>

      <footer className="content-footer">
        <div className="footer-brand"><span className="brand-mark" aria-hidden="true"><i /><i /></span><div><strong>PinboardShot</strong><p>原生 macOS 截图、标注与贴图工具</p></div></div>
        <div className="footer-meta">
          <Link href="/">首页</Link>
          <a href={GITHUB_URL} target="_blank" rel="noreferrer">GitHub</a>
          <Link href="/privacy">隐私政策</Link>
        </div>
      </footer>
    </main>
  );
}
