"use client";

import Image from "next/image";
import { useState, type CSSProperties } from "react";
import styles from "./magnetic-showcase.module.css";

type Language = "zh" | "en";
type Stage = "expanded" | "pinned" | "folded";

const photos = [
  { src: "/showcase/snow-mountain.jpg", time: "09:41" },
  { src: "/showcase/blossoms.jpg", time: "09:38" },
  { src: "/showcase/sunset.jpg", time: "09:32" },
  { src: "/showcase/lakeside-panel.jpg", time: "09:26" },
  { src: "/showcase/lakeside-portrait.png", time: "09:18" },
];

const copy = {
  zh: {
    eyebrow: "磁力桌面",
    title: <>随手展开，<br />用完收回。</>,
    intro: "最近的截图像磁铁一样收在桌边。展开扇面，抽出一张作为桌面参考；需要时再收回边缘，继续工作。",
    preview: "旁侧预览，让视线在扇面和工作之间轻松切换。",
    documentLabel: "工作区 / 设计评审",
    documentTitle: <>让细节<br />自然对齐。</>,
    documentBody: "把截图暂存在桌边，抽出需要的一张，和手头的页面并排对照。",
    documentTag: "参考  /  03",
    collection: "截图盒",
    collectionCount: "20 / 页",
    cardLabel: "示例截图",
    buttons: ["展开扇面", "抽出贴图", "收回桌边"],
    status: {
      expanded: "扇面已展开 · 点击一张截图，或抽出贴图",
      pinned: "一张截图已抽出，作为桌面参考 · 示例演示",
      folded: "磁吸已收回桌边 · 点击细线扇柄重新展开",
    },
    points: [
      ["扇子式收放", "展开看见最近截图，收回时轻轻叠成扇柄。"],
      ["抽出即可贴图", "从扇面取一张，放在工作内容旁边参考。"],
      ["截图盒渐进浏览", "扇面每组最多 10 张；截图盒按每页 20 张浏览。"],
    ],
    capacity: "默认容量 10 张 · 可设 1–100 张 · 每组最多 10 张",
    guide: "在「设置 → 贴图工作区 → 磁力桌面」开启。需要开启截图历史；默认关闭。无需账户，也不会上传截图。",
    pull: "点击截图，抽成桌面参考",
    foldedHandle: "展开磁吸",
  },
  en: {
    eyebrow: "Magnetic Desktop",
    title: <>Unfold a reference.<br />Fold it away.</>,
    intro: "Recent captures gather at the edge of your desktop. Open the fan, pull one out as a working reference, then fold the rest back when you’re ready to move on.",
    preview: "A side preview keeps your attention moving easily between the fan and your work.",
    documentLabel: "WORKSPACE / DESIGN REVIEW",
    documentTitle: <>Let the details<br />fall into place.</>,
    documentBody: "Keep screenshots at the edge, pull out the one you need, and compare it alongside the page you’re working on.",
    documentTag: "REFERENCE  /  03",
    collection: "SCREENSHOT BOX",
    collectionCount: "20 / PAGE",
    cardLabel: "Sample capture",
    buttons: ["Open the fan", "Pull out a pin", "Fold to the edge"],
    status: {
      expanded: "Fan open · Select a capture or pull out a pin",
      pinned: "One capture pulled out as a desktop reference · Demo",
      folded: "Magnet folded to the edge · Select the fan handle to reopen",
    },
    points: [
      ["Fan-like motion", "Open to browse recent captures; fold them into a slim edge handle."],
      ["Pull out a pin", "Take a capture from the fan and keep it beside your work."],
      ["Browse the screenshot box", "Up to 10 captures per fan group; the box shows 20 per page."],
    ],
    capacity: "10 captures by default · Set capacity from 1–100 · Up to 10 per group",
    guide: "Turn it on in Settings → Pin Workspaces → Magnetic Desktop. Screenshot history must be enabled. Off by default; no account or uploads required.",
    pull: "Select a capture to pull it out",
    foldedHandle: "Open magnetic desktop",
  },
} as const;

