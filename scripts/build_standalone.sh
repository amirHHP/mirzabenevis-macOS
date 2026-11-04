#!/usr/bin/env bash
# Standalone macOS build & DMG installer generator for Mirza Benevis
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"
cd "$ROOT_DIR"

BUILD_DIR="build_output"
APP_NAME="MirzaBenevis"
APP_DISPLAY_NAME="Mirza Benevis"
APP_BUNDLE="${BUILD_DIR}/${APP_NAME}.app"
CONTENTS_DIR="${APP_BUNDLE}/Contents"
MACOS_DIR="${APP_BUNDLE}/Contents/MacOS"
RESOURCES_DIR="${APP_BUNDLE}/Contents/Resources"
MODULES_DIR="${BUILD_DIR}/modules"

echo ""
echo "╔══════════════════════════════════════════╗"
echo "║   Mirza Benevis — macOS Build Script     ║"
echo "╚══════════════════════════════════════════╝"
echo ""

# ─── Step 1: Prepare Build Directories ───────────────────────────────────────

echo "=== 1/7 Preparing Build Directories ==="
rm -rf "$BUILD_DIR"
mkdir -p "$MACOS_DIR"
mkdir -p "$RESOURCES_DIR"
mkdir -p "$MODULES_DIR"

# ─── Step 2: Generate App Icon ───────────────────────────────────────────────

echo "=== 2/7 Generating App Icon ==="
ICON_SOURCE="installer/icon_1024_rgba.png"
ICNS_FILE="installer/AppIcon.icns"

if [ -f "$ICNS_FILE" ]; then
    echo "  Using pre-built icon: ${ICNS_FILE}"
    cp "$ICNS_FILE" "${RESOURCES_DIR}/AppIcon.icns"
elif [ -f "$ICON_SOURCE" ]; then
    echo "  Building .icns from ${ICON_SOURCE}..."
    ICONSET_DIR="${BUILD_DIR}/AppIcon.iconset"
    mkdir -p "$ICONSET_DIR"

    for s in 16 32 64 128 256 512 1024; do
        sips -z $s $s "$ICON_SOURCE" --out "$ICONSET_DIR/icon_${s}x${s}.png" > /dev/null 2>&1
    done

    cp "$ICONSET_DIR/icon_32x32.png" "$ICONSET_DIR/icon_16x16@2x.png"
    cp "$ICONSET_DIR/icon_64x64.png" "$ICONSET_DIR/icon_32x32@2x.png"
    cp "$ICONSET_DIR/icon_256x256.png" "$ICONSET_DIR/icon_128x128@2x.png"
    cp "$ICONSET_DIR/icon_512x512.png" "$ICONSET_DIR/icon_256x256@2x.png"
    cp "$ICONSET_DIR/icon_1024x1024.png" "$ICONSET_DIR/icon_512x512@2x.png"
    rm -f "$ICONSET_DIR/icon_64x64.png" "$ICONSET_DIR/icon_1024x1024.png"

    iconutil -c icns "$ICONSET_DIR" -o "${RESOURCES_DIR}/AppIcon.icns"
    rm -rf "$ICONSET_DIR"
    echo "  ✅ Icon generated"
else
    echo "  ⚠️ No icon source found, skipping"
fi

# ─── Step 3: Create whisper modulemap and compile whisper if needed ──────────

echo "=== 3/7 Preparing whisper.cpp ==="
if [ ! -f "build_whisper/src/libwhisper.a" ]; then
    echo "  Building whisper.cpp static libraries with cmake..."
    cmake -B build_whisper -S vendor/whisper.cpp -DGGML_METAL=ON -DWHISPER_BUILD_EXAMPLES=OFF -DWHISPER_BUILD_TESTS=OFF
    cmake --build build_whisper --config Release -j
fi

