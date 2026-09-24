"use client";
import Image from "next/image";
import { useEffect, useRef, useState, useSyncExternalStore } from "react";
import type { SpatialController } from "./spatial-renderer";
const motionQuery = "(prefers-reduced-motion: reduce)";
const subscribeMotion = (notify: () => void) => {
    const media = window.matchMedia(motionQuery);
    media.addEventListener("change", notify);
    return () => media.removeEventListener("change", notify);
};
const readMotion = () => window.matchMedia(motionQuery).matches;
const serverMotion = () => true;
export function SpatialShowcase({ language }: {
    language: "zh" | "en";
}) {
    const host = useRef<HTMLDivElement>(null);
    const controller = useRef<SpatialController | null>(null);
    const [ready, setReady] = useState(false);
    const [expanded, setExpanded] = useState(true);
    const [userPaused, setUserPaused] = useState<boolean | null>(null);
    const reducedMotion = useSyncExternalStore(subscribeMotion, readMotion, serverMotion);
    const paused = userPaused ?? reducedMotion;
    const zh = language === "zh";
    const latest = useRef({ expanded, paused });
    useEffect(() => {
        latest.current = { expanded, paused };
        controller.current?.setExpanded(expanded);
        controller.current?.setPaused(paused);
    }, [expanded, paused]);
    useEffect(() => {
        const element = host.current;
        if (!element)
            return;
        let cancelled = false;
        // Load WebGL only on the client and keep the server-rendered artwork usable without it.
        import("./spatial-renderer").then(({ createSpatialRenderer }) => {
            if (cancelled)
                return;
            controller.current = createSpatialRenderer(element, () => { if (!cancelled)
                setReady(false); });
            controller.current.setExpanded(latest.current.expanded);
            controller.current.setPaused(latest.current.paused);
            setReady(true);
        }).catch(() => { if (!cancelled)
            setReady(false); });
        return () => {
            cancelled = true;
            controller.current?.dispose();
            controller.current = null;
        };
    }, []);
    return <div className="spatial-showcase">
    <div className={`spatial-scene${ready ? " is-ready" : ""}`} ref={host}>
      <div className="spatial-aura" aria-hidden="true"/>
      <span className="spatial-word" aria-hidden="true">UNFRAME.</span>
      <div className="spatial-poster"><Image unoptimized src="/showcase/chromatic.svg" alt={zh ? "电光蓝光影截图，悬浮在深色画布上" : "An electric-blue light study floating above a dark canvas"} width="1000" height="720"/></div>
      {ready && <button type="button" className="spatial-hit-area" aria-label={zh ? "切换卡片聚合与展开" : "Toggle stacked and floating cards"} onClick={() => setExpanded(value => !value)}/>}
      <div className="spatial-badge"><i />{expanded ? (zh ? "PIN / 自由悬浮" : "PIN / FREE TO FLOAT") : (zh ? "CAPTURE / 聚合成片" : "CAPTURE / ALL TOGETHER")}</div>
      <div className="spatial-caption"><span>LIVE / SPATIAL CANVAS</span><span>{zh ? "移动鼠标探索 · 点击场景切换形态" : "MOVE TO EXPLORE · CLICK TO REARRANGE"}</span></div>
    </div>
    {ready && <div className="spatial-controls">
      <span className="spatial-dot"/><span>{expanded ? (zh ? "自由悬浮" : "Free to float") : (zh ? "聚合成片" : "All together")}</span>
      <button type="button" onClick={() => setExpanded(value => !value)} aria-pressed={!expanded}>{expanded ? (zh ? "聚合成片" : "Bring together") : (zh ? "释放灵感" : "Set ideas free")} <span aria-hidden="true">↗</span></button>
      <button type="button" className="spatial-pause" onClick={() => setUserPaused(!paused)} aria-pressed={paused}>{paused ? (zh ? "播放动效" : "Play motion") : (zh ? "暂停动效" : "Pause motion")}</button>
    </div>}
  </div>;
}
