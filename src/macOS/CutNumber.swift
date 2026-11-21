import SwiftUI
import AppKit
import UniformTypeIdentifiers
import AVFoundation
import CoreImage
import ImageIO

struct Frame: Identifiable {
    let id = UUID()
    var url: URL
}
struct RenameFailure: LocalizedError {
    var message: String
    var errorDescription: String? { message }
}
struct SequenceEngine {
    static func names(_ files: [URL], start: Int, digits: Int, prefix: String) throws -> [String] {
        guard !files.isEmpty else { throw RenameFailure(message: T("addFirst")) }
        guard start >= 0, start <= 999_999_999 - files.count else { throw RenameFailure(message: T("invalidStart")) }
        guard !prefix.contains("/"), !prefix.contains(":"), !prefix.contains("\n"), !prefix.contains("\0") else { throw RenameFailure(message: T("invalidPrefix")) }
        let extensions = Set(files.map { $0.pathExtension.lowercased() })
        guard extensions.count == 1 else { throw RenameFailure(message: T("sameExtension")) }
        return files.enumerated().map { index, url in
            let number = String(start + index)
            return prefix + String(repeating: "0", count: max(0, digits - number.count)) + number + "." + url.pathExtension.lowercased()
        }
    }
    static func run(files: [URL], names: [String], destination: URL?, rename: Bool) throws -> [URL] {
        let fm = FileManager.default
        guard files.count == names.count, !files.isEmpty else { throw RenameFailure(message: T("invalidFiles")) }
        let targets = zip(files, names).map { source, name in (destination ?? source.deletingLastPathComponent()).appendingPathComponent(name) }
        guard Set(targets.map { $0.path.lowercased() }).count == targets.count else { throw RenameFailure(message: T("duplicate")) }
        let sources = Set(files.map { $0.standardizedFileURL.path })
        for (source, target) in zip(files, targets) {
            let values = try source.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
            guard values.isRegularFile == true, values.isSymbolicLink != true else { throw RenameFailure(message: (T("readError") + "\n" + source.lastPathComponent)) }
            if fm.fileExists(atPath: target.path), !(rename && sources.contains(target.standardizedFileURL.path)) {
                throw RenameFailure(message: (T("collision") + "\n" + target.lastPathComponent))
            }
        }
        if !rename {
            var created: [URL] = []
            do {
                for (source, target) in zip(files, targets) { try fm.copyItem(at: source, to: target); created.append(target) }
            } catch {
                var cleanup: [String] = []
                for url in created { do { try fm.removeItem(at: url) } catch { cleanup.append(url.path) } }
                throw RenameFailure(message: (T("failed") + "\n" + error.localizedDescription) + (cleanup.isEmpty ? ("\n" + T("copiedCleanup")) : ("\n" + T("cleanupNeeded") + "\n") + cleanup.joined(separator: "\n")))
            }
            return targets
        }
        // Stage every source beside itself so swaps never overwrite another frame.
        let staged = files.map { $0.deletingLastPathComponent().appendingPathComponent(".sequence-" + UUID().uuidString + ".tmp") }
        var stagedCount = 0
        var finishedCount = 0
        do {
            for i in files.indices { try fm.moveItem(at: files[i], to: staged[i]); stagedCount += 1 }
            for i in files.indices { try fm.moveItem(at: staged[i], to: targets[i]); finishedCount += 1 }
        } catch {
            var recovery: [String] = []
            for i in (0..<finishedCount).reversed() {
                do { try fm.moveItem(at: targets[i], to: staged[i]) }
                catch { recovery.append("\(targets[i].path) → \(files[i].path)") }
            }
            for i in 0..<stagedCount where fm.fileExists(atPath: staged[i].path) {
                do { try fm.moveItem(at: staged[i], to: files[i]) }
                catch { recovery.append("\(staged[i].path) → \(files[i].path)") }
            }
            throw RenameFailure(message: (T("failed") + "\n" + error.localizedDescription) + (recovery.isEmpty ? ("\n" + T("restored")) : ("\n" + T("recoveryNeeded") + "\n") + recovery.joined(separator: "\n")))
        }
        return targets
    }
}