cp vendor/whisper.cpp/include/whisper.h "$MODULES_DIR/"
cp vendor/whisper.cpp/ggml/include/ggml.h "$MODULES_DIR/"
cp vendor/whisper.cpp/ggml/include/ggml-alloc.h "$MODULES_DIR/"
cp vendor/whisper.cpp/ggml/include/ggml-backend.h "$MODULES_DIR/"
cp vendor/whisper.cpp/ggml/include/ggml-metal.h "$MODULES_DIR/"
cp vendor/whisper.cpp/ggml/include/ggml-cpu.h "$MODULES_DIR/"
cp vendor/whisper.cpp/ggml/include/ggml-blas.h "$MODULES_DIR/"
cp vendor/whisper.cpp/ggml/include/gguf.h "$MODULES_DIR/"

cat > "$MODULES_DIR/module.modulemap" << 'EOF'
module whisper {
    header "whisper.h"
    export *
}
EOF

# ─── Step 4: Compile Swift ───────────────────────────────────────────────────

echo "=== 4/7 Compiling Swift Source Files ==="
SWIFT_FILES=$(find MacApp/MirzaBenevis -name "*.swift")

SDK_PATH=""
for sdk in \
  "/Library/Developer/CommandLineTools/SDKs/MacOSX26.5.sdk" \
  "/Library/Developer/CommandLineTools/SDKs/MacOSX26.sdk" \
  "/Library/Developer/CommandLineTools/SDKs/MacOSX15.4.sdk" \
  "/Library/Developer/CommandLineTools/SDKs/MacOSX15.sdk" \
  "/Library/Developer/CommandLineTools/SDKs/MacOSX14.sdk"; do
  if [ -d "$sdk" ]; then
    SDK_PATH="$sdk"
    break
  fi
done

if [ -z "$SDK_PATH" ]; then
  SDK_PATH=$(xcrun --show-sdk-path)
fi

echo "  SDK: ${SDK_PATH}"
echo "  Compiling..."

mkdir -p /tmp/clang_module_cache

swiftc -sdk "$SDK_PATH" \
  -I "$MODULES_DIR" \
  -module-cache-path /tmp/clang_module_cache \
  -O \
  -target arm64-apple-macosx14.0 \
  -o "${MACOS_DIR}/${APP_NAME}" \
  $SWIFT_FILES \
  -L build_whisper/src \
  -L build_whisper/ggml/src \
  -L build_whisper/ggml/src/ggml-metal \
  -L build_whisper/ggml/src/ggml-blas \
  -lwhisper -lggml -lggml-base -lggml-cpu -lggml-metal -lggml-blas \
  -lc++ \
  -framework Accelerate -framework Metal -framework Foundation -framework AVFoundation -framework ScreenCaptureKit -framework SwiftUI -framework Combine -framework Security -framework EventKit

echo "  ✅ Compilation successful"

# ─── Step 5: Prepare App Bundle ──────────────────────────────────────────────

echo "=== 5/7 Preparing App Bundle ==="

# Copy and update Info.plist
cp MacApp/MirzaBenevis/Info.plist "${CONTENTS_DIR}/Info.plist"
sed -i '' "s/\$(EXECUTABLE_NAME)/${APP_NAME}/g" "${CONTENTS_DIR}/Info.plist"

# Add icon reference to Info.plist (inject before closing </dict>)
if ! grep -q "CFBundleIconFile" "${CONTENTS_DIR}/Info.plist"; then
    sed -i '' 's|</dict>|    <key>CFBundleIconFile</key>\
    <string>AppIcon</string>\
</dict>|' "${CONTENTS_DIR}/Info.plist"
    echo "  Added CFBundleIconFile to Info.plist"
fi

# Add PkgInfo
echo -n "APPL????" > "${CONTENTS_DIR}/PkgInfo"

# Copy pre-downloaded models if they exist
if [ -d "models" ]; then
  echo "  Copying pre-downloaded models..."
  cp models/ggml-*.bin "${RESOURCES_DIR}/" 2>/dev/null || true
fi

echo "  ✅ App bundle ready"

# ─── Step 6: Code Signing ────────────────────────────────────────────────────

