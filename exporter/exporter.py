#!/usr/bin/env python3
"""Local saved-dub exporter and non-destructive folder backup for Choicer Voicer."""
from __future__ import annotations

import argparse
import ast
import configparser
import hashlib
import json
import math
import os
import re
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

AUDIO_EXTENSIONS = {".wav", ".ogg", ".mp3", ".flac"}
PACK_FOLDERS = ("packs_voice", "packs_chatter", "packs_player", "packs_host", "packs_judges", "packs_menu", "packs_studio")


EVENTS_FILE: Path | None = None  # --events: also append each event here (the game reads it; no shell needed)


def emit(kind: str, **values) -> None:
    line = json.dumps({"type": kind, **values}, ensure_ascii=False)
    print(line, flush=True)
    if EVENTS_FILE:
        with EVENTS_FILE.open("a", encoding="utf-8") as events:
            events.write(line + "\n")


def game_root() -> Path:
    if sys.platform == "darwin":
        return Path.home() / "Library/Application Support/YeahMaybe/ChoicerVoicer/game"
    if os.name == "nt":
        return Path(os.environ["APPDATA"]) / "YeahMaybe/ChoicerVoicer/game"
    return Path.home() / ".local/share/YeahMaybe/ChoicerVoicer/game"


def executable(name: str) -> str:
    found = shutil.which(name)
    if found:
        return found
    for folder in ("/opt/homebrew/bin", "/usr/local/bin", str(Path(__file__).parent / "bin")):
        candidate = Path(folder) / (name + (".exe" if os.name == "nt" else ""))
        if candidate.is_file():
            return str(candidate)
    raise ValueError(f"{name} is required. Install FFmpeg from https://ffmpeg.org/download.html")


def probe(path: Path) -> dict:
    output = subprocess.check_output([executable("ffprobe"), "-v", "error", "-show_streams", "-show_format", "-of", "json", str(path)], text=True)
    return json.loads(output)


def within(root: Path, relative: str) -> Path:
    if Path(relative).is_absolute() or ".." in Path(relative).parts:
        raise ValueError("Choose a path inside the selected folder")
    path = (root / relative).resolve()
    if not path.is_relative_to(root.resolve()):
        raise ValueError("The selected path leaves the game folder")
    return path


def ini_data(path: Path) -> dict:
    parser = configparser.ConfigParser(interpolation=None, strict=False)
    parser.read(path, encoding="utf-8-sig")
    return dict(parser["data"]) if parser.has_section("data") else {}


def timestamps(value: str) -> list[float]:
    text = value.strip()
    if text.startswith("PackedFloat"):
        text = "[" + text[text.index("(") + 1:text.rindex(")")] + "]"
    try:
        values = ast.literal_eval(text)
    except (SyntaxError, ValueError) as error:
        raise ValueError(f"Invalid dub timestamps: {value}") from error
    if not isinstance(values, (list, tuple)) or any(isinstance(item, bool) or not isinstance(item, (int, float)) or not math.isfinite(item) or item < 0 for item in values):
        raise ValueError("Dub timestamps must be finite, non-negative seconds")
    return [float(item) for item in values]


CONFIG_EXTENSIONS = (".ini", ".cfg", ".txt")  # same set the game scans (VD.SCANNED_CONFIG_EXTENSIONS)


def cues(pack: Path) -> list[dict]:
    result = []
    seen = set()
    configs = [path for path in pack.rglob("*") if path.suffix.lower() in CONFIG_EXTENSIONS]
    for path in sorted(configs, key=lambda p: (str(p.parent), p.stem, CONFIG_EXTENSIONS.index(p.suffix.lower()))):
        if path.name.startswith("_") or path.is_symlink() or not path.is_file() or (path.parent, path.stem) in seen:
            continue
        data = ini_data(path)
        if "dub_timestamps" not in data:
            continue
        seen.add((path.parent, path.stem))
        original = next((candidate for candidate in path.parent.iterdir()
                         if candidate.stem == path.stem and candidate.is_file() and not candidate.is_symlink() and candidate.suffix.lower() in AUDIO_EXTENSIONS), None)
        if original is None:
            continue  # stray clip file without audio: the game skips these too
        result.append({"stem": path.stem, "original": original, "times": timestamps(data["dub_timestamps"])})
    return result


