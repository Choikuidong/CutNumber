#!/bin/zsh
set -eu
cd -- "${0:A:h}"
app_dir="../../build/macOS/컷넘버.app"
mkdir -p "$app_dir/Contents/MacOS" "$app_dir/Contents/Resources"
cp Info.plist "$app_dir/Contents/Info.plist"
cp ../Shared/translations.json "$app_dir/Contents/Resources/"
cp Resources/* "$app_dir/Contents/Resources/"
xcrun swiftc -parse-as-library -O -target arm64-apple-macosx13.0 CutNumber.swift Localization.swift AboutView.swift -o "$app_dir/Contents/MacOS/CutNumber"
codesign --force --deep --sign - "$app_dir"