enum TimeOrder: String, CaseIterable, Identifiable {
    case created = "createdOld"
    case modified = "modifiedOld"
    case createdNewest = "createdNew"
    case modifiedNewest = "modifiedNew"
    var id: String { rawValue }
    var newest: Bool { self == .createdNewest || self == .modifiedNewest }
    var modification: Bool { self == .modified || self == .modifiedNewest }
}
struct ImageImport {
    static let keys: Set<URLResourceKey> = [.isRegularFileKey, .isDirectoryKey, .isSymbolicLinkKey, .contentTypeKey, .creationDateKey, .contentModificationDateKey]
    static func sorted(_ urls: [URL], order: TimeOrder) throws -> [URL] {
        let records = try urls.map { url -> (URL, Date?) in
            let values = try url.resourceValues(forKeys: keys)
            return (url, order.modification ? values.contentModificationDate : values.creationDate)
        }
        return records.sorted { a, b in
            if a.1 != b.1 {
                guard let left = a.1 else { return false }
                guard let right = b.1 else { return true }
                return order.newest ? left > right : left < right
            }
            return a.0.path.compare(b.0.path, options: [.numeric, .literal]) == .orderedAscending
        }.map { $0.0 }
    }
    static func collect(_ inputs: [URL], recursive: Bool, order: TimeOrder) throws -> [URL] {
        var result: [URL] = []
        var seen: Set<String> = []
        func image(_ url: URL) throws -> Bool {
            let values = try url.resourceValues(forKeys: keys)
            return values.isRegularFile == true && values.isSymbolicLink != true && values.contentType?.conforms(to: .image) == true
        }
        for input in inputs {
            let values = try input.resourceValues(forKeys: keys)
            if values.isSymbolicLink == true { continue }
            var candidates: [URL] = []
            if values.isDirectory == true {
                if recursive {
                    var traversalError: Error?
                    guard let enumerator = FileManager.default.enumerator(at: input, includingPropertiesForKeys: Array(keys), options: [.skipsHiddenFiles, .skipsPackageDescendants], errorHandler: { _, error in traversalError = error; return false }) else {
                        throw RenameFailure(message: (T("readError") + "\n" + input.path))
                    }
                    for case let url as URL in enumerator { if try image(url) { candidates.append(url) } }
                    if let traversalError { throw traversalError }
                } else {
                    let children = try FileManager.default.contentsOfDirectory(at: input, includingPropertiesForKeys: Array(keys), options: [.skipsHiddenFiles, .skipsPackageDescendants])
                    candidates = try children.filter { try image($0) }
                }
                candidates = try sorted(candidates, order: order)
            } else if try image(input) { candidates = [input] }
            for url in candidates {
                let canonical = url.standardizedFileURL
                if seen.insert(canonical.path).inserted { result.append(canonical) }
            }
        }
        return result
    }
}

