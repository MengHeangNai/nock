import SwiftUI
import AppKit
import PDFKit
import Vision
import QuickLookThumbnailing
import UniformTypeIdentifiers

// MARK: - Actions

/// Things the Shelf can do with its files. New files (converted images, PDFs, archives) go to Downloads.
enum ShelfActions {
    static var outputFolder: URL {
        FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser
    }

    static func quickLook(_ urls: [URL]) {
        guard !urls.isEmpty else { return }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/qlmanage")
        process.arguments = ["-p"] + urls.map(\.path)
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try? process.run()
    }

    static func open(_ urls: [URL]) {
        urls.forEach { NSWorkspace.shared.open($0) }
    }

    static func reveal(_ urls: [URL]) {
        NSWorkspace.shared.activateFileViewerSelecting(urls)
    }

    static func airDrop(_ urls: [URL]) {
        NSSharingService(named: .sendViaAirDrop)?.perform(withItems: urls)
    }

    static func share(_ urls: [URL], from view: NSView?) {
        guard let view else { return }
        NSSharingServicePicker(items: urls).show(relativeTo: view.bounds, of: view, preferredEdge: .minY)
    }

    private static func isImage(_ url: URL) -> Bool {
        (UTType(filenameExtension: url.pathExtension)?.conforms(to: .image)) ?? false
    }

    private static func isPDF(_ url: URL) -> Bool {
        url.pathExtension.lowercased() == "pdf"
    }

    /// Saves a copy of each image in another format, next to the original (or in Downloads).
    static func convertImages(_ urls: [URL], to type: UTType, completion: @escaping ([URL]) -> Void) {
        DispatchQueue.global(qos: .userInitiated).async {
            var created: [URL] = []
            for url in urls where isImage(url) {
                guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
                      let image = CGImageSourceCreateImageAtIndex(source, 0, nil),
                      let ext = type.preferredFilenameExtension else { continue }
                let name = url.deletingPathExtension().lastPathComponent + "." + ext
                for folder in [url.deletingLastPathComponent(), outputFolder] {
                    let target = uniqueURL(folder.appendingPathComponent(name))
                    guard let destination = CGImageDestinationCreateWithURL(target as CFURL, type.identifier as CFString, 1, nil) else { continue }
                    CGImageDestinationAddImage(destination, image, [kCGImageDestinationLossyCompressionQuality: 0.9] as CFDictionary)
                    if CGImageDestinationFinalize(destination) {
                        created.append(target)
                        break
                    }
                }
            }
            DispatchQueue.main.async { completion(created) }
        }
    }

    /// Combines images and PDFs, in order, into one PDF in Downloads.
    static func combineIntoPDF(_ urls: [URL], completion: @escaping (URL?) -> Void) {
        DispatchQueue.global(qos: .userInitiated).async {
            let document = PDFDocument()
            for url in urls {
                if isPDF(url), let pdf = PDFDocument(url: url) {
                    for index in 0..<pdf.pageCount {
                        if let page = pdf.page(at: index) { document.insert(page, at: document.pageCount) }
                    }
                } else if isImage(url), let image = NSImage(contentsOf: url), let page = PDFPage(image: image) {
                    document.insert(page, at: document.pageCount)
                }
            }
            var result: URL?
            if document.pageCount > 0 {
                let target = uniqueURL(outputFolder.appendingPathComponent("Shelf \(timestamp()).pdf"))
                if document.write(to: target) { result = target }
            }
            DispatchQueue.main.async { completion(result) }
        }
    }