echo "=== 6/7 Code Signing ==="
SIGNING_IDENTITY="-"
if security find-identity -p codesigning | grep -q "MirzaBenevisLocalSign"; then
  SIGNING_IDENTITY="MirzaBenevisLocalSign"
  echo "  Using local code signing identity: ${SIGNING_IDENTITY}"
  codesign --force --deep \
    --entitlements MacApp/MirzaBenevis/MirzaBenevis.entitlements \
    --sign "$SIGNING_IDENTITY" \
    "$APP_BUNDLE"
else
  echo "  ⚠️ MirzaBenevisLocalSign identity not found. Using ad-hoc signing (without hardened runtime to avoid AMFI SIGKILL)."
  codesign --force --deep \
    --entitlements MacApp/MirzaBenevis/MirzaBenevis.entitlements \
    --sign "-" \
    "$APP_BUNDLE"
fi

if [ "$SIGNING_IDENTITY" = "-" ]; then
  echo "  ✅ Signed (ad-hoc)"
else
  echo "  ✅ Signed with ${SIGNING_IDENTITY}"
fi

# ─── Step 7: Package Release Artifacts (DMG & ZIP) ───────────────────────────

echo "=== 7/7 Packaging Release Artifacts ==="
APP_VERSION=$(/usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" "${CONTENTS_DIR}/Info.plist" 2>/dev/null || echo "1.0.0")
echo "  Version: v${APP_VERSION}"

DMG_VERSIONED="${BUILD_DIR}/${APP_NAME}-v${APP_VERSION}.dmg"
DMG_FILE="${BUILD_DIR}/${APP_NAME}.dmg"
ZIP_VERSIONED="${BUILD_DIR}/${APP_NAME}-v${APP_VERSION}.zip"
ZIP_FILE="${BUILD_DIR}/${APP_NAME}.zip"

# 1. Create ZIP archive (preserves symlinks and code signature)
echo "  Creating ZIP archive..."
ditto -c -k --sequesterRsrc --keepParent "$APP_BUNDLE" "$ZIP_VERSIONED"
cp -f "$ZIP_VERSIONED" "$ZIP_FILE"
echo "  ✅ ZIP created: ${ZIP_VERSIONED}"

# 2. Create DMG Installer
DMG_TEMP="${BUILD_DIR}/dmg_staging"
rm -rf "$DMG_TEMP"
mkdir -p "$DMG_TEMP"
cp -R "$APP_BUNDLE" "$DMG_TEMP/"
ln -s /Applications "$DMG_TEMP/Applications"
rm -f "$DMG_VERSIONED" "$DMG_FILE"

if hdiutil create -volname "${APP_DISPLAY_NAME}" -srcfolder "$DMG_TEMP" -ov -format UDZO "$DMG_VERSIONED" > /dev/null 2>&1; then
    cp -f "$DMG_VERSIONED" "$DMG_FILE"
    echo "  ✅ DMG created at: ${DMG_VERSIONED}"
else
    echo "  ℹ️ DMG creation skipped or not permitted in current sandbox. ZIP is ready: ${ZIP_VERSIONED}"
fi
rm -rf "$DMG_TEMP"

# ─── Done ────────────────────────────────────────────────────────────────────

APP_SIZE=$(du -sh "$APP_BUNDLE" | cut -f1)

echo ""
echo "╔══════════════════════════════════════════╗"
echo "║          ✅ Build Successful!             ║"
echo "╠══════════════════════════════════════════╣"
echo "║  App:     ${APP_BUNDLE} (${APP_SIZE})"
if [ -f "$DMG_VERSIONED" ]; then
    DMG_SIZE=$(du -h "$DMG_VERSIONED" | cut -f1)
    echo "║  DMG:     ${DMG_VERSIONED} (${DMG_SIZE})"
fi
if [ -f "$ZIP_VERSIONED" ]; then
    ZIP_SIZE=$(du -h "$ZIP_VERSIONED" | cut -f1)
    echo "║  ZIP:     ${ZIP_VERSIONED} (${ZIP_SIZE})"
fi
echo "╚══════════════════════════════════════════╝"
echo ""
