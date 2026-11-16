#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
swift build -c release --product WaveAce --scratch-path build/swift
mkdir -p build/WaveAce.app/Contents/MacOS
cp build/swift/release/WaveAce build/WaveAce.app/Contents/MacOS/WaveAce
cp Resources/Info.plist build/WaveAce.app/Contents/Info.plist
codesign --force --sign - build/WaveAce.app
echo "Aplikace: $PWD/build/WaveAce.app"