    /// Compresses the files into one .zip in Downloads.
    static func compress(_ urls: [URL], completion: @escaping (URL?) -> Void) {
        DispatchQueue.global(qos: .userInitiated).async {
            let staging = FileManager.default.temporaryDirectory
                .appendingPathComponent("GlassDock-\(UUID().uuidString)", isDirectory: true)
            defer { try? FileManager.default.removeItem(at: staging) }
            var result: URL?
            do {
                try FileManager.default.createDirectory(at: staging, withIntermediateDirectories: true)
                for url in urls {
                    try FileManager.default.copyItem(at: url, to: uniqueURL(staging.appendingPathComponent(url.lastPathComponent)))
                }
                let target = uniqueURL(outputFolder.appendingPathComponent("Shelf \(timestamp()).zip"))
                let process = Process()
                process.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
                process.arguments = ["-c", "-k", "--sequesterRsrc", staging.path, target.path]
                try process.run()
                process.waitUntilExit()
                if process.terminationStatus == 0 { result = target }
            } catch {
                NSLog("GlassDock: compress failed: \(error.localizedDescription)")
            }
            DispatchQueue.main.async { completion(result) }
        }
    }

    /// Recognizes text in images (and reads the text of PDFs), on this Mac.
    static func recognizeText(_ urls: [URL], completion: @escaping (String) -> Void) {
        DispatchQueue.global(qos: .userInitiated).async {
            var pieces: [String] = []
            for url in urls {
                if isPDF(url), let text = PDFDocument(url: url)?.string, !text.isEmpty {
                    pieces.append(text)
                } else if isImage(url),
                          let source = CGImageSourceCreateWithURL(url as CFURL, nil),
                          let image = CGImageSourceCreateImageAtIndex(source, 0, nil) {
                    let request = VNRecognizeTextRequest()
                    request.recognitionLevel = .accurate
                    request.usesLanguageCorrection = true
                    try? VNImageRequestHandler(cgImage: image).perform([request])
                    let lines = (request.results ?? []).compactMap { $0.topCandidates(1).first?.string }
                    if !lines.isEmpty { pieces.append(lines.joined(separator: "\n")) }
                }
            }
            let text = pieces.joined(separator: "\n\n")
            DispatchQueue.main.async { completion(text) }
        }
    }

    static func totalSize(of urls: [URL]) -> Int64 {
        var total: Int64 = 0
        for url in urls {
            let values = try? url.resourceValues(forKeys: [.isDirectoryKey, .totalFileAllocatedSizeKey, .fileSizeKey])
            if values?.isDirectory == true {
                let enumerator = FileManager.default.enumerator(at: url, includingPropertiesForKeys: [.totalFileAllocatedSizeKey])
                while let file = enumerator?.nextObject() as? URL {
                    total += Int64((try? file.resourceValues(forKeys: [.totalFileAllocatedSizeKey]).totalFileAllocatedSize) ?? 0)
                }
            } else {
                total += Int64(values?.fileSize ?? values?.totalFileAllocatedSize ?? 0)
            }
        }
        return total
    }

    private static func timestamp() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd 'at' HH.mm.ss"
        return formatter.string(from: Date())
    }

    static func uniqueURL(_ url: URL) -> URL {
        guard FileManager.default.fileExists(atPath: url.path) else { return url }
        let base = url.deletingPathExtension().lastPathComponent
        let ext = url.pathExtension
        for index in 2... {
            let name = ext.isEmpty ? "\(base) \(index)" : "\(base) \(index).\(ext)"
            let candidate = url.deletingLastPathComponent().appendingPathComponent(name)
            if !FileManager.default.fileExists(atPath: candidate.path) { return candidate }
        }
        return url
    }
}

/// Shows an NSMenu of closures at the cursor.
final class ClosureMenu: NSObject {
    private var actions: [() -> Void] = []

