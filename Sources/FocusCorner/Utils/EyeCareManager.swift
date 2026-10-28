import Foundation
import AppKit
import SwiftUI
import Combine

public enum EyeBreakKind: String, Codable {
    case micro20s = "MICRO_20S"     // Har 20 daqiqada -> 20 soniya (Uzoqqa qarash + ko'z pirpiratish)
    case macro5m = "MACRO_5M"       // Har 60 daqiqada (3 ta kichik sikldan so'ng) -> 3-5 daqiqa katta tanaffus
}

public struct EyeCareConfig: Codable, Equatable {
    public var isEnabled: Bool
    public var microIntervalMinutes: Int // Default: 20 daqiqa (AOA / Aston University 20-20-20)
    public var microDurationSeconds: Int // Default: 20 soniya (15s, 20s, 30s)
    public var macroEveryNCycles: Int    // Default: 3 sikl (60 daqiqada 1 marta Katta tanaffus)
    public var macroDurationSeconds: Int // Default: 180 soniya (3 daqiqa)

    public init(
        isEnabled: Bool = true,
        microIntervalMinutes: Int = 20,
        microDurationSeconds: Int = 20,
        macroEveryNCycles: Int = 3,
        macroDurationSeconds: Int = 180
    ) {
        self.isEnabled = isEnabled
        self.microIntervalMinutes = max(5, min(60, microIntervalMinutes))
        self.microDurationSeconds = max(10, min(60, microDurationSeconds))
        self.macroEveryNCycles = max(2, min(6, macroEveryNCycles))
        self.macroDurationSeconds = max(60, min(600, macroDurationSeconds))
    }
}

@MainActor
public final class EyeCareManager: ObservableObject {
    public static let shared = EyeCareManager()

    @Published public var config: EyeCareConfig = EyeCareConfig()
    @Published public var isBreakActive: Bool = false
    @Published public var activeBreakKind: EyeBreakKind = .micro20s
    @Published public var breakRemainingSeconds: Int = 20
    @Published public var breakTotalSeconds: Int = 20
    @Published public var secondsUntilNextMicro: Int = 20 * 60
    @Published public var completedMicroCycles: Int = 0
    @Published public var currentExercisePrompt: String = ""
    @Published public var currentExerciseTitle: String = ""

    private let configURL: URL
    private var monitorTimer: Timer?
    private var exerciseIndex: Int = 0

    private let microExercises: [(title: String, prompt: String)] = [
        (
            "👁 Ko'z Dami (20-20-20 Qoidasi)",
            "6 metr uzoqlikka qarang va 10 marta ohista to'liq ko'z yumib-oching"
        ),
        (
            "💧 Ko'z Namligi va Fokus Mashqi",
            "Ko'zni 3 soniya erkin yuming, so'ng deraza yoki uzoq nuqtaga boqing"
        ),
        (
            "✨ Kiprik va Akkomodatsiya Mashqi",
            "Yaqin (30 sm) va uzoq (6 m) nuqtaga navbat bilan 5 marta qarang"
        )
    ]

    private init() {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let baseDir = home.appendingPathComponent(".focus_corner", isDirectory: true)
        self.configURL = baseDir.appendingPathComponent("eyecare_config.json")
        loadConfig()
        resetCountdown()
        startTicker()
    }

    public func loadConfig() {
        if let data = try? Data(contentsOf: configURL),
           let loaded = try? JSONDecoder().decode(EyeCareConfig.self, from: data) {
            self.config = loaded
        } else {
            self.config = EyeCareConfig()
            saveConfig()
        }
    }

    public func saveConfig() {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        if let data = try? encoder.encode(config) {
            try? data.write(to: configURL, options: .atomic)
        }
    }

    public func resetCountdown() {
        secondsUntilNextMicro = config.microIntervalMinutes * 60
    }

    public var nextBreakSummaryText: String {
        guard config.isEnabled else { return "Ko'z himoyasi o'chirilgan" }
        let mins = max(1, (secondsUntilNextMicro + 59) / 60)
        let cyclesLeft = max(1, config.macroEveryNCycles - (completedMicroCycles % config.macroEveryNCycles))
        return "Kichik (\(config.microDurationSeconds)s): \(mins) daq • Katta: \(cyclesLeft) sikldan so'ng"
    }

    public var breakProgressFraction: Double {
        guard breakTotalSeconds > 0 else { return 0 }
        let elapsed = Double(breakTotalSeconds - breakRemainingSeconds)
        return max(0.0, min(1.0, elapsed / Double(breakTotalSeconds)))
    }

    // MARK: - Trigger Micro (20s) or Macro (3-5m) Break Harmlessly

    public func triggerMicroBreakNow() {
        let ex = microExercises[abs(exerciseIndex) % microExercises.count]
        exerciseIndex += 1
        activeBreakKind = .micro20s
        currentExerciseTitle = ex.title
        currentExercisePrompt = ex.prompt
        breakTotalSeconds = config.microDurationSeconds
        breakRemainingSeconds = config.microDurationSeconds
        isBreakActive = true
        NSSound(named: "Tink")?.play()
        WindowController.shared.showEyeCareToastPanel()
    }

