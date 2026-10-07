# Desk Control

[中文](README.md) · [Downloads](https://github.com/Liu-Da/desk-ctrl/releases) · [Issues](https://github.com/Liu-Da/desk-ctrl/issues)

A native macOS app for controlling LINAK standing desks over Bluetooth, built with SwiftUI and CoreBluetooth. Requires macOS 13 or later, with no third-party runtime dependencies.

- Read the desk height in real time.
- Hold the up/down buttons to move, or release the height slider to move to a selected height.
- Store up to five favorite positions, calibration, and height limits per desk.
- Automatically reconnect to the last successfully connected desk.
- Keep the connection active after closing the main window, with height and favorites available from the menu bar.
- Stop sending movement commands on stale telemetry, timeout, lack of progress, height limits, or desk errors.

Hardware testing has covered the **LINAK DPG1C-C005-01** panel. Other LINAK Bluetooth desks may be compatible, but have not been individually verified. This is an independent community project with no affiliation with LINAK.

![Desk Control main window](docs/images/main-window.jpg)

*Screenshot from version 1.2.0. Favorite names and heights are user-configurable.*

## Install

Download a DMG from [GitHub Releases](https://github.com/Liu-Da/desk-ctrl/releases), open it, and drag **Desk Control** to **Applications**. Eject the disk image and launch the installed app.

The first binary release is for **Apple Silicon Macs**. Intel users can build from source on their Mac; check each release for its supported architecture.

Builds currently use an ad-hoc signature and are not notarized by Apple. If macOS blocks the first launch, review the app's opening options in **System Settings → Privacy & Security**, or build from source.

## Build from source

Use a Swift 6 toolchain, such as Xcode 16 or newer with its command-line tools. Tests use the bundled [Swift Testing](https://github.com/swiftlang/swift-testing) library.

```sh
git clone https://github.com/Liu-Da/desk-ctrl.git
cd desk-ctrl
./scripts/check.sh
./scripts/build.sh
./scripts/package-dmg.sh
```

The app is created at `dist/Desk Control.app`. The DMG filename uses the app version, currently `dist/Desk-Control-1.2.1.dmg`. The build script compiles for the native architecture of the Mac running it.

## Connect and use

1. Allow Bluetooth access when macOS prompts you.
2. Hold the desk panel's Bluetooth button for two seconds until its blue light flashes. Match its `DESK` number in the app; disconnect any phone already connected to the desk.
3. Scan and connect from Settings. Connecting and scanning do not move the desk.
4. Compare the height with the panel. If the base height cannot be read automatically, enter the panel's current height in Settings and calibrate.
5. Hold an up/down button to move and release it to send a stop command. Esc or ⌘. also sends stop.
6. Drag the slider to select a height. Releasing it starts movement; pressing Esc or switching windows while dragging cancels selection.
7. Use the favorites editor to add, rename, delete, and save up to five positions. Favorites are stored locally and do not overwrite the panel's memory positions.

The default app limits are 60–130 cm. Adjust them for your desk; they do not change its mechanical travel limits.

The app remembers the last desk by Bluetooth UUID. On launch it tries the cached device, then makes at most one scan-and-connect fallback for the same UUID. A manual disconnect suppresses automatic reconnect for the current run. Reconnection never resumes an earlier movement.

Closing the main window keeps the app in the menu bar. Choose **退出 Desk Control** or press ⌘Q to quit. Moves started from a menu-bar favorite continue in the background; moves started from the main window stop when that window loses focus or closes.

## Movement handling

Commands are renewed every 0.3 seconds. Movement ends when telemetry is over two seconds old, height has not changed for three seconds, a move exceeds 45 seconds, a configured limit is reached, or the desk reports an error. Sleep and app termination also stop command renewal and attempt to send stop.

A Bluetooth disconnection can prevent the stop packet from reaching the desk. Keep the desk's physical controls accessible and observe its actual motion.

## Development and diagnostics

The 14 tests cover protocol encoding and units, device matching, movement limits and timeouts, favorites storage and migration, remembered desk data, and bounded reconnect attempts. CI runs tests, app builds, and signature verification on Apple Silicon and Intel macOS runners. Hardware behavior needs separate testing.

```sh
./scripts/check.sh
open "/Applications/Desk Control.app" --args --diagnostics /tmp/desk-control-diagnostics.json
```

Settings also provides a diagnostics copy button. Diagnostics can include Bluetooth identifiers, desk names, favorites, and logs; remove anything you do not wish to publish before attaching them to an Issue. Settings are stored locally under the app identifier `local.liuda.desk-control`.

See [CONTRIBUTING.md](CONTRIBUTING.md) for contribution steps and the [Chinese README](README.md#协议依据) for protocol references.

## License

[MIT License](LICENSE) · Copyright © 2026 LiuDa.
