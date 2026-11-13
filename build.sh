#!/bin/bash
# Build and optionally install the native macOS FlightSaver screen saver.
set -euo pipefail
cd "$(dirname "$0")"

NAME="FlightSaver"
VERSION="$(tr -d '[:space:]' < VERSION)"
ARCH="${ARCH:-$(uname -m)}"
OUT="build/${NAME}.saver"

if [[ "$(uname -s)" != "Darwin" ]]; then
  echo "FlightSaver must be built on macOS (AppKit and ScreenSaver.framework are required)." >&2
  exit 1
fi

if [[ "$ARCH" != "arm64" && "$ARCH" != "x86_64" ]]; then
  echo "Unsupported ARCH '$ARCH'. Use arm64 or x86_64." >&2
  exit 1
fi

for tool in swiftc codesign; do
  command -v "$tool" >/dev/null 2>&1 || {
    echo "Missing required tool: $tool. Install Xcode Command Line Tools." >&2
    exit 1
  }
done

rm -rf build
mkdir -p "$OUT/Contents/MacOS"

swiftc -O \
  -target "${ARCH}-apple-macos12.0" \
  -module-name "$NAME" \
  -emit-library -Xlinker -bundle \
  -swift-version 5 \
  -framework ScreenSaver -framework AppKit \
  Sources/*.swift \
  -o "$OUT/Contents/MacOS/$NAME"

cp Info.plist "$OUT/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $VERSION" "$OUT/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $VERSION" "$OUT/Contents/Info.plist"
codesign --force --sign - "$OUT"

case "${1:-}" in
  --install)
    DEST="$HOME/Library/Screen Savers"
    mkdir -p "$DEST"
    rm -rf "$DEST/$NAME.saver"
    cp -R "$OUT" "$DEST/"
    killall legacyScreenSaver 2>/dev/null || true
    killall WallpaperAgent 2>/dev/null || true
    echo "Installed $NAME $VERSION to $DEST/$NAME.saver"
    ;;
  "")
    echo "Built $OUT ($ARCH, version $VERSION). Use ./build.sh --install to install it."
    ;;
  *)
    echo "Usage: ./build.sh [--install]" >&2
    exit 2
    ;;
esac