    public func triggerMacroBreakNow() {
        activeBreakKind = .macro5m
        currentExerciseTitle = "🌿 Katta Tanaffus Vaqti (60 daqiqa to'ldi!)"
        currentExercisePrompt = "Katta tanaffus qabul qiling: ekrandan uzoqlashing, ko'zni 1 daqiqa yuming va suv iching"
        breakTotalSeconds = config.macroDurationSeconds
        breakRemainingSeconds = config.macroDurationSeconds
        isBreakActive = true
        NSSound(named: "Glass")?.play()
        WindowController.shared.showEyeCareToastPanel()
    }

    public func dismissOrCompleteBreak(completed: Bool = true) {
        isBreakActive = false
        WindowController.shared.hideEyeCareToastPanel()
        resetCountdown()
        if completed {
            NSSound(named: "Pop")?.play()
        }
    }

    public func snoozeBreak(minutes: Int = 5) {
        isBreakActive = false
        WindowController.shared.hideEyeCareToastPanel()
        secondsUntilNextMicro = minutes * 60
    }

    private func startTicker() {
        monitorTimer?.invalidate()
        monitorTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self = self, self.config.isEnabled else { return }
                if self.isBreakActive {
                    if self.breakRemainingSeconds > 1 {
                        self.breakRemainingSeconds -= 1
                    } else {
                        self.dismissOrCompleteBreak(completed: true)
                    }
                } else {
                    if self.secondsUntilNextMicro > 1 {
                        self.secondsUntilNextMicro -= 1
                    } else {
                        self.completedMicroCycles += 1
                        if self.completedMicroCycles % self.config.macroEveryNCycles == 0 {
                            self.triggerMacroBreakNow()
                        } else {
                            self.triggerMicroBreakNow()
                        }
                    }
                }
            }
        }
    }
}

// MARK: - Harmless Non-Intrusive Floating EyeCare Banner View

public struct EyeCareBannerHUDView: View {
    @ObservedObject private var eyeCare = EyeCareManager.shared

    public init() {}

    private var accent: Color {
        eyeCare.activeBreakKind == .macro5m
            ? Color(red: 0.98, green: 0.76, blue: 0.28) // Warm Gold for Macro Break
            : Color(red: 0.24, green: 0.86, blue: 0.64) // Soothing Mint Emerald for 20s Eye Break
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Image(systemName: eyeCare.activeBreakKind == .macro5m ? "figure.walk" : "eye.fill")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundColor(accent)

                VStack(alignment: .leading, spacing: 1.5) {
                    Text(eyeCare.currentExerciseTitle)
                        .font(.system(size: 11.5, weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                    Text(eyeCare.currentExercisePrompt)
                        .font(.system(size: 10.5, weight: .regular))
                        .foregroundColor(.white.opacity(0.82))
                        .lineLimit(2)
                }

                Spacer(minLength: 4)

                // Countdown Badge
                Text(eyeCare.activeBreakKind == .macro5m
                     ? String(format: "%d:%02d", eyeCare.breakRemainingSeconds / 60, eyeCare.breakRemainingSeconds % 60)
                     : "\(eyeCare.breakRemainingSeconds)s")
                    .font(.system(size: 16, weight: .heavy, design: .monospaced))
                    .foregroundColor(accent)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(accent.opacity(0.16))
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

                // Quick Dismiss / Snooze Icons
                Button(action: { eyeCare.snoozeBreak(minutes: 5) }) {
                    Text("+5m")
                        .font(.system(size: 9.5, weight: .semibold))
                        .foregroundColor(.white.opacity(0.65))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 4)
                        .background(Color.white.opacity(0.08))
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)
                .help("5 daqiqaga kechiktirish")

                Button(action: { eyeCare.dismissOrCompleteBreak(completed: true) }) {
                    Image(systemName: "checkmark")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(accent)
                        .frame(width: 22, height: 22)
                        .background(accent.opacity(0.18))
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
                .help("Bajarildi / Yopish")
            }

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.white.opacity(0.08))
                        .frame(height: 3)
                    Capsule()
                        .fill(accent)
                        .frame(width: max(6, geo.size.width * eyeCare.breakProgressFraction), height: 3)
                }
            }
            .frame(height: 3)
        }
        .padding(.horizontal, 13)
        .padding(.vertical, 9)
        .frame(maxWidth: .infinity)
        .background(
            ZStack {
                VisualEffectView(material: .hudWindow, blendingMode: .behindWindow)
                Color(red: 0.06, green: 0.09, blue: 0.11).opacity(0.94)
            }
        )
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(accent.opacity(0.45), lineWidth: 1.2)
        )
        .environment(\.colorScheme, .dark)
    }
}
