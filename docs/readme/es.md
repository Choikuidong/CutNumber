# CutNumber

[日本語](ja.md) · [English](../../README.md) · [한국어](ko.md) · [简体中文](zh-Hans.md) · **Español** · [Français](fr.md) · [Deutsch](de.md) · [Português](pt.md) · [Русский](ru.md) · [العربية](ar.md)

CutNumber es una aplicación de escritorio gratuita para ordenar imágenes, numerar sus nombres de archivo en lote y exportarlas como vídeo MP4 (H.264) sin audio. Sirve para preparar secuencias de imágenes para After Effects y otros editores.

[Ver la demostración de 32 segundos en YouTube][demo] · [Última versión][latest]

## Descargar

- [DMG para macOS][mac] (Apple Silicon, macOS 13 o posterior). Arrastra **CutNumber.app** a **Aplicaciones** y ábrela desde ahí. La aplicación tiene firma ad hoc y no está notarizada por Apple.
- [ZIP para Windows][win] (x64, Windows 11 o Windows 10 22H2). Extrae todo el ZIP y ejecuta **CutNumber.exe**. Ejecuta **Install.cmd** para crear accesos directos. El ZIP incluye el entorno de ejecución de .NET.

## Cómo usar CutNumber

1. Añade imágenes o carpetas desde la barra de herramientas, arrastrándolas o pegándolas.
2. Ordena por fecha de creación o modificación, o mueve las filas manualmente. Selecciona un fotograma para ver su vista previa.
3. Guarda copias numeradas o cambia el nombre de los archivos originales. Para crear un vídeo, elige la velocidad de fotogramas y exporta a MP4.

El idioma inicial es el inglés. Elige **Español** en el menú **Language**. El cambio es inmediato y se guarda para la próxima vez.

![CutNumber en macOS con la lista de fotogramas, los nombres numerados y la vista previa][screenshot]

[Compilar desde el código fuente (en inglés)][build]

Desarrollado por Kuidong Choi en [Apple Craft][studio].

© 2026 Apple Craft. All rights reserved.

[demo]: https://www.youtube.com/shorts/Fzm5j8mUUQo
[latest]: https://github.com/Choikuidong/CutNumber/releases/latest
[mac]: https://github.com/Choikuidong/CutNumber/releases/download/v1.0.4/CutNumber-1.0.4.dmg
[win]: https://github.com/Choikuidong/CutNumber/releases/download/v1.0.4/CutNumber-Windows-1.0.4.zip
[screenshot]: ../images/cutnumber-macos.png
[build]: ../../README.md#build-from-source
[studio]: https://applecraft.kr
