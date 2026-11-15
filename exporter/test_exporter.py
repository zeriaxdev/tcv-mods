import array
import contextlib
import io
import json
import math
import tempfile
import unittest
from unittest.mock import patch
import wave
from pathlib import Path

import exporter


def tone(path, seconds=0.1):
    samples = array.array('h', [int(7000 * math.sin(2 * math.pi * 440 * n / 48000)) for n in range(round(seconds * 48000))])
    with wave.open(str(path), 'wb') as output:
        output.setnchannels(1)
        output.setsampwidth(2)
        output.setframerate(48000)
        output.writeframes(samples.tobytes())


class ExportTests(unittest.TestCase):
    def test_automatic_backup_waits_for_editor_and_release_apps(self):
        import re
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            with patch.object(exporter.sys, 'platform', 'darwin'), patch.object(exporter.subprocess, 'run') as run:
                run.return_value.returncode = 0
                result = exporter.backup(root / 'game', None, root / 'cloud', ['recordings'], automatic=True)
                self.assertTrue(result['deferred'])
                pattern = run.call_args.args[0][-1]
                for binary in ('GodotRuntime', 'The Choicer Voicer'):
                    self.assertRegex('/Applications/Game.app/Contents/MacOS/' + binary, pattern)
                self.assertIsNone(re.search(pattern, '/Applications/Unrelated.app/Contents/MacOS/Other'))
                self.assertFalse((root / 'cloud').exists())

    def test_delays_and_repeated_cues_reach_actual_audio(self):
        with tempfile.TemporaryDirectory() as directory, contextlib.redirect_stdout(io.StringIO()):
            root = Path(directory)
            voice = root / 'voice.wav'
            tone(voice)
            paths, graph = exporter.audio_graph([(voice, 0.2), (voice, 0.7)], 1.0, None)
            output = root / 'mix.wav'
            exporter.run_ffmpeg(['-i', str(paths[0]), '-filter_complex', graph, '-map', '[mix]', '-c:a', 'pcm_s16le', '-ar', '48000', '-ac', '2', str(output)], 1, 0, 1, root / 'log')
            with wave.open(str(output)) as recording:
                self.assertEqual(recording.getnframes(), 48000)
                samples = array.array('h', recording.readframes(recording.getnframes()))
            def peak(start, end):
                return max(abs(value) for value in samples[round(start * 96000):round(end * 96000)])
            self.assertEqual(peak(0, 0.19), 0)
            self.assertGreater(peak(0.21, 0.28), 1000)
            self.assertEqual(peak(0.4, 0.6), 0)
            self.assertGreater(peak(0.71, 0.78), 1000)

    def test_single_channel_stereo_microphones_are_centered(self):
        for active in (0, 1):
            with self.subTest(active=active), tempfile.TemporaryDirectory() as directory, contextlib.redirect_stdout(io.StringIO()):
                root = Path(directory)
                voice = root / '_dubrecord_voice.wav'
                samples = array.array('h')
                for n in range(4800):
                    value = int(7000 * math.sin(2 * math.pi * 440 * n / 48000))
                    samples.extend((value, 0) if active == 0 else (0, value))
                with wave.open(str(voice), 'wb') as output:
                    output.setnchannels(2); output.setsampwidth(2); output.setframerate(48000)
                    output.writeframes(samples.tobytes())
                paths, graph = exporter.audio_graph([(voice, 0.0)], 0.2, None)
                output = root / 'centered.wav'
                exporter.run_ffmpeg(['-i', str(paths[0]), '-filter_complex', graph, '-map', '[mix]', '-c:a', 'pcm_s16le', '-ar', '48000', '-ac', '2', str(output)], .2, 0, 1, root / 'log')
                with wave.open(str(output)) as recording:
                    result = array.array('h', recording.readframes(recording.getnframes()))
                self.assertEqual(result[0::2], result[1::2], 'Microphone voice must be identical in both ears')
                self.assertGreater(max(result), 6000, 'Centering must not halve a one-sided microphone level')

    def test_backing_track_keeps_its_stereo_layout(self):
        with tempfile.TemporaryDirectory() as directory, contextlib.redirect_stdout(io.StringIO()):
            root = Path(directory)
            voice = root / '_dubrecord_voice.wav'
            tone(voice)
            bed = root / 'bed.wav'
            samples = array.array('h')
            for n in range(24000):
                samples.extend((0, int(3000 * math.sin(2 * math.pi * 220 * n / 48000))))
            with wave.open(str(bed), 'wb') as output:
                output.setnchannels(2); output.setsampwidth(2); output.setframerate(48000)
                output.writeframes(samples.tobytes())
            paths, graph = exporter.audio_graph([(voice, 0.2)], .5, 0)
            output = root / 'mix.wav'
            exporter.run_ffmpeg(['-i', str(bed), '-i', str(paths[0]), '-filter_complex', graph, '-map', '[mix]', '-c:a', 'pcm_s16le', '-ar', '48000', '-ac', '2', str(output)], .5, 0, 1, root / 'log')
            with wave.open(str(output)) as recording:
                result = array.array('h', recording.readframes(4800))
            self.assertEqual(max(abs(x) for x in result[0::2]), 0)
            self.assertGreater(max(abs(x) for x in result[1::2]), 2000)

    def test_missing_take_policy_matches_game_or_silence(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            pack, session = root / 'pack', root / 'session'
            pack.mkdir(); session.mkdir()
            for name, time in [('first', 0.2), ('second', 0.7)]:
                tone(pack / (name + '.wav'))
                (pack / (name + '.ini')).write_text('[data]\ndub_timestamps=[' + str(time) + ']\n')
            tone(session / '_dubrecord_first.wav')
            events, matched, total = exporter.timeline(pack, session)
            self.assertEqual((matched, total), (1, 2))
            self.assertEqual(events[0][0], session / '_dubrecord_first.wav')
            self.assertEqual(events[1][0], pack / 'second.wav')
            self.assertEqual(len(exporter.timeline(pack, session, False)[0]), 1)

    def test_txt_and_cfg_clip_metadata_like_the_game(self):
        # Packs such as "Breaking Bad - My House" keep clip data in .txt files.
        with tempfile.TemporaryDirectory() as directory:
            pack = Path(directory)
            for name, extension in [('a', '.txt'), ('b', '.CFG'), ('c', '.ini')]:
                tone(pack / (name + '.mp3'))
                (pack / (name + extension)).write_text('[data]\ncaption="x"\ndub_timestamps=[1.0]\n')
            (pack / 'c.txt').write_text('[data]\ndub_timestamps=[9.0]\n')  # .ini wins for the same clip
            (pack / 'stray_39-011.ini').write_text('[data]\ndub_timestamps=[39.0]\n')  # no audio: skipped like the game
            found = {cue['stem']: cue['times'] for cue in exporter.cues(pack)}
            self.assertEqual(found, {'a': [1.0], 'b': [1.0], 'c': [1.0]})

    def test_path_and_timestamps_reject_unsafe_input(self):
        for text in ['[-1]', '[float("nan")]', '[True]', '__import__("os").getcwd()']:
            with self.assertRaises(ValueError): exporter.timestamps(text)
        self.assertEqual(exporter.timestamps('PackedFloat32Array(0.2, 1.5)'), [0.2, 1.5])
        with self.assertRaises(ValueError): exporter.within(Path('/tmp/safe'), '../outside')

    def test_backup_keeps_conflicts_and_never_deletes(self):
        with tempfile.TemporaryDirectory() as directory, contextlib.redirect_stdout(io.StringIO()):
            root = Path(directory)
            game, cloud = root / 'game', root / 'cloud'
            recording = game / 'recordings/session'
            recording.mkdir(parents=True)
            take = recording / 'voice.wav'
            take.write_bytes(b'original take')
            result = exporter.backup(game, None, cloud, ['recordings'])
            self.assertEqual(result['copied'], 1)
            target = cloud / 'recordings/session/voice.wav'
            self.assertEqual(target.read_bytes(), b'original take')
            take.write_bytes(b'new different take')
            result = exporter.backup(game, None, cloud, ['recordings'])
            self.assertEqual(result['conflicts_preserved'], 1)
            self.assertEqual(target.read_bytes(), b'original take')
            self.assertEqual(len(list(target.parent.glob('voice*'))), 2)
            result = exporter.backup(game, None, cloud, ['recordings'])
            self.assertEqual(result['copied'], 0)
            take.unlink()
            exporter.backup(game, None, cloud, ['recordings'])
            self.assertTrue(target.exists())

    def test_export_backup_does_not_copy_unrelated_desktop_files(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            desktop = root / 'Desktop'; desktop.mkdir()
            (desktop / 'private.txt').write_text('never upload')
            (desktop / 'unrelated.mov').write_bytes(b'never upload')
            (desktop / 'Dub.mp4').write_bytes(b'export')
            (desktop / 'Dub.wav').write_bytes(b'export audio')
            (desktop / 'Dub.export.json').write_text(json.dumps({'pack':'pack','session':'session','recorded_takes':1}))
            files = exporter.backup_files(root / 'game', desktop, ['videos'])
            self.assertEqual({source.name for source, _relative in files}, {'Dub.mp4','Dub.wav','Dub.export.json'})
            cloud = root / 'cloud'
            exporter.backup(root / 'game', desktop, cloud, ['videos'], dry_run=True)
            self.assertFalse(cloud.exists())


if __name__ == '__main__': unittest.main()
