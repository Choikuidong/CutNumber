#!/bin/zsh
set -eu
cd -- "${0:A:h}/.."
test_dir="build/AboutLayoutCheck"
mkdir -p "$test_dir"
cp src/Shared/translations.json "$test_dir/"
cp src/macOS/Resources/AppleCraftSymbol.png "$test_dir/"
xcrun swiftc -parse-as-library src/macOS/Localization.swift src/macOS/AboutView.swift tests/AboutLayoutCheck.swift -o "$test_dir/check"
"$test_dir/check"
