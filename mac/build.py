#!/usr/bin/env python3
"""Build an unofficial local macOS app from the user's own Windows game."""
from __future__ import annotations

import argparse
import hashlib
import importlib.util
import io
import json
import os
import plistlib
import re
import shutil
import subprocess
import sys
import tempfile
import time
import urllib.request
import zipfile
from pathlib import Path

VERSION = "0.5.3"
ROOT = Path(__file__).resolve().parent
REPO = ROOT.parent  # tcv-mods: mods/, exporter/ and install_mod.py live here
CACHE = Path.home() / "Library/Caches/tcv-mods"
ITCH = "https://yeahmaybe.itch.io/the-choicer-voicer"
# Official builds only, pinned by SHA-256. Downloaded once into CACHE.
GODOT_URL = "https://github.com/godotengine/godot-builds/releases/download/4.4.1-stable/"
GODOT = (GODOT_URL + "Godot_v4.4.1-stable_macos.universal.zip",
         "6c670596d21afb7917c739d0b85b10b4ac6a44051ffa2a672f90bc7da5062864")
TEMPLATES = GODOT_URL + "Godot_v4.4.1-stable_export_templates.tpz"
MACOS_TEMPLATE_SHA = "1e955db74f0d012f379efaf1b526be3b32ae5be675868dc4ead86b807212474d"
GDRE = ("https://github.com/GDRETools/gdsdecomp/releases/download/v2.6.3/GDRE_tools-v2.6.3-macos.zip",
        "61268c5d47d6fb48a28bf3fcf3c3e9ad44c7e99e0f4d3c2a19db74cf10bd4321")


def mod_version() -> str:
    found = re.search(r'MOD_VERSION: String = "([^"]+)"', (REPO / "mods/multiplayer/net/net_manager.gd").read_text())
    return found[1] if found else "unknown"


class HttpFile(io.RawIOBase):
    """Seekable read-only view of a URL using Range requests, so zipfile can pull
    the macOS template out of the 1 GB templates archive without downloading it all."""

    def __init__(self, url: str):
        with urllib.request.urlopen(urllib.request.Request(url, method="HEAD")) as response:
            self.url, self.size = response.url, int(response.headers["Content-Length"])
        self.pos = 0

    def seekable(self): return True
    def readable(self): return True
    def tell(self): return self.pos

    def seek(self, offset, whence=0):
        self.pos = {0: offset, 1: self.pos + offset, 2: self.size + offset}[whence]
        return self.pos

    def readinto(self, buffer):
        if self.pos >= self.size or not len(buffer):
            return 0
        end = min(self.pos + len(buffer), self.size) - 1
        request = urllib.request.Request(self.url, headers={"Range": f"bytes={self.pos}-{end}"})
        with urllib.request.urlopen(request) as response:
            data = response.read()
        buffer[:len(data)] = data
        self.pos += len(data)
        return len(data)


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for block in iter(lambda: stream.read(1 << 20), b""):
            digest.update(block)
    return digest.hexdigest()


def fetch(url: str, digest: str, target: Path, what: str) -> Path:
    if not (target.exists() and sha256(target) == digest):
        print(f"  Downloading {what}", flush=True)
        part = target.with_name(target.name + ".part")
        with urllib.request.urlopen(url) as response, part.open("wb") as output:
            shutil.copyfileobj(response, output, 1 << 20)
        if sha256(part) != digest:
            part.unlink()
            raise RuntimeError(f"The download of {what} didn't match its checksum, so it wasn't used. Try again.")
        part.replace(target)
    return target


