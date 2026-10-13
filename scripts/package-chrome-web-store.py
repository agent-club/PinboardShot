#!/usr/bin/env python3
"""Build a Chrome Web Store ZIP from the development extension files."""

import hashlib
import json
from pathlib import Path
from zipfile import ZIP_DEFLATED, ZipFile, ZipInfo


ROOT = Path(__file__).resolve().parents[1]
EXTENSION = ROOT / "browser-extension"
OUTPUT = ROOT / ".build" / "chrome-web-store"
FILES = (
    "manifest.json",
    "background.js",
    "capture.js",
    "popup.html",
    "popup.js",
    "popup.css",
    "lib/planner.mjs",
    "lib/native-protocol.mjs",
    "lib/native-client.mjs",
    "lib/browser-image.mjs",
    "lib/browser-download.mjs",
    "icons/icon16.png",
    "icons/icon32.png",
    "icons/icon48.png",
    "icons/icon128.png",
    "icons/capture-scene.png",
    "icons/ui-pause.svg",
    "icons/ui-play.svg",
    "icons/ui-stop.svg",
    "icons/ui-check.svg",
    "icons/ui-x.svg",
    "icons/ui-warning-circle.svg",
    "icons/ui-scan.svg",
    "icons/ui-arrow-right.svg",
    "icons/Phosphor-LICENSE.txt",
)


def main() -> None:
    manifest = json.loads((EXTENSION / "manifest.json").read_text())
    # The source key keeps the unpacked development ID stable. The dashboard
    # rejects that field when creating a new store item, so strip it in the ZIP.
    manifest.pop("key", None)
    referenced = {
        manifest["background"]["service_worker"],
        manifest["side_panel"]["default_path"],
        *manifest["icons"].values(),
        *manifest["action"]["default_icon"].values(),
    }
    if not referenced.issubset(FILES):
        raise ValueError(f"Unpackaged manifest references: {sorted(referenced - set(FILES))}")

    OUTPUT.mkdir(parents=True, exist_ok=True)
    destination = OUTPUT / f"PinboardShot-Browser-Capture-{manifest['version']}-store.zip"
    with ZipFile(destination, "w", compression=ZIP_DEFLATED, compresslevel=9) as archive:
        for name in FILES:
            source = EXTENSION / name
            if not source.is_file() or source.is_symlink():
                raise ValueError(f"Missing or unsafe extension file: {name}")
            data = (
                (json.dumps(manifest, ensure_ascii=False, indent=2) + "\n").encode()
                if name == "manifest.json"
                else source.read_bytes()
            )
            info = ZipInfo(name, date_time=(2026, 1, 1, 0, 0, 0))
            info.compress_type = ZIP_DEFLATED
            info.external_attr = 0o644 << 16
            archive.writestr(info, data)
    with ZipFile(destination) as archive:
        if archive.testzip() is not None or archive.namelist() != list(FILES):
            raise ValueError("Generated ZIP failed validation")
        if "key" in json.loads(archive.read("manifest.json")):
            raise ValueError("Store manifest contains a development key")

    print(destination)
    print(f"SHA-256 {hashlib.sha256(destination.read_bytes()).hexdigest()}")


if __name__ == "__main__":
    main()
