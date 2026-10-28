import Foundation
import AppKit
import AVFoundation
import Combine
import UniformTypeIdentifiers

@MainActor
public final class NotebookManager: NSObject, ObservableObject, AVAudioRecorderDelegate, AVAudioPlayerDelegate {
    public static let shared = NotebookManager()

    @Published public var selectedCategory: NotebookCategory = .insights
    @Published public var pagesByCategory: [NotebookCategory: [NotebookPageManifest]] = [:]
    @Published public var activePageIdByCategory: [NotebookCategory: String] = [:]
    @Published public var currentManifest: NotebookPageManifest = NotebookPageManifest(category: .insights)

    // Voice Recording & Playback State
    @Published public var isRecordingVoice: Bool = false
    @Published public var recordingSeconds: Int = 0
    @Published public var playingAttachmentId: UUID? = nil
    @Published public var lastAutoSaveStatus: String = "Avto-saqlandi"

    public weak var activeTextView: NSTextView?

    public let notebookRootURL: URL
    private var saveWorkItem: DispatchWorkItem?
    private var audioRecorder: AVAudioRecorder?
    private var audioPlayer: AVAudioPlayer?
    private var recordingTimer: Timer?
    private var currentRecordingFileName: String = ""

    private override init() {
        let home = FileManager.default.homeDirectoryForCurrentUser
        self.notebookRootURL = home
            .appendingPathComponent(".focus_corner", isDirectory: true)
            .appendingPathComponent("notebook", isDirectory: true)
        super.init()
        ensureDirectoryStructure()
        loadCategory(selectedCategory)
    }

    // MARK: - Directory & Manifest Management (Zero-RAM Bloat: Only 1 Page Loaded at a Time)

    public func categoryDirURL(for category: NotebookCategory) -> URL {
        notebookRootURL.appendingPathComponent(category.folderName, isDirectory: true)
    }

    public func mediaDirURL(for category: NotebookCategory) -> URL {
        categoryDirURL(for: category).appendingPathComponent("media", isDirectory: true)
    }

    private func manifestListURL(for category: NotebookCategory) -> URL {
        categoryDirURL(for: category).appendingPathComponent("pages_index.json")
    }

    private func ensureDirectoryStructure() {
        let fm = FileManager.default
        for cat in NotebookCategory.allCases {
            try? fm.createDirectory(at: categoryDirURL(for: cat), withIntermediateDirectories: true)
            try? fm.createDirectory(at: mediaDirURL(for: cat), withIntermediateDirectories: true)
        }
    }

    public func switchCategory(_ category: NotebookCategory) {
        flushPendingSaveImmediately()
        selectedCategory = category
        loadCategory(category)
        // Release any cached temporary allocations when switching categories
        DevChannelManager.shared.silentMemoryTrim()
    }

    public func loadCategory(_ category: NotebookCategory) {
        let indexURL = manifestListURL(for: category)
        var pages: [NotebookPageManifest] = []
        if let data = try? Data(contentsOf: indexURL),
           let decoded = try? JSONDecoder().decode([NotebookPageManifest].self, from: data),
           !decoded.isEmpty {
            pages = decoded
        } else {
            let initialPage = NotebookPageManifest(
                pageId: "page_1",
                title: "\(category.displayName) #1",
                category: category,
                createdAt: Self.timestampString(),
                updatedAt: Self.timestampString(),
                rtfFileName: "page_1.rtf",
                attachments: []
            )
            pages = [initialPage]
            savePagesIndex(pages, for: category)
            seedInitialPageIfNeeded(initialPage)
        }

        pagesByCategory[category] = pages
        let targetId = activePageIdByCategory[category] ?? pages.first!.pageId
        if let found = pages.first(where: { $0.pageId == targetId }) ?? pages.first {
            activePageIdByCategory[category] = found.pageId
            currentManifest = found
            loadRTFIntoActiveEditor(for: found)
        }
    }

    private func seedInitialPageIfNeeded(_ manifest: NotebookPageManifest) {
        let rtfURL = categoryDirURL(for: manifest.category).appendingPathComponent(manifest.rtfFileName)
        guard !FileManager.default.fileExists(atPath: rtfURL.path) else { return }

        let welcomeText: String
        switch manifest.category {
        case .insights:
            welcomeText = "💡 Insightlar va Kashfiyotlar\n\n• Bugun tushunib yetgan eng muhim fikringizni shu yerga yozib boring...\n"
        case .quickCapture:
            welcomeText = "📌 Tezkor Eslab Qolish\n\n• Ko'chada eshitilgan fikr, kitob, odam yoki muhim eslatmalar...\n"
        case .journal:
            welcomeText = "📖 Journaling & Falsafiy Fikrlar\n\n• Chuqur mulohazalar, iqtiboslar va kundalik yozuvlar...\n"
        }

        let attr = Self.makeDefaultAttributedString(welcomeText)
        saveAttributedStringToDisk(attr, to: rtfURL)
    }

