import SwiftUI
import AppKit

/// Compact Detachable Floating 3-Day RPA Matrix HUD
public struct RulesView: View {
    @ObservedObject private var storage = StorageManager.shared
    @ObservedObject private var windowController = WindowController.shared

    @State private var newRuleText: String = ""
    @State private var editingRuleId: UUID? = nil
    @State private var editingRuleText: String = ""
    @FocusState private var isInputFocused: Bool

    public init() {}

    public var body: some View {
        let dayCols = storage.rpaThreeDayColumns
        let noErr = storage.currentGuNoErrorScore
        let todayX = storage.todayRPAXCount

        return ZStack(alignment: .topLeading) {
            ZStack {
                VisualEffectView(material: .hudWindow, blendingMode: .behindWindow)
                Color(red: 0.08, green: 0.09, blue: 0.12).opacity(0.93)
            }
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(Color.white.opacity(0.12), lineWidth: 1)
            )

            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 7) {
                    FocusCornerLogoBadge(size: 17)

                    Text("RPA Jadvali")
                        .font(.system(size: 12, weight: .bold, design: .rounded))
                        .foregroundColor(.white.opacity(0.95))

                    Text("• Gu No-Error \(noErr)/20%")
                        .font(.system(size: 10.5, weight: .semibold, design: .rounded))
                        .foregroundColor(todayX == 0 ? Color(red: 0.24, green: 0.86, blue: 0.64) : Color(red: 0.98, green: 0.42, blue: 0.42))

                    Spacer()

                    Button(action: { windowController.hideRulesPanel() }) {
                        Image(systemName: "xmark")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundColor(.white.opacity(0.5))
                    }
                    .buttonStyle(.plain)
                }

                // 3-Day Column Headers
                HStack(spacing: 5) {
                    Text("TAQIQLANGAN ODAT")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundColor(.white.opacity(0.50))
                        .frame(maxWidth: .infinity, alignment: .leading)

                    ForEach(dayCols) { col in
                        VStack(spacing: 0.5) {
                            Text(col.title)
                                .font(.system(size: 9, weight: .bold))
                                .foregroundColor(col.isToday ? .cyan : .white.opacity(0.70))
                            Text(col.shortDate)
                                .font(.system(size: 8, design: .monospaced))
                                .foregroundColor(.white.opacity(0.45))
                        }
                        .frame(width: 52)
                    }
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color.white.opacity(0.04))
                .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))

                ScrollView(.vertical, showsIndicators: false) {
                    LazyVStack(alignment: .leading, spacing: 5) {
                        ForEach(storage.rules) { rule in
                            HStack(alignment: .center, spacing: 5) {
                                if editingRuleId == rule.id {
                                    TextField("Odat...", text: $editingRuleText, onCommit: {
                                        storage.updateRule(rule, newTitle: editingRuleText, newType: rule.ruleType)
                                        editingRuleId = nil
                                    })
                                    .textFieldStyle(.plain)
                                    .font(.system(size: 11))
                                    .foregroundColor(.white)
                                } else {
                                    Text(rule.title)
                                        .font(.system(size: 11, weight: .medium))
                                        .foregroundColor(.white.opacity(0.90))
                                        .lineLimit(2)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        .onTapGesture {
                                            windowController.rulesPanel?.focusForTextInput()
                                            editingRuleId = rule.id
                                            editingRuleText = rule.title
                                        }
                                }

                                ForEach(dayCols) { col in
                                    let marked = rule.isMarkedX(on: col.dateString)
                                    Button(action: {
                                        storage.toggleRPAMarkX(rule, on: col.dateString)
                                    }) {
                                        Text(marked ? "X" : "—")
                                            .font(.system(size: marked ? 11.5 : 10, weight: marked ? .heavy : .regular, design: .rounded))
                                            .foregroundColor(marked ? Color(red: 1.0, green: 0.38, blue: 0.40) : .white.opacity(0.28))
                                            .frame(width: 52, height: 26)
                                            .background(marked ? Color.red.opacity(0.24) : Color.white.opacity(0.04))
                                            .overlay(
                                                RoundedRectangle(cornerRadius: 6, style: .continuous)
                                                    .stroke(marked ? Color.red.opacity(0.75) : Color.white.opacity(0.07), lineWidth: 1)
                                            )
                                            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                            .padding(.horizontal, 8)
                            .padding(.vertical, 5)
                            .background(Color.white.opacity(0.04))
                            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                        }
                    }
                }
            }
            .padding(12)
        }
        .environment(\.colorScheme, .dark)
    }
}