def fetch_macos_template(target: Path) -> Path:
    if not (target.exists() and sha256(target) == MACOS_TEMPLATE_SHA):
        print("  Downloading the Godot 4.4.1 Mac template (about 115 MB, not the whole 1 GB archive)", flush=True)
        part = target.with_name(target.name + ".part")
        with zipfile.ZipFile(io.BufferedReader(HttpFile(TEMPLATES), 1 << 22)) as archive:
            with archive.open("templates/macos.zip") as source, part.open("wb") as output:
                shutil.copyfileobj(source, output, 1 << 20)
        if sha256(part) != MACOS_TEMPLATE_SHA:
            part.unlink()
            raise RuntimeError("The Godot Mac template didn't match its checksum, so it wasn't used. Try again.")
        part.replace(target)
    return target


def unpack(archive: Path, target: Path) -> Path:
    if not target.exists():
        temporary = target.with_name(target.name + ".tmp")
        shutil.rmtree(temporary, ignore_errors=True)
        subprocess.run(["ditto", "-x", "-k", str(archive), str(temporary)], check=True)  # keeps permissions and symlinks
        temporary.replace(target)
    return target


def ask(question: str) -> str:
    if not sys.stdin.isatty():
        return ""
    try:
        return input(question).strip()
    except EOFError:
        return ""


def dropped_path(text: str) -> Path:
    """A file dragged onto Terminal arrives quoted or with backslash-escaped spaces."""
    text = text.strip()
    if len(text) > 1 and text[0] == text[-1] and text[0] in "'\"":
        text = text[1:-1]
    return Path(re.sub(r"\\(.)", r"\1", text)).expanduser()


def find_game(folders: list[Path]) -> Path | None:
    """The newest 0.5.3 download from itch.io: its ZIP or the standard exe."""
    found = []
    for folder in folders:
        if folder.is_dir():
            for path in folder.iterdir():
                name = path.name.lower().replace(" ", "")
                if "choicervoicer" in name and re.search(r"0[._-]5[._-]3", name) and (
                        name.endswith(".zip") or (name.endswith(".exe") and "standard" in name)):
                    found.append(path)
    return max(found, key=lambda path: path.stat().st_mtime) if found else None


def locate_game(selected: Path | None) -> Path:
    if selected:
        return selected
    game = find_game([Path.home() / "Downloads", Path.home() / "Desktop"])
    if game:
        print(f"Using your game download: {game}")
        return game
    if not sys.stdin.isatty():
        raise ValueError(f"Game download not found in Downloads. Pass its path: the ZIP of 0.5.3 for Windows from {ITCH}")
    print(f"\nYour game download wasn't found in Downloads. Get 0.5.3 for Windows from your itch.io library:\n  {ITCH}\n"
          "Then drag the downloaded ZIP onto this window and press Enter.")
    answer = ask("Game ZIP (or q to cancel): ")
    if not answer or answer.lower() == "q":
        raise ValueError("Cancelled. Nothing was changed.")
    return dropped_path(answer)


def install_app(app: Path, output: Path, replace: bool) -> None:
    """Move the new app into place. An old one goes to the Trash only once the
    new one is ready, and comes back if the swap fails."""
    with tempfile.TemporaryDirectory(prefix=".tcv-install-", dir=output.parent) as scratch:
        staged = Path(scratch) / output.name
        shutil.move(str(app), staged)
        backup = None
        if output.exists():
            if not replace:
                raise ValueError("An app appeared at the destination during the build; it was kept")
            trash = Path.home() / ".Trash"
            trash.mkdir(exist_ok=True)
            backup = trash / f"{output.stem} {time.strftime('%Y-%m-%d %H.%M.%S')}.app"
            output.rename(backup)
        try:
            staged.rename(output)
        except BaseException:
            if backup:
                backup.rename(output)
            raise
        if backup:
            print(f"The old app is in the Trash: {backup.name}")


def tool_path(value: Path, name: str) -> Path:
    path = value.expanduser().resolve()
    if path.suffix == ".app":
        path = path / "Contents" / "MacOS" / name
    if not path.is_file() or not os.access(path, os.X_OK):
        raise ValueError(f"Executable not found: {path}")
    return path


