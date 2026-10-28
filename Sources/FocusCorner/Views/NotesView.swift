import SwiftUI
import AppKit

public enum CalmMainTab: String, CaseIterable, Identifiable {
    case tasks = "Vazifalar"
    case notebook = "Bloknot"
    case terminal = "Terminal"
    case timer = "Timer"
    case rulesAndBalance = "Eslatmalar"

    public var id: String { rawValue }

    public var iconName: String {
        switch self {
        case .tasks: return "checklist"
        case .notebook: return "book.pages.fill"
        case .terminal: return "terminal.fill"
        case .timer: return "timer"
        case .rulesAndBalance: return "sparkles"
        }
    }
}

public struct NotesView: View {
    @ObservedObject private var storage = StorageManager.shared
    @ObservedObject private var windowController = WindowController.shared
    @ObservedObject private var timerManager = FocusTimerManager.shared
    @ObservedObject private var devManager = DevChannelManager.shared
    @ObservedObject private var eyeCare = EyeCareManager.shared

    @State private var activeTab: CalmMainTab = .tasks
    // Hidden by default so user ONLY sees Today's tasks unless they click to expand!
    @State private var showUpcomingMultiDaySection: Bool = false
    @State private var showCompletedSection: Bool = false
    @State private var showQuickSettingsPopover: Bool = false
    @State private var showEyeCarePopover: Bool = false

    // Effortless Task Input State
    @State private var newTaskTitle: String = ""
    @State private var newTaskDurationDays: Int = 1
    @State private var editingTaskId: UUID? = nil
    @State private var editingTaskTitle: String = ""
    @FocusState private var isTaskInputFocused: Bool

    // Effortless RPA Rule Input State
    @State private var newRuleText: String = ""
    @State private var editingRuleId: UUID? = nil
    @State private var editingRuleText: String = ""
    @FocusState private var isRuleInputFocused: Bool

    public init() {}

    /// Faqat bugungi (1 kunlik / 1 kun qolgan) va muddati o'tgan vazifalar — har doim asosiy ro'yxatda ko'rinadi
    private var todayFocusTasks: [TaskItem] {
        storage.tasks.filter { !$0.isCompleted && $0.remainingDays <= 1 }
    }

    /// 2-3 kunlik (Havorang) va 4+ kunlik (Ko'kish oq) vazifalar — foydalanuvchi ochmaguncha yopiq turadi
    private var upcomingMultiDayTasks: [TaskItem] {
        storage.tasks.filter { !$0.isCompleted && $0.remainingDays >= 2 }
    }

    /// Bajarilgan (Yashil) vazifalar — alohida yig'iladigan bo'limda turadi
    private var completedTasks: [TaskItem] {
        storage.tasks.filter { $0.isCompleted }
    }

