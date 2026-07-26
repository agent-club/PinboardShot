import path from "node:path";
import { fileURLToPath } from "node:url";
import sharp from "sharp";

const scriptDirectory = path.dirname(fileURLToPath(import.meta.url));
const websiteDirectory = path.resolve(scriptDirectory, "..");
const sourcePath = path.join(
  websiteDirectory,
  "public/showcase/lakeside-portrait.png",
);
const outputPath = path.join(websiteDirectory, "public/og.png");

const width = 1920;
const height = 990;

const photo = await sharp(sourcePath)
  .resize(720, 900, { fit: "cover", position: "centre" })
  .png()
  .toBuffer();
const photoData = `data:image/png;base64,${photo.toString("base64")}`;

const svg = `
<svg xmlns="http://www.w3.org/2000/svg" width="${width}" height="${height}" viewBox="0 0 ${width} ${height}">
  <defs>
    <linearGradient id="background" x1="0" y1="0" x2="1" y2="1">
      <stop offset="0" stop-color="#ffffff"/>
      <stop offset=".54" stop-color="#fbfbff"/>
      <stop offset="1" stop-color="#f4f0ff"/>
    </linearGradient>
    <radialGradient id="blueGlow" cx="0" cy="1" r="1">
      <stop offset="0" stop-color="#d9e8ff" stop-opacity=".92"/>
      <stop offset=".55" stop-color="#edf4ff" stop-opacity=".34"/>
      <stop offset="1" stop-color="#ffffff" stop-opacity="0"/>
    </radialGradient>
    <radialGradient id="purpleGlow" cx="1" cy="1" r="1">
      <stop offset="0" stop-color="#b77cff" stop-opacity=".48"/>
      <stop offset=".44" stop-color="#dbc9ff" stop-opacity=".28"/>
      <stop offset="1" stop-color="#ffffff" stop-opacity="0"/>
    </radialGradient>
    <linearGradient id="beam" x1="0" y1="0" x2="1" y2=".7">
      <stop offset="0" stop-color="#d4c9ff" stop-opacity="0"/>
      <stop offset=".44" stop-color="#d9d0ff" stop-opacity=".36"/>
      <stop offset="1" stop-color="#c7b4ff" stop-opacity="0"/>
    </linearGradient>
    <filter id="windowShadow" x="-40%" y="-40%" width="180%" height="200%">
      <feDropShadow dx="0" dy="18" stdDeviation="18" flood-color="#6f72a8" flood-opacity=".22"/>
    </filter>
    <filter id="pinShadow" x="-50%" y="-40%" width="200%" height="220%">
      <feDropShadow dx="0" dy="34" stdDeviation="28" flood-color="#7250dc" flood-opacity=".38"/>
    </filter>
    <filter id="toolbarShadow" x="-40%" y="-60%" width="180%" height="240%">
      <feDropShadow dx="0" dy="18" stdDeviation="14" flood-color="#292d4c" flood-opacity=".28"/>
    </filter>
    <clipPath id="selectionClip">
      <rect x="816" y="410" width="274" height="314" rx="5"/>
    </clipPath>
    <clipPath id="windowClip">
      <rect x="1178" y="391" width="292" height="364" rx="12"/>
    </clipPath>
    <clipPath id="pinClip">
      <rect x="1550" y="237" width="330" height="430" rx="17"/>
    </clipPath>
  </defs>

  <rect width="${width}" height="${height}" fill="url(#background)"/>
  <rect width="780" height="520" y="470" fill="url(#blueGlow)"/>
  <rect x="1100" y="290" width="820" height="700" fill="url(#purpleGlow)"/>

  <path d="M1035 450 C1260 390 1495 282 1918 258 L1918 354 C1510 371 1280 436 1065 514 Z"
        fill="url(#beam)"/>
  <path d="M1010 525 C1285 488 1525 398 1920 404 L1920 476 C1530 462 1270 535 1030 575 Z"
        fill="#d9d3ff" opacity=".16"/>

  <g fill="#061333">
    <text x="62" y="383" font-family="-apple-system, BlinkMacSystemFont, 'SF Pro Display', sans-serif"
          font-size="88" font-weight="740" letter-spacing="0">PinboardShot</text>
    <text x="62" y="525" font-family="-apple-system, BlinkMacSystemFont, 'PingFang SC', sans-serif"
          font-size="70" font-weight="750" letter-spacing="0">截图、标注、贴屏，</text>
    <text x="62" y="622" font-family="-apple-system, BlinkMacSystemFont, 'PingFang SC', sans-serif"
          font-size="70" font-weight="750" letter-spacing="0">一气呵成。</text>
    <text x="62" y="705" fill="#3e4965"
          font-family="-apple-system, BlinkMacSystemFont, 'PingFang SC', sans-serif"
          font-size="32" font-weight="450" letter-spacing="0">原生 macOS 工具 · 纯本地运行</text>
  </g>

  <g opacity=".92">
    <path d="M15 806 C210 680 330 916 548 848 S760 715 965 748"
          fill="none" stroke="#d9e8ff" stroke-width="4"/>
    <path d="M15 840 C214 724 334 954 556 878 S785 731 1010 775"
          fill="none" stroke="#ffffff" stroke-width="3"/>
  </g>

  <g filter="url(#windowShadow)">
    <rect x="816" y="410" width="274" height="314" rx="5" fill="#ffffff"/>
    <image href="${photoData}" x="816" y="410" width="274" height="314"
           preserveAspectRatio="xMidYMid slice" clip-path="url(#selectionClip)"/>
  </g>

  <g fill="none" stroke="#4d83ff" stroke-width="3">
    <rect x="806" y="400" width="294" height="334" rx="4" stroke-dasharray="13 11"/>
    <rect x="798" y="392" width="20" height="20" rx="4" fill="#ffffff"/>
    <rect x="1088" y="392" width="20" height="20" rx="4" fill="#ffffff"/>
    <rect x="798" y="722" width="20" height="20" rx="4" fill="#ffffff"/>
    <rect x="1088" y="722" width="20" height="20" rx="4" fill="#ffffff"/>
  </g>

  <g filter="url(#windowShadow)">
    <rect x="1162" y="342" width="324" height="430" rx="18" fill="#ffffff"
          stroke="#dce4f4" stroke-width="3"/>
    <image href="${photoData}" x="1178" y="391" width="292" height="364"
           preserveAspectRatio="xMidYMid slice" clip-path="url(#windowClip)"/>
    <rect x="1178" y="391" width="292" height="364" rx="12" fill="none"
          stroke="#d7dfef" stroke-width="2"/>
    <circle cx="1190" cy="367" r="8" fill="#ff625f"/>
    <circle cx="1217" cy="367" r="8" fill="#ffbd44"/>
    <circle cx="1244" cy="367" r="8" fill="#39c554"/>
  </g>

  <g fill="none" stroke="#ff7267" stroke-width="7" stroke-linecap="round" stroke-linejoin="round">
    <rect x="1222" y="503" width="96" height="69"/>
    <path d="M1342 492 L1401 428 M1401 428 L1393 458 M1401 428 L1372 439"/>
    <path d="M1380 639 H1423"/>
  </g>
  <text x="1385" y="632" fill="#ff7267"
        font-family="Georgia, serif" font-size="62" font-weight="700">T</text>

  <g transform="rotate(-2 1715 430)" filter="url(#pinShadow)">
    <rect x="1528" y="166" width="374" height="536" rx="22"
          fill="#fbfcff" stroke="#cfdcf7" stroke-width="3"/>
    <image href="${photoData}" x="1550" y="237" width="330" height="430"
           preserveAspectRatio="xMidYMid slice" clip-path="url(#pinClip)"/>
    <rect x="1550" y="237" width="330" height="430" rx="17" fill="none"
          stroke="#d7dfef" stroke-width="2"/>
    <g transform="translate(1562 188) rotate(-38 16 16)" fill="#704df6">
      <rect x="7" y="3" width="18" height="8" rx="2.5"/>
      <path d="M10 10 H22 L20 18 L25 22 V24 H7 V22 L12 18 Z"/>
      <path d="M14.5 23 H17.5 L16 35 Z"/>
    </g>
    <path d="M1870 192 L1889 211 M1889 192 L1870 211"
          fill="none" stroke="#59647f" stroke-width="4" stroke-linecap="round"/>

    <g fill="none" stroke="#ff7267" stroke-width="8" stroke-linecap="round" stroke-linejoin="round">
      <rect x="1611" y="396" width="112" height="82"/>
      <path d="M1764 365 L1832 291 M1832 291 L1825 323 M1832 291 L1801 301"/>
      <path d="M1798 550 H1845"/>
    </g>
    <text x="1803" y="542" fill="#ff7267"
          font-family="Georgia, serif" font-size="70" font-weight="700">T</text>
  </g>

  <g filter="url(#toolbarShadow)">
    <path d="M737 756 H916 L936 735 L956 756 H1136 Q1152 756 1152 772 V831 Q1152 848 1135 848 H737 Q720 848 720 831 V773 Q720 756 737 756 Z"
          fill="#171b2b"/>
    <rect x="756" y="783" width="34" height="34" rx="5" fill="none"
          stroke="#f4f6ff" stroke-width="3" stroke-dasharray="7 6"/>
    <rect x="832" y="782" width="38" height="38" fill="none"
          stroke="#f4f6ff" stroke-width="4"/>
    <path d="M909 817 L951 775 M951 775 L944 798 M951 775 L928 782"
          fill="none" stroke="#f4f6ff" stroke-width="5" stroke-linecap="round" stroke-linejoin="round"/>
    <text x="992" y="821" fill="#ff7267"
          font-family="Georgia, serif" font-size="58" font-weight="700">T</text>
    <circle cx="1106" cy="802" r="22" fill="#ff7267"/>
  </g>
</svg>`;

await sharp(Buffer.from(svg)).png({ compressionLevel: 9 }).toFile(outputPath);
console.log(`Generated ${outputPath}`);
