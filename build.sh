#!/bin/bash
set -e

APP="SprintTimer.app"
BINARY="CountdownTimer"

rm -rf "$APP"

echo "Compiling..."
swiftc CountdownTimer.swift -o "$BINARY"

mkdir -p "$APP/Contents/MacOS"
cp "$BINARY" "$APP/Contents/MacOS/$BINARY"
cp Info.plist "$APP/Contents/Info.plist"

echo "Done — built $APP"
echo "To install: cp -r $APP /Applications/"
