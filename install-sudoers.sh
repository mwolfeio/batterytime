#!/bin/bash
# Optional. Lets BatteryTime change the energy mode without the administrator prompt by installing
# /etc/sudoers.d/batterytime, which allows only `pmset -b|-c powermode 0|1|2`.
# Asks for your password once (sudo). Remove with: sudo rm /etc/sudoers.d/batterytime
set -euo pipefail
cd "$(dirname "$0")"

USER_NAME="${SUDO_USER:-$(id -un)}"
TMP="$(mktemp)"
trap 'rm -f "$TMP"' EXIT

sed "s/__USER__/$USER_NAME/g" Resources/sudoers-batterytime > "$TMP"
/usr/sbin/visudo -cf "$TMP" >/dev/null       # refuse to install a rule that doesn't parse

sudo /usr/bin/install -m 0440 -o root -g wheel "$TMP" /etc/sudoers.d/batterytime
sudo /usr/sbin/visudo -c >/dev/null           # whole sudoers config still valid
echo "Installed /etc/sudoers.d/batterytime for $USER_NAME."