    private func savePagesIndex(_ pages: [NotebookPageManifest], for category: NotebookCategory) {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        if let data = try? encoder.encode(pages) {
            try? data.write(to: manifestListURL(for: category), options: .atomic)
        }
    }

    private func updateCurrentManifestInIndex() {
        var list = pagesByCategory[selectedCategory] ?? [currentManifest]
        if let idx = list.firstIndex(where: { $0.pageId == currentManifest.pageId }) {
            list[idx] = currentManifest
        } else {
            list.insert(currentManifest, at: 0)
        }
        pagesByCategory[selectedCategory] = list
        savePagesIndex(list, for: selectedCategory)
    }

    // MARK: - Create New Page ("Yangi ochish") & Switch Page

    public func createNewPage() {
        flushPendingSaveImmediately()
        var list = pagesByCategory[selectedCategory] ?? []
        let nextNum = list.count + 1
        let pid = "page_\(Int(Date().timeIntervalSince1970))"
        let newPage = NotebookPageManifest(
            pageId: pid,
            title: "\(selectedCategory.displayName) #\(nextNum) (\(TaskItem.todayString()))",
            category: selectedCategory,
            createdAt: Self.timestampString(),
            updatedAt: Self.timestampString(),
            rtfFileName: "\(pid).rtf",
            attachments: []
        )
        let headerAttr = Self.makeDefaultAttributedString("📅 \(Self.timestampString()) — \(newPage.title)\n\n")
        let rtfURL = categoryDirURL(for: selectedCategory).appendingPathComponent(newPage.rtfFileName)
        saveAttributedStringToDisk(headerAttr, to: rtfURL)

        list.insert(newPage, at: 0)
        pagesByCategory[selectedCategory] = list
        activePageIdByCategory[selectedCategory] = newPage.pageId
        currentManifest = newPage
        savePagesIndex(list, for: selectedCategory)
        loadRTFIntoActiveEditor(for: newPage)
        StorageManager.shared.showToast("📄 Yangi sahifa ochildi: \(newPage.title)")
    }

    public func selectPage(_ page: NotebookPageManifest) {
        flushPendingSaveImmediately()
        activePageIdByCategory[selectedCategory] = page.pageId
        currentManifest = page
        loadRTFIntoActiveEditor(for: page)
    }

    // MARK: - Stream-to-Disk Auto-Save Engine

    public func loadRTFIntoActiveEditor(for manifest: NotebookPageManifest) {
        guard let tv = activeTextView else { return }
        let rtfURL = categoryDirURL(for: manifest.category).appendingPathComponent(manifest.rtfFileName)
        let loaded = loadAttributedStringFromDisk(from: rtfURL)
        tv.textStorage?.setAttributedString(loaded)
    }

    public func loadCurrentPageAttributedString() -> NSAttributedString {
        let rtfURL = categoryDirURL(for: currentManifest.category).appendingPathComponent(currentManifest.rtfFileName)
        return loadAttributedStringFromDisk(from: rtfURL)
    }

    private func loadAttributedStringFromDisk(from url: URL) -> NSAttributedString {
        if let data = try? Data(contentsOf: url),
           let attr = try? NSAttributedString(
               data: data,
               options: [.documentType: NSAttributedString.DocumentType.rtf],
               documentAttributes: nil
           ) {
            return attr
        }
        return Self.makeDefaultAttributedString("")
    }

    private func saveAttributedStringToDisk(_ attr: NSAttributedString, to url: URL) {
        let range = NSRange(location: 0, length: attr.length)
        if let data = try? attr.rtf(from: range, documentAttributes: [.documentType: NSAttributedString.DocumentType.rtf]) {
            try? data.write(to: url, options: .atomic)
        }
    }

