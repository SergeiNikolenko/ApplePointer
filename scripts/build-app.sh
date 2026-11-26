#!/bin/bash
set -euo pipefail

cd "$(dirname "$0")/.."
PKG_ROOT="$(pwd)"
OUT_APP="${OUT_APP:-$PKG_ROOT/build/ApplePointer.app}"
VERSION="$(cat "$PKG_ROOT/VERSION" 2>/dev/null || echo 1.0.0)"
BUILD_NUM="$(git rev-list --count HEAD 2>/dev/null || echo 1)"

EXTRA_SWIFT_FLAGS=()
if [ -n "${SWIFT_BUILD_FLAGS:-}" ]; then
    # shellcheck disable=SC2206
    EXTRA_SWIFT_FLAGS=(${SWIFT_BUILD_FLAGS})
fi

if [ "${APPLEPOINTER_UNIVERSAL:-0}" = "1" ]; then
    ARCH_FLAGS=(--arch arm64 --arch x86_64)
elif [ -n "${BUILD_ARCHS:-}" ]; then
    # shellcheck disable=SC2206
    ARCH_FLAGS=(${BUILD_ARCHS})
else
    ARCH_FLAGS=(--arch "$(uname -m)")
fi

swift build -c release "${ARCH_FLAGS[@]}" "${EXTRA_SWIFT_FLAGS[@]}"
BIN_DIR=$(swift build -c release "${ARCH_FLAGS[@]}" "${EXTRA_SWIFT_FLAGS[@]}" --show-bin-path)

STAGING=$(mktemp -d)
cleanup() {
    rm -rf "$STAGING"
}
trap cleanup EXIT

APP="$STAGING/ApplePointer.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp -f "$BIN_DIR/ApplePointer" "$APP/Contents/MacOS/ApplePointer"
chmod 0755 "$APP/Contents/MacOS/ApplePointer"
cp -f "$PKG_ROOT/Resources/Info.plist" "$APP/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $VERSION" "$APP/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $BUILD_NUM" "$APP/Contents/Info.plist"
if [ -f "$PKG_ROOT/Resources/AppIcon.icns" ]; then
    cp -f "$PKG_ROOT/Resources/AppIcon.icns" "$APP/Contents/Resources/AppIcon.icns"
fi

xattr -cr "$APP"
if [ -n "${SIGN_IDENTITY:-}" ]; then
    IDENTITY="$SIGN_IDENTITY"
else
    IDENTITY="$(security find-identity -v -p codesigning 2>/dev/null | awk '/Apple Development|Developer ID Application/ { print $2; exit }' || true)"
fi
SIGN=(codesign --force --timestamp=none --sign "${IDENTITY:--}")
"${SIGN[@]}" --entitlements "$PKG_ROOT/Resources/ApplePointer.entitlements" "$APP"
codesign --verify --deep --strict "$APP"

mkdir -p "$(dirname "$OUT_APP")"
rm -rf "$OUT_APP"
ditto --norsrc --noextattr --noqtn "$APP" "$OUT_APP"
xattr -dr com.apple.FinderInfo "$OUT_APP" 2>/dev/null || true
xattr -dr com.apple.ResourceFork "$OUT_APP" 2>/dev/null || true
codesign --verify --deep "$OUT_APP"

echo "Built and verified $OUT_APP"
