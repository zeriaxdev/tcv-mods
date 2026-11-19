#!/bin/sh
# Double-click to build The Choicer Voicer with these mods as a Mac app, from your own itch.io download.
cd "$(dirname "$0")" || exit 1
if ! command -v python3 >/dev/null 2>&1; then
  echo "Python 3 is needed. Install it from https://www.python.org/downloads/macos/ then double-click this again."
  echo; echo "Press Enter to close."; read -r _; exit 1
fi
python3 mac/build.py "$@"
status=$?
echo; echo "Press Enter to close."; read -r _
exit "$status"
