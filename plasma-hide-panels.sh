#!/usr/bin/env bash
CFG="$HOME/.config/plasma-org.kde.plasma.mobileshell-appletsrc"
[ ! -f "$CFG" ] && exit 0
sed -i '/^\[Containments\]\[2\]$/,/^\[Containments\]\[3\]$/{
  /^\[Containments\]\[3\]$/!d
}' "$CFG"
sed -i '/^\[Containments\]\[3\]$/,$d' "$CFG"
chmod 444 "$CFG"
exit 0