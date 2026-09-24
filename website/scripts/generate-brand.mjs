import { readFile, writeFile, mkdir, copyFile } from "node:fs/promises";
import { fileURLToPath } from "node:url";
import path from "node:path";
import sharp from "sharp";

const website = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");
const root = path.resolve(website, "..");
const iconSource = path.join(root, "Resources/AppIcon.svg");
const source = await readFile(iconSource);
const iconset = path.join(root, "Resources/Assets.xcassets/AppIcon.appiconset");
const manifest = JSON.parse(await readFile(path.join(iconset, "Contents.json"), "utf8"));
for (const image of manifest.images) {
  const pixels = Number(image.size.split("x")[0]) * Number(image.scale.replace("x", ""));
  await sharp(source).resize(pixels, pixels).png().toFile(path.join(iconset, image.filename));
}
await mkdir(path.join(website, "public/brand"), { recursive: true });
await copyFile(iconSource, path.join(website, "public/brand/mark.svg"));
for (const [filename, size] of [["app/icon.png",512],["app/apple-icon.png",180],["public/brand/guardian.png",256]]) {
  await sharp(source).resize(size,size).png().toFile(path.join(website,filename));
}
// ICO stores two PNG entries so the same vector stays sharp in small browser tabs.
const sizes = [16,32];
const entries = await Promise.all(sizes.map(size => sharp(source).resize(size,size).png().toBuffer()));
const header = Buffer.alloc(6+16*entries.length);
header.writeUInt16LE(1,2);header.writeUInt16LE(entries.length,4);
let offset = header.length;
entries.forEach((entry,index) => {
  const at = 6+index*16;
  header[at]=sizes[index];header[at+1]=sizes[index];
  header.writeUInt16LE(1,at+4);header.writeUInt16LE(32,at+6);
  header.writeUInt32LE(entry.length,at+8);header.writeUInt32LE(offset,at+12);offset+=entry.length;
});
await writeFile(path.join(website,"app/favicon.ico"),Buffer.concat([header,...entries]));
console.log(`Generated ${manifest.images.length} macOS icon sizes and website icons from Resources/AppIcon.svg`);