struct VideoExport {
    static func load(_ url: URL) throws -> CIImage {
        guard let image = CIImage(contentsOf: url, options: [.applyOrientationProperty: true]),
              !image.extent.isEmpty, !image.extent.isInfinite,
              image.extent.width.isFinite, image.extent.height.isFinite else {
            throw RenameFailure(message: (T("imageError") + "\n" + url.lastPathComponent))
        }
        return image
    }
    static func export(files: [URL], destination: URL, fps: Int, progress: @escaping @Sendable (Double) -> Void) async throws {
        guard !files.isEmpty, [1, 12, 24, 25, 30, 60].contains(fps) else { throw RenameFailure(message: T("invalidFiles")) }
        let fm = FileManager.default
        guard !fm.fileExists(atPath: destination.path) else { throw RenameFailure(message: T("collision")) }
        let first = try load(files[0])
        let scale = min(1, 4096 / max(first.extent.width, first.extent.height))
        let width = max(2, Int(ceil(first.extent.width * scale / 2)) * 2)
        let height = max(2, Int(ceil(first.extent.height * scale / 2)) * 2)
        let size = CGRect(x: 0, y: 0, width: width, height: height)
        let temporary = destination.deletingLastPathComponent().appendingPathComponent(".cutnumber-" + UUID().uuidString + ".mp4")
        let writer = try AVAssetWriter(outputURL: temporary, fileType: .mp4)
        defer { if fm.fileExists(atPath: temporary.path) { try? fm.removeItem(at: temporary) } }
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: width, AVVideoHeightKey: height,
            AVVideoCompressionPropertiesKey: [AVVideoAverageBitRateKey: min(80_000_000, max(2_000_000, width * height * fps / 5)), AVVideoExpectedSourceFrameRateKey: fps]
        ])
        input.expectsMediaDataInRealTime = false
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey as String: width, kCVPixelBufferHeightKey as String: height,
            kCVPixelBufferIOSurfacePropertiesKey as String: [:]
        ])
        guard writer.canAdd(input) else { throw RenameFailure(message: T("videoError")) }
        writer.add(input)
        guard writer.startWriting() else { throw writer.error ?? RenameFailure(message: T("videoError")) }
        writer.startSession(atSourceTime: .zero)
        let context = CIContext(options: [.cacheIntermediates: false])
        let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)!
        do {
            for (index, url) in files.enumerated() {
                let deadline = Date().addingTimeInterval(60)
                while !input.isReadyForMoreMediaData {
                    guard writer.status == .writing else { throw writer.error ?? RenameFailure(message: T("videoError")) }
                    guard Date() < deadline else { throw RenameFailure(message: T("videoTimeout")) }
                    try await Task.sleep(nanoseconds: 10_000_000)
                }
                try autoreleasepool {
                    let image = try load(url)
                    let factor = min(CGFloat(width) / image.extent.width, CGFloat(height) / image.extent.height)
                    let normalized = image.transformed(by: CGAffineTransform(translationX: -image.extent.minX, y: -image.extent.minY))
                    let scaled = normalized.transformed(by: CGAffineTransform(scaleX: factor, y: factor))
                    let positioned = scaled.transformed(by: CGAffineTransform(translationX: (CGFloat(width) - scaled.extent.width) / 2, y: (CGFloat(height) - scaled.extent.height) / 2))
                    let composed = positioned.composited(over: CIImage(color: .black).cropped(to: size))
                    guard let pool = adaptor.pixelBufferPool else { throw RenameFailure(message: T("memory")) }
                    var buffer: CVPixelBuffer?
                    guard CVPixelBufferPoolCreatePixelBuffer(nil, pool, &buffer) == kCVReturnSuccess, let buffer else { throw RenameFailure(message: T("memory")) }
                    context.render(composed, to: buffer, bounds: size, colorSpace: colorSpace)
                    guard adaptor.append(buffer, withPresentationTime: CMTime(value: Int64(index), timescale: Int32(fps))) else { throw writer.error ?? RenameFailure(message: (T("videoError") + "\n" + url.lastPathComponent)) }
                }
                progress(Double(index + 1) / Double(files.count))
            }
            input.markAsFinished()
            writer.endSession(atSourceTime: CMTime(value: Int64(files.count), timescale: Int32(fps)))
            await writer.finishWriting()
            guard writer.status == .completed else { throw writer.error ?? RenameFailure(message: T("videoError")) }
            try fm.moveItem(at: temporary, to: destination)
        } catch { writer.cancelWriting(); throw error }
    }
}

