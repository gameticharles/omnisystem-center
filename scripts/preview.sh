#!/usr/bin/env bash
# Renders preview.png (the marketplace image) from docs/preview/preview.html.
# Refresh the three screenshots first: open each tab with
# `omarchy-shell omnisystem-center show <tab>` (the Energy tab with
# `energyPeriod week`), grab the panel with grim, and trim the two scrolling
# tabs to the Overview's height above their power row.
set -euo pipefail
cd "$(dirname "$0")/../docs/preview"
out=$(mktemp --suffix=.png)
chromium --headless=new --disable-gpu --hide-scrollbars --force-device-scale-factor=1 \
  --window-size=2000,1240 --screenshot="$out" "file://$PWD/preview.html" 2>/dev/null
magick "$out" -strip -define png:compression-level=9 ../../preview.png
rm -f "$out"
echo "wrote preview.png"
