#!/usr/bin/env bash
# Mirza Benevis - Build & Install to /Applications
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"
cd "$ROOT_DIR"

echo "╔═══════════════════════════════════════════════════╗"
echo "║   Mirza Benevis — Build & Install to macOS        ║"
echo "╚═══════════════════════════════════════════════════╝"
echo ""

# 1. Check prerequisites
echo "=== 1/3 Checking Prerequisites ==="
if ! command -v cmake &>/dev/null; then
    echo "❌ CMake پیدا نشد. لطفاً ابتدا با دستور زیر آن را نصب کنید:"
    echo "   brew install cmake"
    exit 1
fi

if ! xcrun --find swiftc &>/dev/null; then
    echo "❌ ابزارهای کامپایلر Swift پیدا نشد. لطفاً دستور زیر را اجرا کنید:"
    echo "   xcode-select --install"
    exit 1
fi
echo "  ✅ پیش‌نیازها آماده هستند (CMake و کامپایلر Swift)"

# 2. Run standalone build
echo ""
echo "=== 2/3 Building Mirza Benevis ==="
chmod +x "$ROOT_DIR/scripts/build_standalone.sh"
"$ROOT_DIR/scripts/build_standalone.sh"

# 3. Install to /Applications
echo ""
echo "=== 3/3 Installing to /Applications ==="
APP_SOURCE="${ROOT_DIR}/build_output/MirzaBenevis.app"
APP_TARGET="/Applications/Mirza Benevis.app"

if [ ! -d "$APP_SOURCE" ]; then
    echo "❌ فایل خروجی بیلد در ${APP_SOURCE} یافت نشد!"
    exit 1
fi

# Close app if already running
pkill -x "MirzaBenevis" 2>/dev/null || true

# Copy to /Applications (with graceful fallback to sudo or ~/Applications if permission is restricted)
if rm -rf "$APP_TARGET" 2>/dev/null && cp -R "$APP_SOURCE" "$APP_TARGET" 2>/dev/null; then
    echo "  ✅ با موفقیت در ${APP_TARGET} کپی شد."
elif command -v sudo &>/dev/null && sudo rm -rf "$APP_TARGET" 2>/dev/null && sudo cp -R "$APP_SOURCE" "$APP_TARGET" 2>/dev/null; then
    echo "  ✅ با موفقیت با مجوز دسترسی در ${APP_TARGET} کپی شد."
else
    USER_APPS="${HOME}/Applications"
    mkdir -p "$USER_APPS"
    APP_TARGET="${USER_APPS}/Mirza Benevis.app"
    rm -rf "$APP_TARGET"
    cp -R "$APP_SOURCE" "$APP_TARGET"
    echo "  ✅ با موفقیت در پوشه کاربری ${APP_TARGET} کپی شد."
fi

# Remove quarantine attribute to prevent Gatekeeper issues
xattr -cr "$APP_TARGET" 2>/dev/null || true

echo ""
echo "╔═══════════════════════════════════════════════════╗"
echo "║             🎉 نصب با موفقیت انجام شد!            ║"
echo "╠═══════════════════════════════════════════════════╣"
echo "║  برنامه در پوشه Applications قرار گرفت.           ║"
echo "║  برای اجرا کافیست روی آیکون برنامه کلیک کنید یا   ║"
echo "║  دستور زیر را در ترمینال بزنید:                   ║"
echo "║  open \"$APP_TARGET\""
echo "╚═══════════════════════════════════════════════════╝"
echo ""
