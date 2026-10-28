import Foundation
import AppKit
import Darwin

public struct ChannelMetadata: Codable, Equatable {
    public var version: String
    public var activeChannel: String // "dev" or "release"
    public var sourceRepoPath: String
    public var lastBuildTime: String
    public var buildCount: Int

    public init(
        version: String = "v2.2.0-Synergy",
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
    @Published public var memoryFootprintMB: Double = 14.0

    private let metaFileURL: URL
    private let baseDirURL: URL

    private init() {
        let home = FileManager.default.homeDirectoryForCurrentUser
        self.baseDirURL = home.appendingPathComponent(".focus_corner", isDirectory: true)
        self.metaFileURL = baseDirURL.appendingPathComponent("channel_meta.json")
        loadMetadata()
        refreshMemoryUsage()
        startAutoMemoryGuardian()
    }

    private var memoryGuardianTimer: Timer?

    private func startAutoMemoryGuardian() {
        memoryGuardianTimer = Timer.scheduledTimer(withTimeInterval: 45.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.silentMemoryTrim()
            }
        }
    }

    public func silentMemoryTrim() {
        URLCache.shared.removeAllCachedResponses()
        let fm = FileManager.default
        if let items = try? fm.contentsOfDirectory(at: baseDirURL, includingPropertiesForKeys: nil) {
            for url in items where url.pathExtension == "tmp" {
                try? fm.removeItem(at: url)
            }
        }
        autoreleasepool { URLCache.shared.removeAllCachedResponses() }
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
                version: "v2.2.0-Synergy",
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

    public func refreshMemoryUsage() {
        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size) / 4
        let kerr: kern_return_t = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &count)
            }
        }
        if kerr == KERN_SUCCESS {
            let mb = Double(info.resident_size) / (1024.0 * 1024.0)
            self.memoryFootprintMB = round(mb * 10) / 10.0
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
            StorageManager.shared.showToast("⚠️ Dev manba papkasi topilmadi: \(repoPath)")
            return
        }

        isBuilding = true
        buildStatusLog = "🔄 [\(channel.uppercased())] Kompilyatsiya va yangilash boshlandi..."
        StorageManager.shared.settings.updateChannel = channel
        StorageManager.shared.saveSettings()

        let flag = (channel == "dev") ? "--dev" : "--release"
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.arguments = [runScript, flag]
        process.currentDirectoryURL = URL(fileURLWithPath: repoPath)
        try? process.run()
    }

    public func performSafeRollback() {
        let rollbackURL = baseDirURL.appendingPathComponent("channels/rollback/FocusCorner")
        let activeBinURL = baseDirURL.appendingPathComponent("bin/FocusCorner")
        let userAppBinURL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Applications/FocusCorner.app/Contents/MacOS/FocusCorner")

        guard FileManager.default.fileExists(atPath: rollbackURL.path) else {
            StorageManager.shared.showToast("⚠️ Rollback uchun zahira binary topilmadi.")
            return
        }

        do {
            if FileManager.default.fileExists(atPath: activeBinURL.path) {
                try FileManager.default.removeItem(at: activeBinURL)
            }
            try FileManager.default.copyItem(at: rollbackURL, to: activeBinURL)
            if FileManager.default.fileExists(atPath: userAppBinURL.path) {
                try? FileManager.default.removeItem(at: userAppBinURL)
                try? FileManager.default.copyItem(at: rollbackURL, to: userAppBinURL)
            }
            StorageManager.shared.appendHistoryLine("- [DEV-ROLLBACK] [{TIMESTAMP}] Oldingi barqaror binary tiklandi")
            restartApplication()
        } catch {
            StorageManager.shared.showToast("❌ Rollback xatosi: \(error.localizedDescription)")
        }
    }

    public func cleanStaleCachesAndTempFiles() {
        let fm = FileManager.default
        var cleanedCount = 0

        if let items = try? fm.contentsOfDirectory(at: baseDirURL, includingPropertiesForKeys: nil) {
            for url in items where url.pathExtension == "tmp" || url.lastPathComponent == ".DS_Store" {
                try? fm.removeItem(at: url)
                cleanedCount += 1
            }
        }

        if !metadata.sourceRepoPath.isEmpty {
            let buildDir = URL(fileURLWithPath: metadata.sourceRepoPath).appendingPathComponent(".build")
            if fm.fileExists(atPath: buildDir.path) {
                try? fm.removeItem(at: buildDir)
                cleanedCount += 1
            }
        }

        refreshMemoryUsage()
        buildStatusLog = "🧹 Kesh va ortiqcha fayllar tozalandi (\(cleanedCount) obyekt). history.md daxlsiz!"
        StorageManager.shared.showToast("🧹 Keraksiz kesh fayllari tozalandi! history.md va sozlamalar 100% saqlab qolindi.")
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
