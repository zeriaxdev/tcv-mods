# Testing and compatibility

## Run the regression checks

Use Godot 4.4.1 with a local recovered game project containing the mod. Pass each script in `tests/` through `--script`, for example:

```sh
Godot --headless --path /path/to/patched-game \
  --script /path/to/this-project/tests/repro_catalog.gd
```

The game project and assets are supplied locally; they are not test fixtures in this repository.

## Verified

- Cancellation and rapid selection do not apply stale catalog responses.
- Native menu navigation, return behavior and layout bounds pass local checks at 1152 × 648.
- The standalone browser imports and runs against a clean 0.5.3 project without multiplayer hooks or a `Net` service.
- Installed/download searches are case-insensitive and remember each tab’s query.
- Canceling a stalled local HTTP response returns without blocking the main thread.
- Settings-style tab buttons in Community Packs and the Online menu; the Online and Community packs buttons appear together with the main menu.
- Downloads run on a background thread: a 66 MB pack took 4.6 s instead of 14.8 s at 60 fps.
- Slow GameBanana mirrors are skipped: a 241 MB pack took 28.5 s instead of 152 s, and its MD5 matched GameBanana's.
- A real GameBanana RAR pack (RAR5) installs through the same safety checks as ZIPs.
- Leftover partial downloads older than 10 minutes are removed at startup; download failures are written to the game log.
- Save Dub exports a real saved dub to MP4 in about 5 s on macOS, the button fills with the progress, and a failed export offers Retry video.

## Still to verify

- Running the Windows installer on Windows.
- Save Dub on Windows and Linux, and RAR packs on Windows (`tar.exe`).
- Completing a multiplayer round between macOS and Windows.
- Microphone device changes during a running game. Restarting may be necessary after changing inputs.

Headless UI checks verify structure and resources; they do not replace visual or multiplayer playtesting.