def run(arguments: list[str], log: Path) -> None:
    with log.open("ab") as stream:
        stream.write(("\n$ " + " ".join(arguments) + "\n").encode())
        result = subprocess.run(arguments, stdout=stream, stderr=subprocess.STDOUT)
    if result.returncode:
        raise RuntimeError(f"Build step failed ({result.returncode}); see {log}")


def unpack_game(game: Path, destination: Path) -> Path:
    if not game.is_file():
        raise ValueError(f"Supply your purchased Windows exe or ZIP: {game}")
    if game.suffix.lower() == ".zip":
        with zipfile.ZipFile(game) as archive:
            choices = [entry for entry in archive.infolist()
                       if entry.filename.lower().endswith(".exe")
                       and "standard" in Path(entry.filename).name.lower()]
            if len(choices) != 1:
                raise ValueError("ZIP must contain exactly one standard Windows game exe")
            # Read only the chosen member into a fixed destination; never extract paths.
            target = destination / "owned-game.exe"
            with archive.open(choices[0]) as source, target.open("wb") as output:
                shutil.copyfileobj(source, output)
    else:
        target = game
    with target.open("rb") as stream:
        if stream.read(2) != b"MZ":
            raise ValueError("The selected input is not a Windows executable")
    return target


def repair_paths(project: Path) -> int:
    # GDRE sometimes inserts spaces around shorthand node-path separators.
    pattern = re.compile(r'(\$%?[A-Za-z_]\w*)((?:\s*/\s*%?[A-Za-z_]\w*)+)')
    repaired = 0
    for path in project.rglob("*.gd"):
        text = path.read_text(encoding="utf-8-sig")
        fixed = pattern.sub(lambda match: match[1] + re.sub(r"\s*/\s*", "/", match[2]), text)
        if fixed != text:
            path.write_text(fixed, encoding="utf-8")
            repaired += 1
    return repaired


def apply_mod(project: Path, repository: Path, features: list[str] | None) -> list[str]:
    installer = repository.resolve() / "install_mod.py"
    if not installer.is_file():
        raise ValueError(f"Mod installer not found: {installer}")
    spec = importlib.util.spec_from_file_location("local_tcv_mod", installer)
    if spec is None or spec.loader is None:
        raise ValueError("Could not load the local mod installer")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module.apply_mod(project, features)


def app_metadata(source: dict, icon: str) -> dict:
    result = source.copy()
    for key in ["CFBundleDocumentTypes", "UTExportedTypeDeclarations", "UTImportedTypeDeclarations", "CFBundleURLTypes"]:
        result.pop(key, None)
    result.update({
        "CFBundleIdentifier": "dev.zeriax.tcv.local",
        "CFBundleName": "The Choicer Voicer",
        "CFBundleDisplayName": "The Choicer Voicer",
        "CFBundleExecutable": source.get("CFBundleExecutable", "ChoicerVoicer"),
        "CFBundleIconFile": icon,
        "CFBundleShortVersionString": VERSION,
        "CFBundleVersion": "1",
        "LSApplicationCategoryType": "public.app-category.games",
        "NSMicrophoneUsageDescription": "Record your voice for The Choicer Voicer.",
        # App Nap throttles a background game to a crawl: pack downloads fell from
        # ~14 MB/s to ~0.5 MB/s and online sessions stop answering in time.
        "NSAppSleepDisabled": True,
    })
    return result