def recordings(session: Path) -> dict[str, Path]:
    return {path.stem.removeprefix("_dubrecord_"): path for path in sorted(session.iterdir())
            if path.is_file() and not path.is_symlink() and path.name.startswith("_dubrecord_") and path.suffix.lower() in AUDIO_EXTENSIONS}


def library(root: Path) -> list[dict]:
    result = []
    voice = root / "packs_voice"
    if not voice.is_dir():
        raise ValueError(f"Game packs not found in {voice}")
    for video in sorted(voice.rglob("dub_video.*")):
        if video.suffix.lower() not in {".ogv", ".mp4", ".webm", ".mov", ".mkv"} or video.is_symlink():
            continue
        pack = video.parent
        relative = pack.relative_to(voice).as_posix()
        saved = root / "recordings/dub_recordings" / relative
        if not saved.is_dir():
            continue
        metadata = probe(video)
        stream = next((item for item in metadata["streams"] if item["codec_type"] == "video"), None)
        if stream is None:
            continue
        pack_cues = cues(pack)
        sessions = []
        for session in saved.iterdir():
            if not session.is_dir() or session.is_symlink():
                continue
            takes = recordings(session)
            matched = sum(clip["stem"] in takes for clip in pack_cues)
            if not matched and "freestyle" not in takes:
                continue
            sessions.append({"id": session.name, "name": session.name, "takes": matched, "total": len(pack_cues),
                             "freestyle": "freestyle" in takes,
                             "modified": max(path.stat().st_mtime for path in takes.values())})
        if not sessions:
            continue
        title = ini_data(pack / "_pack_info.ini").get("title", "")
        try:
            title = json.loads(title)
        except (ValueError, TypeError):
            title = pack.name
        result.append({"id": relative, "title": title, "width": stream["width"], "height": stream["height"],
                       "fps": stream.get("avg_frame_rate") if stream.get("avg_frame_rate") not in {None,"0/0"} else stream.get("r_frame_rate", ""),
                       "duration": float(metadata["format"]["duration"]),
                       "sessions": sorted(sessions, key=lambda item: item["modified"], reverse=True)})
    return sorted(result, key=lambda pack: pack["sessions"][0]["modified"], reverse=True)


def timeline(pack: Path, session: Path, keep_original: bool = True) -> tuple[list[tuple[Path, float]], int, int]:
    takes = recordings(session)
    if "freestyle" in takes:
        return [(takes["freestyle"], 0.0)], 1, 1
    clips = cues(pack)
    matched = sum(clip["stem"] in takes for clip in clips)
    if not matched:
        raise ValueError("No matching recorded takes in this session")
    events = []
    for clip in clips:
        audio = takes.get(clip["stem"], clip["original"] if keep_original else None)
        if audio is not None:
            events.extend((audio, time) for time in clip["times"])
    return events, matched, len(clips)


def center_microphone(path: Path) -> str:
    if not path.name.startswith("_dubrecord_"):
        return ""
    import array
    import wave
    try:
        with wave.open(str(path)) as recording:
            channels = recording.getnchannels()
            width = recording.getsampwidth()
            if channels == 1:
                return ",pan=stereo|c0=c0|c1=c0"
            if channels != 2 or width != 2:
                return ",aformat=channel_layouts=mono,pan=stereo|c0=c0|c1=c0"
            samples = array.array("h", recording.readframes(recording.getnframes()))
            if sys.byteorder != "little":
                samples.byteswap()
        left = sum(value * value for value in samples[0::2])
        right = sum(value * value for value in samples[1::2])
        # A mono USB mic can occupy either input of a stereo capture bus.
        if right < left * 0.0001:
            mono = "c0"
        elif left < right * 0.0001:
            mono = "c1"
        else:
            mono = "0.5*c0+0.5*c1"
        return f",pan=mono|c0={mono},pan=stereo|c0=c0|c1=c0"
    except (wave.Error, EOFError):
        return ",aformat=channel_layouts=mono,pan=stereo|c0=c0|c1=c0"


