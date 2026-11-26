# CutNumber

[日本語](ja.md) · [English](../../README.md) · [한국어](ko.md) · **简体中文** · [Español](es.md) · [Français](fr.md) · [Deutsch](de.md) · [Português](pt.md) · [Русский](ru.md) · [العربية](ar.md)

CutNumber 是一款免费的桌面应用，可排列图像、批量生成连续编号的文件名，并将图像序列导出为无声 H.264 MP4。你可以用它准备导入 After Effects 等软件的图像序列。

[在 YouTube 观看 32 秒演示][demo] · [最新版本][latest]

## 下载

- [macOS DMG][mac]（Apple 芯片，macOS 13 或更高版本）。打开 DMG，将 **CutNumber.app** 拖入「应用程序」文件夹，然后启动。应用采用临时签名，未经 Apple 公证。
- [Windows ZIP][win]（x64，Windows 11 或 Windows 10 22H2）。完整解压后运行 **CutNumber.exe**。运行 **Install.cmd** 可创建快捷方式。压缩包附带所需的 .NET 运行时。

## 使用方法

1. 通过工具栏、拖放或粘贴添加图像或文件夹。
2. 按创建或修改时间排序，也可手动移动列表中的行。选中一帧即可预览。
3. 保存带连续编号的副本，或直接重命名原文件。制作视频时，选择帧率并导出为 MP4。

默认使用英语。在顶部的 **Language** 菜单中选择 **简体中文**，界面会立即切换，并记住该设置。

![macOS 版 CutNumber 的帧列表、编号文件名和预览][screenshot]

[从源代码构建（英语）][build]

由 [Apple Craft][studio] 的 Kuidong Choi 开发。

© 2026 Apple Craft. All rights reserved.

[demo]: https://www.youtube.com/shorts/Fzm5j8mUUQo
[latest]: https://github.com/Choikuidong/CutNumber/releases/latest
[mac]: https://github.com/Choikuidong/CutNumber/releases/download/v1.0.4/CutNumber-1.0.4.dmg
[win]: https://github.com/Choikuidong/CutNumber/releases/download/v1.0.4/CutNumber-Windows-1.0.4.zip
[screenshot]: ../images/cutnumber-macos.png
[build]: ../../README.md#build-from-source
[studio]: https://applecraft.kr
