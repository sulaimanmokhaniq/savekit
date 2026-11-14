#!/usr/bin/env bash
# Rebuilds the gallery-dl bundle shipped inside the APK.
#
# gallery-dl and its dependencies are pure Python, so they run on the Python runtime that
# youtubedl-android already embeds. This script downloads their wheels from PyPI and packs
# them into android/app/src/main/assets/gallerydl/, where GalleryEngine.kt unpacks them on
# first launch. Run it to refresh the version new installs start with; existing installs
# update gallery-dl in place through the app's "Update Engine" action.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="$ROOT/android/app/src/main/assets/gallerydl"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

python3 -m pip download --quiet --no-deps --only-binary=:all: \
  --python-version 3.11 --implementation py --abi none --platform any \
  -d "$WORK/wheels" \
  gallery-dl requests urllib3 idna certifi charset-normalizer

mkdir -p "$WORK/site"
for wheel in "$WORK"/wheels/*.whl; do
  unzip -qo "$wheel" -d "$WORK/site"
done
rm -rf "$WORK"/site/*.dist-info "$WORK"/site/*.data

VERSION="$(basename "$WORK"/wheels/gallery_dl-*.whl | cut -d- -f2)"

mkdir -p "$OUT"
rm -f "$OUT/site.zip"
(cd "$WORK/site" && zip -qr -X "$OUT/site.zip" .)
printf '%s\n' "$VERSION" > "$OUT/version.txt"

echo "Bundled gallery-dl $VERSION -> $OUT"