export function MagneticShowcase({ language }: { language: Language }) {
  const [stage, setStage] = useState<Stage>("expanded");
  const [selectedIndex, setSelectedIndex] = useState(2);
  const text = copy[language];

  function selectCapture(index: number) {
    setSelectedIndex(index);
    setStage("pinned");
  }

  return (
    <section
      className={styles.root}
      id="magnetic-desktop"
      aria-labelledby="magnetic-title"
      data-stage={stage}
    >
      <div className={styles.heading}>
        <div>
          <p className={styles.eyebrow}><span aria-hidden="true" />{text.eyebrow}</p>
          <h2 id="magnetic-title">{text.title}</h2>
        </div>
        <p className={styles.intro}>{text.intro}<span>{text.preview}</span></p>
      </div>

      <div className={styles.demo}>
        <div className={styles.desktopBar} aria-hidden="true">
          <span><i /> PinboardShot</span>
          <span>{text.documentLabel}</span>
          <span>REFERENCE</span>
        </div>

        <article className={styles.document} aria-label={text.documentLabel}>
          <span className={styles.documentIndex}>FIELD NOTES  /  024</span>
          <h3>{text.documentTitle}</h3>
          <p>{text.documentBody}</p>
          <span className={styles.documentRule} />
          <span className={styles.documentTag}>{text.documentTag}</span>
        </article>

        <div className={styles.fan} role="group" aria-label={text.pull}>
          {photos.map((photo, index) => (
            <button
              className={styles.capture}
              key={photo.src}
              type="button"
              style={{ "--fan-index": index } as CSSProperties}
              data-selected={selectedIndex === index}
              onClick={() => selectCapture(index)}
              aria-label={`${text.cardLabel} ${index + 1}, ${photo.time}`}
              aria-hidden={stage === "folded"}
              tabIndex={stage === "folded" ? -1 : undefined}
            >
              <Image src={photo.src} alt="" fill unoptimized sizes="(max-width: 700px) 150px, 190px" loading="lazy" />
              <span className={styles.timestamp}>{photo.time}</span>
            </button>
          ))}
          <button
            className={styles.fanHandle}
            type="button"
            onClick={() => setStage("expanded")}
            aria-label={text.foldedHandle}
            aria-hidden={stage !== "folded"}
            tabIndex={stage === "folded" ? undefined : -1}
          >
            <span /><span /><span /><span /><span />
          </button>
        </div>

        <div className={styles.collectionBox} aria-hidden={stage === "folded"}>
          <div className={styles.collectionLabel}><span>{text.collection}</span><span>{text.collectionCount}</span></div>
          <div className={styles.collectionThumbs} aria-hidden="true">
            {photos.slice(0, 4).map((photo) => <Image key={photo.src} src={photo.src} alt="" width={80} height={54} unoptimized loading="lazy" />)}
            <span>+8</span>
          </div>
        </div>
        <span className={styles.previewCaption}>{text.pull}</span>
      </div>

      <div className={styles.controls}>
        {text.buttons.map((label, index) => {
          const target: Stage = index === 0 ? "expanded" : index === 1 ? "pinned" : "folded";
          return (
            <button
              className={stage === target ? styles.activeControl : ""}
              type="button"
              key={label}
              aria-pressed={stage === target}
              onClick={() => setStage(target)}
            >
              <span aria-hidden="true">0{index + 1}</span>{label}
            </button>
          );
        })}
      </div>
      <p className={styles.status} aria-live="polite" aria-atomic="true">{text.status[stage]}</p>

      <div className={styles.details}>
        <div className={styles.points}>
          {text.points.map(([title, body], index) => (
            <article className={styles.point} key={title}>
              <span>0{index + 1}</span><div><h3>{title}</h3><p>{body}</p></div>
            </article>
          ))}
        </div>
        <div className={styles.setup}>
          <p>{text.capacity}</p>
          <p>{text.guide}</p>
        </div>
      </div>
    </section>
  );
}