def audio_graph(events: list[tuple[Path, float]], duration: float, backing_index: int | None) -> tuple[list[Path], str]:
    paths = list(dict.fromkeys(path for path, _time in events))
    filters = []
    if backing_index is None:
        filters.append(f"anullsrc=r=48000:cl=stereo,atrim=duration={duration:.6f}[bed]")
        offset = 0
    else:
        filters.append(f"[{backing_index}:a]aresample=48000,aformat=channel_layouts=stereo,apad,atrim=duration={duration:.6f}[bed]")
        offset = 1
    labels = ["[bed]"]
    for index, path in enumerate(paths):
        times = [time for source, time in events if source == path and time < duration]
        if not times:
            continue
        source = f"[{index + offset}:a]aresample=48000" + center_microphone(path) + ",aformat=channel_layouts=stereo"
        if len(times) > 1:
            filters.append(source + f",asplit={len(times)}" + "".join(f"[s{index}_{n}]" for n in range(len(times))))
        for occurrence, time in enumerate(times):
            label = f"a{index}_{occurrence}"
            delay = round(time * 48000)
            input_label = f"[s{index}_{occurrence}]" if len(times) > 1 else source + ","
            filters.append(input_label + f"adelay={delay}S:all=1[{label}]")
            labels.append(f"[{label}]")
    filters.append("".join(labels) + f"amix=inputs={len(labels)}:duration=first:normalize=0,alimiter=limit=0.95:level=false:latency=true,atrim=duration={duration:.6f}[mix]")
    return paths, ";".join(filters)


def run_ffmpeg(arguments: list[str], duration: float, start: float, span: float, log: Path) -> None:
    command = [executable("ffmpeg"), "-hide_banner", "-nostdin", "-loglevel", "error", "-progress", "pipe:1", "-nostats", *arguments]
    with log.open("ab") as errors:
        process = subprocess.Popen(command, stdout=subprocess.PIPE, stderr=errors, text=True)
        try:
            for line in process.stdout:
                key, _, value = line.strip().partition("=")
                if key == "out_time_us":
                    try:
                        fraction = min(1.0, max(0.0, int(value) / 1_000_000 / duration))
                    except ValueError:
                        continue
                    emit("progress", fraction=start + span * fraction)
            if process.wait():
                raise RuntimeError(f"FFmpeg failed. Details: {log}")
        except BaseException:
            if process.poll() is None:
                process.terminate()
            process.wait()
            raise
        finally:
            process.stdout.close()


def export_dub(root: Path, pack_id: str, session_id: str, output: Path, keep_original: bool = True, backing_on: bool = True) -> dict:
    pack = within(root / "packs_voice", pack_id)
    session = within(root / "recordings/dub_recordings" / pack_id, session_id)
    video = next((path for path in pack.glob("dub_video.*") if path.suffix.lower() in {".ogv", ".mp4", ".mov", ".webm", ".mkv"}), None)
    if video is None:
        raise ValueError("The pack has no supported source video")
    metadata = probe(video)
    source = next(item for item in metadata["streams"] if item["codec_type"] == "video")
    duration = float(metadata["format"]["duration"])
    if not math.isfinite(duration) or duration <= 0:
        raise ValueError("Invalid source video duration")
    events, take_count, clip_count = timeline(pack, session, keep_original)
    output = output.expanduser().resolve()
    if output.suffix.lower() != ".mp4":
        raise ValueError("Choose an .mp4 output file")
    audio_output = output.with_suffix(".wav")
    if output.exists() or audio_output.exists():
        raise ValueError("Choose a new filename; existing exports are never overwritten")
    output.parent.mkdir(parents=True, exist_ok=True)
    backing = next((path for path in pack.glob("_backing_track.*") if path.suffix.lower() in AUDIO_EXTENSIONS), None) if backing_on else None
    paths, graph = audio_graph(events, duration, 0 if backing else None)
    sources = [video, *paths, *([backing] if backing else [])]
    before = {path: (path.stat().st_size, path.stat().st_mtime_ns) for path in sources}
    log = output.with_suffix(".export.log")
    emit("status", message=f"Mixing {take_count}/{clip_count} recorded takes")
    with tempfile.TemporaryDirectory(prefix=".tcv-export-", dir=output.parent) as temporary:
        scratch = Path(temporary)
        mix = scratch / "dub.wav"
        args = []
        for path in ([backing] if backing else []) + paths:
            args.extend(["-i", str(path)])
        args += ["-filter_complex", graph, "-map", "[mix]", "-c:a", "pcm_s16le", "-ar", "48000", "-ac", "2", str(mix)]
        run_ffmpeg(args, duration, 0.0, 0.15, log)
        emit("status", message=f"Encoding {source['width']}×{source['height']} at the source frame rate")
        movie = scratch / "dub.mp4"
        run_ffmpeg(["-i", str(video), "-i", str(mix), "-map", "0:v:0", "-map", "1:a:0", "-t", str(duration),
                    "-vf", "setpts=PTS-STARTPTS,pad=ceil(iw/2)*2:ceil(ih/2)*2", "-c:v", "libx264", "-preset", "veryfast", "-crf", "16",  # veryfast: ~3x faster than fast, SSIM 0.995 vs 0.996 on Theora sources
                    "-pix_fmt", "yuv420p", "-c:a", "aac", "-b:a", "320k", "-ar", "48000", "-movflags", "+faststart", str(movie)], duration, 0.15, 0.85, log)
        if any((path.stat().st_size, path.stat().st_mtime_ns) != state for path, state in before.items()):
            raise ValueError("The recording changed during export. Finish recording, then export again")
        rendered = probe(movie)
        picture = next(item for item in rendered["streams"] if item["codec_type"] == "video")
        if abs(float(rendered["format"]["duration"]) - duration) > 0.15 or picture["width"] < source["width"] or picture["height"] < source["height"]:
            raise ValueError("Export validation failed: duration or resolution does not match the source")
        # Hard links provide a no-overwrite final commit on the same volume.
        audio_committed = False
        try:
            os.link(mix, audio_output)
            audio_committed = True
            os.link(movie, output)
        except OSError:
            if audio_committed:
                audio_output.unlink()
            raise
    details = {"video": str(output), "audio": str(audio_output), "width": picture["width"], "height": picture["height"],
               "duration": duration, "recorded_takes": take_count, "total_clips": clip_count, "pack": pack_id, "session": session_id}
    output.with_suffix(".export.json").write_text(json.dumps(details, indent=2))
    emit("result", **details)
    return details


