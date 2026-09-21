#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
INSTALL_DIR="$HOME/Library/Application Support/bluer-bubbles"
BINARY_PATH="$INSTALL_DIR/bluer-bubbles-mac"
PLIST_PATH="$HOME/Library/LaunchAgents/com.bluer-bubbles.mac.plist"
LABEL="com.bluer-bubbles.mac"

cd "$ROOT_DIR"

swift build -c release
BIN_DIR="$(swift build -c release --show-bin-path)"
mkdir -p "$INSTALL_DIR" "$HOME/Library/LaunchAgents" "$HOME/Library/Logs"

launchctl bootout "gui/$(id -u)" "$PLIST_PATH" 2>/dev/null || true

cat > "$PLIST_PATH" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
  "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>$LABEL</string>
    <key>ProgramArguments</key>
    <array>
        <string>$BINARY_PATH</string>
    </array>
    <key>WorkingDirectory</key>
    <string>$INSTALL_DIR</string>
    <key>RunAtLoad</key>
    <true/>
    <key>KeepAlive</key>
    <true/>
    <key>ProcessType</key>
    <string>Interactive</string>
    <key>StandardOutPath</key>
    <string>$HOME/Library/Logs/bluer-bubbles-mac.log</string>
    <key>StandardErrorPath</key>
    <string>$HOME/Library/Logs/bluer-bubbles-mac.error.log</string>
</dict>
</plist>
PLIST

cp "$BIN_DIR/bluer-bubbles-mac" "$BINARY_PATH"
chmod 755 "$BINARY_PATH"

launchctl bootstrap "gui/$(id -u)" "$PLIST_PATH"

echo "Installed and started $LABEL"
