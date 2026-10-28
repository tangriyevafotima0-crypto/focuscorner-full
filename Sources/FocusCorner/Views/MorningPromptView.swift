import SwiftUI
import AppKit

public struct MorningPromptView: View {
    @ObservedObject private var storage = StorageManager.shared
    public var onYes: () -> Void
    public var onNo: () -> Void

    public init(onYes: @escaping () -> Void, onNo: @escaping () -> Void) {
        self.onYes = onYes
        self.onNo = onNo
    }

    private var dueTodayCount: Int {
        let today = TaskItem.todayString()
        return storage.tasks.filter { !$0.isCompleted && $0.scheduledDate <= today }.count
    }

    public var body: some View {
        ZStack {
            VisualEffectView(material: .hudWindow, blendingMode: .behindWindow)
                .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .stroke(Color.white.opacity(0.18), lineWidth: 1)
                )

            VStack(spacing: 14) {
                HStack(spacing: 8) {
                    FocusCornerLogoBadge(size: 22)
                    Text("FocusCorner Synergy — Kunlik Start")
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                        .foregroundColor(.white.opacity(0.92))
                }

                Text("Bugun yangi tasklar bormi?")
                    .font(.system(size: 20, weight: .heavy, design: .rounded))
                    .foregroundColor(.white)

                HStack(spacing: 12) {
                    Label("SAT: \(storage.satTracker.totalSATScore)/1600", systemImage: "graduationcap.fill")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(.cyan)
                    Label("ExAcc: \(storage.formatPoints(storage.exAcc.totalStandardCharge))", systemImage: "bolt.fill")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(.orange)
                    Label("RPA: \(storage.currentGuNoErrorScore)/20%", systemImage: "shield.lefthalf.filled")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(.green)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(Color.white.opacity(0.07))
                .clipShape(Capsule())

                HStack(spacing: 14) {
                    Button(action: onNo) {
                        Text("Yo'q (Faqat RPA qolsin)")
                            .font(.system(size: 12.5, weight: .semibold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 9)
                            .background(Color.white.opacity(0.1))
                            .foregroundColor(.white.opacity(0.85))
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                    }
                    .buttonStyle(.plain)

                    Button(action: onYes) {
                        Text("Ha (Tasklar & Synergy)")
                            .font(.system(size: 12.5, weight: .bold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 9)
                            .background(
                                LinearGradient(
                                    colors: [Color.cyan, Color.blue],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .foregroundColor(.white)
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                    }
                    .buttonStyle(.plain)
                }
                .padding(.top, 4)
            }
            .padding(22)
        }
        .environment(\.colorScheme, .dark)
    }
}
