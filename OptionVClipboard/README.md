# OptionVClipboard

Private macOS clipboard history for local use.

## Build

```bash
cd OptionVClipboard
./scripts/build-app.sh
```

## Install

```bash
./scripts/install.sh
```

This copies the signed app bundle to `~/Applications/OptionVClipboard.app`.

## Test

```bash
swift test
```

If SwiftPM cannot find Swift Testing on a Command Line Tools-only install, run:

```bash
DEVELOPER_DIR="$(xcode-select -p)" swift test
```

## Run

Open `~/Applications/OptionVClipboard.app` from Finder or Launchpad.
The app is an `LSUIElement` agent, so it should run without a normal Dock icon.

## Picker Shortcuts

- `Option+V` opens history.
- Single-click an item to select it.
- `Enter` copies the selected item to the clipboard and closes the picker.
- `Command+C` copies the selected item to the clipboard and closes the picker.
- Double-click an item to copy it, return to the previous app, and paste it with `Command+V`.

Double-click auto-paste requires macOS Accessibility permission because the app must synthesize `Command+V`. If macOS prompts, enable OptionVClipboard in System Settings, then try again.

After double-clicking, auto-paste waits for the previous app to become active. The pending paste is cancelled after 3 seconds or when you copy another history item with `Enter` or `Command+C`.

## Uninstall

```bash
./scripts/uninstall.sh
```

This quits the running app if it is active and removes the app bundle from `~/Applications`.
It does not delete encrypted clipboard history or the Keychain encryption key.

## Privacy Model

The app is local only and uses Apple frameworks only.
It keeps plain-text clipboard history encrypted on disk.
The encryption key stays in macOS Keychain.
Clipboard capture should respect do-not-retain pasteboard markers, ignore obvious secret-like text, and store only plain text.

## Storage Location

Expected storage lives under the user Library support area, typically:

`~/Library/Application Support/OptionVClipboard/`

Encrypted history should stay there, while the encryption key stays in Keychain.

## Manual Test Checklist

1. Build the app bundle with `./scripts/build-app.sh`.
2. Install it with `./scripts/install.sh`.
3. Launch the app and confirm it runs as a menu-bar agent.
4. Copy plain text in another app and confirm it appears in history.
5. Copy the same text again and confirm it does not spam duplicate entries.
6. Copy text marked as transient or concealed and confirm it is skipped.
7. Pause capture and confirm new copies are not stored.
8. Resume capture and confirm storage starts again.
9. Quit the app and confirm the app bundle remains installed.
10. Uninstall with `./scripts/uninstall.sh` and confirm the bundle is removed while storage remains intact.
