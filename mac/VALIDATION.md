# Testing and compatibility

## Automated checks

```sh
python3 -m unittest discover -s . -p test_build.py
```

Checks cover executable validation, ZIP path containment, recovered resource-path repair and app metadata.

## Verified

A local release build from the standard Windows 0.5.3 executable with multiplayer completed. Its app signature verifies. The release runtime reports no editor/debug feature; both the bundle icon and packed macOS icon match the supplied ICNS file.

## Known limits

- Microphone hot switching is not verified. Select the input before launching; restart after a device change if capture stops.
- Using a Bluetooth headset microphone can reduce Bluetooth playback quality. A separate microphone avoids that mode switch.
- Builds are locally signed, not Apple-notarized.
- A complete Mac–Windows multiplayer round remains unverified.
