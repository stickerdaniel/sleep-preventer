#!/bin/bash
set -e

cd "$(dirname "$0")/.."

APP_NAME="sleep-preventer"
INSTALL_DIR="/usr/local/bin"
LABEL="com.sleep-preventer"
PLIST="$HOME/Library/LaunchAgents/${LABEL}.plist"
SUDOERS_DST="/etc/sudoers.d/${APP_NAME}"
USER_NAME="$(id -un)"

echo "Installing Sleep Preventer..."
echo ""

# 1. Build
echo "1. Building release binary..."
swift build -c release
echo "   Done."
echo ""

# 2. Install binary
echo "2. Installing binary to $INSTALL_DIR..."
if [ -w "$INSTALL_DIR" ]; then
    cp ".build/release/$APP_NAME" "$INSTALL_DIR/"
else
    echo "   Requires sudo..."
    sudo cp ".build/release/$APP_NAME" "$INSTALL_DIR/"
fi
echo "   Done."
echo ""

# 3. Sudoers drop-in (passwordless pmset)
echo "3. Installing sudoers rule for passwordless pmset..."
SUDOERS_TMP="$(mktemp)"
trap 'rm -f "$SUDOERS_TMP"' EXIT
cat > "$SUDOERS_TMP" <<EOF
${USER_NAME} ALL=(ALL) NOPASSWD: /usr/bin/pmset -a disablesleep *
${USER_NAME} ALL=(ALL) NOPASSWD: /usr/bin/pmset sleepnow
EOF

if sudo visudo -cf "$SUDOERS_TMP" >/dev/null; then
    sudo install -m 440 -o root -g wheel "$SUDOERS_TMP" "$SUDOERS_DST"
    echo "   Installed: $SUDOERS_DST"
else
    echo "   ERROR: sudoers fragment failed visudo check; not installed." >&2
    exit 1
fi
echo ""

# 4. LaunchAgent
echo "4. Installing LaunchAgent..."
mkdir -p "$(dirname "$PLIST")"
cat > "$PLIST" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>${LABEL}</string>
    <key>ProgramArguments</key>
    <array>
        <string>${INSTALL_DIR}/${APP_NAME}</string>
    </array>
    <key>RunAtLoad</key>
    <true/>
    <key>KeepAlive</key>
    <dict>
        <key>SuccessfulExit</key>
        <false/>
    </dict>
    <key>ThrottleInterval</key>
    <integer>5</integer>
    <key>StandardOutPath</key>
    <string>/tmp/${APP_NAME}.log</string>
    <key>StandardErrorPath</key>
    <string>/tmp/${APP_NAME}.log</string>
</dict>
</plist>
EOF
echo "   Wrote: $PLIST"
echo ""

# 5. Reload (modern API; idempotent)
echo "5. Loading LaunchAgent..."
launchctl bootout "gui/$(id -u)/${LABEL}" 2>/dev/null || true
launchctl bootout "gui/$(id -u)" "$PLIST" 2>/dev/null || true
launchctl bootstrap "gui/$(id -u)" "$PLIST"
launchctl kickstart -k "gui/$(id -u)/${LABEL}"
echo "   Done. Will auto-start on login."
echo ""

echo "Installation complete."
echo ""
echo "Look for the bolt icon in the menubar. Click + 15 min to start a timer."
