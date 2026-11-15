#!/usr/bin/env python3
"""Fail if the repository or a release ZIP contains anything from the game itself.

    python3 scripts/check_no_game_files.py              # files tracked by git
    python3 scripts/check_no_game_files.py --zip X.zip  # a release archive

The game is paid. A built game, its data file, its decompiled project or its
media must never end up in this repository or in a release.
"""
from __future__ import annotations

import argparse
import os
import subprocess
import sys
import zipfile
from pathlib import PurePosixPath

FORBIDDEN_SUFFIXES = {
    ".exe", ".pck", ".dll", ".so", ".dylib", ".dmg", ".tpz",
    ".ogv", ".ogg", ".wav", ".mp3", ".mp4", ".webm",
    ".ttf", ".otf", ".tres", ".res", ".scn", ".gdc", ".import", ".ctex", ".icns",
}
FORBIDDEN_PARTS = {"work", ".cache", ".godot", "install_logs", "recovered", "game-source"}
SCREENSHOT_DIR = "docs/screenshots"
IMAGE_SUFFIXES = {".png", ".jpg", ".jpeg", ".gif", ".webp"}
MAX_BYTES = 2 * 1024 * 1024


def problems(entries: list[tuple[str, int]]) -> list[str]:
    found = []
    for name, size in entries:
        path = PurePosixPath(name)
        suffix = path.suffix.lower()
        if suffix in FORBIDDEN_SUFFIXES:
            found.append(f"{name}: {suffix} files are game or media files")
        elif set(path.parts) & FORBIDDEN_PARTS or any(part.endswith(".app") for part in path.parts):
            found.append(f"{name}: inside a build or decompiled-project folder")
        elif suffix in IMAGE_SUFFIXES and SCREENSHOT_DIR not in name:
            found.append(f"{name}: images belong in {SCREENSHOT_DIR}")
        elif size > MAX_BYTES:
            found.append(f"{name}: {size // 1024} KB is larger than anything this project ships")
    return found


def tracked_files() -> list[tuple[str, int]]:
    names = subprocess.run(["git", "ls-files", "-z"], check=True, capture_output=True).stdout.decode().split("\0")
    return [(name, os.path.getsize(name) if os.path.exists(name) else 0) for name in names if name]


def zip_entries(path: str) -> list[tuple[str, int]]:
    with zipfile.ZipFile(path) as archive:
        return [(info.filename, info.file_size) for info in archive.infolist() if not info.is_dir()]


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--zip", help="check this release ZIP instead of the git checkout")
    args = parser.parse_args()
    entries = zip_entries(args.zip) if args.zip else tracked_files()
    found = problems(entries)
    for line in found:
        print(f"NOT ALLOWED: {line}")
    print(f"checked {len(entries)} files: {'FAILED' if found else 'no game files found'}")
    return 1 if found else 0


if __name__ == "__main__":
    sys.exit(main())
