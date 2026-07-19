import { readFile } from "node:fs/promises";
import path from "node:path";
import { fileURLToPath } from "node:url";

const scriptDirectory = path.dirname(fileURLToPath(import.meta.url));
const websiteDirectory = path.resolve(scriptDirectory, "..");
const applicationDirectory = path.resolve(websiteDirectory, "..");
const infoPlistPath = path.join(applicationDirectory, "Resources", "Info.plist");
const releasePath = path.join(websiteDirectory, "content", "current-release.json");

function readPlistString(plist, key) {
  const escapedKey = key.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
  const match = plist.match(new RegExp(`<key>${escapedKey}</key>\\s*<string>([^<]+)</string>`));

  if (!match) {
    throw new Error(`Missing ${key} in ${infoPlistPath}`);
  }

  return match[1].trim();
}

const [plist, releaseSource] = await Promise.all([
  readFile(infoPlistPath, "utf8"),
  readFile(releasePath, "utf8"),
]);
const release = JSON.parse(releaseSource);
const version = readPlistString(plist, "CFBundleShortVersionString");
const build = readPlistString(plist, "CFBundleVersion");

if (release.version !== version || release.build !== build) {
  console.error(
    `Website release metadata is ${release.version} (${release.build}); expected ${version} (${build}).`,
  );
  process.exit(1);
}

console.log(`Website release metadata matches PinboardShot ${version} (${build}).`);
