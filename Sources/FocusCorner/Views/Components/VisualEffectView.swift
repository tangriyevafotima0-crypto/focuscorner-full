import SwiftUI
import AppKit

public struct VisualEffectView: NSViewRepresentable {
    public var material: NSVisualEffectView.Material
    public var blendingMode: NSVisualEffectView.BlendingMode
    public var state: NSVisualEffectView.State

    public init(
        material: NSVisualEffectView.Material = .hudWindow,
        blendingMode: NSVisualEffectView.BlendingMode = .behindWindow,
        state: NSVisualEffectView.State = .active
    ) {
        self.material = material
        self.blendingMode = blendingMode
        self.state = state
    }

    public func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = blendingMode
        view.state = state
        view.appearance = NSAppearance(named: .vibrantDark)
        return view
    }

    public func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.material = material
        nsView.blendingMode = blendingMode
        nsView.state = state
    }
}

/// Interactive bottom-right corner drag grip for smooth custom resizing of borderless NSPanels
public struct ResizeGripHandle: View {
    public var onDragDelta: (NSSize) -> Void
    @State private var lastTranslation: CGSize = .zero

    public init(onDragDelta: @escaping (NSSize) -> Void) {
        self.onDragDelta = onDragDelta
    }

    public var body: some View {
        ZStack(alignment: .bottomTrailing) {
            Color.clear
                .frame(width: 20, height: 20)
            Image(systemName: "arrow.up.left.and.arrow.down.right")
                .font(.system(size: 9, weight: .bold))
                .foregroundColor(.white.opacity(0.45))
                .padding(4)
        }
        .contentShape(Rectangle())
        .help("O'lchamni o'zgartirish uchun torting (Resize)")
        .gesture(
            DragGesture(minimumDistance: 1)
                .onChanged { value in
                    let dx = value.translation.width - lastTranslation.width
                    let dy = value.translation.height - lastTranslation.height
                    lastTranslation = value.translation
                    onDragDelta(NSSize(width: dx, height: dy))
                }
                .onEnded { _ in
                    lastTranslation = .zero
                }
        )
    }
}
