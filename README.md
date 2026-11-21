# CutNumber

CutNumber is a desktop app for arranging images, renaming them as a numbered sequence, and exporting the sequence as a silent H.264 MP4.

## Download for macOS

Download **CutNumber-1.0.4.dmg** from [the v1.0.4 release](https://github.com/Choikuidong/CutNumber/releases/tag/v1.0.4). Open the disk image, drag CutNumber into **Applications**, then launch it from there. This build requires an Apple Silicon Mac running macOS 13 or later. The app is ad hoc signed and has not been notarized by Apple.

## Use CutNumber

1. Add images or folders using the toolbar, drag and drop, or paste.
2. Arrange the frames. Sort by creation or modification time, move rows, and select a frame to preview it.
3. Save copies with sequential file names, rename the originals, or export the list as an MP4 at the selected frame rate.

English is the default. The language selector supports Korean, Japanese, Simplified Chinese, Spanish, French, German, Portuguese, Russian, and Arabic. Changes apply immediately and are saved for the next launch. Native file dialog controls and system error details can follow the operating system language.

## Build from source

On an Apple Silicon Mac with Xcode Command Line Tools:

```sh
./src/macOS/build.command
```

The built application is placed in the macOS subfolder of `build`.

To build the self-contained Windows x64 application with the .NET 10 SDK:

```sh
dotnet publish src/Windows/CutNumber.csproj -c Release -r win-x64 --self-contained true -o build/Windows
```

Windows 11 x64 and Windows 10 22H2 x64 are the intended targets. HEIC and WebP support can depend on installed codecs. Windows N may require the Media Feature Pack for video export. The Windows build was cross-compiled and its file operations were tested. The Windows interface, installation, and video export have not been exercised on Windows.

## Checks

```sh
python3 tests/check-translations.py
./tests/check-macos-about.command
dotnet run --project tests/LocalizationTests.csproj
```

Developed by Kuidong Choi at [Apple Craft](https://applecraft.kr).

© 2026 Apple Craft. All rights reserved.
