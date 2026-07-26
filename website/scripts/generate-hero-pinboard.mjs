import path from "node:path";
import { fileURLToPath } from "node:url";
import sharp from "sharp";

const scriptDirectory = path.dirname(fileURLToPath(import.meta.url));
const websiteDirectory = path.resolve(scriptDirectory, "..");
const showcaseDirectory = path.join(websiteDirectory, "public/showcase");
const outputPath = path.join(showcaseDirectory, "hero-pinboard.png");

async function photoData(filename, width, height, options = {}) {
  let image = sharp(path.join(showcaseDirectory, filename));

  if (options.extract) {
    image = image.extract(options.extract);
  }

  const buffer = await image
    .resize(width, height, {
      fit: "cover",
      position: options.position ?? "centre",
    })
    .modulate({
      brightness: options.brightness ?? 1,
      saturation: options.saturation ?? 1,
    })
    .png()
    .toBuffer();

  return `data:image/png;base64,${buffer.toString("base64")}`;
}

const [snow, blossom, sunset, lake] = await Promise.all([
  photoData("snow-mountain.jpg", 612, 314, {
    extract: { left: 703, top: 713, width: 897, height: 369 },
    brightness: 1.03,
    saturation: 0.88,
  }),
  photoData("blossoms.jpg", 562, 394, {
    brightness: 1.03,
    saturation: 0.88,
  }),
  photoData("sunset.jpg", 672, 394, {
    position: "centre",
    brightness: 1.03,
    saturation: 0.9,
  }),
  photoData("lakeside-panel.jpg", 592, 348, {
    brightness: 1.01,
    saturation: 0.9,
  }),
]);

const svg = `
<svg xmlns="http://www.w3.org/2000/svg" width="1440" height="980" viewBox="0 0 720 490">
  <defs>
    <filter id="shadow" x="-30%" y="-30%" width="160%" height="190%">
      <feDropShadow dx="0" dy="16" stdDeviation="13" flood-color="#424962" flood-opacity=".22"/>
    </filter>
    <clipPath id="snow-clip"><rect x="17" y="76" width="306" height="157" rx="15"/></clipPath>
    <clipPath id="blossom-clip"><rect x="397" y="50" width="281" height="197" rx="15"/></clipPath>
    <clipPath id="sunset-clip"><rect x="92" y="277" width="336" height="197" rx="15"/></clipPath>
    <clipPath id="lake-clip"><rect x="392" y="305" width="296" height="174" rx="15"/></clipPath>
  </defs>

  <g transform="rotate(-2.2 170 140)">
    <rect x="15" y="45" width="310" height="190" rx="20" fill="#ffffff"
          stroke="#d7deeb" stroke-width="1.5" filter="url(#shadow)"/>
    <image href="${snow}" x="17" y="76" width="306" height="157"
           preserveAspectRatio="xMidYMid slice" clip-path="url(#snow-clip)"/>
    <rect x="16.5" y="75.5" width="307" height="158" rx="15" fill="none"
          stroke="#d7deea" stroke-width="1"/>
    <circle cx="33" cy="61" r="5" fill="#ff625f"/>
    <circle cx="50" cy="61" r="5" fill="#ffbd44"/>
    <circle cx="67" cy="61" r="5" fill="#39c554"/>
  </g>

  <g transform="rotate(2 537 135)">
    <rect x="395" y="20" width="285" height="230" rx="20" fill="#ffffff"
          stroke="#d7deeb" stroke-width="1.5" filter="url(#shadow)"/>
    <image href="${blossom}" x="397" y="50" width="281" height="197"
           preserveAspectRatio="xMidYMid slice" clip-path="url(#blossom-clip)"/>
    <rect x="396.5" y="49.5" width="282" height="198" rx="15" fill="none"
          stroke="#d7deea" stroke-width="1"/>
    <circle cx="414" cy="35" r="5" fill="#ff625f"/>
    <circle cx="431" cy="35" r="5" fill="#ffbd44"/>
    <circle cx="448" cy="35" r="5" fill="#39c554"/>
  </g>

  <g transform="rotate(.7 260 360)">
    <rect x="90" y="245" width="340" height="230" rx="20" fill="#ffffff"
          stroke="#d7deeb" stroke-width="1.5" filter="url(#shadow)"/>
    <image href="${sunset}" x="92" y="277" width="336" height="197"
           preserveAspectRatio="xMidYMid slice" clip-path="url(#sunset-clip)"/>
    <rect x="91.5" y="276.5" width="337" height="198" rx="15" fill="none"
          stroke="#d7deea" stroke-width="1"/>
    <circle cx="109" cy="261" r="5" fill="#ff625f"/>
    <circle cx="126" cy="261" r="5" fill="#ffbd44"/>
    <circle cx="143" cy="261" r="5" fill="#39c554"/>
  </g>

  <g transform="rotate(-1.2 540 377)">
    <rect x="390" y="275" width="300" height="205" rx="20" fill="#ffffff"
          stroke="#d7deeb" stroke-width="1.5" filter="url(#shadow)"/>
    <image href="${lake}" x="392" y="305" width="296" height="174"
           preserveAspectRatio="xMidYMid slice" clip-path="url(#lake-clip)"/>
    <rect x="391.5" y="304.5" width="297" height="175" rx="15" fill="none"
          stroke="#d7deea" stroke-width="1"/>
    <circle cx="409" cy="290" r="5" fill="#ff625f"/>
    <circle cx="426" cy="290" r="5" fill="#ffbd44"/>
    <circle cx="443" cy="290" r="5" fill="#39c554"/>
  </g>
</svg>`;

await sharp(Buffer.from(svg))
  .png({ compressionLevel: 9 })
  .toFile(outputPath);

console.log(`Generated ${outputPath}`);
