#!/bin/bash
# Builds STICKWARS, installs it to /Applications and opens it (the setup window walks through permissions).
set -euo pipefail
cd "$(dirname "$0")"
./build.sh
pkill -x STICKWARS 2>/dev/null && sleep 0.5 || true
rm -rf /Applications/STICKWARS.app
cp -R STICKWARS.app /Applications/
open /Applications/STICKWARS.app
echo "Installed /Applications/STICKWARS.app"