def macos_template(archive_path: Path, work: Path) -> Path:
    """Accept an official templates archive or its macos.zip member."""
    archive_path = archive_path.expanduser().resolve()
    with zipfile.ZipFile(archive_path) as archive:
        if "templates/macos.zip" in archive.namelist():
            target = work / "macos.zip"
            with archive.open("templates/macos.zip") as source, target.open("wb") as output:
                shutil.copyfileobj(source, output)
        else:
            target = archive_path
    with zipfile.ZipFile(target) as archive:
        if not any(name.endswith("/Contents/MacOS/godot_macos_release.universal")
                   for name in archive.namelist()):
            raise ValueError("Supply Godot 4.4.1 export templates containing the macOS release runtime")
    return target


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("game", type=Path, nargs="?", help="Your 0.5.3 Windows ZIP or standard exe from itch.io (found in Downloads if left out)")
    parser.add_argument("--godot", type=Path, help="Godot 4.4.1 .app or executable (downloaded if left out)")
    parser.add_argument("--gdre", type=Path, help="GDRETools 2.6.3 .app or executable (downloaded if left out)")
    parser.add_argument("--templates", type=Path, help="Godot 4.4.1 export templates .tpz or macos.zip (downloaded if left out)")
    parser.add_argument("--features", help="comma-separated: community-packs,multiplayer,save-as-video,translations (default: all)")
    parser.add_argument("--no-mods", action="store_true", help="build the plain game without any mods")
    parser.add_argument("--icon", type=Path, help="Optional local .icns file; no icon is included in this repository")
    parser.add_argument("--output", type=Path, default=Path.home() / "Applications" / "The Choicer Voicer.app")
    parser.add_argument("--replace", action="store_true", help="replace an existing app once the new one is built; the old one goes to the Trash")
    parser.add_argument("--i-own-the-game", action="store_true", help="confirm you own a copy bought on itch.io (asked otherwise)")
    args = parser.parse_args(argv)
    if sys.platform != "darwin":
        raise ValueError("This builder runs on macOS")
    # Not a purchase check (nothing offline can prove that); the tool is only for people who bought the game.
    print(f"tcv-mods {mod_version()}")
    print("This builds a Mac app from your own copy of The Choicer Voicer. It doesn't include or download the game.")
    print(f"Buy it at {ITCH}\n")
    if subprocess.run(["/usr/bin/pgrep", "-x", "The Choicer Voicer"], capture_output=True).returncode == 0:
        raise ValueError("Close The Choicer Voicer first, then run the builder again")
    CACHE.mkdir(parents=True, exist_ok=True)
    free = shutil.disk_usage(CACHE).free
    if free < 2_000_000_000:
        raise ValueError(f"Not enough free disk space: the build needs about 2 GB, {free // 1_000_000} MB is free")
    if not args.i_own_the_game and ask("Do you own a copy of The Choicer Voicer bought on itch.io? [y/N] ").lower() not in ("y", "yes"):
        raise ValueError("This builder is only for people who own the game (add --i-own-the-game when not interactive)")
    output = args.output.expanduser().resolve()
    if output.suffix != ".app":
        raise ValueError("--output must end in .app")
    replace = output.exists()
    if replace and not args.replace and ask(f"{output} is already there. Replace it once the new one is built? The old one goes to the Trash. [y/N] ").lower() not in ("y", "yes"):
        raise ValueError("Your app was kept. Add --replace, or choose another --output")
    if args.icon and (not args.icon.is_file() or args.icon.suffix.lower() != ".icns"):
        raise ValueError("--icon must be an existing local .icns file")
    game_file = locate_game(args.game).expanduser().resolve()
    print("Getting the build tools (only the first time)", flush=True)
    godot = tool_path(args.godot or unpack(fetch(*GODOT, CACHE / "godot-4.4.1.zip", "Godot 4.4.1 (about 150 MB)"), CACHE / "godot-4.4.1") / "Godot.app", "Godot")
    if args.gdre:
        gdre = tool_path(args.gdre, "Godot RE Tools")
    else:
        unpacked = unpack(fetch(*GDRE, CACHE / "gdre-2.6.3.zip", "GDRETools 2.6.3 (about 70 MB)"), CACHE / "gdre-2.6.3")
        gdre = tool_path(next(unpacked.rglob("*.app")), "Godot RE Tools")
    templates = args.templates or fetch_macos_template(CACHE / "godot-4.4.1-macos.zip")
    godot_app = godot.parent.parent.parent
    if godot_app.suffix != ".app":
        raise ValueError("Godot must be inside the official Godot.app bundle")
    version = subprocess.check_output([str(godot), "--version"], text=True).strip()
    if not version.startswith("4.4.1."):
        raise ValueError(f"Use Godot 4.4.1 for this game, received {version}")
    output.parent.mkdir(parents=True, exist_ok=True)
    log = CACHE / "build.log"
    log.write_text(f"tcv-mods {mod_version()}\n")
    with tempfile.TemporaryDirectory(prefix="tcv-build-", dir=CACHE) as scratch:  # not in Applications: Spotlight and launchers index it
        work = Path(scratch)
        template = macos_template(templates, work)
        game = unpack_game(game_file, work)
        project = work / "project"
        print("1/4 Recovering your local game", flush=True)
        run([str(gdre), "--headless", f"--recover={game}", f"--output-dir={project}"], log)
        game_source = project / "common/globals/m.gd"
        if not game_source.exists() or not re.search(r'const\s+GAME_VERSION\s*:\s*String\s*=\s*"0\.5\.3"', game_source.read_text()):
            raise ValueError("This game file is not version 0.5.3. Download the standard Windows build of 0.5.3 from your itch.io library: https://yeahmaybe.itch.io/the-choicer-voicer")
        repair_paths(project)
        features: list[str] = []
        if not args.no_mods:
            features = apply_mod(project, REPO, args.features.split(",") if args.features else None)
        settings = project / "project.godot"
        settings.write_text(settings.read_text().replace(
            "[rendering]", "[rendering]\ntextures/vram_compression/import_etc2_astc=true", 1))
        if args.icon:
            shutil.copy2(args.icon, project / "cv_mac_icon.icns")
            settings.write_text(settings.read_text().replace(
                "[application]", '[application]\nconfig/macos_native_icon="res://cv_mac_icon.icns"', 1))
        print("2/4 Importing game resources", flush=True)
        (project / "export_presets.cfg").write_text('''[preset.0]
name="Local Mac app"
runnable=false
include_filter="*.icns"
platform="macOS"
export_filter="all_resources"
exclude_filter="net/_selftest.gd,net/_nettest.gd"
script_export_mode=2
[preset.0.options]
texture_format/s3tc_bptc=true
texture_format/etc2_astc=false
codesign/codesign=0
application/bundle_identifier="dev.zeriax.tcv.local"
privacy/microphone_usage_description="Record your voice for The Choicer Voicer."
''' + "custom_template/release=" + json.dumps(str(template)) + "\n")
        run([str(godot), "--headless", "--editor", "--path", str(project), "--import"], log)
        print("3/4 Exporting the release app", flush=True)
        app = work / "The Choicer Voicer.app"
        run([str(godot), "--headless", "--path", str(project), "--export-release", "Local Mac app", str(app)], log)
        resources = app / "Contents/Resources"
        plist = app / "Contents/Info.plist"
        metadata = plistlib.loads(plist.read_bytes())
        plist.write_bytes(plistlib.dumps(app_metadata(metadata, metadata["CFBundleIconFile"])))
        shutil.copy2(REPO / "NOTICE.md", resources / "Local build notice.txt")
        # A mod that ships the video exporter (Save Dub -> MP4) gets it inside the app.
        if "save-as-video" in features:  # Save Dub runs it from inside the app
            shutil.copy2(REPO / "exporter" / "exporter.py", resources / "exporter.py")
        print("4/4 Signing and verifying the app locally", flush=True)
        run(["codesign", "--force", "--deep", "--sign", "-", str(app)], log)
        run(["codesign", "--verify", "--deep", "--strict", str(app)], log)
        install_app(app, output, replace)
    print(f"\nDone: {output}\nOpen it from Applications and allow the microphone.\nLog: {log}")
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except (ValueError, RuntimeError, OSError, zipfile.BadZipFile) as error:
        print(f"Build stopped: {error}", file=sys.stderr)
        raise SystemExit(1)
