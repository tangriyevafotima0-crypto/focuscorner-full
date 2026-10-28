import AppKit
import SwiftUI

public final class FloatingPanel: NSPanel {
    public var allowBackgroundDrag: Bool = true {
        didSet {
            self.isMovableByWindowBackground = allowBackgroundDrag
            self.isMovable = allowBackgroundDrag
        }
    }

    public init(
        contentRect: NSRect,
        level: NSWindow.Level = .statusBar,
        movable: Bool = true
    ) {
        super.init(
            contentRect: contentRect,
            styleMask: [
                .borderless,
                .nonactivatingPanel,
                .resizable
            ],
            backing: .buffered,
            defer: false
        )

        self.allowBackgroundDrag = movable
        self.isFloatingPanel = true
        self.level = level

        self.hidesOnDeactivate = false
        self.worksWhenModal = true
        self.becomesKeyOnlyIfNeeded = false

        self.collectionBehavior = [
            .canJoinAllSpaces,
            .fullScreenAuxiliary,
            .stationary,
            .ignoresCycle
        ]

        self.backgroundColor = .clear
        self.isOpaque = false
        self.hasShadow = true
        self.titleVisibility = .hidden
        self.titlebarAppearsTransparent = true
        self.isMovableByWindowBackground = movable
        self.isMovable = movable
        self.isReleasedWhenClosed = false
        self.animationBehavior = .utilityWindow
    }

    public override var canBecomeKey: Bool { true }
    public override var canBecomeMain: Bool { true }

    public override func sendEvent(_ event: NSEvent) {
        if event.type == .leftMouseDown && !self.ignoresMouseEvents {
            if !NSApp.isActive {
                NSApp.activate(ignoringOtherApps: true)
            }
            if !self.isKeyWindow {
                self.makeKeyAndOrderFront(nil)
            }
        }
        super.sendEvent(event)
    }

    public override func performKeyEquivalent(with event: NSEvent) -> Bool {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        if flags == .command, let ch = event.charactersIgnoringModifiers?.lowercased() {
            switch ch {
            case "v":
                if NSApp.sendAction(#selector(NSText.paste(_:)), to: nil, from: self) { return true }
            case "c":
                if NSApp.sendAction(#selector(NSText.copy(_:)), to: nil, from: self) { return true }
            case "x":
                if NSApp.sendAction(#selector(NSText.cut(_:)), to: nil, from: self) { return true }
            case "a":
                if NSApp.sendAction(#selector(NSText.selectAll(_:)), to: nil, from: self) { return true }
            case "z":
                if NSApp.sendAction(Selector(("undo:")), to: nil, from: self) { return true }
            default:
                break
            }
        }
        return super.performKeyEquivalent(with: event)
    }

    public func focusForTextInput() {
        NSApp.activate(ignoringOtherApps: true)
        self.makeKeyAndOrderFront(nil)
    }
}
