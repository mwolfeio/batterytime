#!/bin/bash
# Starts BatteryTime at login and right now. Run ./build.sh first.
#
# The app lives under ~/Documents, which macOS guards, so the LaunchAgent does not run the binary
# directly: it asks LaunchServices to open the bundle in the background (`/usr/bin/open -g`).
# Pass --dry-run to print the LaunchAgent without installing anything.
set -euo pipefail
cd "$(dirname "$0")"

LABEL=local.batterytime
APP="$(pwd)/BatteryTime.app"
PLIST="$HOME/Library/LaunchAgents/$LABEL.plist"

read -r -d '' CONTENT <<EOF || true
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>Label</key>
	<string>$LABEL</string>
	<key>ProgramArguments</key>
	<array>
		<string>/usr/bin/open</string>
		<string>-g</string>
		<string>$APP</string>
	</array>
	<key>RunAtLoad</key>
	<true/>
	<key>LimitLoadToSessionType</key>
	<string>Aqua</string>
</dict>
</plist>
EOF

if [[ "${1:-}" == "--dry-run" ]]; then
    echo "Would write $PLIST:"
    echo "$CONTENT"
    exit 0
fi

if [[ ! -x "$APP/Contents/MacOS/BatteryTime" ]]; then
    echo "BatteryTime.app not found; run ./build.sh first." >&2
    exit 1
fi

# Replace a running copy (e.g. after a rebuild).
pkill -x BatteryTime 2>/dev/null || true

mkdir -p "$(dirname "$PLIST")"
printf '%s\n' "$CONTENT" > "$PLIST"
plutil -lint "$PLIST" >/dev/null

launchctl bootout "gui/$(id -u)/$LABEL" 2>/dev/null || true
launchctl bootstrap "gui/$(id -u)" "$PLIST"   # RunAtLoad starts it now

for _ in 1 2 3 4 5 6 7 8 9 10; do
    if pgrep -x BatteryTime >/dev/null; then
        echo "BatteryTime is running and will start at login ($PLIST)."
        exit 0
    fi
    sleep 0.5
done
echo "LaunchAgent installed, but BatteryTime did not start; try: open -g \"$APP\"" >&2
exit 1