@MainActor final class Model: ObservableObject {
    @Published var frames: [Frame] = []
    @Published var timeOrder: TimeOrder = .created
    @Published var recursive = false
    @Published var dropTargeted = false
    @Published var selection: Set<UUID> = []
    @Published var start = 1
    @Published var digits = 4
    @Published var prefix = ""
    @Published var rename = false
    @Published var busy = false
    @Published var fps = 24
    @Published var videoProgress: Double?
    @Published var status = T("ready")
    @Published var error: String?
    var preview: [String] { (try? SequenceEngine.names(frames.map(\.url), start: start, digits: digits, prefix: prefix)) ?? [] }
    func add() {
        let panel = NSOpenPanel()
        panel.title = T("add")
        panel.allowedContentTypes = [.image]
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        if panel.runModal() == .OK { importURLs(panel.urls) }
    }
    func addFolder() {
        let panel = NSOpenPanel()
        panel.title = T("chooseInput")
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = T("add")
        if panel.runModal() == .OK { importURLs(panel.urls) }
    }
    func importURLs(_ urls: [URL]) {
        guard !busy, !urls.isEmpty else { return }
        busy = true
        status = T("loading")
        let order = timeOrder
        let includeSubfolders = recursive
        Task {
            do {
                let imported = try await Task.detached(priority: .userInitiated) {
                    try ImageImport.collect(urls, recursive: includeSubfolders, order: order)
                }.value
                var seen = Set(frames.map { $0.url.standardizedFileURL.path })
                var added = 0
                for url in imported where seen.insert(url.path).inserted {
                    frames.append(Frame(url: url)); added += 1
                }
                status = added == 0 ? T("noNew") : T("added", added, frames.count)
            } catch { self.error = error.localizedDescription; status = T("failed") }
            busy = false
        }
    }
    func pasteFiles() {
        let urls = NSPasteboard.general.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL] ?? []
        if urls.isEmpty { status = T("pasteHint") }
        else { importURLs(urls) }
    }
    func drop(_ providers: [NSItemProvider]) -> Bool {
        guard !busy else { return false }
        Task {
            var urls: [URL] = []
            for provider in providers {
                let url: URL? = await withCheckedContinuation { continuation in
                    provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
                        if let url = item as? URL { continuation.resume(returning: url) }
                        else if let data = item as? Data { continuation.resume(returning: URL(dataRepresentation: data, relativeTo: nil)) }
                        else { continuation.resume(returning: nil) }
                    }
                }
                if let url, url.isFileURL { urls.append(url) }
            }
            if urls.isEmpty { status = T("emptyNote") }
            else { importURLs(urls) }
        }
        return true
    }
    func sortByTime() {
        do {
            let sorted = try ImageImport.sorted(frames.map(\.url), order: timeOrder)
            let byPath = Dictionary(uniqueKeysWithValues: frames.map { ($0.url.path, $0) })
            frames = sorted.compactMap { byPath[$0.path] }
            status = (T("sorted", T(timeOrder.rawValue)))
        } catch { self.error = error.localizedDescription }
    }
    func move(up: Bool) {
        if up {
            for i in frames.indices.dropFirst() where selection.contains(frames[i].id) && !selection.contains(frames[i-1].id) { frames.swapAt(i, i-1) }
        } else if frames.count > 1 {
            for i in (0..<(frames.count-1)).reversed() where selection.contains(frames[i].id) && !selection.contains(frames[i+1].id) { frames.swapAt(i, i+1) }
        }
    }
    func exportVideo() {
        guard !busy, !frames.isEmpty else { return }
        let panel = NSSavePanel()
        panel.title = T("saveVideo")
        panel.allowedContentTypes = [.mpeg4Movie]
        panel.nameFieldStringValue = "CutNumber.mp4"
        panel.canCreateDirectories = true
        guard panel.runModal() == .OK, let destination = panel.url else { return }
        let files = frames.map(\.url)
        let rate = fps
        busy = true
        videoProgress = 0
        status = T("encoding")
        Task {
            do {
                try await Task.detached(priority: .userInitiated) {
                    try await VideoExport.export(files: files, destination: destination, fps: rate) { value in
                        Task { @MainActor in self.videoProgress = value }
                    }
                }.value
                status = (T("videoDone", files.count, rate))
                NSWorkspace.shared.activateFileViewerSelecting([destination])
            } catch { self.error = error.localizedDescription; status = T("videoError") }
            busy = false
            videoProgress = nil
        }
    }
    func execute() {
        do {
            let files = frames.map(\.url)
            let names = try SequenceEngine.names(files, start: start, digits: digits, prefix: prefix)
            var destination: URL?
            if rename {
                let alert = NSAlert()
                alert.messageText = (T("confirmRename", files.count))
                alert.informativeText = T("confirmNote")
                alert.addButton(withTitle: T("rename"))
                alert.addButton(withTitle: T("cancel"))
                guard alert.runModal() == .alertFirstButtonReturn else { return }
            } else {
                let panel = NSOpenPanel()
                panel.title = T("chooseOutput")
                panel.canChooseFiles = false
                panel.canChooseDirectories = true
                panel.canCreateDirectories = true
                panel.prompt = T("copy")
                guard panel.runModal() == .OK, let url = panel.url else { return }
                destination = url
            }
            busy = true
            let shouldRename = rename
            let targetDirectory = destination
            Task {
                do {
                    let result = try await Task.detached(priority: .userInitiated) {
                        try SequenceEngine.run(files: files, names: names, destination: targetDirectory, rename: shouldRename)
                    }.value
                    if shouldRename { frames = result.map { Frame(url: $0) }; selection = [] }
                    status = T("filesDone", result.count, shouldRename ? T("rename") : T("copy"))
                    if let first = result.first { NSWorkspace.shared.activateFileViewerSelecting([first]) }
                } catch { self.error = error.localizedDescription }
                busy = false
            }
        } catch { self.error = error.localizedDescription }
    }
}

private enum Palette {
    static let background = Color(red: 0.055, green: 0.067, blue: 0.09)
    static let panel = Color(red: 0.085, green: 0.10, blue: 0.13)
    static let accent = Color(red: 0.57, green: 0.88, blue: 0.64)
    static let muted = Color(red: 0.55, green: 0.60, blue: 0.67)
}
@MainActor final class PreviewLoader: ObservableObject {
    @Published var image: NSImage?
    @Published var dimensions = ""
    @Published var loading = false
    @Published var failed = false

