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
        // Keep background drag enabled for smooth moving, while sendEvent activates key input immediately
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

    public func focusForTextInput() {
        NSApp.activate(ignoringOtherApps: true)
        self.makeKeyAndOrderFront(nil)
    }
}
