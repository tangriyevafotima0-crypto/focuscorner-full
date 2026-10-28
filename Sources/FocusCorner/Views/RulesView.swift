import SwiftUI
import AppKit

public struct RulesView: View {
    @ObservedObject private var storage = StorageManager.shared
    @ObservedObject private var windowController = WindowController.shared

    @State private var newRuleText: String = ""
    @State private var editingRuleId: UUID? = nil
    @State private var editingRuleText: String = ""
    @FocusState private var isInputFocused: Bool

    public init() {}

    public var body: some View {
        ZStack(alignment: .bottomTrailing) {
            ZStack {
                VisualEffectView(material: .hudWindow, blendingMode: .behindWindow)
                Color(red: 0.08, green: 0.09, blue: 0.12).opacity(0.92)
            }
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(Color.white.opacity(0.12), lineWidth: 1)
            )

            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 6) {
                    Circle()
                        .fill(Color(red: 0.30, green: 0.66, blue: 1.00))
                        .frame(width: 7, height: 7)

                    Text("Eslatmalar")
                        .font(.system(size: 12, weight: .bold, design: .rounded))
                        .foregroundColor(.white.opacity(0.92))

                    Spacer()

                    Button(action: { windowController.hideRulesPanel() }) {
                        Image(systemName: "xmark")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundColor(.white.opacity(0.5))
                    }
                    .buttonStyle(.plain)
                }

                HStack(spacing: 6) {
                    TextField("Yangi eslatma yozing...", text: $newRuleText, onCommit: submitNewRule)
                        .textFieldStyle(.plain)
                        .focused($isInputFocused)
                        .font(.system(size: 11.5))
                        .foregroundColor(.white)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 5)
                        .background(Color.white.opacity(0.07))
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                        .onTapGesture {
                            windowController.rulesPanel?.focusForTextInput()
                            isInputFocused = true
                        }

                    if !newRuleText.isEmpty {
                        Button(action: submitNewRule) {
                            Image(systemName: "arrow.up.circle.fill")
                                .font(.system(size: 16))
                                .foregroundColor(Color(red: 0.30, green: 0.66, blue: 1.00))
                        }
                        .buttonStyle(.plain)
                    }
                }

                ScrollView(.vertical, showsIndicators: false) {
                    LazyVStack(alignment: .leading, spacing: 5) {
                        ForEach(storage.rules) { rule in
                            HStack(alignment: .center, spacing: 8) {
                                Circle()
                                    .fill(Color.white.opacity(0.35))
                                    .frame(width: 5, height: 5)

                                if editingRuleId == rule.id {
                                    TextField("Eslatma...", text: $editingRuleText, onCommit: {
                                        storage.updateRule(rule, newTitle: editingRuleText, newType: rule.ruleType)
                                        editingRuleId = nil
                                    })
                                    .textFieldStyle(.plain)
                                    .font(.system(size: 11.5))
                                    .foregroundColor(.white)
                                } else {
                                    Text(rule.title)
                                        .font(.system(size: 11.5, weight: .regular))
                                        .foregroundColor(.white.opacity(0.88))
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        .onTapGesture {
                                            windowController.rulesPanel?.focusForTextInput()
                                            editingRuleId = rule.id
                                            editingRuleText = rule.title
                                        }
                                }

                                Button(action: { storage.deleteRuleForce(rule) }) {
                                    Image(systemName: "xmark")
                                        .font(.system(size: 9))
                                        .foregroundColor(.white.opacity(0.3))
                                }
                                .buttonStyle(.plain)
                            }
                            .padding(.horizontal, 9)
                            .padding(.vertical, 6)
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

    private func submitNewRule() {
        let trimmed = newRuleText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        storage.addRule(title: trimmed, type: .doRule, isLocked: false)
        newRuleText = ""
    }
}
