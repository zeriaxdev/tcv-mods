import importlib.util
import plistlib
import tempfile
import unittest
import unittest.mock
import zipfile
from pathlib import Path

import os
import time

import build
from build import app_metadata, dropped_path, fetch, find_game, install_app, macos_template, repair_paths, unpack_game


class BuilderTests(unittest.TestCase):
    def test_reject_non_executable(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            game = root / "game.exe"
            game.write_bytes(b"not a PE executable")
            with self.assertRaises(ValueError):
                unpack_game(game, root)

    def test_zip_member_cannot_escape_destination(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            archive = root / "owned.zip"
            with zipfile.ZipFile(archive, "w") as zip_file:
                zip_file.writestr("../../standard.exe", b"MZtest")
                zip_file.writestr("../../unwanted.txt", b"do not extract")
            result = unpack_game(archive, root)
            self.assertEqual(result, root / "owned-game.exe")
            self.assertEqual(sorted(path.name for path in root.iterdir()), ["owned-game.exe", "owned.zip"])

    def test_repair_decompiler_paths_preserves_arithmetic(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            source = root / "example.gd"
            source.write_text("var node = $Panel / Button\nvar ratio = width / height\n")
            self.assertEqual(repair_paths(root), 1)
            self.assertEqual(source.read_text(), "var node = $Panel/Button\nvar ratio = width / height\n")

    def test_app_does_not_claim_editor_documents(self):
        metadata = app_metadata({"CFBundleDocumentTypes": [".godot"], "Other": "keep"}, "custom.icns")
        self.assertNotIn("CFBundleDocumentTypes", metadata)
        self.assertEqual(metadata["Other"], "keep")
        self.assertIn("NSMicrophoneUsageDescription", metadata)
        self.assertEqual(metadata["CFBundleIconFile"], "custom.icns")
        plistlib.loads(plistlib.dumps(metadata))

    def test_release_template_can_be_supplied_as_tpz(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            template = root / "source.zip"
            with zipfile.ZipFile(template, "w") as archive:
                archive.writestr("macos_template.app/Contents/MacOS/godot_macos_release.universal", b"runtime")
            package = root / "templates.tpz"
            with zipfile.ZipFile(package, "w") as archive:
                archive.write(template, "templates/macos.zip")
                archive.writestr("../../unwanted", b"must not extract")
            result = macos_template(package, root)
            self.assertEqual(result, root / "macos.zip")
            self.assertEqual(result.read_bytes(), template.read_bytes())
            self.assertEqual(len(list(root.iterdir())), 3)

    def test_debug_only_template_is_rejected(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            template = root / "debug.zip"
            with zipfile.ZipFile(template, "w") as archive:
                archive.writestr("macos_template.app/Contents/MacOS/godot_macos_debug.universal", b"runtime")
            with self.assertRaisesRegex(ValueError, "release runtime"):
                macos_template(template, root)

    def test_exported_executable_name_is_preserved(self):
        self.assertEqual(app_metadata({"CFBundleExecutable": "The Choicer Voicer"}, "icon.icns")["CFBundleExecutable"], "The Choicer Voicer")

    def test_dragged_path_loses_quotes_and_escapes(self):
        self.assertEqual(dropped_path("/Users/me/Downloads/TheChoicerVoicer\\ 0.5.3\\ \\(Windows\\).zip "),
                         Path("/Users/me/Downloads/TheChoicerVoicer 0.5.3 (Windows).zip"))
        self.assertEqual(dropped_path("'/tmp/a b.zip'"), Path("/tmp/a b.zip"))

    def test_finds_newest_download_and_ignores_others(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            older = root / "TheChoicerVoicer_0-5-3 standard.exe"
            newer = root / "TheChoicerVoicer 0.5.3 (Windows).zip"
            for path in [older, newer, root / "TheChoicerVoicer 0.5.2 (Windows).zip",
                         root / "TheChoicerVoicer_0-5-3 compatibility.exe", root / "notes 0.5.3.zip"]:
                path.write_bytes(b"x")
            os.utime(older, (time.time() - 100, time.time() - 100))
            self.assertEqual(find_game([root, root / "missing"]), newer)
            newer.unlink()
            self.assertEqual(find_game([root]), older)

    def test_replace_moves_old_app_to_trash_only_after_new_is_in_place(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            home = root / "home"
            (home / ".Trash").mkdir(parents=True)
            output = root / "Apps/The Choicer Voicer.app"
            (output / "Contents").mkdir(parents=True)
            (output / "Contents/old").write_text("old")
            new = root / "work/The Choicer Voicer.app"
            (new / "Contents").mkdir(parents=True)
            (new / "Contents/new").write_text("new")
            with unittest.mock.patch.object(Path, "home", return_value=home):
                with self.assertRaises(ValueError):
                    install_app(new, output, replace=False)
                self.assertTrue((output / "Contents/old").exists(), "the old app must stay without --replace")
                new = root / "work2/The Choicer Voicer.app"
                (new / "Contents").mkdir(parents=True)
                (new / "Contents/new").write_text("new")
                install_app(new, output, replace=True)
            self.assertTrue((output / "Contents/new").exists())
            trashed = list((home / ".Trash").iterdir())
            self.assertEqual(len(trashed), 1)
            self.assertTrue((trashed[0] / "Contents/old").exists())
            self.assertEqual([path.name for path in output.parent.iterdir()], ["The Choicer Voicer.app"])

    def test_download_with_wrong_checksum_is_thrown_away(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            source = root / "source.zip"
            source.write_bytes(b"godot")
            target = root / "cache.zip"
            with self.assertRaisesRegex(RuntimeError, "checksum"):
                fetch(source.as_uri(), "0" * 64, target, "test")
            self.assertEqual(sorted(path.name for path in root.iterdir()), ["source.zip"])
            self.assertEqual(fetch(source.as_uri(), build.sha256(source), target, "test").read_bytes(), b"godot")


if __name__ == "__main__":
    unittest.main()
