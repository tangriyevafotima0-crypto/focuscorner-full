import SwiftUI
import AppKit

public final class NotebookNSTextView: NSTextView {
    public override func mouseDown(with event: NSEvent) {
        if !NSApp.isActive {
            NSApp.activate(ignoringOtherApps: true)
        }
        self.window?.makeKeyAndOrderFront(nil)
        super.mouseDown(with: event)
    }

    public override func paste(_ sender: Any?) {
        // If user pastes an image/screenshot (Cmd+V), stream it directly to disk media/ folder
        if NotebookManager.shared.pasteImageFromClipboardIfAvailable() {
            return
        }
        super.paste(sender)
    }

    public override func performKeyEquivalent(with event: NSEvent) -> Bool {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        if flags == .command, let ch = event.charactersIgnoringModifiers?.lowercased() {
            switch ch {
            case "b":
                NotebookManager.shared.toggleBold()
                return true
            case "=", "+":
                NotebookManager.shared.adjustFontSize(delta: 2)
                return true
            case "-":
                NotebookManager.shared.adjustFontSize(delta: -2)
                return true
            case "1":
                NotebookManager.shared.switchCategory(.insights)
                return true
            case "2":
                NotebookManager.shared.switchCategory(.quickCapture)
                return true
            case "3":
                NotebookManager.shared.switchCategory(.journal)
                return true
            default:
                break
            }
        }
        return super.performKeyEquivalent(with: event)
    }
}

public struct RichNotebookEditor: NSViewRepresentable {
    public var pageId: String
    public var category: NotebookCategory

    public init(pageId: String, category: NotebookCategory) {
        self.pageId = pageId
        self.category = category
    }

    public func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    public func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.drawsBackground = false

        let textView = NotebookNSTextView()
        textView.isRichText = true
        textView.allowsUndo = true
        textView.isEditable = true
        textView.isSelectable = true
        textView.importsGraphics = false
        textView.drawsBackground = false
        textView.textContainerInset = NSSize(width: 10, height: 10)
        textView.insertionPointColor = NSColor(calibratedRed: 0.35, green: 0.75, blue: 1.0, alpha: 1.0)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.containerSize = NSSize(width: scrollView.contentSize.width, height: CGFloat.greatestFiniteMagnitude)
        textView.delegate = context.coordinator

        let initialAttr = NotebookManager.shared.loadCurrentPageAttributedString()
        textView.textStorage?.setAttributedString(initialAttr)

        scrollView.documentView = textView
        NotebookManager.shared.activeTextView = textView
        context.coordinator.lastLoadedKey = "\(category.rawValue)_\(pageId)"
        return scrollView
    }

    public func updateNSView(_ nsView: NSScrollView, context: Context) {
        guard let textView = nsView.documentView as? NotebookNSTextView else { return }
        NotebookManager.shared.activeTextView = textView
        let key = "\(category.rawValue)_\(pageId)"
        if context.coordinator.lastLoadedKey != key {
            context.coordinator.lastLoadedKey = key
            let loaded = NotebookManager.shared.loadCurrentPageAttributedString()
            textView.textStorage?.setAttributedString(loaded)
        }
    }

    public final class Coordinator: NSObject, NSTextViewDelegate {
        public var lastLoadedKey: String = ""

        public func textDidChange(_ notification: Notification) {
            Task { @MainActor in
                NotebookManager.shared.scheduleDebouncedAutoSave()
            }
        }
    }
}
