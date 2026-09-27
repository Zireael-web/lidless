<img src="design/icon-variants/calm.png" alt="Lidless app icon" width="128">

# Lidless

**English** | [Русский](README.ru.md)

A macOS menu bar utility for open-lid clamshell mode. When a trusted physical external display is connected, Lidless disables the MacBook built-in display at the WindowServer display-layout level while keeping the keyboard, trackpad, speakers and external display active. Everything runs locally.

A personal side project for my own MacBook, where I explore native macOS development in Swift.

[Controls](#controls) · [Safety](#safety) · [Build](#build) · [Install](#install) · [Recovery](#recovery) · [Limitations](#known-limitations)

**Swift · AppKit · SwiftUI · macOS 13+ · Apple Silicon**

## Warning

This app uses undocumented private macOS display APIs. It is not App Store compatible and may break after macOS updates. It is intended for personal local use only.

## Controls

- `Turn Off Built-in Now` — disables the built-in display right away when an active physical external display is available.
- `Restore` — restores the built-in display.
- `Restore & Pause App` — restores the built-in display, turns off auto mode and keeps the app inert in the menu bar.
- `Resume Auto Mode` — re-enables automatic built-in display disabling.
- `Quit & Restore` — restores the built-in display before quitting.
- `Copy Diagnostics` — copies private API, display and persisted state diagnostics to the clipboard.

## Hotkeys

```text
Ctrl + Cmd + D         Toggle built-in display
Ctrl + Opt + Cmd + R   Restore & Pause App
```

## Safety

- The built-in display is never disabled unless an active physical external display is detected.
- Auto mode disables the built-in display after an external display is detected and settled.
- Disconnecting the external display restores the built-in display.
- The app restores the built-in display on quit.
- Startup recovery restores the built-in display if the previous run crashed or left a stale display-off lease.
- A watchdog helper restores the built-in display if the main app dies while the display-off lease is active.
- AirPlay, Sidecar, DisplayLink, dummy and virtual displays are not trusted by default.

## Build

Requires a Mac with Apple Silicon and the Xcode Command Line Tools. From the repository root:

```sh
./build.sh
```

The build output is:

```text
build/Lidless.app
dist/Lidless.app.zip
dist/Lidless.pkg      (when pkgbuild is available)
```

During the build, `tools/generate_icons.swift` redraws the app icon and the variants in `design/icon-variants/`.

## Install

```sh
./install.sh
```

The installer builds the app, copies it to `/Applications/Lidless.app` and launches it. On first launch, the app registers itself and its watchdog as user LaunchAgents so Lidless starts after login.

To copy the app to `/Applications` without launching it:

```sh
./install.sh --no-launch
```

## Recovery

If the built-in display does not come back:

1. Disconnect the external display cable; Lidless should restore the built-in display.
2. Reopen Lidless; startup recovery will try to re-enable the built-in display.
3. Reboot the Mac if WindowServer is stuck.

Some monitors and docks keep reporting an external display even when the panel is powered off. In that case macOS may still consider the external display active, so Lidless cannot reliably tell that the monitor is not visible.

## Private APIs

Loaded at runtime with `dlopen`/`dlsym`:

```text
SLSConfigureDisplayEnabled
CGSConfigureDisplayEnabled
```

Lidless does not link private frameworks directly and uses `.forSession` display configuration by default.

On macOS 26.5.1, old `CGDisplayConfigRef` transactions can return `CGError 1001` for no-op enable calls. Lidless uses the matching private SkyLight transaction path first and treats `1001` as success only when the display is already in the requested active or inactive state.

## Known limitations

- The `Ctrl + Cmd + D` toggle hotkey conflicts with the macOS system shortcut for looking up a word in the dictionary. If dictionary lookup stops working, change or disable one of the shortcuts.
- Trusted-display detection is name-based. AirPlay displays advertise the receiver device name (for example a TV model), and localized display names may not contain the filtered fragments, so such displays can be misclassified as trusted physical monitors.
- The build targets Apple Silicon (`arm64`) only.

## Project structure

```text
Lidless/
├── Lidless/
│   ├── App/                 Entry point and AppDelegate
│   ├── Core/Display/        Display state, supervisor and the private API bridge
│   ├── Core/Hotkeys/        Global hotkeys
│   ├── Integrations/        LaunchAgents for starting at login
│   ├── Persistence/         State saved between launches
│   ├── UI/MenuBar/          Menu bar item and control popover
│   └── Info.plist
├── LidlessWatchdog/         Watchdog helper
├── tools/generate_icons.swift
├── design/icon-variants/    Icon variants
├── build.sh
└── install.sh
```

## License

[MIT](LICENSE)
