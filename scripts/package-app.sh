#!/bin/sh
set -eu

root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
app="$root/dist/ClipHaven.app"
scratch=$(mktemp -d /tmp/cliphaven-package.XXXXXX)

cd "$root"
"$root/scripts/build-icon.sh"
swift build -c release --scratch-path "$scratch"

rm -rf "$app"
mkdir -p "$app/Contents/MacOS"
mkdir -p "$app/Contents/Resources"
cp -L "$scratch/release/ClipHaven" "$app/Contents/MacOS/ClipHaven"
cp "$root/packaging/Info.plist" "$app/Contents/Info.plist"
cp -L "$root/assets/ClipHavenIcon.icns" "$app/Contents/Resources/ClipHavenIcon.icns"
chmod 755 "$app/Contents/MacOS/ClipHaven"
plutil -lint "$app/Contents/Info.plist"
echo "$app"
