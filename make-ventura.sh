#!/bin/bash
# Builds the Ventura-compatible variant (DJ-mode audio tap compiled out) → dist/Dockly-Ventura.dmg
set -e
cd "$(dirname "$0")"
DOCKLY_SUFFIX="-Ventura" DOCKLY_DEFINES="-Xswiftc -DDOCKLY_VENTURA" ./make-dmg.sh
