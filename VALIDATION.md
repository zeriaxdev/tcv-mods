# Validation

Run Godot 4.4.1 against your own local recovered/patched game, with a test script under tests/ passed to --script.

The cancellation and rapid-selection repros failed before the fixes and pass afterward. Native menu state, return navigation, and 1152×648 bounds checks pass. Community Packs was also recovered/applied/imported and tested against a clean 0.5.3 game with no Net autoload or multiplayer hooks.

The user's video showed successful local hosting; it did not demonstrate a cross-platform round. Physical audio-device switching and a Windows installer run remain unverified.

The captured user recording, screenshots, logs, game source, assets, packs and saves are deliberately outside these repositories. Tests use synthetic data.
