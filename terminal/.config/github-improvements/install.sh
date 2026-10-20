#!/bin/bash
set -euo pipefail

SOURCE="https://raw.githubusercontent.com/mikaelweiss/dotfiles/main/terminal/.config/github-improvements"
TARGET="$HOME/.github-improvements"

mkdir -p "$TARGET"
for file in manifest.json content.js styles.css; do
  curl -fsSL "$SOURCE/$file" -o "$TARGET/$file"
done
printf '%s' "$TARGET" | pbcopy

cat <<EOF
GitHub Improvements downloaded to $TARGET (path copied to your clipboard).

Browsers only load extensions you pick yourself, so finish in your browser:
  1. Open arc://extensions (or chrome://extensions).
  2. Turn on Developer mode, top right.
  3. Click Load unpacked, press Cmd+Shift+G, paste, and press Enter twice.

To update later, run this command again and click reload on the extension.
EOF
