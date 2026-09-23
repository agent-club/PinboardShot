import path from "node:path";
import { fileURLToPath } from "node:url";
import sharp from "sharp";

const scriptDirectory = path.dirname(fileURLToPath(import.meta.url));
const websiteDirectory = path.resolve(scriptDirectory, "..");
const photoPath = path.join(websiteDirectory, "public/showcase/lakeside-portrait.png");
const guardianPath = path.join(websiteDirectory, "public/brand/guardian.png");
const outputPath = path.join(websiteDirectory, "public/og.png");

const width = 1920;
const height = 990;
const photo = await sharp(photoPath).resize(900, 760, { fit: "cover" }).png().toBuffer();
const guardian = await sharp(guardianPath).resize(256, 256).png().toBuffer();
const photoData = `data:image/png;base64,${photo.toString("base64")}`;
const guardianData = `data:image/png;base64,${guardian.toString("base64")}`;

const svg = `
<svg xmlns="http://www.w3.org/2000/svg" width="${width}" height="${height}" viewBox="0 0 ${width} ${height}">
  <defs>
    <linearGradient id="paper" x1="0" y1="0" x2="1" y2="1">
      <stop stop-color="#FFFDF3"/>
      <stop offset=".55" stop-color="#F6F7EC"/>
      <stop offset="1" stop-color="#E8F0E3"/>
    </linearGradient>
    <linearGradient id="stage" x1="0" y1="0" x2="1" y2="1">
      <stop stop-color="#286B59"/>
      <stop offset="1" stop-color="#0D332C"/>
    </linearGradient>
    <filter id="shadow" x="-40%" y="-40%" width="180%" height="200%">
      <feDropShadow dx="0" dy="24" stdDeviation="25" flood-color="#14392C" flood-opacity=".20"/>
    </filter>
    <clipPath id="photoClip"><rect x="1097" y="294" width="563" height="435" rx="22"/></clipPath>
    <clipPath id="pinClip"><rect x="1485" y="476" width="265" height="280" rx="14"/></clipPath>
  </defs>

  <rect width="${width}" height="${height}" fill="url(#paper)"/>
  <circle cx="141" cy="138" r="302" fill="#F5DEA7" opacity=".22"/>
  <circle cx="878" cy="886" r="290" fill="#BBD9B5" opacity=".20"/>
  <path d="M0 860C323 788 620 906 921 823" fill="none" stroke="#D8E8D6" stroke-width="3"/>
  <path d="M0 890C323 818 620 936 921 853" fill="none" stroke="#FFFDF5" stroke-width="3"/>

  <image href="${guardianData}" x="110" y="104" width="116" height="116"/>
  <text x="250" y="181" fill="#173E31" font-family="-apple-system, BlinkMacSystemFont, sans-serif" font-size="67" font-weight="740">PinboardShot</text>
  <rect x="116" y="272" width="247" height="49" rx="24" fill="#E3EFE1"/>
  <circle cx="145" cy="297" r="8" fill="#E5A956"/>
  <text x="166" y="307" fill="#2A7657" font-family="-apple-system, BlinkMacSystemFont, 'PingFang SC', sans-serif" font-size="22" font-weight="660">为 macOS 精心打造</text>

  <text x="113" y="455" fill="#173E31" font-family="-apple-system, BlinkMacSystemFont, 'PingFang SC', sans-serif" font-size="106" font-weight="760">截图，然后</text>
  <text x="113" y="590" fill="#173E31" font-family="-apple-system, BlinkMacSystemFont, 'PingFang SC', sans-serif" font-size="106" font-weight="760">留在眼前。</text>
  <text x="120" y="686" fill="#5A7563" font-family="-apple-system, BlinkMacSystemFont, sans-serif" font-size="43" font-weight="560">Capture it. Keep it in sight.</text>
  <rect x="115" y="757" width="616" height="75" rx="37" fill="#1D6B51"/>
  <text x="156" y="807" fill="#FFFDF2" font-family="-apple-system, BlinkMacSystemFont, 'PingFang SC', sans-serif" font-size="28" font-weight="650">原生 macOS  ·  本地优先  ·  免费开源</text>

  <rect x="979" y="90" width="844" height="806" rx="64" fill="url(#stage)"/>
  <path d="M1037 267C1261 113 1554 135 1763 270" fill="none" stroke="#B3DDAC" stroke-opacity=".15" stroke-width="2"/>
  <path d="M1016 836C1236 723 1523 759 1781 654" fill="none" stroke="#B3DDAC" stroke-opacity=".12" stroke-width="2"/>
  <circle cx="1631" cy="242" r="257" fill="#F4CF88" opacity=".07"/>

  <g filter="url(#shadow)">
    <rect x="1058" y="234" width="641" height="534" rx="32" fill="#FFFDF5"/>
    <rect x="1058" y="234" width="641" height="60" rx="32" fill="#EFF4E9"/>
    <rect x="1058" y="263" width="641" height="31" fill="#EFF4E9"/>
    <circle cx="1093" cy="264" r="9" fill="#E9C791"/>
    <circle cx="1123" cy="264" r="9" fill="#A8CFAC"/>
    <circle cx="1153" cy="264" r="9" fill="#A8CFAC"/>
    <image href="${photoData}" x="1097" y="294" width="563" height="435" preserveAspectRatio="xMidYMid slice" clip-path="url(#photoClip)"/>
    <rect x="1158" y="351" width="338" height="297" rx="12" fill="#E9F5EA" fill-opacity=".14" stroke="#FDFEF6" stroke-width="7" stroke-dasharray="17 12"/>
    <circle cx="1158" cy="351" r="10" fill="#FFFDF5" stroke="#2E8466" stroke-width="5"/>
    <circle cx="1496" cy="351" r="10" fill="#FFFDF5" stroke="#2E8466" stroke-width="5"/>
    <circle cx="1158" cy="648" r="10" fill="#FFFDF5" stroke="#2E8466" stroke-width="5"/>
    <circle cx="1496" cy="648" r="10" fill="#FFFDF5" stroke="#2E8466" stroke-width="5"/>
  </g>

  <g transform="rotate(6 1618 604)" filter="url(#shadow)">
    <rect x="1454" y="403" width="327" height="393" rx="27" fill="#FFFDF3"/>
    <rect x="1454" y="403" width="327" height="73" rx="27" fill="#EEF4E9"/>
    <rect x="1454" y="444" width="327" height="32" fill="#EEF4E9"/>
    <circle cx="1483" cy="439" r="8" fill="#D8E3D5"/><circle cx="1511" cy="439" r="8" fill="#D8E3D5"/><circle cx="1539" cy="439" r="8" fill="#D8E3D5"/>
    <image href="${photoData}" x="1485" y="476" width="265" height="280" preserveAspectRatio="xMidYMid slice" clip-path="url(#pinClip)"/>
    <circle cx="1645" cy="400" r="28" fill="#F0B461"/>
    <path d="M1645 428V463" stroke="#B67542" stroke-width="10" stroke-linecap="round"/>
  </g>
  <image href="${guardianData}" x="1030" y="728" width="173" height="173"/>
</svg>`;

await sharp(Buffer.from(svg)).png({ compressionLevel: 9 }).toFile(outputPath);
console.log(`Generated ${outputPath}`);
