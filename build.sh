#!/bin/bash
set -e

APP="SprintTimer.app"
BINARY="CountdownTimer"

rm -rf "$APP"

echo "Generating icon..."
swift make_icon.swift

echo "Compiling..."
swiftc CountdownTimer.swift -o "$BINARY"

mkdir -p "$APP/Contents/MacOS"
mkdir -p "$APP/Contents/Resources"
cp "$BINARY"       "$APP/Contents/MacOS/$BINARY"
cp Info.plist      "$APP/Contents/Info.plist"
cp AppIcon.icns    "$APP/Contents/Resources/AppIcon.icns"

echo "Done — built $APP"
echo "To install: cp -r $APP /Applications/"
