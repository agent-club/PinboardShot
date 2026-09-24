import path from "node:path";
import { fileURLToPath } from "node:url";
import sharp from "sharp";

const website = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");
const icon = await sharp(path.join(website,"public/brand/mark.svg")).resize(160,160).png().toBuffer();
const art = await sharp(path.join(website,"public/showcase/chromatic.svg")).resize(820,590).png().toBuffer();
const fluid = await sharp(path.join(website,"public/showcase/fluid.svg")).resize(380,274).png().toBuffer();
const svg = `<svg xmlns="http://www.w3.org/2000/svg" width="1920" height="990" viewBox="0 0 1920 990">
<defs><radialGradient id="g"><stop stop-color="#193b81"/><stop offset="1" stop-color="#07080b"/></radialGradient><linearGradient id="t"><stop stop-color="#eef4ff"/><stop offset="1" stop-color="#5f8eff"/></linearGradient></defs>
<rect width="1920" height="990" fill="#07080b"/><ellipse cx="1370" cy="500" rx="670" ry="590" fill="url(#g)"/>
<image href="data:image/png;base64,${icon.toString('base64')}" x="90" y="85" width="110" height="110"/>
<g font-family="-apple-system, BlinkMacSystemFont, sans-serif"><text x="220" y="158" fill="#f1f5ff" font-size="55" font-weight="700">PinboardShot</text><text x="108" y="281" fill="#8aa5cf" font-size="21" letter-spacing="6">CAPTURE. ANNOTATE. LEVITATE.</text>
<text x="100" y="445" fill="#f5f7ff" font-size="112" font-weight="760">打破屏幕</text><text x="100" y="588" fill="url(#t)" font-size="112" font-weight="760">边界。</text><text x="108" y="698" fill="#a8b7d2" font-size="42">Beyond the screen.</text><text x="108" y="834" fill="#8498ba" font-size="26">原生 macOS · 本地优先 · 免费开源</text></g>
<ellipse cx="1370" cy="510" rx="430" ry="290" fill="none" stroke="#5a83e8" stroke-width="3" transform="rotate(-18 1370 510)"/>
<g transform="translate(1490 215) rotate(12)"><rect width="380" height="308" rx="16" fill="#1a263e" stroke="#607dae"/><image href="data:image/png;base64,${fluid.toString('base64')}" x="8" y="26" width="364" height="274"/></g>
<g transform="translate(922 290) rotate(-8)"><rect width="820" height="628" rx="20" fill="#1a263e" stroke="#82acff" stroke-width="2"/><image href="data:image/png;base64,${art.toString('base64')}" x="8" y="30" width="804" height="590"/></g></svg>`;
await sharp(Buffer.from(svg)).png({compressionLevel:9}).toFile(path.join(website,"public/og.png"));
console.log("Generated the electric-blue PinboardShot social image");