    func load(_ url: URL?) async {
        image = nil
        dimensions = ""
        failed = false
        loading = url != nil
        guard let url else { return }
        let result = await Task.detached(priority: .userInitiated) {
            guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else {
                return (nil as CGImage?, "")
            }
            let options: [CFString: Any] = [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: 1600,
                kCGImageSourceShouldCacheImmediately: true
            ]
            let thumbnail = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
            let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
            var width = properties?[kCGImagePropertyPixelWidth] as? Int ?? 0
            var height = properties?[kCGImagePropertyPixelHeight] as? Int ?? 0
            let orientation = properties?[kCGImagePropertyOrientation] as? Int ?? 1
            if (5...8).contains(orientation) { swap(&width, &height) }
            return (thumbnail, width > 0 && height > 0 ? "\(width) × \(height) px" : "")
        }.value
        guard !Task.isCancelled else { return }
        loading = false
        dimensions = result.1
        if let cgImage = result.0 {
            image = NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
        } else {
            failed = true
        }
    }
}

struct PhotoPreview: View {
    @ObservedObject private var language = InterfaceLanguage.shared
    let url: URL?
    let selectionCount: Int
    @StateObject private var loader = PreviewLoader()

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                Image(systemName: "photo").foregroundStyle(Palette.accent)
                Text(T("preview")).font(.system(size: 15, weight: .semibold))
                Spacer()
            }
            ZStack {
                RoundedRectangle(cornerRadius: 12).fill(Color.black.opacity(0.25))
                if loader.loading {
                    ProgressView()
                } else if let image = loader.image {
                    Image(nsImage: image).resizable().scaledToFit().padding(12)
                } else {
                    VStack(spacing: 12) {
                        Image(systemName: loader.failed ? "exclamationmark.triangle" : "photo")
                            .font(.system(size: 32, weight: .light))
                        Text(loader.failed ? T("imageError") : T("selectPhoto"))
                            .font(.system(size: 12))
                    }.foregroundStyle(Palette.muted).padding()
                }
            }.frame(maxWidth: .infinity, maxHeight: .infinity)
            if let url {
                Text(url.lastPathComponent).font(.system(size: 13, weight: .medium))
                    .lineLimit(3).textSelection(.enabled).help(url.path)
                Text(loader.dimensions).font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(Palette.muted)
                if selectionCount > 1 {
                    Text((T("selected", selectionCount)))
                        .font(.system(size: 11)).foregroundStyle(Palette.muted)
                }
            }
        }
        .padding(20)
        .frame(width: 290)
        .background(Palette.panel)
        .task(id: url) { await loader.load(url) }
    }
}

