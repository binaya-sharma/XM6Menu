#!/bin/zsh
set -euo pipefail

ROOT_DIR="${0:A:h:h}"
CONFIGURATION="${1:-debug}"
OUTPUT_DIR="$ROOT_DIR/outputs"
APP_DIR="$OUTPUT_DIR/XM6 Controller.app"

case "$CONFIGURATION" in
    debug|release) ;;
    *)
        echo "Configuration must be 'debug' or 'release'." >&2
        exit 64
        ;;
esac

cd "$ROOT_DIR"
mkdir -p "$ROOT_DIR/work/swiftpm-cache" "$ROOT_DIR/work/module-cache" "$ROOT_DIR/work/build"
export CLANG_MODULE_CACHE_PATH="$ROOT_DIR/work/module-cache"
SDK_PATH="$(xcrun --sdk macosx --show-sdk-path)"
ARCH="$(uname -m)"
INTERFACE_FILE="$(find "$SDK_PATH/usr/lib/swift/Swift.swiftmodule" -name "$ARCH*-apple-macos.swiftinterface" -print -quit)"
SDK_COMPILER_VERSION="$(sed -n 's/.*swiftlang-\([0-9.]*\).*/\1/p' "$INTERFACE_FILE" | head -1)"
ACTIVE_COMPILER_VERSION="$(swift --version 2>&1 | sed -n 's/.*swiftlang-\([0-9.]*\).*/\1/p' | head -1)"

if [[ "$SDK_COMPILER_VERSION" == "$ACTIVE_COMPILER_VERSION" ]] && \
    swift build -c "$CONFIGURATION" --cache-path "$ROOT_DIR/work/swiftpm-cache"; then
    BIN_DIR="$(swift build -c "$CONFIGURATION" --cache-path "$ROOT_DIR/work/swiftpm-cache" --show-bin-path)"
    EXECUTABLE="$BIN_DIR/XM6Controller"
else
    # Some Command Line Tools previews ship a compiler and SDK with different
    # patch builds. Compile directly using the SDK's interface version.
    /usr/bin/swiftc \
        -Xfrontend -interface-compiler-version -Xfrontend "$SDK_COMPILER_VERSION" \
        -module-cache-path "$ROOT_DIR/work/module-cache" \
        -target "$ARCH-apple-macosx14.0" -sdk "$SDK_PATH" -parse-as-library \
        "$ROOT_DIR"/Sources/XM6Controller/*.swift \
        -framework AppKit -framework ApplicationServices -framework SwiftUI \
        -framework CoreAudio -framework IOBluetooth -framework ServiceManagement \
        -o "$ROOT_DIR/work/build/XM6Controller"
    EXECUTABLE="$ROOT_DIR/work/build/XM6Controller"
fi

STAGING_DIR="$(mktemp -d "$ROOT_DIR/work/app-stage.XXXXXX")"
trap 'rm -rf "$STAGING_DIR"' EXIT
STAGED_APP="$STAGING_DIR/XM6 Controller.app"

mkdir -p "$STAGED_APP/Contents/MacOS" "$STAGED_APP/Contents/Resources" "$OUTPUT_DIR"
cp "$EXECUTABLE" "$STAGED_APP/Contents/MacOS/XM6Controller"
cp "$ROOT_DIR/Resources/Info.plist" "$STAGED_APP/Contents/Info.plist"
cp "$ROOT_DIR/Resources/AppIcon.icns" "$STAGED_APP/Contents/Resources/AppIcon.icns"
cp "$ROOT_DIR/Resources/XM6ProductRender.png" "$STAGED_APP/Contents/Resources/XM6ProductRender.png"
codesign --force --sign - "$STAGED_APP"

rm -rf "$APP_DIR"
mv "$STAGED_APP" "$APP_DIR"

echo "$APP_DIR"
