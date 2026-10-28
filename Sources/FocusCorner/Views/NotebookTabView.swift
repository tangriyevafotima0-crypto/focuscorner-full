import SwiftUI
import AppKit

public struct NotebookTabView: View {
    @ObservedObject private var notebook = NotebookManager.shared
    @ObservedObject private var windowController = WindowController.shared

    @State private var showLinkInputPopover: Bool = false
    @State private var newLinkURL: String = ""
    @State private var newLinkTitle: String = ""

    public init() {}

    public var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            // 1. Top Row: 3 Category Pills (Insightlar | Eslab qolish | Journaling) + Page & Export Icons
            HStack(spacing: 5) {
                ForEach(NotebookCategory.allCases) { cat in
                    let isSel = (notebook.selectedCategory == cat)
                    Button(action: {
                        withAnimation(.easeInOut(duration: 0.15)) {
                            notebook.switchCategory(cat)
                        }
                    }) {
                        HStack(spacing: 4) {
                            Image(systemName: cat.iconName)
                                .font(.system(size: 10, weight: .semibold))
                            Text(cat.displayName)
                                .font(.system(size: 10.5, weight: isSel ? .semibold : .regular))
                        }
                        .padding(.horizontal, 9)
                        .padding(.vertical, 5)
                        .background(isSel ? cat.accentColor.opacity(0.20) : Color.white.opacity(0.05))
                        .foregroundColor(isSel ? cat.accentColor : .white.opacity(0.62))
                        .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .help(cat.subtitleHint)
                }

                Spacer(minLength: 2)

                // Page selector menu (if multiple pages exist in this category)
                let pages = notebook.pagesByCategory[notebook.selectedCategory] ?? []
                if pages.count > 1 {
                    Menu {
                        ForEach(pages, id: \.pageId) { p in
                            Button(action: { notebook.selectPage(p) }) {
                                Text(p.pageId == notebook.currentManifest.pageId ? "✓ \(p.title)" : p.title)
                            }
                        }
                    } label: {
                        Image(systemName: "doc.on.doc")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(.white.opacity(0.70))
                            .frame(width: 24, height: 24)
                            .background(Color.white.opacity(0.06))
                            .clipShape(Circle())
                    }
                    .menuStyle(.borderlessButton)
                    .fixedSize()
                    .help("Oldingi sahifalarni tanlash (\(pages.count) ta)")
                }

                // New Page Icon Button ("Yangi ochish")
                Button(action: { notebook.createNewPage() }) {
                    Image(systemName: "doc.badge.plus")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.white.opacity(0.78))
                        .frame(width: 24, height: 24)
                        .background(Color.white.opacity(0.06))
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
                .help("Yangi toza sahifa ochish (eski sahifa arxivda saqlanadi)")

                // Download / Export Icon Button ("Yuklab olish")
                Button(action: { notebook.exportCurrentNotebookToDownloads() }) {
                    Image(systemName: "arrow.down.doc.fill")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(Color(red: 0.35, green: 0.75, blue: 1.00))
                        .frame(width: 24, height: 24)
                        .background(Color(red: 0.35, green: 0.75, blue: 1.00).opacity(0.15))
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
                .help("Bloknotni (matn, rasm va ovozlar bilan) Downloads papkasiga tartibli yuklab olish")
            }

            // 2. Compact Icon-Only Formatting & Multi-Media Toolbar
            HStack(spacing: 4) {
                // Bold
                toolbarIconButton("bold", help: "Qalin yozuv (⌘B)") {
                    notebook.toggleBold()
                }
                // Larger Text
                toolbarIconButton("textformat.size.larger", help: "Kattaroq shrift (⌘+)") {
                    notebook.adjustFontSize(delta: 2)
                }
                // Smaller Text
                toolbarIconButton("textformat.size.smaller", help: "Kichikroq shrift (⌘-)") {
                    notebook.adjustFontSize(delta: -2)
                }

                // Color Palette Menu
                Menu {
                    ForEach(NoteHighlightColor.allCases) { col in
                        Button(action: { notebook.applyTextColor(col) }) {
                            Text("● \(col.rawValue)")
                        }
                    }
                } label: {
                    Image(systemName: "paintpalette.fill")
                        .font(.system(size: 10.5, weight: .medium))
                        .foregroundColor(Color(red: 0.98, green: 0.78, blue: 0.28))
                        .frame(width: 24, height: 22)
                        .background(Color.white.opacity(0.05))
                        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
                .help("Yozuv rangini bo'yash (esdan chiqmasligi uchun)")

                Divider().frame(height: 13)

                // Bullet List (•)
                toolbarIconButton("list.bullet", help: "Nuqtali ro'yxat (•)") {
                    notebook.insertBulletList()
                }
                // Numbered List (1. 2. 3.)
                toolbarIconButton("list.number", help: "Raqamli ro'yxat (1. 2. 3.)") {
                    notebook.insertNumberedList()
                }
                // Table Grid
                toolbarIconButton("tablecells", help: "Jadval (Table) qo'shish") {
                    notebook.insertTableGrid()
                }

                Divider().frame(height: 13)

                // Attach Image
                toolbarIconButton("photo.on.rectangle.angled", help: "Rasm qo'shish (yoki ⌘V orqali skrinshot joylash)") {
                    notebook.pickAndAttachImage()
                }

                // Record Voice Note
                Button(action: { notebook.toggleVoiceRecording() }) {
                    HStack(spacing: 3) {
                        Image(systemName: notebook.isRecordingVoice ? "stop.circle.fill" : "mic.fill")
                            .font(.system(size: 10.5, weight: .bold))
                        if notebook.isRecordingVoice {
                            Text(String(format: "%02d:%02d", notebook.recordingSeconds / 60, notebook.recordingSeconds % 60))
                                .font(.system(size: 9.5, weight: .bold, design: .monospaced))
                        }
                    }
                    .padding(.horizontal, notebook.isRecordingVoice ? 7 : 0)
                    .frame(minWidth: 24, minHeight: 22)
                    .background(notebook.isRecordingVoice ? Color.red.opacity(0.28) : Color.white.opacity(0.05))
                    .foregroundColor(notebook.isRecordingVoice ? .red : .white.opacity(0.78))
                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                }
                .buttonStyle(.plain)
                .help(notebook.isRecordingVoice ? "Ovoz yozishni to'xtatish va saqlash" : "Ovozli xabar yozish")

                // Attach Link
                Button(action: {
                    withAnimation(.easeInOut(duration: 0.15)) {
                        showLinkInputPopover.toggle()
                    }
                    if showLinkInputPopover {
                        windowController.notesPanel?.focusForTextInput()
                    }
                }) {
                    Image(systemName: "link.badge.plus")
                        .font(.system(size: 10.5, weight: .medium))
                        .foregroundColor(showLinkInputPopover ? Color(red: 0.35, green: 0.75, blue: 1.0) : .white.opacity(0.78))
                        .frame(width: 24, height: 22)
                        .background(Color.white.opacity(0.05))
                        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                }
                .buttonStyle(.plain)
                .help("Link (havola) qo'shish")

                // Timestamp Divider
                toolbarIconButton("clock", help: "Sana va vaqt belgisini kiritish") {
                    notebook.insertTimestampDivider()
                }

                Spacer()

                Text(notebook.lastAutoSaveStatus)
                    .font(.system(size: 9, weight: .medium))
                    .foregroundColor(.white.opacity(0.35))
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 4)
            .background(Color.white.opacity(0.035))
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

            // Optional inline link bar when 🔗 is clicked
            if showLinkInputPopover {
                HStack(spacing: 6) {
                    Image(systemName: "link")
                        .font(.system(size: 10.5))
                        .foregroundColor(Color(red: 0.35, green: 0.75, blue: 1.0))
                    TextField("https://...", text: $newLinkURL, onCommit: submitLink)
                        .textFieldStyle(.plain)
                        .font(.system(size: 11))
                        .foregroundColor(.white)
                    TextField("Nomi (ixtiyoriy)", text: $newLinkTitle, onCommit: submitLink)
                        .textFieldStyle(.plain)
                        .font(.system(size: 11))
                        .foregroundColor(.white.opacity(0.8))
                        .frame(width: 110)
                    Button(action: submitLink) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 14))
                            .foregroundColor(Color(red: 0.35, green: 0.75, blue: 1.0))
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Color.white.opacity(0.06))
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            }

            // 3. Rich Text Editor Surface
            RichNotebookEditor(
                pageId: notebook.currentManifest.pageId,
                category: notebook.selectedCategory
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.white.opacity(0.035))
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(Color.white.opacity(0.08), lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

            // 4. Compact Media Strip (Only shown if attachments exist on this page)
            if !notebook.currentManifest.attachments.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(notebook.currentManifest.attachments) { att in
                            attachmentChip(att)
                        }
                    }
                }
                .frame(height: 28)
            }
        }
    }

    private func toolbarIconButton(_ icon: String, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 10.5, weight: .medium))
                .foregroundColor(.white.opacity(0.78))
                .frame(width: 24, height: 22)
                .background(Color.white.opacity(0.05))
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        }
        .buttonStyle(.plain)
        .help(help)
    }

    private func attachmentChip(_ att: NotebookAttachment) -> some View {
        let isPlaying = (notebook.playingAttachmentId == att.id)
        let iconName: String
        let accent: Color
        switch att.kind {
        case .image:
            iconName = "photo.fill"
            accent = Color(red: 0.35, green: 0.75, blue: 1.0)
        case .audio:
            iconName = isPlaying ? "stop.fill" : "play.fill"
            accent = isPlaying ? .green : Color(red: 0.98, green: 0.78, blue: 0.28)
        case .link:
            iconName = "arrow.up.right.square.fill"
            accent = Color(red: 0.68, green: 0.52, blue: 0.98)
        }

        return HStack(spacing: 5) {
            Button(action: { notebook.openOrPlayAttachment(att) }) {
                HStack(spacing: 4) {
                    Image(systemName: iconName)
                        .font(.system(size: 9.5, weight: .bold))
                        .foregroundColor(accent)
                    Text(att.title)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(.white.opacity(0.88))
                        .lineLimit(1)
                }
            }
            .buttonStyle(.plain)

            Button(action: { notebook.deleteAttachment(att) }) {
                Image(systemName: "xmark")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundColor(.white.opacity(0.35))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(accent.opacity(0.12))
        .clipShape(Capsule())
    }

    private func submitLink() {
        guard !newLinkURL.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        notebook.attachLink(newLinkURL, label: newLinkTitle)
        newLinkURL = ""
        newLinkTitle = ""
        showLinkInputPopover = false
    }
}
