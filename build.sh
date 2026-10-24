#!/bin/bash
set -e

DIR="$(cd "$(dirname "$0")" && pwd)"
APP_NAME="Lattice.app"
BUILD_DIR="$DIR/build"
APP_DIR="$BUILD_DIR/$APP_NAME"
CONTENTS="$APP_DIR/Contents"
MACOS="$CONTENTS/MacOS"
RESOURCES="$CONTENTS/Resources"

# Handle arguments
INSTALL=false
CLEAN=false
MAKE_DMG=false

for arg in "$@"; do
    case "$arg" in
        --install|-i)
            INSTALL=true
            ;;
        --clean|-c)
            CLEAN=true
            ;;
        --dmg|-d)
            MAKE_DMG=true
            ;;
        --help|-h)
            echo "Usage: ./build.sh [OPTIONS]"
            echo "Options:"
            echo "  --install, -i    Compile and install Lattice.app to /Applications"
            echo "  --dmg, -d        Compile and package a distributable Lattice.dmg installer"
            echo "  --clean, -c      Clean build directory before building"
            echo "  --help, -h       Show this help message"
            exit 0
            ;;
    esac
done

if [ "$CLEAN" = true ]; then
    echo "🧹 Cleaning build artifacts..."
    rm -rf "$BUILD_DIR"
fi

echo "🔨 Building Lattice for macOS..."

mkdir -p "$MACOS" "$RESOURCES"

# Detect target architecture
ARCH="$(uname -m)"
echo "Target architecture: $ARCH (macOS 14.0+)"

# Compile Swift sources
swiftc -O "$DIR"/src/*.swift -o "$MACOS/Lattice" -target "${ARCH}-apple-macos14.0"

# Copy Info.plist
cp "$DIR/Info.plist" "$CONTENTS/Info.plist"

# Copy Icon
if [ -f "$DIR/AppIcon.icns" ]; then
    cp "$DIR/AppIcon.icns" "$RESOURCES/AppIcon.icns"
elif [ -f "$DIR/assets/icon.icns" ]; then
    cp "$DIR/assets/icon.icns" "$RESOURCES/AppIcon.icns"
fi

# Ad-hoc code sign with stable designated requirement to preserve TCC identity
codesign --force --deep -s - -r="designated => identifier \"com.fontour.lattice\"" "$APP_DIR"

echo "✅ Build successful: $APP_DIR"

# Install to /Applications if requested
if [ "$INSTALL" = true ]; then
    echo "📦 Installing to /Applications/$APP_NAME..."
    pkill -f "Lattice.app/Contents/MacOS/Lattice" || true
    sleep 0.5
    rm -rf "/Applications/$APP_NAME"
    cp -R "$APP_DIR" "/Applications/$APP_NAME"
    echo "🎉 Installed to /Applications/$APP_NAME successfully!"
    echo "🚀 Launching Lattice..."
    open "/Applications/$APP_NAME"
fi

# Package DMG if requested
if [ "$MAKE_DMG" = true ]; then
    DMG_NAME="Lattice.dmg"
    DMG_PATH="$BUILD_DIR/$DMG_NAME"
    DMG_STAGING="$BUILD_DIR/dmg_staging"
    
    echo "📀 Creating DMG installer package: $DMG_PATH..."
    rm -rf "$DMG_STAGING" "$DMG_PATH"
    mkdir -p "$DMG_STAGING"
    
    cp -R "$APP_DIR" "$DMG_STAGING/"
    ln -s /Applications "$DMG_STAGING/Applications"
    
    hdiutil create -volname "Lattice" -srcfolder "$DMG_STAGING" -ov -format UDZO "$DMG_PATH" > /dev/null
    rm -rf "$DMG_STAGING"
    
    echo "🎉 DMG created successfully: $DMG_PATH ($(du -h "$DMG_PATH" | cut -f1))"
fi