    public func scheduleDebouncedAutoSave() {
        lastAutoSaveStatus = "Saqlanmoqda..."
        saveWorkItem?.cancel()
        let item = DispatchWorkItem { [weak self] in
            Task { @MainActor in
                self?.flushPendingSaveImmediately()
            }
        }
        saveWorkItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.55, execute: item)
    }

    public func flushPendingSaveImmediately() {
        saveWorkItem?.cancel()
        saveWorkItem = nil
        guard let tv = activeTextView, let storage = tv.textStorage else { return }
        let rtfURL = categoryDirURL(for: currentManifest.category).appendingPathComponent(currentManifest.rtfFileName)
        saveAttributedStringToDisk(storage, to: rtfURL)
        currentManifest.updatedAt = Self.timestampString()
        updateCurrentManifestInIndex()
        lastAutoSaveStatus = "Avto-saqlandi"
    }

    // MARK: - Rich Text Formatting Actions (Icon-Driven)

    public func toggleBold() {
        guard let tv = activeTextView, let storage = tv.textStorage else { return }
        let sel = tv.selectedRange()
        let fm = NSFontManager.shared
        if sel.length > 0 {
            storage.beginEditing()
            storage.enumerateAttribute(.font, in: sel, options: []) { val, range, _ in
                let currentFont = (val as? NSFont) ?? NSFont.systemFont(ofSize: 13)
                let isBold = fm.traits(of: currentFont).contains(.boldFontMask)
                let newFont = isBold
                    ? fm.convert(currentFont, toNotHaveTrait: .boldFontMask)
                    : fm.convert(currentFont, toHaveTrait: .boldFontMask)
                storage.addAttribute(.font, value: newFont, range: range)
            }
            storage.endEditing()
            scheduleDebouncedAutoSave()
        } else {
            var attrs = tv.typingAttributes
            let currentFont = (attrs[.font] as? NSFont) ?? NSFont.systemFont(ofSize: 13)
            let isBold = fm.traits(of: currentFont).contains(.boldFontMask)
            attrs[.font] = isBold
                ? fm.convert(currentFont, toNotHaveTrait: .boldFontMask)
                : fm.convert(currentFont, toHaveTrait: .boldFontMask)
            tv.typingAttributes = attrs
        }
    }

    public func adjustFontSize(delta: CGFloat) {
        guard let tv = activeTextView, let storage = tv.textStorage else { return }
        let sel = tv.selectedRange()
        if sel.length > 0 {
            storage.beginEditing()
            storage.enumerateAttribute(.font, in: sel, options: []) { val, range, _ in
                let currentFont = (val as? NSFont) ?? NSFont.systemFont(ofSize: 13)
                let newSize = max(10, min(26, currentFont.pointSize + delta))
                if let resized = NSFont(descriptor: currentFont.fontDescriptor, size: newSize) {
                    storage.addAttribute(.font, value: resized, range: range)
                }
            }
            storage.endEditing()
            scheduleDebouncedAutoSave()
        } else {
            var attrs = tv.typingAttributes
            let currentFont = (attrs[.font] as? NSFont) ?? NSFont.systemFont(ofSize: 13)
            let newSize = max(10, min(26, currentFont.pointSize + delta))
            if let resized = NSFont(descriptor: currentFont.fontDescriptor, size: newSize) {
                attrs[.font] = resized
                tv.typingAttributes = attrs
            }
        }
    }

    public func applyTextColor(_ highlight: NoteHighlightColor) {
        guard let tv = activeTextView, let storage = tv.textStorage else { return }
        let sel = tv.selectedRange()
        if sel.length > 0 {
            storage.beginEditing()
            storage.addAttribute(.foregroundColor, value: highlight.nsColor, range: sel)
            storage.endEditing()
            scheduleDebouncedAutoSave()
        } else {
            var attrs = tv.typingAttributes
            attrs[.foregroundColor] = highlight.nsColor
            tv.typingAttributes = attrs
        }
    }

    public func insertBulletList() {
        insertTextAtCursor("\n  • ")
    }

    public func insertNumberedList() {
        insertTextAtCursor("\n  1. \n  2. \n  3. ")
    }

    public func insertTableGrid(rows: Int = 3, cols: Int = 3) {
        var tableStr = "\n┌────────────────┬────────────────┬────────────────┐\n"
        tableStr += "│ Ustun 1        │ Ustun 2        │ Ustun 3        │\n"
        tableStr += "├────────────────┼────────────────┼────────────────┤\n"
        for r in 1..<rows {
            tableStr += "│ Qator \(r)        │                │                │\n"
        }
        tableStr += "└────────────────┴────────────────┴────────────────┘\n"
        insertTextAtCursor(tableStr, monospaced: true)
    }

    public func insertTimestampDivider() {
        let stamp = "\n── 📅 \(Self.timestampString()) ──\n"
        insertTextAtCursor(stamp, color: NSColor(calibratedRed: 0.36, green: 0.84, blue: 0.96, alpha: 1.0))
    }

    public func insertTextAtCursor(_ text: String, monospaced: Bool = false, color: NSColor? = nil) {
        guard let tv = activeTextView, let storage = tv.textStorage else { return }
        let font = monospaced
            ? NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
            : NSFont.systemFont(ofSize: 13, weight: .regular)
        let fg = color ?? NSColor(calibratedWhite: 0.94, alpha: 1.0)
        let attr = NSAttributedString(
            string: text,
            attributes: [
                .font: font,
                .foregroundColor: fg
            ]
        )
        let sel = tv.selectedRange()
        storage.beginEditing()
        storage.replaceCharacters(in: sel, with: attr)
        storage.endEditing()
        let newCursor = sel.location + attr.length
        tv.setSelectedRange(NSRange(location: newCursor, length: 0))
        scheduleDebouncedAutoSave()
    }

    // MARK: - Multi-Modal Attachments: Image, Voice Note & Link

    public func pickAndAttachImage() {
        // First check if user has an image copied on the clipboard; otherwise open file picker
        let panel = NSOpenPanel()
        panel.title = "Bloknotga rasm qo'shish"
        panel.allowedContentTypes = [UTType.image, UTType.png, UTType.jpeg]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false

        NSApp.activate(ignoringOtherApps: true)
        if panel.runModal() == .OK, let srcURL = panel.url {
            attachImage(from: srcURL)
        }
    }

    public func pasteImageFromClipboardIfAvailable() -> Bool {
        let pb = NSPasteboard.general
        guard let img = NSImage(pasteboard: pb),
              let tiff = img.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff),
              let jpegData = rep.representation(using: .jpeg, properties: [.compressionFactor: 0.78]) else {
            return false
        }
        let fileName = "img_\(Int(Date().timeIntervalSince1970)).jpg"
        let destURL = mediaDirURL(for: selectedCategory).appendingPathComponent(fileName)
        do {
            try jpegData.write(to: destURL, options: .atomic)
            registerAttachment(
                kind: .image,
                title: "Skrinshot (\(Self.shortTimeString()))",
                relativePath: "media/\(fileName)"
            )
            return true
        } catch {
            return false
        }
    }

    private func attachImage(from srcURL: URL) {
        guard let img = NSImage(contentsOf: srcURL),
              let tiff = img.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff),
              let jpegData = rep.representation(using: .jpeg, properties: [.compressionFactor: 0.78]) else {
            return
        }
        let cleanBase = srcURL.deletingPathExtension().lastPathComponent
        let fileName = "img_\(Int(Date().timeIntervalSince1970))_\(cleanBase.prefix(16)).jpg"
        let destURL = mediaDirURL(for: selectedCategory).appendingPathComponent(fileName)
        do {
            try jpegData.write(to: destURL, options: .atomic)
            registerAttachment(
                kind: .image,
                title: srcURL.lastPathComponent,
                relativePath: "media/\(fileName)"
            )
        } catch {
            StorageManager.shared.showToast("⚠️ Rasmni saqlashda xatolik yuz berdi")
        }
    }

    public func toggleVoiceRecording() {
        if isRecordingVoice {
            stopVoiceRecording()
        } else {
            startVoiceRecording()
        }
    }

    private func startVoiceRecording() {
        let fileName = "voice_\(Int(Date().timeIntervalSince1970)).m4a"
        let destURL = mediaDirURL(for: selectedCategory).appendingPathComponent(fileName)
        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
            AVSampleRateKey: 22050.0,
            AVNumberOfChannelsKey: 1,
            AVEncoderAudioQualityKey: AVAudioQuality.medium.rawValue,
            AVEncoderBitRateKey: 32000
        ]

        do {
            let recorder = try AVAudioRecorder(url: destURL, settings: settings)
            recorder.delegate = self
            if recorder.record() {
                self.audioRecorder = recorder
                self.currentRecordingFileName = fileName
                self.recordingSeconds = 0
                self.isRecordingVoice = true
                recordingTimer?.invalidate()
                recordingTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
                    Task { @MainActor in
                        self?.recordingSeconds += 1
                    }
                }
            } else {
                StorageManager.shared.showToast("🎙 Mikrofon ruxsatini tizim sozlamalaridan tekshiring")
            }
        } catch {
            StorageManager.shared.showToast("🎙 Ovoz yozishni boshlab bo'lmadi")
        }
    }

    private func stopVoiceRecording() {
        recordingTimer?.invalidate()
        recordingTimer = nil
        let dur = max(1, recordingSeconds)
        audioRecorder?.stop()
        audioRecorder = nil
        isRecordingVoice = false

        if !currentRecordingFileName.isEmpty {
            let mins = dur / 60
            let secs = dur % 60
            let durLabel = String(format: "%02d:%02d", mins, secs)
            registerAttachment(
                kind: .audio,
                title: "Ovozli xabar (\(durLabel) • \(Self.shortTimeString()))",
                relativePath: "media/\(currentRecordingFileName)"
            )
            currentRecordingFileName = ""
        }
    }

    public func attachLink(_ urlString: String, label: String = "") {
        var trimmed = urlString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        if !trimmed.lowercased().hasPrefix("http://") && !trimmed.lowercased().hasPrefix("https://") {
            trimmed = "https://" + trimmed
        }
        let display = label.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? trimmed : label
        registerAttachment(kind: .link, title: display, relativePath: trimmed)
    }

    private func registerAttachment(kind: NotebookAttachmentKind, title: String, relativePath: String) {
        let item = NotebookAttachment(
            kind: kind,
            title: title,
            relativeFilePath: relativePath,
            createdAt: Self.timestampString()
        )
        currentManifest.attachments.insert(item, at: 0)
        updateCurrentManifestInIndex()

        let tagIcon: String
        switch kind {
        case .image: tagIcon = "🖼 Rasm"
        case .audio: tagIcon = "🎙 Ovoz"
        case .link: tagIcon = "🔗 Link"
        }
        insertTextAtCursor(
            "\n[\(tagIcon): \(title)]\n",
            color: NSColor(calibratedRed: 0.38, green: 0.78, blue: 1.00, alpha: 1.0)
        )
    }

    public func openOrPlayAttachment(_ att: NotebookAttachment) {
        switch att.kind {
        case .link:
            if let u = URL(string: att.relativeFilePath) {
                NSWorkspace.shared.open(u)
            }
        case .image:
            let fileURL = categoryDirURL(for: selectedCategory).appendingPathComponent(att.relativeFilePath)
            NSWorkspace.shared.open(fileURL)
        case .audio:
            if playingAttachmentId == att.id {
                audioPlayer?.stop()
                audioPlayer = nil
                playingAttachmentId = nil
                return
            }
            let fileURL = categoryDirURL(for: selectedCategory).appendingPathComponent(att.relativeFilePath)
            if let player = try? AVAudioPlayer(contentsOf: fileURL) {
                player.delegate = self
                player.play()
                self.audioPlayer = player
                self.playingAttachmentId = att.id
            } else {
                NSWorkspace.shared.open(fileURL)
            }
        }
    }

    public func deleteAttachment(_ att: NotebookAttachment) {
        if att.kind != .link {
            let fileURL = categoryDirURL(for: selectedCategory).appendingPathComponent(att.relativeFilePath)
            try? FileManager.default.removeItem(at: fileURL)
        }
        currentManifest.attachments.removeAll { $0.id == att.id }
        updateCurrentManifestInIndex()
    }

    nonisolated public func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor in
            self.playingAttachmentId = nil
            self.audioPlayer = nil
        }
    }

    // MARK: - Smart Organized Export ("Yuklab olish" -> ~/Downloads)

    public func exportCurrentNotebookToDownloads() {
        flushPendingSaveImmediately()
        let fm = FileManager.default
        let downloadsDir = fm.homeDirectoryForCurrentUser.appendingPathComponent("Downloads", isDirectory: true)
        let safeCat = selectedCategory.folderName
        let dateStamp = TaskItem.todayString()
        let exportFolderName = "FocusCorner_Bloknot_\(safeCat)_\(dateStamp)"
        let exportDir = downloadsDir.appendingPathComponent(exportFolderName, isDirectory: true)
        let exportMediaDir = exportDir.appendingPathComponent("media", isDirectory: true)

        try? fm.removeItem(at: exportDir)
        try? fm.createDirectory(at: exportMediaDir, withIntermediateDirectories: true)

        // 1. Copy active RTF and also write clean Markdown
        let srcRTF = categoryDirURL(for: selectedCategory).appendingPathComponent(currentManifest.rtfFileName)
        let dstRTF = exportDir.appendingPathComponent("\(currentManifest.title).rtf")
        try? fm.copyItem(at: srcRTF, to: dstRTF)

        let attr = loadCurrentPageAttributedString()
        let plainText = attr.string
        let dstMD = exportDir.appendingPathComponent("\(currentManifest.title).md")
        try? plainText.write(to: dstMD, atomically: true, encoding: .utf8)

        // 2. Copy all attached images and voice notes neatly into media/
        var mediaHTMLBlocks = ""
        for att in currentManifest.attachments {
            if att.kind == .link {
                mediaHTMLBlocks += "<div class='card'>🔗 <b>Link:</b> <a href='\(att.relativeFilePath)' target='_blank'>\(att.title)</a></div>\n"
            } else {
                let srcMedia = categoryDirURL(for: selectedCategory).appendingPathComponent(att.relativeFilePath)
                let fileName = (att.relativeFilePath as NSString).lastPathComponent
                let dstMedia = exportMediaDir.appendingPathComponent(fileName)
                try? fm.copyItem(at: srcMedia, to: dstMedia)

                if att.kind == .image {
                    mediaHTMLBlocks += "<div class='card'><div>🖼 <b>\(att.title)</b> (\(att.createdAt))</div><img src='media/\(fileName)' style='max-width:100%;max-height:420px;border-radius:10px;margin-top:8px;'/></div>\n"
                } else if att.kind == .audio {
                    mediaHTMLBlocks += "<div class='card'><div>🎙 <b>\(att.title)</b></div><audio controls src='media/\(fileName)' style='margin-top:8px;width:100%;'></audio></div>\n"
                }
            }
        }

        // 3. Generate self-contained, organized index.html so user can view text + images + voice notes together
        let escapedText = plainText
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\n", with: "<br/>")

        let html = """
        <!DOCTYPE html>
        <html lang="uz">
        <head>
        <meta charset="UTF-8">
        <title>\(currentManifest.title) — FocusCorner Bloknot</title>
        <style>
            body { font-family: -apple-system, BlinkMacSystemFont, sans-serif; background: #0f1117; color: #f0f4f8; max-width: 820px; margin: 36px auto; padding: 24px; line-height: 1.65; }
            h1 { color: #58a6ff; margin-bottom: 4px; }
            .meta { color: #8b949e; font-size: 13px; margin-bottom: 24px; }
            .note-body { background: #161b22; border: 1px solid #30363d; border-radius: 14px; padding: 22px; font-size: 15px; white-space: pre-wrap; margin-bottom: 24px; }
            .card { background: #161b22; border: 1px solid #30363d; border-radius: 12px; padding: 14px; margin-bottom: 12px; }
            a { color: #58a6ff; }
        </style>
        </head>
        <body>
            <h1>\(currentManifest.title)</h1>
            <div class="meta">Bo'lim: \(selectedCategory.displayName) • Eksport vaqti: \(Self.timestampString())</div>
            <div class="note-body">\(escapedText)</div>
            \(mediaHTMLBlocks.isEmpty ? "" : "<h2>Biriktirilgan Rasmlar, Ovozli Xabarlar va Linklar</h2>" + mediaHTMLBlocks)
        </body>
        </html>
        """
        let htmlURL = exportDir.appendingPathComponent("Bloknot_Ko'rish.html")
        try? html.write(to: htmlURL, atomically: true, encoding: .utf8)

        NSWorkspace.shared.activateFileViewerSelecting([exportDir])
        StorageManager.shared.showToast("⬇️ Bloknot (matn, rasm va ovozlar bilan) Downloads papkasiga yuklandi!")
    }

    // MARK: - Helpers

    public static func makeDefaultAttributedString(_ text: String) -> NSAttributedString {
        let para = NSMutableParagraphStyle()
        para.lineSpacing = 3.5
        return NSAttributedString(
            string: text,
            attributes: [
                .font: NSFont.systemFont(ofSize: 13, weight: .regular),
                .foregroundColor: NSColor(calibratedWhite: 0.94, alpha: 1.0),
                .paragraphStyle: para
            ]
        )
    }

    public static func timestampString(from date: Date = Date()) -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd HH:mm"
        f.timeZone = TimeZone.current
        return f.string(from: date)
    }

    public static func shortTimeString(from date: Date = Date()) -> String {
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        f.timeZone = TimeZone.current
        return f.string(from: date)
    }
}
