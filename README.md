# Sleep Preventer

A tiny macOS menubar app that keeps your Mac awake for a fixed amount of time, then lets it sleep normally. While active, closing the lid does not put the Mac to sleep — useful when an AI agent or long-running task needs to keep working on your laptop while you carry it.

| Feature | Detail |
|---|---|
| Manual timer | Click "+15 min" to add 15 minutes; click "Stop" to cancel. |
| Closed lid, awake system | Lid close → backlight off (zero display battery), but the system stays awake. |
| Auto-sleep on expiry | Timer reaches zero → normal sleep is re-enabled; if the lid is closed, the Mac sleeps immediately. |
| Battery-friendly | No always-on background loop. Sleep prevention only runs while the timer is active. |
| Crash-safe | LaunchAgent restarts on non-zero exit. Boot reconciliation clears any leaked `disablesleep=1`. |

## Install

```bash
git clone https://github.com/stickerdaniel/sleep-preventer ~/Documents/development/sleep-preventer
cd ~/Documents/development/sleep-preventer
./scripts/install.sh
```

The installer will:

1. Build the release binary with `swift build -c release`.
2. Copy it to `/usr/local/bin/sleep-preventer` (asks for sudo).
3. Install a scoped passwordless sudoers rule at `/etc/sudoers.d/sleep-preventer` allowing only `pmset -a disablesleep *` and `pmset sleepnow`.
4. Drop a LaunchAgent at `~/Library/LaunchAgents/com.sleep-preventer.plist` and start it via `launchctl bootstrap` + `kickstart`.

After install, look for a `bolt.slash` icon in your menubar.

## Usage

| Click | Effect |
|---|---|
| `+ 15 min` (idle) | Starts a 15-minute timer. Icon becomes `bolt.fill`. System sleep is disabled. |
| `+ 15 min` (running) | Adds 15 minutes to the remaining time. |
| `Stop` | Cancels the timer. If the lid is closed, the Mac sleeps immediately. |
| `Quit` | Exits the app cleanly. Sleep is re-enabled. The LaunchAgent does **not** auto-restart after a clean Quit (`KeepAlive: {SuccessfulExit: false}`). |

## How it works

- `pmset -a disablesleep 1` (via sudoers) prevents both lid-close and idle sleep.
- A polled `ioreg AppleClamshellState` check detects lid open/close and calls `pmset displaysleepnow` on close to kill the backlight while the system stays awake.
- On timer expiry or Stop, `pmset -a disablesleep 0` re-enables sleep. If the lid is closed at that moment, `pmset sleepnow` puts the Mac to sleep immediately.

## Requirements

- macOS 14 (Sonoma) or later
- Swift 5.9+
- Admin password (one time, during install) for the sudoers rule

## Uninstall

```bash
launchctl bootout "gui/$(id -u)/com.sleep-preventer" 2>/dev/null || true
rm -f ~/Library/LaunchAgents/com.sleep-preventer.plist
sudo rm -f /usr/local/bin/sleep-preventer
sudo rm -f /etc/sudoers.d/sleep-preventer
sudo pmset -a disablesleep 0
```

## Predecessor

Sleep Preventer replaces [opencode-sleep-control](https://github.com/stickerdaniel/opencode-sleep-control), which was driven by an HTTP `/active`/`/idle` plugin model intended for OpenCode. The new app trades that for a simpler manual timer UI — no daemon dependency on an external editor.

## License

MIT — see [LICENSE](LICENSE).