    public var body: some View {
        ZStack(alignment: .bottomTrailing) {
            ZStack {
                VisualEffectView(material: .hudWindow, blendingMode: .behindWindow)
                Color(red: 0.08, green: 0.09, blue: 0.12).opacity(0.93)
            }
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(Color.white.opacity(0.11), lineWidth: 1)
            )

            VStack(alignment: .leading, spacing: 9) {
                topHeaderBar

                if eyeCare.isBreakActive {
                    EyeCareBannerHUDView()
                }

                if let toast = storage.toastBanner {
                    toastBannerView(toast)
                }

                if !storage.settings.isNotesCollapsed {
                    integratedRPAReminderBar

                    mainTabSelectorBar

                    Group {
                        switch activeTab {
                        case .tasks:
                            calmTasksTabContent
                        case .notebook:
                            NotebookTabView()
                        case .terminal:
                            TerminalTabView()
                        case .timer:
                            calmTimerTabContent
                        case .rulesAndBalance:
                            calmRulesAndBalanceTabContent
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)

            if !storage.settings.isNotesCollapsed {
                ResizeGripHandle { delta in
                    windowController.resizeNotesPanel(byDelta: delta)
                }
            }
        }
        .environment(\.colorScheme, .dark)
        .onChange(of: windowController.requestedMainTab) { _, newTab in
            if let tab = newTab {
                withAnimation(.easeInOut(duration: 0.15)) {
                    activeTab = tab
                }
                windowController.requestedMainTab = nil
            }
        }
    }

    // MARK: - Icon-Driven Calm Top Header Bar

    private var topHeaderBar: some View {
        HStack(spacing: 7) {
            Circle()
                .fill(Color(red: 0.30, green: 0.66, blue: 1.00))
                .frame(width: 8, height: 8)

            Text("FocusCorner")
                .font(.system(size: 13, weight: .bold, design: .rounded))
                .foregroundColor(.white.opacity(0.95))

            Text("• SAT \(storage.satTracker.totalSATScore) • ExAcc \(storage.formatPoints(storage.exAcc.totalStandardCharge))")
                .font(.system(size: 10.5, weight: .medium, design: .rounded))
                .foregroundColor(.white.opacity(0.48))
                .lineLimit(1)

            Spacer()

            // 1. EyeCare 20-20-20 & Macro Break Icon (👁)
            Button(action: {
                showEyeCarePopover.toggle()
            }) {
                Image(systemName: eyeCare.config.isEnabled ? "eye.fill" : "eye.slash")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(
                        eyeCare.isBreakActive
                            ? .green
                            : (eyeCare.config.isEnabled ? Color(red: 0.24, green: 0.86, blue: 0.64) : .white.opacity(0.45))
                    )
                    .frame(width: 24, height: 24)
                    .background(Color.white.opacity(0.06))
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
            .help("Ko'z himoyasi (20-20-20 qoidasi va Katta tanaffus)")
            .popover(isPresented: $showEyeCarePopover, arrowEdge: .bottom) {
                eyeCareControlPopover
            }

            // 2. Bloknot Quick Icon (⌥ + Space)
            headerCircleIconButton(
                icon: "book.pages.fill",
                tint: activeTab == .notebook ? Color(red: 0.98, green: 0.78, blue: 0.28) : .white.opacity(0.70),
                help: "Bloknotni ochish (Tezkor tugma: ⌥ + Space yoki ⌘⇧B)"
            ) {
                withAnimation(.easeInOut(duration: 0.15)) {
                    activeTab = .notebook
                }
            }

            // 2B. Built-in Terminal & Backup Quick Icon (⌘⇧K)
            headerCircleIconButton(
                icon: "terminal.fill",
                tint: activeTab == .terminal ? Color(red: 0.30, green: 0.66, blue: 1.00) : .white.opacity(0.70),
                help: "Ichki Terminal va Backup markazini ochish (⌘⇧K)"
            ) {
                withAnimation(.easeInOut(duration: 0.15)) {
                    activeTab = .terminal
                }
            }

            // 3. Start Focus Timer Icon (⌘⇧T)
            headerCircleIconButton(
                icon: "play.fill",
                tint: Color(red: 0.42, green: 0.74, blue: 1.00),
                help: "Fokus Timerni boshlash (⌘⇧T)"
            ) {
                if timerManager.isActive {
                    windowController.enterZenTimerMode()
                } else if timerManager.config.mode == .exam {
                    timerManager.startExam()
                } else {
                    timerManager.startSingular()
                }
            }

            // 4. Copy Gemini Report Icon
            headerCircleIconButton(
                icon: "doc.on.clipboard",
                tint: .white.opacity(0.70),
                help: "Hisobotni buferga nusxalash"
            ) {
                _ = storage.copyGeminiSyncReportToClipboard()
            }

            // 5. Compact Settings & RAM Monitor Icon (⚙️)
            Button(action: {
                devManager.refreshMemoryUsage()
                showQuickSettingsPopover.toggle()
            }) {
                Image(systemName: "gearshape")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.white.opacity(0.68))
                    .frame(width: 24, height: 24)
                    .background(Color.white.opacity(0.06))
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
            .help("Sozlamalar va RAM xotira nazorati")
            .popover(isPresented: $showQuickSettingsPopover, arrowEdge: .bottom) {
                compactSettingsAndRAMPopover
            }

            // 6. Collapse / Expand Window Icon
            headerCircleIconButton(
                icon: storage.settings.isNotesCollapsed ? "chevron.down" : "chevron.up",
                tint: .white.opacity(0.68),
                help: storage.settings.isNotesCollapsed ? "Kengaytirish" : "Mini-bar holatiga yig'ish"
            ) {
                windowController.toggleNotesCollapsed()
            }
        }
    }

    private func headerCircleIconButton(
        icon: String,
        tint: Color,
        help: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(tint)
                .frame(width: 24, height: 24)
                .background(Color.white.opacity(0.06))
                .clipShape(Circle())
        }
        .buttonStyle(.plain)
        .help(help)
    }

    // MARK: - EyeCare 20-20-20 & Macro-Break Control Popover

    private var eyeCareControlPopover: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack {
                Image(systemName: "eye.fill")
                    .foregroundColor(Color(red: 0.24, green: 0.86, blue: 0.64))
                Text("Ko'z Salomatligi (20-20-20)")
                    .font(.system(size: 11.5, weight: .bold))
                    .foregroundColor(.white)
                Spacer()
                Toggle("", isOn: Binding(
                    get: { eyeCare.config.isEnabled },
                    set: { val in
                        eyeCare.config.isEnabled = val
                        eyeCare.saveConfig()
                    }
                ))
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.small)
            }

            Text(eyeCare.nextBreakSummaryText)
                .font(.system(size: 10, weight: .medium, design: .monospaced))
                .foregroundColor(Color(red: 0.24, green: 0.86, blue: 0.64))

            HStack(spacing: 5) {
                Text("Kichik dam:")
                    .font(.system(size: 10))
                    .foregroundColor(.white.opacity(0.65))
                ForEach([15, 20, 30], id: \.self) { secs in
                    let isSel = (eyeCare.config.microDurationSeconds == secs)
                    Button("\(secs)s") {
                        eyeCare.config.microDurationSeconds = secs
                        eyeCare.saveConfig()
                    }
                    .buttonStyle(.plain)
                    .font(.system(size: 9.5, weight: isSel ? .bold : .regular, design: .monospaced))
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(isSel ? Color(red: 0.24, green: 0.86, blue: 0.64).opacity(0.24) : Color.white.opacity(0.07))
                    .foregroundColor(isSel ? Color(red: 0.24, green: 0.86, blue: 0.64) : .white.opacity(0.75))
                    .clipShape(Capsule())
                }
                Spacer()
            }

            HStack(spacing: 6) {
                Button(action: {
                    showEyeCarePopover = false
                    eyeCare.triggerMicroBreakNow()
                }) {
                    HStack(spacing: 4) {
                        Image(systemName: "eye")
                        Text("\(eyeCare.config.microDurationSeconds)s Ko'z Mashqi")
                    }
                    .font(.system(size: 10, weight: .semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
                    .background(Color(red: 0.24, green: 0.86, blue: 0.64).opacity(0.20))
                    .foregroundColor(Color(red: 0.24, green: 0.86, blue: 0.64))
                    .clipShape(RoundedRectangle(cornerRadius: 7))
                }
                .buttonStyle(.plain)

                Button(action: {
                    showEyeCarePopover = false
                    eyeCare.triggerMacroBreakNow()
                }) {
                    HStack(spacing: 4) {
                        Image(systemName: "figure.walk")
                        Text("Katta Tanaffus")
                    }
                    .font(.system(size: 10, weight: .semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
                    .background(Color(red: 0.98, green: 0.76, blue: 0.28).opacity(0.20))
                    .foregroundColor(Color(red: 0.98, green: 0.76, blue: 0.28))
                    .clipShape(RoundedRectangle(cornerRadius: 7))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(12)
        .frame(width: 265)
        .environment(\.colorScheme, .dark)
    }

    // MARK: - Subtle Settings & Tiny RAM Indicator Popover

    private var compactSettingsAndRAMPopover: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 6) {
                Image(systemName: "memorychip")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.green)
                Text(String(format: "RAM bosimi: %.1f MB", devManager.memoryFootprintMB))
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    .foregroundColor(.white)
                Spacer()
                Button(action: {
                    devManager.silentMemoryTrim()
                }) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(.cyan)
                        .frame(width: 20, height: 20)
                        .background(Color.white.opacity(0.08))
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
                .help("Keshni darhol tozalash (Avto-tozalash har 30 soniyada ishlaydi)")
            }

            Divider().overlay(Color.white.opacity(0.1))

            HStack(spacing: 8) {
                Image(systemName: "sun.max")
                    .font(.system(size: 10.5))
                    .foregroundColor(.white.opacity(0.65))
                Slider(
                    value: Binding(
                        get: { storage.settings.notesOpacity },
                        set: { val in
                            storage.settings.notesOpacity = val
                            storage.settings.rulesOpacity = val
                            storage.saveSettings()
                            windowController.applyWindowLayerAndOpacitySettings()
                        }
                    ),
                    in: 0.40...1.0
                )
                Text("\(Int(storage.settings.notesOpacity * 100))%")
                    .font(.system(size: 9.5, design: .monospaced))
                    .foregroundColor(.white.opacity(0.6))
                    .frame(width: 28, alignment: .trailing)
            }

            HStack {
                Text("Bloknot chaqirish:")
                    .font(.system(size: 10))
                    .foregroundColor(.white.opacity(0.6))
                Spacer()
                Text("⌥ + Space")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.white.opacity(0.08))
                    .clipShape(RoundedRectangle(cornerRadius: 4))
            }
        }
        .padding(12)
        .frame(width: 235)
        .environment(\.colorScheme, .dark)
    }

    // MARK: - Quiet 1-Line Integrated RPA Strip

    private var integratedRPAReminderBar: some View {
        HStack(spacing: 6) {
            Text(timerManager.activeRPAReminderText)
                .font(.system(size: 10.5, weight: .regular))
                .foregroundColor(.white.opacity(0.62))
                .lineLimit(1)
                .onTapGesture {
                    timerManager.cycleRPAReminder()
                }

            Spacer()

            Button(action: {
                withAnimation(.easeInOut(duration: 0.15)) {
                    activeTab = .rulesAndBalance
                }
            }) {
                Image(systemName: "slider.horizontal.3")
                    .font(.system(size: 9.5))
                    .foregroundColor(.white.opacity(0.42))
            }
            .buttonStyle(.plain)
            .help("Eslatmalarni tahrirlash")
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(Color.white.opacity(0.035))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private func toastBannerView(_ text: String) -> some View {
        HStack(spacing: 6) {
            Text(text)
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(.white)
                .lineLimit(2)
            Spacer()
            Button(action: { storage.toastBanner = nil }) {
                Image(systemName: "xmark")
                    .font(.system(size: 9.5))
                    .foregroundColor(.white.opacity(0.6))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Color(red: 0.20, green: 0.48, blue: 0.85).opacity(0.35))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    // MARK: - Clean 4-Tab Bar

    private var mainTabSelectorBar: some View {
        HStack(spacing: 4) {
            ForEach(CalmMainTab.allCases) { tab in
                let isSelected = (activeTab == tab)
                Button(action: {
                    if activeTab == .notebook && tab != .notebook {
                        NotebookManager.shared.flushPendingSaveImmediately()
                    }
                    withAnimation(.easeInOut(duration: 0.15)) {
                        activeTab = tab
                    }
                }) {
                    HStack(spacing: 4) {
                        Image(systemName: tab.iconName)
                            .font(.system(size: 10, weight: .semibold))
                        Text(tab.rawValue)
                            .font(.system(size: 10.5, weight: isSelected ? .semibold : .regular))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 5.5)
                    .background(isSelected ? Color.white.opacity(0.12) : Color.clear)
                    .foregroundColor(isSelected ? .white : .white.opacity(0.55))
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(3)
        .background(Color.white.opacity(0.04))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    // =========================================================================
    // MARK: - TAB 1: Today-First Tasks View (2-3+ Day Tasks Hidden in Collapsible Category!)
    // =========================================================================

    private var calmTasksTabContent: some View {
        VStack(alignment: .leading, spacing: 9) {
            // 1. Instant-Focus Single-Line Task Input Bar
            HStack(spacing: 8) {
                Image(systemName: "plus")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(previewVisualState(for: newTaskDurationDays).accentColor)

                TextField("Yangi vazifa yozing va Enter bosing...", text: $newTaskTitle, onCommit: submitNewTask)
                    .textFieldStyle(.plain)
                    .focused($isTaskInputFocused)
                    .font(.system(size: 12.5))
                    .foregroundColor(.white)

                Menu {
                    Button("🔵 Bugun (Ochiq ko'k)") { newTaskDurationDays = 1 }
                    Button("🩵 2 kun (Havorang — Keyingi kunlar bo'limiga)") { newTaskDurationDays = 2 }
                    Button("🩵 3 kun (Havorang — Keyingi kunlar bo'limiga)") { newTaskDurationDays = 3 }
                    Button("❄️ 5 kun (Ko'kish oq — Keyingi kunlar bo'limiga)") { newTaskDurationDays = 5 }
                    Button("❄️ 7 kun (Ko'kish oq — Keyingi kunlar bo'limiga)") { newTaskDurationDays = 7 }
                    Button("❄️ 14 kun (Ko'kish oq — Keyingi kunlar bo'limiga)") { newTaskDurationDays = 14 }
                } label: {
                    HStack(spacing: 4) {
                        Circle()
                            .fill(previewVisualState(for: newTaskDurationDays).accentColor)
                            .frame(width: 6, height: 6)
                        Text(newTaskDurationDays == 1 ? "Bugun" : "\(newTaskDurationDays) kun")
                            .font(.system(size: 10.5, weight: .semibold))
                            .foregroundColor(previewVisualState(for: newTaskDurationDays).accentColor)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(previewVisualState(for: newTaskDurationDays).accentColor.opacity(0.14))
                    .clipShape(Capsule())
                }
                .menuStyle(.borderlessButton)
                .fixedSize()

                if !newTaskTitle.isEmpty {
                    Button(action: submitNewTask) {
                        Image(systemName: "arrow.up.circle.fill")
                            .font(.system(size: 16))
                            .foregroundColor(previewVisualState(for: newTaskDurationDays).accentColor)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 11)
            .padding(.vertical, 8)
            .background(Color.white.opacity(0.06))
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(isTaskInputFocused ? Color(red: 0.30, green: 0.66, blue: 1.00).opacity(0.45) : Color.white.opacity(0.08), lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .contentShape(Rectangle())
            .onTapGesture {
                windowController.notesPanel?.focusForTextInput()
                isTaskInputFocused = true
            }

            // 2. Tasks ScrollView: ONLY Today's tasks shown upfront!
            // 2-3+ day tasks & Completed tasks live in clean collapsible categories below!
            ScrollView(.vertical, showsIndicators: false) {
                LazyVStack(alignment: .leading, spacing: 6) {
                    // Section A: Today's Tasks (Always Visible)
                    if todayFocusTasks.isEmpty {
                        HStack(spacing: 6) {
                            Image(systemName: "checkmark.seal.fill")
                                .font(.system(size: 12))
                                .foregroundColor(Color(red: 0.30, green: 0.66, blue: 1.00))
                            Text("Bugungi barcha vazifalar bajarilgan!")
                                .font(.system(size: 11.5, weight: .medium))
                                .foregroundColor(.white.opacity(0.65))
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.white.opacity(0.035))
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    } else {
                        ForEach(todayFocusTasks) { task in
                            calmTaskRow(task)
                        }
                    }

                    // Section B: 2-3+ Day Upcoming Tasks (Collapsed by Default until user wants to see them!)
                    if !upcomingMultiDayTasks.isEmpty {
                        VStack(alignment: .leading, spacing: 6) {
                            Button(action: {
                                withAnimation(.easeInOut(duration: 0.16)) {
                                    showUpcomingMultiDaySection.toggle()
                                }
                            }) {
                                HStack(spacing: 6) {
                                    Image(systemName: showUpcomingMultiDaySection ? "chevron.down" : "chevron.right")
                                        .font(.system(size: 9, weight: .bold))
                                        .foregroundColor(TaskVisualState.threeDaysSkyCyan.accentColor)
                                    Text("Keyingi kunlar (2–3+ kunlik)")
                                        .font(.system(size: 10.5, weight: .semibold))
                                        .foregroundColor(TaskVisualState.threeDaysSkyCyan.accentColor.opacity(0.92))
                                    Text("\(upcomingMultiDayTasks.count)")
                                        .font(.system(size: 9.5, weight: .bold, design: .monospaced))
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 1.5)
                                        .background(TaskVisualState.threeDaysSkyCyan.accentColor.opacity(0.16))
                                        .foregroundColor(TaskVisualState.threeDaysSkyCyan.accentColor)
                                        .clipShape(Capsule())
                                    Spacer()
                                }
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6.5)
                                .background(Color.white.opacity(0.035))
                                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                            }
                            .buttonStyle(.plain)
                            .padding(.top, 4)

                            if showUpcomingMultiDaySection {
                                ForEach(upcomingMultiDayTasks) { task in
                                    calmTaskRow(task)
                                }
                            }
                        }
                    }

                    // Section C: Completed Tasks (Collapsed by Default)
                    if !completedTasks.isEmpty {
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Button(action: {
                                    withAnimation(.easeInOut(duration: 0.16)) {
                                        showCompletedSection.toggle()
                                    }
                                }) {
                                    HStack(spacing: 6) {
                                        Image(systemName: showCompletedSection ? "chevron.down" : "chevron.right")
                                            .font(.system(size: 9, weight: .bold))
                                        Text("Bajarilganlar (\(completedTasks.count))")
                                            .font(.system(size: 10.5, weight: .semibold))
                                    }
                                    .foregroundColor(TaskVisualState.completedGreen.accentColor.opacity(0.88))
                                }
                                .buttonStyle(.plain)

                                Spacer()

                                Button(action: { storage.clearCompletedTasks() }) {
                                    Image(systemName: "trash")
                                        .font(.system(size: 10))
                                        .foregroundColor(.white.opacity(0.4))
                                }
                                .buttonStyle(.plain)
                                .help("Bajarilganlarni ro'yxatdan tozalash")
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5.5)
                            .background(Color.white.opacity(0.03))
                            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                            .padding(.top, 2)

                            if showCompletedSection {
                                ForEach(completedTasks) { task in
                                    calmTaskRow(task)
                                }
                            }
                        }
                    }
                }
                .padding(.vertical, 2)
            }
        }
    }

    private func previewVisualState(for days: Int) -> TaskVisualState {
        if days <= 1 { return .dueTodayBrightBlue }
        if days <= 3 { return .threeDaysSkyCyan }
        return .moreDaysIceWhiteBlue
    }

    private func calmTaskRow(_ task: TaskItem) -> some View {
        let state = task.visualState
        return HStack(alignment: .center, spacing: 10) {
            Button(action: {
                withAnimation(.spring(response: 0.25, dampingFraction: 0.78)) {
                    storage.toggleTask(task)
                }
            }) {
                ZStack {
                    Circle()
                        .stroke(state.accentColor, lineWidth: 1.6)
                        .frame(width: 17, height: 17)
                    if task.isCompleted {
                        Circle()
                            .fill(state.accentColor)
                            .frame(width: 17, height: 17)
                        Image(systemName: "checkmark")
                            .font(.system(size: 9.5, weight: .bold))
                            .foregroundColor(.black)
                    } else {
                        Circle()
                            .fill(state.accentColor.opacity(0.22))
                            .frame(width: 9, height: 9)
                    }
                }
            }
            .buttonStyle(.plain)

            VStack(alignment: .leading, spacing: 3) {
                if editingTaskId == task.id {
                    TextField("Vazifa nomi...", text: $editingTaskTitle, onCommit: {
                        storage.updateTaskTitle(task, newTitle: editingTaskTitle)
                        editingTaskId = nil
                    })
                    .textFieldStyle(.plain)
                    .font(.system(size: 12.5, weight: .medium))
                    .foregroundColor(.white)
                } else {
                    Text(task.cleanDisplayTitle)
                        .font(.system(size: 12.5 * storage.settings.fontScale, weight: .medium))
                        .foregroundColor(
                            task.isCompleted
                                ? state.accentColor.opacity(0.90)
                                : .white.opacity(0.94)
                        )
                        .strikethrough(task.isCompleted, color: state.accentColor.opacity(0.5))
                        .fixedSize(horizontal: false, vertical: true)
                        .onTapGesture {
                            windowController.notesPanel?.focusForTextInput()
                            editingTaskId = task.id
                            editingTaskTitle = task.title
                        }
                }

                Menu {
                    Button("🔵 Bugun / 1 kun qoldi (Ochiq ko'k)") { storage.setTaskDurationDays(task, days: 1) }
                    Button("🩵 2 kun qoldi (Havorang — Keyingi kunlar)") { storage.setTaskDurationDays(task, days: 2) }
                    Button("🩵 3 kun qoldi (Havorang — Keyingi kunlar)") { storage.setTaskDurationDays(task, days: 3) }
                    Button("❄️ 5 kun qoldi (Ko'kish oq — Keyingi kunlar)") { storage.setTaskDurationDays(task, days: 5) }
                    Button("❄️ 7 kun qoldi (Ko'kish oq — Keyingi kunlar)") { storage.setTaskDurationDays(task, days: 7) }
                    Button("❄️ 14 kun qoldi (Ko'kish oq — Keyingi kunlar)") { storage.setTaskDurationDays(task, days: 14) }
                    Divider()
                    Button("🔴 1 kun o'tib ketdi (Qizil)") { storage.setTaskOverdueByDays(task, overdueDays: 1) }
                    Button("🟢 Bajarildi / Qaytarish (Yashil)") { storage.toggleTask(task) }
                } label: {
                    Text(task.bottomStatusBadgeText)
                        .font(.system(size: 10, weight: .semibold, design: .rounded))
                        .foregroundColor(state.accentColor.opacity(0.92))
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
            }

            Spacer(minLength: 4)

            if !task.isCompleted {
                Button(action: {
                    timerManager.startQuickTimerForTask(task)
                }) {
                    Image(systemName: "play.fill")
                        .font(.system(size: 9.5, weight: .bold))
                        .foregroundColor(state.accentColor)
                        .frame(width: 24, height: 24)
                        .background(state.accentColor.opacity(0.14))
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
                .help("Ushbu vazifa uchun Timerni boshlash")
            }

            Button(action: {
                storage.deleteTask(task)
            }) {
                Image(systemName: "xmark")
                    .font(.system(size: 9.5, weight: .medium))
                    .foregroundColor(.white.opacity(0.28))
                    .frame(width: 20, height: 20)
            }
            .buttonStyle(.plain)
            .help("O'chirish")
        }
        .padding(.horizontal, 11)
        .padding(.vertical, 8.5)
        .background(state.subtleRowFill)
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(state.subtleBorderStroke, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private func submitNewTask() {
        let trimmed = newTaskTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        storage.addTask(
            title: trimmed,
            source: .general,
            durationDays: newTaskDurationDays
        )
        newTaskTitle = ""
        isTaskInputFocused = true
    }

    // =========================================================================
    // MARK: - TAB 3: Calm Timer View (Singular & Exam)
    // =========================================================================

    private var calmTimerTabContent: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                ForEach(TimerMode.allCases) { mode in
                    let isSel = (timerManager.config.mode == mode)
                    Button(action: {
                        withAnimation(.easeInOut(duration: 0.15)) {
                            timerManager.config.mode = mode
                            timerManager.saveConfig()
                        }
                    }) {
                        Text(mode == .singular ? "Singular (Doimiy)" : "Exam (Bosqichli)")
                            .font(.system(size: 11, weight: isSel ? .semibold : .regular))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 6)
                            .background(isSel ? Color(red: 0.30, green: 0.66, blue: 1.00).opacity(0.22) : Color.white.opacity(0.05))
                            .foregroundColor(isSel ? Color(red: 0.45, green: 0.76, blue: 1.00) : .white.opacity(0.65))
                            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }
            }

            if timerManager.config.mode == .singular {
                calmSingularSetupView
            } else {
                calmExamSetupView
            }
        }
    }

    private var calmSingularSetupView: some View {
        VStack(spacing: 14) {
            Spacer(minLength: 4)

            HStack(spacing: 18) {
                Button(action: {
                    timerManager.config.singularMinutes = max(5, timerManager.config.singularMinutes - 5)
                    timerManager.saveConfig()
                }) {
                    Image(systemName: "minus")
                        .font(.system(size: 12, weight: .bold))
                        .frame(width: 30, height: 30)
                        .background(Color.white.opacity(0.08))
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)

                Text("\(timerManager.config.singularMinutes) daqiqa")
                    .font(.system(size: 26, weight: .bold, design: .rounded))
                    .foregroundColor(.white)

                Button(action: {
                    timerManager.config.singularMinutes = min(240, timerManager.config.singularMinutes + 5)
                    timerManager.saveConfig()
                }) {
                    Image(systemName: "plus")
                        .font(.system(size: 12, weight: .bold))
                        .frame(width: 30, height: 30)
                        .background(Color.white.opacity(0.08))
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
            }

            HStack(spacing: 6) {
                ForEach([15, 25, 45, 60, 90], id: \.self) { mins in
                    let isSel = (timerManager.config.singularMinutes == mins)
                    Button(action: {
                        timerManager.config.singularMinutes = mins
                        timerManager.saveConfig()
                    }) {
                        Text("\(mins)m")
                            .font(.system(size: 11, weight: isSel ? .bold : .medium, design: .monospaced))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 6)
                            .background(isSel ? Color(red: 0.30, green: 0.66, blue: 1.00).opacity(0.24) : Color.white.opacity(0.06))
                            .foregroundColor(isSel ? Color(red: 0.45, green: 0.76, blue: 1.00) : .white.opacity(0.75))
                            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }
            }

            Spacer(minLength: 4)

            Button(action: {
                timerManager.startSingular(minutes: timerManager.config.singularMinutes)
            }) {
                HStack(spacing: 6) {
                    Image(systemName: "play.fill")
                        .font(.system(size: 11, weight: .bold))
                    Text("Timerni Boshlash")
                        .font(.system(size: 12.5, weight: .semibold))
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .background(Color(red: 0.24, green: 0.58, blue: 0.96))
                .foregroundColor(.white)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            }
            .buttonStyle(.plain)
        }
        .padding(14)
        .background(Color.white.opacity(0.04))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private var calmExamSetupView: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                ForEach(ExamTemplatePreset.allCases) { preset in
                    Button(action: { timerManager.applyExamPreset(preset) }) {
                        Text(preset.shortTitle)
                            .font(.system(size: 10, weight: .medium))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color.white.opacity(0.06))
                            .foregroundColor(.white.opacity(0.8))
                            .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }
                Spacer()
            }

            ScrollView(.vertical, showsIndicators: false) {
                LazyVStack(alignment: .leading, spacing: 5) {
                    ForEach(Array(timerManager.config.examParts.enumerated()), id: \.element.id) { idx, part in
                        calmExamPartRow(index: idx, part: part)
                    }
                }
            }

            HStack(spacing: 6) {
                Button(action: { timerManager.addExamPart(minutes: 45, kind: .work) }) {
                    Image(systemName: "plus")
                        .font(.system(size: 11, weight: .bold))
                        .frame(width: 30, height: 30)
                        .background(Color.white.opacity(0.07))
                        .foregroundColor(.white.opacity(0.85))
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
                .buttonStyle(.plain)
                .help("Yangi Ish qismi qo'shish")

                Button(action: { timerManager.addExamPart(minutes: 10, kind: .rest) }) {
                    Image(systemName: "cup.and.saucer.fill")
                        .font(.system(size: 11, weight: .bold))
                        .frame(width: 30, height: 30)
                        .background(Color.white.opacity(0.07))
                        .foregroundColor(Color(red: 0.24, green: 0.84, blue: 0.58))
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
                .buttonStyle(.plain)
                .help("Yangi Dam olish qismi qo'shish")

                Button(action: { timerManager.startExam() }) {
                    HStack(spacing: 5) {
                        Image(systemName: "play.fill")
                            .font(.system(size: 10, weight: .bold))
                        Text("Exam Timerni Boshlash")
                            .font(.system(size: 11.5, weight: .semibold))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .background(Color(red: 0.24, green: 0.58, blue: 0.96))
                    .foregroundColor(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(10)
        .background(Color.white.opacity(0.04))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private func calmExamPartRow(index: Int, part: TimerPart) -> some View {
        let isBreak = (part.kind == .rest)
        let accent = isBreak ? Color(red: 0.24, green: 0.84, blue: 0.58) : Color(red: 0.32, green: 0.68, blue: 1.00)
        return HStack(spacing: 8) {
            Text("\(index + 1).")
                .font(.system(size: 11, weight: .bold, design: .monospaced))
                .foregroundColor(accent)
                .frame(width: 18, alignment: .leading)

            TextField("Qism nomi...", text: Binding(
                get: { part.title },
                set: { timerManager.updateExamPart(id: part.id, title: $0) }
            ))
            .textFieldStyle(.plain)
            .font(.system(size: 11.5))
            .foregroundColor(.white.opacity(0.92))

            Button(action: {
                timerManager.updateExamPart(id: part.id, kind: isBreak ? .work : .rest)
            }) {
                Text(isBreak ? "Dam" : "Ish")
                    .font(.system(size: 9.5, weight: .semibold))
                    .padding(.horizontal, 7)
                    .padding(.vertical, 2.5)
                    .background(accent.opacity(0.16))
                    .foregroundColor(accent)
                    .clipShape(Capsule())
            }
            .buttonStyle(.plain)

            HStack(spacing: 4) {
                Button(action: {
                    let step = part.durationMinutes <= 10 ? 1 : 5
                    timerManager.updateExamPart(id: part.id, minutes: max(1, part.durationMinutes - step))
                }) {
                    Image(systemName: "minus")
                        .font(.system(size: 8.5, weight: .bold))
                        .frame(width: 18, height: 18)
                        .background(Color.white.opacity(0.07))
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)

                Text("\(part.durationMinutes)m")
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    .foregroundColor(.white)
                    .frame(width: 34, alignment: .center)

                Button(action: {
                    let step = part.durationMinutes < 10 ? 1 : 5
                    timerManager.updateExamPart(id: part.id, minutes: min(240, part.durationMinutes + step))
                }) {
                    Image(systemName: "plus")
                        .font(.system(size: 8.5, weight: .bold))
                        .frame(width: 18, height: 18)
                        .background(Color.white.opacity(0.07))
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
            }

            if timerManager.config.examParts.count > 1 {
                Button(action: { timerManager.removeExamPart(id: part.id) }) {
                    Image(systemName: "xmark")
                        .font(.system(size: 9))
                        .foregroundColor(.white.opacity(0.35))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Color.white.opacity(0.04))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    // =========================================================================
    // MARK: - TAB 4: Calm Integrated Eslatmalar (RPA) & Balance
    // =========================================================================

    private var calmRulesAndBalanceTabContent: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 8) {
                Image(systemName: "sparkles")
                    .font(.system(size: 11.5))
                    .foregroundColor(Color(red: 0.36, green: 0.86, blue: 0.96))

                TextField("Yangi eslatma yoki qoida yozing va Enter bosing...", text: $newRuleText, onCommit: submitNewRule)
                    .textFieldStyle(.plain)
                    .focused($isRuleInputFocused)
                    .font(.system(size: 12))
                    .foregroundColor(.white)

                if !newRuleText.isEmpty {
                    Button(action: submitNewRule) {
                        Image(systemName: "arrow.up.circle.fill")
                            .font(.system(size: 16))
                            .foregroundColor(Color(red: 0.36, green: 0.86, blue: 0.96))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 11)
            .padding(.vertical, 8)
            .background(Color.white.opacity(0.06))
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(isRuleInputFocused ? Color(red: 0.36, green: 0.86, blue: 0.96).opacity(0.45) : Color.white.opacity(0.08), lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .contentShape(Rectangle())
            .onTapGesture {
                windowController.notesPanel?.focusForTextInput()
                isRuleInputFocused = true
            }

            ScrollView(.vertical, showsIndicators: false) {
                LazyVStack(alignment: .leading, spacing: 5) {
                    ForEach(storage.rules) { rule in
                        HStack(alignment: .center, spacing: 9) {
                            Circle()
                                .fill(Color(red: 0.36, green: 0.86, blue: 0.96).opacity(0.75))
                                .frame(width: 6, height: 6)

                            if editingRuleId == rule.id {
                                TextField("Eslatma matni...", text: $editingRuleText, onCommit: {
                                    storage.updateRule(rule, newTitle: editingRuleText, newType: rule.ruleType)
                                    editingRuleId = nil
                                })
                                .textFieldStyle(.plain)
                                .font(.system(size: 12))
                                .foregroundColor(.white)
                            } else {
                                Text(rule.title)
                                    .font(.system(size: 12, weight: .regular))
                                    .foregroundColor(.white.opacity(0.90))
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .onTapGesture {
                                        windowController.notesPanel?.focusForTextInput()
                                        editingRuleId = rule.id
                                        editingRuleText = rule.title
                                    }
                            }

                            Button(action: { storage.deleteRuleForce(rule) }) {
                                Image(systemName: "xmark")
                                    .font(.system(size: 9.5))
                                    .foregroundColor(.white.opacity(0.30))
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(.horizontal, 11)
                        .padding(.vertical, 8)
                        .background(Color.white.opacity(0.045))
                        .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
                    }
                }
            }

            HStack(spacing: 10) {
                Text("SAT: \(storage.satTracker.totalSATScore)/1600 (M:\(storage.satTracker.currentMathScore) RW:\(storage.satTracker.currentRWScore))")
                    .font(.system(size: 10.5, weight: .medium))
                    .foregroundColor(.white.opacity(0.65))

                Spacer()

                Button(action: { windowController.toggleRulesPanel() }) {
                    Image(systemName: windowController.isRulesVisible ? "pip.exit" : "pip.enter")
                        .font(.system(size: 11))
                        .foregroundColor(.white.opacity(0.75))
                        .frame(width: 24, height: 24)
                        .background(Color.white.opacity(0.07))
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
                .help(windowController.isRulesVisible ? "Alohida eslatma oynasini yopish" : "Eslatmalarni alohida mini-oyna qilish")
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Color.white.opacity(0.035))
            .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
        }
    }

    private func submitNewRule() {
        let trimmed = newRuleText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        storage.addRule(title: trimmed, type: .doRule, isLocked: false)
        newRuleText = ""
        isRuleInputFocused = true
    }
}
