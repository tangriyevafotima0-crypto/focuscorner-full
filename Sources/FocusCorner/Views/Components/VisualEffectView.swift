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

/// Custom vector emblem logo for FocusCorner (Sapphire-Cyan Squircle + Primeval Aperture Diamond + Focus Core)
public struct FocusCornerLogoBadge: View {
    public var size: CGFloat

    public init(size: CGFloat = 20) {
        self.size = size
    }

    public var body: some View {
        ZStack {
            // Outer Sapphire-Cyan Squircle Shield
            RoundedRectangle(cornerRadius: size * 0.28, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            Color(red: 0.14, green: 0.42, blue: 0.92),
                            Color(red: 0.06, green: 0.16, blue: 0.38)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: size, height: size)
                .overlay(
                    RoundedRectangle(cornerRadius: size * 0.28, style: .continuous)
                        .stroke(
                            LinearGradient(
                                colors: [
                                    Color(red: 0.45, green: 0.88, blue: 1.00).opacity(0.85),
                                    Color(red: 0.20, green: 0.55, blue: 0.95).opacity(0.30)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: max(1.0, size * 0.06)
                        )
                )
                .shadow(color: Color(red: 0.20, green: 0.68, blue: 1.00).opacity(0.32), radius: size * 0.16, x: 0, y: 1)

            // Inner Rotated Aperture Diamond Ring
            RoundedRectangle(cornerRadius: size * 0.12, style: .continuous)
                .stroke(
                    LinearGradient(
                        colors: [
                            Color(red: 0.42, green: 0.94, blue: 0.88),
                            Color(red: 0.32, green: 0.72, blue: 1.00)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    ),
                    lineWidth: max(1.1, size * 0.075)
                )
                .frame(width: size * 0.50, height: size * 0.50)
                .rotationEffect(.degrees(45))

            // Glowing Center Focus Core
            Circle()
                .fill(
                    RadialGradient(
                        colors: [
                            Color.white,
                            Color(red: 0.36, green: 0.92, blue: 0.96)
                        ],
                        center: .center,
                        startRadius: 0,
                        endRadius: size * 0.16
                    )
                )
                .frame(width: size * 0.24, height: size * 0.24)
        }
        .frame(width: size, height: size)
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
