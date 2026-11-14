# Choicer Voicer — integrated menus fork

Unofficial multiplayer and Community Packs menu changes by **zeriaxdev**, based on [TypeOneAppolo / Appolo's multiplayer mod](https://github.com/TypeOneAppolo/tcv-multiplayer-mod).

This folder is the shareable mod source and Windows installer. It is not a copy of the game. Each player supplies their own purchased game. Do not upload the rebuilt Mac app, Windows exe, exported PCK, recovered project, voice packs or recordings with this kit.

## Windows friends

1. Download your own **0.5.3 standard Windows** build from [YeahMaybe on itch.io](https://yeahmaybe.itch.io/the-choicer-voicer) and extract it.
2. Extract this entire kit. Drag the game's original exe onto **Install.bat**. The installer obtains the Godot/GDRE tools and builds a separate modded exe locally. Keep the original game.
3. Launch the resulting modded exe. Open **Online (F9)** from the main menu. Everyone should use mod **1.1.9 / protocol 8**.
4. One player hosts on port **7654**. Friends join using the host's reachable address. On Tailscale use its 100.x address; with router forwarding forward **UDP**, not a web/HTTP proxy. Match the port in-game and allow the game through Windows Firewall.
5. Test the microphone in Settings before playing. Standard mode needs compatible voice packs. Dub Mode pack sharing is experimental; consult UPSTREAM_README.md.

Installation can take several minutes because it reconstructs and exports the game locally. The Windows installer has not been executed on a Windows PC for this fork. A full Mac–Windows match still needs testing.

## What changes

The browser and lobby are MenuBase pages loaded by the game's existing menu_master. The original shell owns the background, breadcrumb, version and return button. The browser reads the game's existing pack-list style and panel materials at runtime. Action controls extend the game's ButtonCV, retaining its palette and sounds. DuruSans and Waukegan are loaded from the user's own game; they are not bundled here.

These are Godot GDScript mods and small scene definitions, not a website or injected native machine code. The installer recovers an editable project from the supplied game, adds the Net autoload and patches game hooks, then exports it. The Mac adaptation similarly uses the recovered game data with a native Godot runtime; it does not use CrossOver. It is not the developer's original source repository.

The UI fork keeps Appolo's multiplayer protocol and pack installer. It is one combined mod kit, not two independent drag-and-drop plugins.

## Credits and distribution

- **YeahMaybe**: The Choicer Voicer and all original game content. No affiliation or endorsement is claimed.
- **TypeOneAppolo / Appolo**: original multiplayer mod, browser, networking and installer, under the preserved MIT LICENSE.
- **zeriaxdev**: this fork's integrated menu changes and Mac adaptation work.
- **Godot Engine** and **GDRETools**: tools used by the installer; see upstream README and the tools' own licenses.

The MIT license permits modification/distribution of the mod while requiring its copyright and permission notices to remain. It does not grant rights to redistribute the purchased game. See [MIT terms](https://opensource.org/license/mit) and LICENSE.

Action icons, including the supplied GameBanana SVG, are omitted from this revision. No logo artwork is distributed in this kit. Installed packs and downloads use the same native list/detail page as browsing; their former card popups are removed. The inherited Discord/support UI is removed, so this fork does not send users to Appolo for support.

Keep any GitHub repository **private** for now. No GitHub repository has been created or uploaded by this packaging step. Before a public release, confirm the game's modding/reconstruction policy with the developer; this kit is not a legal clearance for the game or community pack content.

## Source map

- `mod/net/community_pack_browser.gd` and `.tscn`: pack page and operations.
- `mod/net/lobby.gd` and `.tscn`: online page and existing lobby actions.
- `mod/net/choicer_button.gd`: thin adapter around the game's ButtonCV.
- `mod/net/choicer_style.gd`: runtime native styles and contrast fixes.
- `mod/net/net_manager.gd` and `mod/patches/`: navigation and game hooks.

See UPSTREAM_README.md for the original installation details, troubleshooting, features and author links. Credits there describe the upstream mod, not ownership by this fork.