struct ContentView: View {
    @ObservedObject private var language = InterfaceLanguage.shared
    @ObservedObject var model: Model
    private var integerFormatter: NumberFormatter {
        let f = NumberFormatter(); f.numberStyle = .none; f.minimum = 0; f.maximum = 999_999_999; return f
    }
    var body: some View {
        VStack(spacing: 0) {
            header
            Rectangle().fill(.white.opacity(0.08)).frame(height: 1)
            HStack(spacing: 0) {
                ScrollView { sidebar }.frame(width: 290)
                Rectangle().fill(.white.opacity(0.08)).frame(width: 1)
                workspace
                Rectangle().fill(.white.opacity(0.08)).frame(width: 1)
                PhotoPreview(
                    url: model.frames.first(where: { model.selection.contains($0.id) })?.url,
                    selectionCount: model.selection.count
                )
            }
            footer
        }
        .environment(\.locale, Locale(identifier: language.code))
        .environment(\.layoutDirection, language.code == "ar" ? .rightToLeft : .leftToRight)
        .background(Palette.background)
        .tint(Palette.accent)
        .preferredColorScheme(.dark)
        .frame(minWidth: 1200, minHeight: 740)
        .overlay { RoundedRectangle(cornerRadius: 12).stroke(model.dropTargeted ? Palette.accent : .clear, lineWidth: 3).padding(4).allowsHitTesting(false) }
        .onDrop(of: [UTType.fileURL.identifier], isTargeted: $model.dropTargeted, perform: model.drop)
        .disabled(model.busy)
        .alert(T("failed"), isPresented: Binding(get: { model.error != nil }, set: { if !$0 { model.error = nil } })) {
            Button(T("ok")) { model.error = nil }
        } message: { Text(model.error ?? "") }
    }
    private var header: some View {
        HStack(spacing: 13) {
            ZStack {
                RoundedRectangle(cornerRadius: 12).fill(Palette.accent.opacity(0.14)).frame(width: 46, height: 46)
                Image(systemName: "number.square.fill").font(.system(size: 27, weight: .medium)).foregroundStyle(Palette.accent)
            }
            VStack(alignment: .leading, spacing: 3) {
                HStack(alignment: .firstTextBaseline, spacing: 9) {
                    Text(T("app")).font(.system(size: 22, weight: .bold))
                    Text("1.0.4").font(.system(size: 10, weight: .semibold, design: .monospaced)).foregroundStyle(Palette.accent)
                        .padding(.horizontal, 7).padding(.vertical, 3).background(Palette.accent.opacity(0.10), in: Capsule())
                }
                Text(T("tagline")).font(.system(size: 11)).foregroundStyle(Palette.muted)
            }
            Spacer()
            Picker(T("language"), selection: $language.code) {
                ForEach(AppLanguage.all) { item in Text(item.name).tag(item.id) }
            }.frame(width: 180)
            .onChange(of: language.code) { _ in model.status = T("savedLanguage") }
            Button(action: model.pasteFiles) { Label(T("paste"), systemImage: "doc.on.clipboard") }.keyboardShortcut("v")
            Button(action: model.addFolder) { Label(T("folder"), systemImage: "folder.badge.plus") }
            Button(action: model.add) { Label(T("add"), systemImage: "plus") }.keyboardShortcut("o")
                .buttonStyle(.borderedProminent).foregroundStyle(Palette.background)
        }.controlSize(.large).padding(.horizontal, 24).padding(.vertical, 18)
    }
    private func sectionTitle(_ number: String, _ title: String, _ icon: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon).foregroundStyle(Palette.accent)
            Text(title).font(.system(size: 13, weight: .semibold))
            Spacer()
            Text(number).font(.system(size: 10, design: .monospaced)).foregroundStyle(Palette.muted)
        }
    }
    private func caption(_ text: String) -> some View {
        Text(text).font(.system(size: 11)).foregroundStyle(Palette.muted)
    }
    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 12) {
                sectionTitle("01", T("import"), "folder")
                caption(T("folderTime"))
                Picker(T("folderTime"), selection: $model.timeOrder) {
                    ForEach(TimeOrder.allCases) { order in Text(T(order.rawValue)).tag(order) }
                }.labelsHidden().id(language.code)
                Toggle(T("subfolders"), isOn: $model.recursive).font(.system(size: 12))
                Button(T("applyTime"), action: model.sortByTime).frame(maxWidth: .infinity).disabled(model.frames.isEmpty)
            }
            Divider()
            VStack(alignment: .leading, spacing: 12) {
                sectionTitle("02", T("filenames"), "textformat.123")
                caption(T("prefix"))
                TextField(T("prefixExample"), text: $model.prefix).textFieldStyle(.roundedBorder)
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 7) {
                        caption(T("start"))
                        TextField("1", value: $model.start, formatter: integerFormatter).textFieldStyle(.roundedBorder)
                    }
                    VStack(alignment: .leading, spacing: 7) {
                        caption(T("digits"))
                        Picker(T("digits"), selection: $model.digits) {
                            ForEach([1, 3, 4, 5, 6], id: \.self) { value in Text(String(repeating: "0", count: value - 1) + "1").tag(value) }
                        }.labelsHidden().frame(width: 108)
                    }
                }
                Picker(T("mode"), selection: $model.rename) {
                    Text(T("copy")).tag(false)
                    Text(T("rename")).tag(true)
                }.labelsHidden()
                caption(model.rename ? T("renameNote") : T("copyNote"))
                Button(action: model.execute) { Label(model.rename ? T("rename") : T("saveSequence"), systemImage: "square.and.arrow.down") }
                    .frame(maxWidth: .infinity).disabled(model.frames.isEmpty)
            }
            Divider()
            VStack(alignment: .leading, spacing: 12) {
                sectionTitle("03", T("video"), "film")
                HStack {
                    caption(T("frameRate"))
                    Spacer()
                    Picker("FPS", selection: $model.fps) {
                        ForEach([1, 12, 24, 25, 30, 60], id: \.self) { value in Text("\(value) FPS").tag(value) }
                    }.labelsHidden().frame(width: 108)
                }
                HStack {
                    Text(T("duration")).font(.system(size: 12)).foregroundStyle(Palette.muted)
                    Spacer()
                    Text(T("seconds", String(format: "%.2f", Double(model.frames.count) / Double(model.fps)))).font(.system(size: 14, weight: .medium, design: .monospaced))
                }
                Button(action: model.exportVideo) { Label(T("saveVideo"), systemImage: "play.rectangle") }
                    .buttonStyle(.borderedProminent).foregroundStyle(Palette.background).disabled(model.frames.isEmpty)
                caption(T("videoNote"))
            }
            Spacer(minLength: 0)
        }.padding(20).background(Palette.panel)
    }
    private var workspace: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 5) {
                    Text(T("frames")).font(.system(size: 18, weight: .semibold))
                    Text(T("listNote")).font(.system(size: 12)).foregroundStyle(Palette.muted)
                }
                Spacer()
                Text(T("frameCount", model.frames.count)).font(.system(size: 11, weight: .medium, design: .monospaced)).foregroundStyle(Palette.accent)
                    .padding(.horizontal, 12).padding(.vertical, 7).background(Palette.accent.opacity(0.08), in: Capsule())
            }.padding(24)
            if model.frames.isEmpty { emptyState.frame(maxWidth: .infinity, maxHeight: .infinity) }
            else { frameTable.padding(.horizontal, 16) }
            HStack(spacing: 8) {
                Button { model.move(up: true) } label: { Image(systemName: "arrow.up") }.help(T("up")).disabled(model.selection.isEmpty)
                Button { model.move(up: false) } label: { Image(systemName: "arrow.down") }.help(T("down")).disabled(model.selection.isEmpty)
                Button(T("remove")) { model.frames.removeAll { model.selection.contains($0.id) }; model.selection = [] }.disabled(model.selection.isEmpty)
                Menu(T("sort")) {
                    Button(T("nameSort")) { model.frames.sort { $0.url.lastPathComponent.localizedStandardCompare($1.url.lastPathComponent) == .orderedAscending } }
                    Button(T("applyTime"), action: model.sortByTime)
                    Button(T("reverse")) { model.frames.reverse() }
                }.frame(width: 76).disabled(model.frames.isEmpty)
                Spacer()
                Button(T("clear")) { model.frames = []; model.selection = [] }.disabled(model.frames.isEmpty)
            }.padding(20)
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "info.circle")
                Text(T("orderHint"))
            }.font(.system(size: 11)).foregroundStyle(Palette.muted).padding(.horizontal, 24).padding(.bottom, 20)
        }
    }
    private var emptyState: some View {
        VStack(spacing: 18) {
            ZStack {
                RoundedRectangle(cornerRadius: 18).fill(.white.opacity(0.03)).frame(width: 92, height: 76).rotationEffect(.degrees(-12)).offset(x: -12, y: -6)
                RoundedRectangle(cornerRadius: 18).fill(Palette.accent.opacity(0.10)).frame(width: 92, height: 76)
                    .overlay { Image(systemName: "photo.stack").font(.system(size: 32, weight: .light)).foregroundStyle(Palette.accent) }
            }.padding(.bottom, 8)
            Text(T("empty")).font(.system(size: 23, weight: .semibold))
            Text(T("emptyNote"))
                .font(.system(size: 13)).foregroundStyle(Palette.muted).multilineTextAlignment(.center).lineSpacing(5)
            Button(T("add"), action: model.add).controlSize(.large).padding(.top, 4)
            Text("PNG / JPG / TIFF / HEIC").font(.system(size: 10, design: .monospaced)).foregroundStyle(Palette.muted.opacity(0.7))
        }.frame(maxWidth: .infinity, maxHeight: .infinity)
            .background { RoundedRectangle(cornerRadius: 18).strokeBorder(Palette.accent.opacity(model.dropTargeted ? 0.8 : 0.15), style: StrokeStyle(lineWidth: 1, dash: [6, 6])).padding(24) }
    }
    private var frameTable: some View {
        let names = model.preview
        return Table(model.frames, selection: $model.selection) {
            TableColumn(T("number")) { frame in
                Text(String(format: "%04d", (model.frames.firstIndex(where: { $0.id == frame.id }) ?? 0) + 1))
                    .font(.system(size: 12, design: .monospaced)).foregroundStyle(Palette.muted)
            }.width(52)
            TableColumn(T("original")) { frame in
                HStack(spacing: 9) {
                    Image(systemName: "photo").foregroundStyle(Palette.muted)
                    Text(frame.url.lastPathComponent).font(.system(size: 12)).help(frame.url.path)
                }.padding(.vertical, 7)
            }
            TableColumn(T("output")) { frame in
                let index = model.frames.firstIndex(where: { $0.id == frame.id }) ?? 0
                Text(index < names.count ? names[index] : T("checkSettings"))
                    .font(.system(size: 12, design: .monospaced)).foregroundStyle(Palette.accent)
            }
        }.scrollContentBackground(.hidden).background(Palette.background)
    }
    private var footer: some View {
        HStack(spacing: 9) {
            if model.busy { ProgressView().controlSize(.mini) }
            else { Circle().fill(Palette.accent).frame(width: 5, height: 5) }
            Text(model.status).font(.system(size: 11)).foregroundStyle(Palette.muted).lineLimit(1)
            Spacer()
            if let progress = model.videoProgress { ProgressView(value: progress).frame(width: 100) }
            Text("CUTNUMBER  /  1.0.4").font(.system(size: 9, design: .monospaced)).foregroundStyle(Palette.muted.opacity(0.7))
        }.padding(.horizontal, 22).padding(.vertical, 13).background(.white.opacity(0.025))
    }
}


