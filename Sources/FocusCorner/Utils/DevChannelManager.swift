import Foundation
import AppKit
import Darwin

@_silgen_name("malloc_zone_pressure_relief")
private func c_malloc_zone_pressure_relief(_ zone: OpaquePointer?, _ goal: Int) -> Int

public struct ChannelMetadata: Codable, Equatable {
    public var version: String
    public var activeChannel: String
    public var sourceRepoPath: String
    public var lastBuildTime: String
    public var buildCount: Int

    public init(
        version: String = "v5.2-TerminalBackup",
        activeChannel: String = "release",
        sourceRepoPath: String = "",
        lastBuildTime: String = "",
        buildCount: Int = 1
    ) {
        self.version = version
        self.activeChannel = activeChannel
        self.sourceRepoPath = sourceRepoPath
        self.lastBuildTime = lastBuildTime
        self.buildCount = buildCount
    }
}

@MainActor
public final class DevChannelManager: ObservableObject {
    public static let shared = DevChannelManager()

    @Published public var metadata: ChannelMetadata = ChannelMetadata()
    @Published public var isBuilding: Bool = false
    @Published public var buildStatusLog: String = "Tayyor (Idle)"
    @Published public var memoryFootprintMB: Double = 16.0

    private let metaFileURL: URL
    private let baseDirURL: URL
    private var memoryGuardianTimer: Timer?

    private init() {
        let home = FileManager.default.homeDirectoryForCurrentUser
        self.baseDirURL = home.appendingPathComponent(".focus_corner", isDirectory: true)
        self.metaFileURL = baseDirURL.appendingPathComponent("channel_meta.json")
        loadMetadata()
        silentMemoryTrim()
        startAutoMemoryGuardian()
    }

    private func startAutoMemoryGuardian() {
        memoryGuardianTimer = Timer.scheduledTimer(withTimeInterval: 30.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.silentMemoryTrim()
            }
        }
    }

    public func silentMemoryTrim() {
        autoreleasepool {
            URLCache.shared.removeAllCachedResponses()
            URLCache.shared.memoryCapacity = 0
            URLCache.shared.diskCapacity = 0
            NSFontManager.shared.fontPanel(false)?.orderOut(nil)
            NSColorPanel.shared.orderOut(nil)
        }
        let fm = FileManager.default
        if let items = try? fm.contentsOfDirectory(at: baseDirURL, includingPropertiesForKeys: nil) {
            for url in items where url.pathExtension == "tmp" {
                try? fm.removeItem(at: url)
            }
        }
        // Return freed malloc pages back to macOS kernel immediately
        _ = c_malloc_zone_pressure_relief(nil, 0)
        refreshMemoryUsage()
    }

    public func loadMetadata() {
        if let data = try? Data(contentsOf: metaFileURL),
           let loaded = try? JSONDecoder().decode(ChannelMetadata.self, from: data) {
            self.metadata = loaded
        } else {
            let defaultRepo = FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent("Downloads/FocusCorner").path
            self.metadata = ChannelMetadata(
                version: "v5.0-EyeCare",
                activeChannel: StorageManager.shared.settings.updateChannel,
                sourceRepoPath: defaultRepo,
                lastBuildTime: TaskItem.todayString(),
                buildCount: 1
            )
            saveMetadata()
        }
    }

    public func saveMetadata() {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        if let data = try? encoder.encode(metadata) {
            try? data.write(to: metaFileURL, options: .atomic)
        }
    }

    /// Reads exact macOS Activity Monitor physical RAM footprint (TASK_VM_INFO.phys_footprint)
    /// instead of shared OS dylib resident_size
    public func refreshMemoryUsage() {
        var vmInfo = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<natural_t>.size)
        let kerr: kern_return_t = withUnsafeMutablePointer(to: &vmInfo) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
            }
        }
        if kerr == KERN_SUCCESS {
            let mb = Double(vmInfo.phys_footprint) / (1024.0 * 1024.0)
            self.memoryFootprintMB = max(8.0, round(mb * 10) / 10.0)
        }
    }

    public var hasRollbackBinary: Bool {
        let rollbackURL = baseDirURL.appendingPathComponent("channels/rollback/FocusCorner")
        return FileManager.default.fileExists(atPath: rollbackURL.path)
    }

    public func triggerHotRebuild(channel: String) {
        guard !isBuilding else { return }
        let repoPath = metadata.sourceRepoPath
        let runScript = URL(fileURLWithPath: repoPath).appendingPathComponent("run.sh").path

        guard FileManager.default.fileExists(atPath: runScript) else {
            buildStatusLog = "❌ Manba papkasi topilmadi: \(repoPath)"
            StorageManager.shared.showToast("⚠️ Manba papkasi topilmadi: \(repoPath)")
            return
        }

        isBuilding = true
        buildStatusLog = "🔄 [\(channel.uppercased())] Yangilanmoqda..."
        StorageManager.shared.settings.updateChannel = channel
        StorageManager.shared.saveSettings()

        let flag = (channel == "dev") ? "--dev" : "--release"
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.arguments = [runScript, flag]
        process.currentDirectoryURL = URL(fileURLWithPath: repoPath)
        process.terminationHandler = { [weak self] _ in
            Task { @MainActor in
                self?.isBuilding = false
                self?.buildStatusLog = "✅ Tayyor (Yangilandi)"
            }
        }
        do {
            try process.run()
        } catch {
            isBuilding = false
            buildStatusLog = "❌ Xatolik: \(error.localizedDescription)"
        }
    }

    public func performSafeRollback() {
        let rollbackURL = baseDirURL.appendingPathComponent("channels/rollback/FocusCorner")
        let activeBinURL = baseDirURL.appendingPathComponent("bin/FocusCorner")
        guard FileManager.default.fileExists(atPath: rollbackURL.path) else { return }
        do {
            if FileManager.default.fileExists(atPath: activeBinURL.path) {
                try FileManager.default.removeItem(at: activeBinURL)
            }
            try FileManager.default.copyItem(at: rollbackURL, to: activeBinURL)
            restartApplication()
        } catch {}
    }

    public func cleanStaleCachesAndTempFiles() {
        silentMemoryTrim()
        if !metadata.sourceRepoPath.isEmpty {
            let buildDir = URL(fileURLWithPath: metadata.sourceRepoPath).appendingPathComponent(".build")
            if FileManager.default.fileExists(atPath: buildDir.path) {
                try? FileManager.default.removeItem(at: buildDir)
            }
        }
        refreshMemoryUsage()
        StorageManager.shared.showToast(String(format: "🧹 Kesh tozalandi! RAM bosimi: %.1f MB", memoryFootprintMB))
    }

    public func openSourceInEditor() {
        let repoURL = URL(fileURLWithPath: metadata.sourceRepoPath)
        NSWorkspace.shared.open(repoURL)
    }

    public func restartApplication() {
        let binPath = LaunchAgentManager.shared.installedAppBinaryPath
        guard FileManager.default.fileExists(atPath: binPath) else { return }
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/bash")
        task.arguments = ["-c", "sleep 0.4 && \"\(binPath)\" &"]
        try? task.run()
        NSApp.terminate(nil)
    }
}
