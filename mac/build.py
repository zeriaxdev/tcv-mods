#!/usr/bin/env python3
"""Build an unofficial local macOS app from the user's own Windows game."""
from __future__ import annotations

import argparse
import importlib.util
import json
import os
import plistlib
import re
import shutil
import subprocess
import sys
import tempfile
import zipfile
from pathlib import Path

VERSION = "0.5.3"
ROOT = Path(__file__).resolve().parent
REPO = ROOT.parent  # tcv-mods: mods/, exporter/ and install_mod.py live here


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


DUB_SCREEN_16_9 = '''\t# 16:10 (Mac builds): this screen places some parts from the top and some from
\t# the bottom of a 1152x648 screen, so extra height pulled the caption into the
\t# waveform. Keep the whole layout in that box, centered, and let only the
\t# background reach the screen edges.
\tvar extra: Vector2 = (get_viewport_rect().size - Vector2(1152, 648)) / 2.0
\tif extra.length() > 0.5:
\t\t$Visuals.set_anchors_preset(Control.PRESET_CENTER)
\t\t$Visuals.offset_left = -576.0
\t\t$Visuals.offset_right = 576.0
\t\t$Visuals.offset_top = -324.0
\t\t$Visuals.offset_bottom = 324.0
\t\t$Visuals/Scanlines.offset_left = -extra.x
\t\t$Visuals/Scanlines.offset_right = extra.x
\t\t$Visuals/Scanlines.offset_top = -extra.y
\t\t$Visuals/Scanlines.offset_bottom = extra.y
'''


def keep_dub_screen_in_16_9(project: Path) -> None:
    script = project / "scenes/gameplay/dub_mode/main/dub_mode.gd"
    text = script.read_text()
    marker = "func _ready() -> void :\n"
    if text.count(marker) != 1:
        raise ValueError("The dub screen's script changed, so it can't be fitted to 16:10. Update mac/build.py.")
    script.write_text(text.replace(marker, marker + DUB_SCREEN_16_9, 1))


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
    parser.add_argument("game", type=Path, help="Your purchased 0.5.3 standard Windows exe or ZIP")
    parser.add_argument("--godot", required=True, type=Path, help="Official Godot 4.4.1 .app or executable")
    parser.add_argument("--gdre", required=True, type=Path, help="GDRETools 2.6.3 .app or executable")
    parser.add_argument("--templates", required=True, type=Path, help="Godot 4.4.1 standard export templates .tpz or macos.zip")
    parser.add_argument("--features", help="comma-separated: community-packs,multiplayer,save-as-video (default: all)")
    parser.add_argument("--no-mods", action="store_true", help="build the plain game without any mods")
    parser.add_argument("--icon", type=Path, help="Optional local .icns file; no icon is included in this repository")
    parser.add_argument("--output", type=Path, default=ROOT / "work" / "The Choicer Voicer.app")
    parser.add_argument("--i-own-the-game", action="store_true", help="confirm you own a copy bought on itch.io (asked otherwise)")
    args = parser.parse_args(argv)
    if sys.platform != "darwin":
        raise ValueError("This builder runs on macOS")
    # Not a purchase check (nothing offline can prove that); the tool is only for people who bought the game.
    print("This builds a Mac app from your own copy of The Choicer Voicer. It doesn't include or download the game.")
    print("Buy it at https://yeahmaybe.itch.io/the-choicer-voicer")
    if subprocess.run(["/usr/bin/pgrep", "-x", "The Choicer Voicer"], capture_output=True).returncode == 0:
        raise ValueError("Close The Choicer Voicer first, then run the builder again")
    target = args.output.expanduser().resolve().parent
    free = shutil.disk_usage(target if target.exists() else Path.home()).free
    if free < 1_500_000_000:
        raise ValueError(f"Not enough free disk space: the build needs about 1.5 GB, {free // 1_000_000} MB is free")
    if not args.i_own_the_game:
        if not sys.stdin.isatty():
            raise ValueError("Confirm that you own the game: add --i-own-the-game")
        if input("Do you own a copy of The Choicer Voicer bought on itch.io? [y/N] ").strip().lower() not in ("y", "yes"):
            raise ValueError("This builder is only for people who own the game")
    output = args.output.expanduser().resolve()
    if output.exists() or output.suffix != ".app":
        raise ValueError("Choose a new .app output path; existing files are never overwritten")
    godot = tool_path(args.godot, "Godot")
    gdre = tool_path(args.gdre, "Godot RE Tools")
    godot_app = godot.parent.parent.parent
    if godot_app.suffix != ".app":
        raise ValueError("Godot must be inside the official Godot.app bundle")
    version = subprocess.check_output([str(godot), "--version"], text=True).strip()
    if not version.startswith("4.4.1."):
        raise ValueError(f"Use Godot 4.4.1 for this game, received {version}")
    if args.icon and (not args.icon.is_file() or args.icon.suffix.lower() != ".icns"):
        raise ValueError("--icon must be an existing local .icns file")
    output.parent.mkdir(parents=True, exist_ok=True)
    log = output.parent / (output.stem + " - build.log")
    with tempfile.TemporaryDirectory(prefix="tcv-local-", dir=output.parent) as scratch:
        work = Path(scratch)
        template = macos_template(args.templates, work)
        game = unpack_game(args.game.expanduser().resolve(), work)
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
        # Macs are 16:10 (below the notch too). The game is laid out for 16:9 and
        # letterboxes; "expand" lets its anchored layouts grow to fill the screen.
        settings.write_text(settings.read_text().replace(
            "[display]", '[display]\nwindow/stretch/aspect="expand"', 1))
        keep_dub_screen_in_16_9(project)
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
        shutil.move(str(app), output)
    print(f"Built: {output}\nLog: {log}\nThe recovered project was temporary and is not uploaded.")
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except (ValueError, RuntimeError, OSError, zipfile.BadZipFile) as error:
        print(f"Build stopped: {error}", file=sys.stderr)
        raise SystemExit(1)
