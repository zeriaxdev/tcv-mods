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

## Still to verify

- Running the Windows installer on Windows.
- Completing a multiplayer round between macOS and Windows.
- Microphone device changes during a running game. Restarting may be necessary after changing inputs.

Headless UI checks verify structure and resources; they do not replace visual or multiplayer playtesting.
