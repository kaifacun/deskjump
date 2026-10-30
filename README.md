<p align="center">
  <img src="docs/icon.png" width="128" alt="DeskJump icon">
</p>

<h1 align="center">DeskJump</h1>

<p align="center">
  Your macOS desktops as numbers in the menu bar. Click one to jump straight to it.
</p>

---

macOS lets you create several desktops (Spaces), but there's no built-in way to see how many you have, which one you're on, or to jump to one with a click. DeskJump adds a small strip to the menu bar:

```
 [1] [■2] [3]
```

- **One box per desktop** on the display under your mouse. The filled box is the desktop you're on.
- **Click a number** to jump straight to that desktop.
- **Full-screen apps** show up as `F`.
- **Multiple displays** with *Displays have separate Spaces* turned on: DeskJump shows the desktops of the display your mouse is on.
- **Right-click** for settings: launch at login, instant switching, open Mission Control, quit.

## Install

### Homebrew

```bash
brew install --cask kaifacun/tap/deskjump
```

### Manual

1. Download `DeskJump-x.y.z.zip` from the [latest release](https://github.com/kaifacun/deskjump/releases/latest).
2. Unzip it and move `DeskJump.app` to `/Applications`.
3. Open it.

DeskJump needs macOS 13 Ventura or later and runs on Apple silicon and Intel Macs.

## First launch

On first launch DeskJump:

1. **Asks for Accessibility access.** Turn on **DeskJump** in *System Settings › Privacy & Security › Accessibility*. DeskJump needs this to send the keyboard shortcut that switches desktops. It works as soon as you flip the switch, with no relaunch.
2. **Registers itself to launch at login.** You can turn this off from the right-click menu or in *System Settings › General › Login Items*.
3. **Turns on macOS's "Switch to Desktop 1–10" shortcuts** (`⌃1` … `⌃0`) if none are set up yet, so clicks jump directly instead of stepping one desktop at a time. These are standard shortcuts in *System Settings › Keyboard › Keyboard Shortcuts › Mission Control*, and you can turn them off there. Note that `⌃1`–`⌃0` will then switch desktops in every app.

## How it works

- **Reading desktops:** DeskJump reads the list of desktops and the current one from the WindowServer, using the same private SkyLight call (`CGSCopyManagedDisplaySpaces`) that the Dock uses. Nothing is modified.
- **Switching:** macOS has no public API for switching desktops. DeskJump posts the same keyboard shortcut you would press:
  - `⌃N` ("Switch to Desktop N") when it's enabled.
  - Otherwise `⌃←` / `⌃→` repeatedly.
  - After a direct jump it checks that it landed on the right desktop and corrects with arrow steps if not.
- **Clicks on the strip:** recent macOS versions deliver every status-item click at the item's center. DeskJump therefore uses the real mouse position to work out which number you clicked.

DeskJump makes no network connections and collects no data.

## Troubleshooting

| Problem | Fix |
|---|---|
| Clicking does nothing | Check that DeskJump is on in *Privacy & Security › Accessibility*. If it is, remove it with **−** and add it again. |
| Jumps step through each desktop | Right-click › **Enable Instant Switching**, or turn on "Switch to Desktop N" in Keyboard Shortcuts. |
| Want logs | `defaults write com.kaifacun.deskjump DebugLogging -bool true`, then see `~/Library/Logs/DeskJump.log`. |

## Uninstall

```bash
brew uninstall --zap --cask deskjump
```

Or quit DeskJump from the right-click menu and delete `/Applications/DeskJump.app`.

## Build from source

You need Xcode or the Command Line Tools (Swift 5.9+).

```bash
git clone https://github.com/kaifacun/deskjump.git
cd deskjump
./build.sh --install    # build a Universal app, copy to /Applications and launch
```

`build.sh` signs with the first *Developer ID Application* or *Apple Development* identity it finds, or ad-hoc otherwise. With ad-hoc signing macOS treats every rebuild as a new app, so you'll need to re-grant Accessibility after each build.

### Releasing (maintainers)

Pushing a tag such as `v1.0.1` runs [`.github/workflows/release.yml`](.github/workflows/release.yml). The workflow:

1. Builds, signs and notarizes the app.
2. Publishes a GitHub release.
3. Updates the cask in [kaifacun/homebrew-tap](https://github.com/kaifacun/homebrew-tap).

It needs these repository secrets:

| Secret | Value |
|---|---|
| `DEVELOPER_ID_CERT_P12_BASE64` | `base64 -i DeveloperID.p12` of your *Developer ID Application* certificate + private key |
| `DEVELOPER_ID_CERT_PASSWORD` | Password of that `.p12` |
| `APPLE_ID` | Apple ID email used for notarization |
| `APPLE_TEAM_ID` | 10-character Team ID |
| `APPLE_APP_PASSWORD` | App-specific password from [account.apple.com](https://account.apple.com) |
| `TAP_GITHUB_TOKEN` | Fine-grained token with *Contents: read & write* on `kaifacun/homebrew-tap` |

## License

[MIT](LICENSE)
