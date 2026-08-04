#!/usr/bin/env bash
# Makes the favicon logo appear LARGER in the tab: trim transparent edges,
# then resize so the logo fills the frame. Requires ImageMagick (convert).
#
# Run from repo root:  ./script/expand_favicon.sh
# Or from guildsync:   ./script/expand_favicon.sh

set -e
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DIR="$(cd "$SCRIPT_DIR/../app/assets/images/favicon" && pwd)"
cd "$DIR"

for size in 32 16; do
  src="favicon-${size}x${size}.png"
  [ -f "$src" ] || { echo "Missing $src"; exit 1; }
  echo "Expanding $src so logo fills ${size}x${size}..."
  convert "$src" -trim -resize "${size}x${size}" "$src"
done
echo "Done. Hard-refresh the site to see the larger tab icon."