    static func show(_ items: [(title: String, action: () -> Void)]) {
        let holder = ClosureMenu()
        let menu = NSMenu()
        for (index, item) in items.enumerated() {
            let menuItem = NSMenuItem(title: item.title, action: #selector(run(_:)), keyEquivalent: "")
            menuItem.target = holder
            menuItem.tag = index
            menu.addItem(menuItem)
            holder.actions.append(item.action)
        }
        menu.popUp(positioning: nil, at: NSEvent.mouseLocation, in: nil)
        _ = holder  // keep alive until the menu closes (popUp is modal)
    }

    @objc private func run(_ sender: NSMenuItem) {
        actions[sender.tag]()
    }
}

/// Gives SwiftUI code access to a button's NSView, for anchoring the share picker.
final class ViewAnchor {
    weak var view: NSView?
}

private struct AnchorView: NSViewRepresentable {
    let anchor: ViewAnchor
    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        anchor.view = view
        return view
    }
    func updateNSView(_ nsView: NSView, context: Context) { anchor.view = nsView }
}

// MARK: - Shelf tab

struct ShelfTab: View {
    @ObservedObject var shelf: ShelfStore
    @State private var selection: Set<URL> = []
    @State private var totalSize: Int64 = 0
    @State private var message: String?
    @State private var busy = false
    @State private var shareAnchor = ViewAnchor()

    /// Actions apply to the selected files, or to everything when nothing is selected.
    private var targets: [URL] {
        selection.isEmpty ? shelf.files : shelf.files.filter(selection.contains)
    }