def digest(path: Path) -> str:
    value = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            value.update(chunk)
    return value.hexdigest()


def backup_files(root: Path, exports: Path | None, categories: list[str]) -> list[tuple[Path, Path]]:
    paths = []
    if "packs" in categories:
        paths += [(root / name, Path(name)) for name in PACK_FOLDERS]
    if "recordings" in categories:
        paths.append((root / "recordings", Path("recordings")))
    files = []
    if "videos" in categories and exports and exports.is_dir():
        # Only our completed exports; selecting Desktop must not upload unrelated files.
        for metadata in sorted(exports.glob("*.export.json")):
            if metadata.is_symlink():
                continue
            try:
                info = json.loads(metadata.read_text())
            except (OSError, ValueError):
                continue
            if not isinstance(info, dict) or not {"pack", "session", "recorded_takes"}.issubset(info):
                continue
            stem = metadata.name.removesuffix(".export.json")
            for suffix in (".mp4", ".wav", ".export.json"):
                source = exports / (stem + suffix)
                if source.is_file() and not source.is_symlink():
                    files.append((source, Path("exports") / source.name))
    for source_root, prefix in paths:
        if not source_root.is_dir():
            continue
        for source in sorted(source_root.rglob("*")):
            if not source.is_file() or source.is_symlink() or any(part.startswith(".tcv-export-") for part in source.parts) or source.name.startswith(".DS_Store") or source.suffix in {".tmp", ".part", ".log"}:
                continue
            if not source.resolve().is_relative_to(source_root.resolve()):
                continue
            files.append((source, prefix / source.relative_to(source_root)))
    return files


