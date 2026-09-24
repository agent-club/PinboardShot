"use client";
import Image from "next/image";
import { useEffect, useRef, useState, type PointerEvent } from "react";
type Position = {
    x: number;
    y: number;
} | null;
const artwork = [
    { src: "/showcase/chromatic.svg", title: "Chromatic — 001", footer: "FORM FOLLOWS FEELING." },
    { src: "/showcase/fluid.svg", title: "Fluid — 002", footer: "CHROMATIC STUDY" },
];
export function PinWorkbench({ language }: {
    language: "zh" | "en";
}) {
    const zh = language === "zh";
    const bench = useRef<HTMLDivElement>(null);
    const pins = useRef<(HTMLElement | null)[]>([]);
    const drag = useRef<{
        index: number;
        pointerId: number;
        x: number;
        y: number;
        left: number;
        top: number;
    } | null>(null);
    const [positions, setPositions] = useState<Position[]>([null, null]);
    const [opacity, setOpacity] = useState(100);
    const [passthrough, setPassthrough] = useState(false);
    const [selected, setSelected] = useState(0);
    const [clicks, setClicks] = useState(0);
    function clamp(index: number, x: number, y: number) {
        const root = bench.current!;
        const pin = pins.current[index]!;
        return { x: Math.max(8, Math.min(root.clientWidth - pin.offsetWidth - 8, x)), y: Math.max(45, Math.min(root.clientHeight - pin.offsetHeight - 92, y)) };
    }
    function move(index: number, x: number, y: number) {
        const next = clamp(index, x, y);
        setPositions(previous => previous.map((position, i) => i === index ? next : position));
    }
    function start(event: PointerEvent<HTMLDivElement>, index: number) {
        if (passthrough || event.button !== 0)
            return;
        const pin = pins.current[index]!;
        event.currentTarget.setPointerCapture(event.pointerId);
        drag.current = { index, pointerId: event.pointerId, x: event.clientX, y: event.clientY, left: pin.offsetLeft, top: pin.offsetTop };
        setSelected(index);
        event.preventDefault();
    }
    function pointerMove(event: PointerEvent<HTMLDivElement>) {
        const current = drag.current;
        if (!current || current.pointerId !== event.pointerId)
            return;
        move(current.index, current.left + event.clientX - current.x, current.top + event.clientY - current.y);
    }
    function togglePassthrough() {
        const next = !passthrough;
        setPassthrough(next);
        if (next && bench.current) {
            // Put the example over the target so visitors can actually test click-through.
            setOpacity(45);
            move(0, bench.current.clientWidth * .06, bench.current.clientWidth < 500 ? 170 : 185);
        }
    }
    function reset() {
        setPositions([null, null]);
        setOpacity(100);
        setPassthrough(false);
        setClicks(0);
        setSelected(0);
    }
    useEffect(() => {
        const observer = new ResizeObserver(() => {
            setPositions(previous => previous.map((position, index) => position ? clamp(index, position.x, position.y) : null));
        });
        if (bench.current)
            observer.observe(bench.current);
        return () => observer.disconnect();
    }, []);
    return <div className="pin-demo">
    <div className="workbench" ref={bench}>
      <div className="desktop-top"><span><i />PinboardShot</span><span>{zh ? "灵感工作区 / 示例画布" : "YOUR WORKSPACE / SAMPLE CANVAS"}</span><span>⌘ ⇧ P</span></div>
      <div className="underlying">
        <div className="document-label">WORKSPACE / NO LIMITS</div><h3>KEEP YOUR<br />FLOW.</h3>
        <p>{zh ? <>把参考留在前景。<br />让专注回到创作。</> : <>Keep your references close.<br />Give your focus to your work.</>}</p>
        <button type="button" onClick={() => setClicks(value => value + 1)}>{zh ? "收下一点灵感" : "Save an idea"}<span aria-hidden="true">＋</span></button>
        <span aria-live="polite">{clicks ? (zh ? `${passthrough ? "已穿过贴图，" : ""}收下第 ${clicks} 个灵感。` : `${passthrough ? "Through the pin: " : ""}${clicks} idea${clicks === 1 ? "" : "s"} saved.`) : (zh ? "开启穿透后，可直接点击贴图下方的按钮" : "Enable click-through to press the button underneath a pin.")}</span>
      </div>
      <span className="background-word" aria-hidden="true">NO LIMITS.</span>
      {artwork.map((art, index) => <article key={art.src} ref={element => { pins.current[index] = element; }} className={`pin ${index === 0 ? "pin-main" : "pin-small"}${selected === index ? " selected" : ""}`} style={{ left: positions[index]?.x, top: positions[index]?.y, opacity: opacity / 100, pointerEvents: passthrough ? "none" : undefined, zIndex: selected === index ? 4 : 2 }} tabIndex={passthrough ? -1 : 0} aria-label={zh ? `示例贴图 ${index + 1}，拖动标题栏或按方向键移动` : `Sample pin ${index + 1}: drag its title bar or use arrow keys to move`} onKeyDown={event => {
                const directions: Record<string, [
                    number,
                    number
                ]> = { ArrowLeft: [-10, 0], ArrowRight: [10, 0], ArrowUp: [0, -10], ArrowDown: [0, 10] };
                const direction = directions[event.key];
                if (!direction || passthrough)
                    return;
                event.preventDefault();
                setSelected(index);
                move(index, event.currentTarget.offsetLeft + direction[0], event.currentTarget.offsetTop + direction[1]);
            }}>
        <div className="pin-bar" onPointerDown={event => start(event, index)} onPointerMove={pointerMove} onPointerUp={() => { drag.current = null; }} onPointerCancel={() => { drag.current = null; }} onLostPointerCapture={() => { drag.current = null; }}><span><i />{art.title}</span><span aria-hidden="true">↗</span></div>
        <Image unoptimized src={art.src} alt={zh ? "抽象蓝色设计示例" : "Abstract blue design sample"} width="1000" height="720" loading="lazy" draggable={false}/>
        <div className="pin-footer"><span>{art.footer}</span><span>0{index + 1}</span></div>
      </article>)}
      <div className="drag-hint">{passthrough ? (zh ? "穿透已开启 · 点击贴图下方的按钮" : "Click-through on · try the button underneath") : (zh ? "↔ 拖动标题栏，自由摆放" : "↔ Drag a title bar to move a pin")}</div>
      <div className="control-panel">
        <label htmlFor="pin-opacity">{zh ? "贴图透明度" : "Pin opacity"}</label><input id="pin-opacity" type="range" min="20" max="100" value={opacity} onChange={event => setOpacity(Number(event.target.value))}/><output htmlFor="pin-opacity">{opacity}%</output><span className="divider"/>
        <button type="button" role="switch" aria-checked={passthrough} onClick={togglePassthrough}><span className="switch" aria-hidden="true"><i /></span>{zh ? "鼠标穿透" : "Click-through"}</button>
        <button type="button" className="reset" onClick={reset}>↺ <span>{zh ? "重置" : "Reset"}</span></button>
      </div>
    </div>
    <div className="playground-foot"><span><i />{zh ? "网页交互示意，使用预置图片" : "Interactive web demo using sample artwork"}</span><span>{zh ? "无需权限 · 随心探索" : "No permissions needed · Explore freely"}</span></div>
  </div>;
}