    var body: some View {
        if shelf.files.isEmpty {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(style: StrokeStyle(lineWidth: 1.5, dash: [6, 5]))
                .foregroundStyle(Color.white.opacity(0.3))
                .overlay {
                    VStack(spacing: 6) {
                        Image(systemName: "tray.and.arrow.down").font(.system(size: 24))
                        Text("Drop files on the notch to keep them here").font(.system(size: 12))
                    }
                    .foregroundStyle(.secondary)
                }
        } else {
            VStack(spacing: 10) {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(alignment: .top, spacing: 10) {
                        ForEach(shelf.files, id: \.self) { url in
                            item(url)
                        }
                    }
                    .padding(.top, 4)
                }
                .frame(maxHeight: .infinity)

                actionBar
            }
            .task(id: shelf.files) {
                let files = shelf.files
                selection = selection.intersection(files)
                totalSize = await Task.detached { ShelfActions.totalSize(of: files) }.value
            }
        }
    }

    private func item(_ url: URL) -> some View {
        let selected = selection.contains(url)
        return VStack(spacing: 6) {
            FileThumbnail(url: url, size: 72)
            Text(url.lastPathComponent)
                .font(.system(size: 12, weight: .medium))
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(width: 92)
        }
        .padding(6)
        .background(selected ? Color.white.opacity(0.14) : Color.clear,
                    in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .contentShape(Rectangle())
        .onTapGesture(count: 2) { ShelfActions.open([url]) }
        .onTapGesture {
            if selected { selection.remove(url) } else { selection.insert(url) }
        }
        .onDrag { NSItemProvider(object: url as NSURL) }
        .contextMenu {
            Button("Open") { ShelfActions.open([url]) }
            Button("Quick Look") { ShelfActions.quickLook([url]) }
            Button("Show in Finder") { ShelfActions.reveal([url]) }
            Divider()
            Button("Remove from Shelf") { shelf.remove(url) }
        }
        .help(url.path)
    }

    private var actionBar: some View {
        HStack(spacing: 8) {
            Group {
                if busy {
                    ProgressView().controlSize(.small)
                } else {
                    Text(message ?? summary)
                }
            }
            .font(.system(size: 12))
            .foregroundStyle(.secondary)
            .lineLimit(1)

            Spacer(minLength: 8)

            action("eye", "Quick Look") { ShelfActions.quickLook(targets) }
            action("arrow.up.forward.app", "Open") { ShelfActions.open(targets) }
            action("folder", "Show in Finder") { ShelfActions.reveal(targets) }
            separator
            action("square.and.arrow.up", "Share") { ShelfActions.share(targets, from: shareAnchor.view) }
                .background(AnchorView(anchor: shareAnchor))
            action("dot.radiowaves.left.and.right", "AirDrop") { ShelfActions.airDrop(targets) }
            separator
            action("arrow.triangle.2.circlepath", "Convert images") { showConvertMenu() }
            action("doc.richtext", "Combine into PDF") { combineIntoPDF() }
            action("doc.zipper", "Compress to .zip") { compress() }
            action("text.viewfinder", "Copy text from images and PDFs") { copyText() }
            separator
            action("xmark", selection.isEmpty ? "Clear Shelf" : "Remove selected") {
                if selection.isEmpty {
                    shelf.clear()
                } else {
                    selection.forEach(shelf.remove)
                    selection.removeAll()
                }
            }
        }
    }

    private var summary: String {
        let count = shelf.files.count
        var parts = ["\(count) \(count == 1 ? "item" : "items")", ByteCountFormatter.string(fromByteCount: totalSize, countStyle: .file)]
        if !selection.isEmpty { parts.append("\(selection.count) selected") }
        parts.append("drag out to copy")
        return parts.joined(separator: " · ")
    }

    private var separator: some View {
        Rectangle().fill(Color.white.opacity(0.15)).frame(width: 1, height: 22)
    }

    private func action(_ symbol: String, _ help: String, perform: @escaping () -> Void) -> some View {
        Button(action: perform) {
            Image(systemName: symbol)
                .font(.system(size: 13, weight: .medium))
                .frame(width: 32, height: 32)
                .background(Color.white.opacity(0.1), in: Circle())
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .disabled(busy)
        .hoverLabel(help, edge: .top, anchor: symbol == "xmark" ? .trailing : .center)
    }

    private func flash(_ text: String) {
        message = text
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
            if message == text { message = nil }
        }
    }

    private func showConvertMenu() {
        let files = targets
        ClosureMenu.show([
            ("Convert to PNG", { convert(files, to: .png) }),
            ("Convert to JPEG", { convert(files, to: .jpeg) }),
            ("Convert to HEIC", { convert(files, to: .heic) }),
        ])
    }

    private func convert(_ files: [URL], to type: UTType) {
        busy = true
        ShelfActions.convertImages(files, to: type) { created in
            busy = false
            created.forEach(shelf.add)
            flash(created.isEmpty ? "No images to convert" : "Converted \(created.count) \(created.count == 1 ? "image" : "images")")
        }
    }

    private func combineIntoPDF() {
        busy = true
        ShelfActions.combineIntoPDF(targets) { url in
            busy = false
            if let url {
                shelf.add(url)
                flash("Saved \(url.lastPathComponent) to Downloads")
            } else {
                flash("No images or PDFs to combine")
            }
        }
    }

    private func compress() {
        busy = true
        ShelfActions.compress(targets) { url in
            busy = false
            if let url {
                shelf.add(url)
                flash("Saved \(url.lastPathComponent) to Downloads")
            } else {
                flash("Couldn't create the archive")
            }
        }
    }

    private func copyText() {
        busy = true
        ShelfActions.recognizeText(targets) { text in
            busy = false
            if text.isEmpty {
                flash("No text found")
            } else {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(text, forType: .string)
                flash("Copied \(text.count) characters of text")
            }
        }
    }
}

/// A Quick Look thumbnail (photos, PDFs, documents), falling back to the file's icon.
struct FileThumbnail: View {
    let url: URL
    let size: CGFloat
    @State private var thumbnail: NSImage?

    var body: some View {
        Group {
            if let thumbnail {
                Image(nsImage: thumbnail)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .clipShape(RoundedRectangle(cornerRadius: size * 0.14, style: .continuous))
            } else {
                Image(nsImage: NSWorkspace.shared.icon(forFile: url.path))
                    .resizable()
            }
        }
        .frame(width: size, height: size)
        .task(id: url) {
            let request = QLThumbnailGenerator.Request(fileAt: url, size: CGSize(width: size, height: size),
                                                       scale: 2, representationTypes: .thumbnail)
            thumbnail = try? await QLThumbnailGenerator.shared.generateBestRepresentation(for: request).nsImage
        }
    }
}