@MainActor final class CutWindow: NSWindow {
    let model = Model()
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard event.modifierFlags.intersection(.deviceIndependentFlagsMask) == .command,
              !model.busy, attachedSheet == nil else { return super.performKeyEquivalent(with: event) }
        let key = event.charactersIgnoringModifiers?.lowercased()
        if let editor = firstResponder as? NSTextView {
            switch key {
            case "a": editor.selectAll(nil)
            case "c": editor.copy(nil)
            case "v": editor.paste(nil)
            case "x": editor.cut(nil)
            case "z": editor.undoManager?.undo()
            default: return super.performKeyEquivalent(with: event)
            }
            return true
        }
        switch key {
        case "o": model.add()
        case "v": model.pasteFiles()
        default: return super.performKeyEquivalent(with: event)
        }
        return true
    }
}

@main @MainActor final class CutNumberApp: NSObject, NSApplicationDelegate {
    private var mainWindow: NSWindow?
    static func main() {
        let app = NSApplication.shared
        let delegate = CutNumberApp()
        app.delegate = delegate
        app.setActivationPolicy(.regular)
        withExtendedLifetime(delegate) { app.run() }
    }
    func applicationDidFinishLaunching(_ notification: Notification) {
        let window = CutWindow(contentRect: NSRect(x: 0, y: 0, width: 1360, height: 820),
                               styleMask: [.titled, .closable, .miniaturizable, .resizable],
                               backing: .buffered, defer: false)
        window.title = T("app")
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.appearance = NSAppearance(named: .darkAqua)
        window.isReleasedWhenClosed = false
        window.contentViewController = NSHostingController(rootView: ContentView(model: window.model))
        window.setContentSize(NSSize(width: 1360, height: 820))
        mainWindow = window
        NotificationCenter.default.addObserver(self, selector: #selector(languageChanged), name: .interfaceLanguageChanged, object: nil)
        rebuildMenu()
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
    @objc private func languageChanged() {
        mainWindow?.title = T("app")
        rebuildMenu()
        if let aboutWindow {
            let visible = aboutWindow.isVisible
            aboutWindow.close()
            self.aboutWindow = nil
            if visible { showAbout() }
        }
    }
    private func rebuildMenu() {
        let menu = NSMenu()
        let applicationItem = menu.addItem(withTitle: T("app"), action: nil, keyEquivalent: "")
        let applicationMenu = NSMenu(title: T("app"))
        applicationItem.submenu = applicationMenu
        let about = applicationMenu.addItem(withTitle: T("about"), action: #selector(showAbout), keyEquivalent: "")
        about.target = self
        applicationMenu.addItem(.separator())
        applicationMenu.addItem(withTitle: T("quit"), action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        NSApp.mainMenu = menu
    }
    private var aboutWindow: NSWindow?
    @objc func showAbout() {
        if let aboutWindow = aboutWindow {
            aboutWindow.makeKeyAndOrderFront(nil)
            return
        }
        let panel = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 520, height: 360),
                             styleMask: [.titled, .closable], backing: .buffered, defer: false)
        panel.title = T("about")
        panel.isReleasedWhenClosed = false
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? ""
        panel.contentView = AboutView(version: version)
        aboutWindow = panel
        panel.center()
        panel.makeKeyAndOrderFront(nil)
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}
