# CutNumber

**日本語** · [English](../../README.md) · [한국어](ko.md) · [简体中文](zh-Hans.md) · [Español](es.md) · [Français](fr.md) · [Deutsch](de.md) · [Português](pt.md) · [Русский](ru.md) · [العربية](ar.md)

画像を並べ替え、連番のファイル名で保存できる無料のデスクトップアプリです。After Effects などに読み込むイメージシーケンスの準備や、静止画から無音の H.264 MP4 を作成するときに使えます。

[YouTube で32秒の操作デモを見る][demo] · [最新リリース][latest]

## ダウンロード

- [macOS 用 DMG][mac]（Apple Silicon、macOS 13 以降）。DMG を開き、**CutNumber.app** を「アプリケーション」フォルダにドラッグしてから起動します。
- [Windows 用 ZIP][win]（x64、Windows 11 または Windows 10 22H2）。ZIP をすべて展開し、**CutNumber.exe** を開きます。ショートカットを作成する場合は **Install.cmd** を実行します。

macOS 版はアドホック署名済みで、Apple の公証は受けていません。Windows 版には必要な .NET ランタイムが同梱されています。

## 使い方

1. ツールバー、ドラッグ＆ドロップ、または貼り付けで画像やフォルダを追加します。
2. 作成日時や更新日時で並べ替えるか、行を移動してフレームの順番を調整します。行を選ぶと、右側に画像のプレビューが表示されます。
3. 元の画像を残して連番付きのコピーを保存するか、元のファイル名を変更します。動画にする場合はフレームレートを選び、MP4 として書き出します。

## 日本語表示

初期設定は英語です。画面上部の **Language** から **日本語** を選ぶと、すぐに表示が切り替わり、次回の起動時にも設定が引き継がれます。ファイル選択ダイアログなど、OS が表示する部分にはシステムの言語設定が適用されます。

![macOS 版 CutNumber のフレーム一覧、連番ファイル名と画像プレビュー][screenshot]

[ソースからビルドする方法（英語）][build]

開発者は [Apple Craft][studio] の Kuidong Choi です。

© 2026 Apple Craft. All rights reserved.

[demo]: https://www.youtube.com/shorts/Fzm5j8mUUQo
[latest]: https://github.com/Choikuidong/CutNumber/releases/latest
[mac]: https://github.com/Choikuidong/CutNumber/releases/download/v1.0.4/CutNumber-1.0.4.dmg
[win]: https://github.com/Choikuidong/CutNumber/releases/download/v1.0.4/CutNumber-Windows-1.0.4.zip
[screenshot]: ../images/cutnumber-macos.png
[build]: ../../README.md#build-from-source
[studio]: https://applecraft.kr