def backup(root: Path, exports: Path | None, destination: Path, categories: list[str], dry_run: bool = False, automatic: bool = False) -> dict:
    destination = destination.expanduser().resolve()
    root = root.resolve()
    if destination == root or destination.is_relative_to(root) or root.is_relative_to(destination):
        raise ValueError("Choose a dedicated backup folder outside the game's data folder")
    if exports and (destination == exports.resolve() or destination.is_relative_to(exports.resolve()) or exports.resolve().is_relative_to(destination)):
        raise ValueError("Choose a separate backup folder outside the export folder")
    if automatic and sys.platform == "darwin":
        running = subprocess.run(["/usr/bin/pgrep", "-f", r"/Contents/MacOS/(GodotRuntime|The Choicer Voicer)( |$)"], stdout=subprocess.DEVNULL).returncode == 0
        if running:
            return {"deferred": True, "reason": "The game is running; waiting until it closes"}
    files = backup_files(root, exports, categories)
    if automatic:
        import time
        files = [(source, relative) for source, relative in files if time.time() - source.stat().st_mtime > 30]
    summary = {"files": len(files), "bytes": sum(source.stat().st_size for source, _relative in files), "destination": str(destination)}
    if dry_run:
        return summary
    copied = skipped = conflicts = 0
    for index, (source, relative) in enumerate(files):
        target = within(destination, relative.as_posix())
        original_state = (source.stat().st_size, source.stat().st_mtime_ns)
        source_hash = digest(source)
        if target.exists():
            if target.stat().st_size == original_state[0] and digest(target) == source_hash:
                skipped += 1
                continue
            target = target.with_name(target.stem + " (conflict-" + source_hash[:12] + ")" + target.suffix)
            if target.exists() and digest(target) == source_hash:
                skipped += 1
                continue
            conflicts += 1
        target.parent.mkdir(parents=True, exist_ok=True)
        with tempfile.NamedTemporaryFile(prefix=".tcv-copy-", dir=target.parent, delete=False) as stream:
            temporary = Path(stream.name)
        try:
            shutil.copy2(source, temporary)
            if original_state != (source.stat().st_size, source.stat().st_mtime_ns) or digest(temporary) != source_hash:
                raise ValueError(f"File changed while backing up: {source.name}; try again after recording finishes")
            # Works on mounted WebDAV as well as cloud-provider folders; exclusive creation never replaces remote takes.
            try:
                os.link(temporary, target)
            except FileExistsError:
                raise ValueError("Another backup is writing this file; try again when it finishes")
            except OSError as error:
                import errno
                if error.errno not in {errno.EPERM, errno.EOPNOTSUPP, errno.EXDEV, errno.ENOSYS}:
                    raise
                created = False
                try:
                    with target.open("xb") as output, temporary.open("rb") as data:
                        created = True
                        shutil.copyfileobj(data, output)
                except BaseException:
                    if created:
                        target.unlink(missing_ok=True)
                    raise
            copied += 1
        finally:
            temporary.unlink(missing_ok=True)
        emit("progress", fraction=(index + 1) / max(1, len(files)))
    return {**summary, "copied": copied, "unchanged": skipped, "conflicts_preserved": conflicts}


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--game-root", type=Path, default=game_root())
    parser.add_argument("--library", action="store_true")
    parser.add_argument("--export", action="store_true")
    parser.add_argument("--pack")
    parser.add_argument("--session")
    parser.add_argument("--output", type=Path)
    parser.add_argument("--mute-backing", action="store_true")
    parser.add_argument("--missing-silence", action="store_true")
    parser.add_argument("--backup", type=Path)
    parser.add_argument("--exports-folder", type=Path)
    parser.add_argument("--categories", default="packs,recordings,videos")
    parser.add_argument("--dry-run", action="store_true")
    parser.add_argument("--automatic", action="store_true")
    parser.add_argument("--events", type=Path, help="also write progress events to this file")
    args = parser.parse_args()
    global EVENTS_FILE
    EVENTS_FILE = args.events
    root = args.game_root.expanduser().resolve()
    if args.library:
        emit("library", packs=library(root), game_root=str(root))
    elif args.export:
        if not all([args.pack, args.session, args.output]):
            raise ValueError("Choose a pack, session and output filename")
        export_dub(root, args.pack, args.session, args.output, not args.missing_silence, not args.mute_backing)
    elif args.backup:
        emit("backup_result", **backup(root, args.exports_folder, args.backup, args.categories.split(","), args.dry_run, args.automatic))
    else:
        parser.print_help()


if __name__ == "__main__":
    import signal
    def cancel_job(_signal, _frame):
        raise KeyboardInterrupt
    signal.signal(signal.SIGTERM, cancel_job)
    try:
        main()
    except KeyboardInterrupt:
        emit("error", message="Canceled")
        raise SystemExit(130)
    except (ValueError, OSError, RuntimeError, subprocess.SubprocessError, configparser.Error) as error:
        emit("error", message=str(error))
        raise SystemExit(1)
