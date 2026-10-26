"""Build the drag-to-Applications DMG without driving Finder or uploading assets."""

import argparse
import fcntl
from pathlib import Path
import subprocess
import tempfile


ROOT = Path(__file__).resolve().parents[1]


def verify_app_copy(mount_point, _settings):
    subprocess.run(
        ["codesign", "--verify", "--deep", "--strict", str(Path(mount_point) / "PinboardShot.app")],
        check=True,
    )


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("output", nargs="?", type=Path)
    parser.add_argument("--check-tools", action="store_true")
    arguments = parser.parse_args()
    try:
        import dmgbuild
    except ImportError:
        parser.exit(
            1,
            "DMG build tools are missing. Run:\n"
            "  python3 -m venv .build/dmg-tools\n"
            "  .build/dmg-tools/bin/python -m pip install -r scripts/requirements-dmg.txt\n",
        )
    if arguments.check_tools:
        return
    if arguments.output is None:
        parser.error("output is required unless --check-tools is used")
    output = arguments.output.resolve()
    if output.exists():
        parser.error(f"Refusing to overwrite an existing DMG: {output}")
    app = ROOT / ".build/app/PinboardShot.app"
    if not (app / "Contents/MacOS/PinboardShot").is_file():
        parser.error("Build .build/app/PinboardShot.app with scripts/build-app.sh first")
    output.parent.mkdir(parents=True, exist_ok=True)
    # Share build-app.sh's fcntl lock so another build cannot replace the signed
    # app while dmgbuild copies its bundle into the image.
    with (ROOT / ".build/app-build.lock").open("a") as build_lock, \
            tempfile.TemporaryDirectory(prefix="pinboardshot-dmg-", dir=ROOT / ".build") as temporary:
        fcntl.lockf(build_lock, fcntl.LOCK_EX)
        background = Path(temporary) / "background.png"
        subprocess.run(
            [
                "swift", "-module-cache-path", str(ROOT / ".build/dmg-tools/swift-module-cache"),
                str(ROOT / "scripts/dmg-background.swift"), str(background),
            ],
            check=True,
        )
        # dmgbuild writes Finder metadata directly, so the layout is reproducible
        # without Apple Events permissions or the user's Finder preferences.
        dmgbuild.build_dmg(
            str(output),
            "PinboardShot",
            settings={
                "format": "UDZO",
                "files": [str(app)],
                "symlinks": {"Applications": "/Applications"},
                # SetFile's hide-extension flag adds FinderInfo to the signed
                # bundle, which strict code-signing verification rejects.
                "hide_extensions": [],
                "create_hook": verify_app_copy,
                "background": str(background),
                "window_rect": ((160, 160), (720, 512)),
                "default_view": "icon-view",
                "show_status_bar": False,
                "show_tab_view": False,
                "show_toolbar": False,
                "show_pathbar": False,
                "show_sidebar": False,
                "arrange_by": None,
                "grid_spacing": 80,
                "icon_size": 112,
                "text_size": 14,
                "icon_locations": {
                    "PinboardShot.app": (190, 248),
                    "Applications": (530, 248),
                    # Keep the background out of the installation area even
                    # when the user enables Finder's Show Hidden Files option.
                    ".background.png": (1000, 80),
                },
                "include_icon_view_settings": True,
            },
        )
    print(output)


if __name__ == "__main__":
    main()
