import SwiftUI
import AppKit

public struct FocusTimerHUDView: View {
    @ObservedObject private var timerManager = FocusTimerManager.shared
    @ObservedObject private var storage = StorageManager.shared
    @ObservedObject private var windowController = WindowController.shared

    public init() {}

    private var themeAccent: Color {
        if timerManager.isPaused {
            return Color(red: 0.96, green: 0.78, blue: 0.32)
        }
        return timerManager.isBreakPhase
            ? Color(red: 0.24, green: 0.84, blue: 0.58) // Calm Mint Green for Break
            : Color(red: 0.32, green: 0.68, blue: 1.00) // Smooth Azure Blue for Focus
    }

    public var body: some View {
        Group {
            if timerManager.isCompactPill {
                ultraCompactPillView
            } else {
                standardZenHUDView
            }
        }
        .environment(\.colorScheme, .dark)
    }

    private var ultraCompactPillView: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(themeAccent)
                .frame(width: 7, height: 7)

            Text(timerManager.formattedTime)
                .font(.system(size: 15.5, weight: .bold, design: .monospaced))
                .foregroundColor(.white)

            if timerManager.config.mode == .exam {
                Text("\(timerManager.currentPartIndex + 1)/\(timerManager.config.examParts.count)")
                    .font(.system(size: 9.5, weight: .semibold, design: .monospaced))
                    .foregroundColor(themeAccent)
            }

            Spacer(minLength: 2)

            Button(action: { timerManager.togglePause() }) {
                Image(systemName: timerManager.isPaused ? "play.fill" : "pause.fill")
                    .font(.system(size: 10.5, weight: .bold))
                    .foregroundColor(.white.opacity(0.9))
                    .frame(width: 22, height: 22)
                    .background(Color.white.opacity(0.10))
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)

            Button(action: { windowController.setTimerCompactPill(false) }) {
                Image(systemName: "arrow.up.left.and.arrow.down.right")
                    .font(.system(size: 9.5, weight: .semibold))
                    .foregroundColor(.white.opacity(0.75))
                    .frame(width: 22, height: 22)
                    .background(Color.white.opacity(0.08))
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)

            Button(action: { timerManager.stopTimer(completedNaturally: false) }) {
                Image(systemName: "xmark")
                    .font(.system(size: 9.5, weight: .bold))
                    .foregroundColor(.white.opacity(0.75))
                    .frame(width: 22, height: 22)
                    .background(Color.white.opacity(0.08))
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            ZStack {
                VisualEffectView(material: .hudWindow, blendingMode: .behindWindow)
                Color(red: 0.08, green: 0.09, blue: 0.12).opacity(0.92)
            }
        )
        .clipShape(Capsule())
        .overlay(
            Capsule()
                .stroke(Color.white.opacity(0.14), lineWidth: 1)
        )
    }

    private var standardZenHUDView: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Top subtle status row
            HStack(spacing: 6) {
                Circle()
                    .fill(themeAccent)
                    .frame(width: 6.5, height: 6.5)

                Text(timerManager.currentHeaderBadge)
                    .font(.system(size: 10, weight: .semibold, design: .rounded))
                    .foregroundColor(themeAccent)

                Spacer()

                Button(action: { windowController.setTimerCompactPill(true) }) {
                    Text("Mini")
                        .font(.system(size: 9.5, weight: .medium))
                        .foregroundColor(.white.opacity(0.6))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.white.opacity(0.07))
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)
                .help("Kichik kapsulaga yig'ish")
            }

            // Main Countdown + Smooth Controls
            HStack(alignment: .center, spacing: 10) {
                Text(timerManager.formattedTime)
                    .font(.system(size: 29, weight: .bold, design: .monospaced))
                    .foregroundColor(.white)
                    .minimumScaleFactor(0.75)
                    .lineLimit(1)

                Spacer(minLength: 4)

                HStack(spacing: 5) {
                    Button(action: { timerManager.togglePause() }) {
                        HStack(spacing: 4) {
                            Image(systemName: timerManager.isPaused ? "play.fill" : "pause.fill")
                                .font(.system(size: 10, weight: .bold))
                            Text(timerManager.isPaused ? "Davom" : "Pauza")
                                .font(.system(size: 10.5, weight: .semibold))
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(themeAccent.opacity(0.22))
                        .foregroundColor(themeAccent)
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    }
                    .buttonStyle(.plain)

                    Button(action: { timerManager.addMinutes(5) }) {
                        Text("+5m")
                            .font(.system(size: 10, weight: .semibold, design: .monospaced))
                            .padding(.horizontal, 7)
                            .padding(.vertical, 6)
                            .background(Color.white.opacity(0.08))
                            .foregroundColor(.white.opacity(0.85))
                            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    }
                    .buttonStyle(.plain)

                    if timerManager.config.mode == .exam {
                        Button(action: { timerManager.skipToNextPart() }) {
                            Image(systemName: "forward.end.fill")
                                .font(.system(size: 10, weight: .semibold))
                                .padding(.horizontal, 7)
                                .padding(.vertical, 6)
                                .background(Color.white.opacity(0.08))
                                .foregroundColor(.white.opacity(0.85))
                                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                        }
                        .buttonStyle(.plain)
                        .help("Keyingi qismga o'tish")
                    }

                    if timerManager.activeTaskId != nil {
                        Button(action: { timerManager.stopTimer(completedNaturally: true, markLinkedTaskDone: true) }) {
                            Image(systemName: "checkmark")
                                .font(.system(size: 10, weight: .bold))
                                .padding(.horizontal, 7)
                                .padding(.vertical, 6)
                                .background(Color.green.opacity(0.22))
                                .foregroundColor(.green)
                                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                        }
                        .buttonStyle(.plain)
                        .help("Vazifani bajarildi deb belgilash")
                    }

                    Button(action: { timerManager.stopTimer(completedNaturally: false) }) {
                        Image(systemName: "xmark")
                            .font(.system(size: 10, weight: .bold))
                            .padding(.horizontal, 7)
                            .padding(.vertical, 6)
                            .background(Color.white.opacity(0.08))
                            .foregroundColor(.white.opacity(0.75))
                            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .help("Timerni yopish va vazifalarga qaytish")
                }
            }

            // Progress bar & quiet 1-line subtitle
            VStack(alignment: .leading, spacing: 5) {
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule()
                            .fill(Color.white.opacity(0.08))
                            .frame(height: 3.5)
                        Capsule()
                            .fill(themeAccent)
                            .frame(width: max(6, geo.size.width * timerManager.progressFraction), height: 3.5)
                    }
                }
                .frame(height: 3.5)

                HStack(spacing: 6) {
                    Text(timerManager.currentDisplaySubtitle)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(.white.opacity(0.75))
                        .lineLimit(1)

                    Spacer()

                    Button(action: { timerManager.cycleRPAReminder() }) {
                        Text(timerManager.activeRPAReminderText)
                            .font(.system(size: 9.5, weight: .regular))
                            .foregroundColor(.white.opacity(0.5))
                            .lineLimit(1)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            ZStack {
                VisualEffectView(material: .hudWindow, blendingMode: .behindWindow)
                Color(red: 0.08, green: 0.09, blue: 0.12).opacity(0.93)
            }
        )
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color.white.opacity(0.12), lineWidth: 1)
        )
    }
}
