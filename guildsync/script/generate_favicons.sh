#!/usr/bin/env bash
# Generate missing favicon assets using ImageMagick's convert.
# Requires: ImageMagick (convert) on PATH.
# Run from repo root: ./script/generate_favicons.sh
# Or from guildsync: ./script/generate_favicons.sh (script uses paths relative to guildsync)

set -e
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DIR="$(cd "$SCRIPT_DIR/../app/assets/images/favicon" && pwd)"
cd "$DIR"

SOURCE_512="android-chrome-512x512.png"
if [[ ! -f "$SOURCE_512" ]]; then
  echo "Source not found: $DIR/$SOURCE_512"
  exit 1
fi

echo "Generating Android Chrome 48x48, 72x72, 144x144 from $SOURCE_512..."
for size in 48 72 144; do
  out="android-chrome-${size}x${size}.png"
  if [[ -f "$out" ]]; then
    echo "  $out exists, skip"
  else
    convert "$SOURCE_512" -resize "${size}x${size}" "$out"
    echo "  created $out"
  fi
done

echo "Generating favicon.ico from 16, 32, 48 PNGs..."
convert favicon-16x16.png favicon-32x32.png favicon-48x48.png favicon.ico
echo "Done."
