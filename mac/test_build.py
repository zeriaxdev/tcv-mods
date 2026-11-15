import importlib.util
import plistlib
import tempfile
import unittest
import zipfile
from pathlib import Path

from build import app_metadata, macos_template, repair_paths, unpack_game


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


if __name__ == "__main__":
    unittest.main()
