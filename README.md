# Choicer Voicer Multiplayer

Play The Choicer Voicer online and browse community dub packs without leaving the game.

The menus use the game's own buttons, fonts, panels and navigation. Includes Appolo's multiplayer mod and the Community Packs browser.

## Install on Windows

You need **The Choicer Voicer 0.5.3 standard Windows build** and **Python 3**.

1. Download the game from [YeahMaybe on itch.io](https://yeahmaybe.itch.io/the-choicer-voicer) and extract its ZIP.
2. [Download this mod](https://github.com/zeriaxdev/tcv-multiplayer/archive/refs/heads/main.zip) and extract the entire ZIP.
3. Drag the original game `.exe` onto `Install.bat`.
4. Wait for the installer to finish, then open the new modded executable.

The installer downloads Godot and GDRETools and builds a separate executable. Start with an unmodified game; keep the original for future updates. If Python is missing, the installer offers installation instructions.

For macOS, use [Choicer Voicer Mac Builder](https://github.com/zeriaxdev/tcv-macos) with this mod.

## Play online

1. Open **Online (F9)** from the main menu.
2. Enter your name. One player chooses **Host**; everyone else enters that player's address and chooses **Join**.
3. Use the same port on every computer; the default is **7654**.
4. Choose your game mode and mark yourself **Ready**.

Every player needs the same multiplayer protocol: **version 1.1.9, protocol 8**. Use a reachable host address: a local address on the same network, a Tailscale address, or a public address with **UDP 7654** forwarded to the host. Allow the game through the firewall.

Dub Mode can offer packs to other players before a round. Each recipient must accept the download. See the [upstream guide](UPSTREAM_README.md) for gameplay and pack-sharing details.

## Community packs

Open **Community packs** from the main menu to search GameBanana, install dub packs and manage downloads. **Installed packs** lists packs managed by the browser. Removing a pack requires confirmation; manually installed folders are left alone.

This mod already includes the browser. Install [Community Packs](https://github.com/zeriaxdev/tcv-community-packs) separately only if you want the browser without multiplayer.

Search also filters Installed packs and Downloads locally. Navigation uses full-size game buttons.

## Development and compatibility

The installer adds GDScript modules and targeted game hooks to a locally recovered project, then exports it with Godot. Game resources are loaded from the installed game, rather than included in the mod.

See [testing and compatibility](VALIDATION.md) for checks and current limitations. The Windows installer and a complete Mac–Windows match still need testing for this fork.

## Unofficial project

This is a fan-made project. It is not made by, endorsed by or affiliated with YeahMaybe, the creator of [The Choicer Voicer](https://yeahmaybe.itch.io/the-choicer-voicer). The game's only official sources are its itch.io page and YeahMaybe's website.

- You need your own copy of the game. Get it from the [official itch.io page](https://yeahmaybe.itch.io/the-choicer-voicer).
- This repository contains no game files. Share this project's code, never a game you built with it: a built game contains YeahMaybe's work.
- Dub packs come from [GameBanana](https://gamebanana.com) and belong to their creators.

If you are YeahMaybe and want anything changed or taken down, [open an issue](https://github.com/zeriaxdev/tcv-multiplayer/issues) and it will be handled promptly.

## Credits and license

- **TypeOneAppolo (Appolo)** made the original multiplayer mod: [TypeOneAppolo/tcv-multiplayer-mod](https://github.com/TypeOneAppolo/tcv-multiplayer-mod). This repository is a fork of it. [Support Appolo on Ko-fi](https://ko-fi.com/appolodev).
- **Herjuus** wrote the original community pack browser, download queue, installer and host pack sync.
- **zeriaxdev** added the native game menus, macOS support, fast downloads, RAR support and automatic video export.
- [The Choicer Voicer](https://yeahmaybe.itch.io/the-choicer-voicer) is made by **YeahMaybe**.
- Built with [Godot](https://godotengine.org/) and [GDRETools](https://github.com/GDRETools/gdsdecomp), which have their own licenses.

The mod code is available under the [MIT license](LICENSE); see [notices](NOTICE.md). The license does not cover the game, its files or community packs.
