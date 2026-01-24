import AppKit
import Foundation
import OSLog

final class LaunchAgentController: ObservableObject {
    static let shared = LaunchAgentController()

    @Published private(set) var isEnabled: Bool

    private let logger = Logger(subsystem: "app.lidless.Lidless", category: "LaunchAgent")
    private let defaults = UserDefaults.standard
    private let defaultConfiguredKey = "LaunchAgentDefaultConfigured"
    private let appLabel = "app.lidless.Lidless"
    private let watchdogLabel = "app.lidless.LidlessWatchdog"

    private var launchAgentsDirectory: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/LaunchAgents", isDirectory: true)
    }

    private var appPlistURL: URL {
        launchAgentsDirectory.appendingPathComponent("\(appLabel).plist")
    }

    private var watchdogPlistURL: URL {
        launchAgentsDirectory.appendingPathComponent("\(watchdogLabel).plist")
    }

    private init() {
        isEnabled = false
        refresh()
    }

    func enableByDefaultIfNeeded() {
        guard defaults.object(forKey: defaultConfiguredKey) == nil else {
            refresh()
            if isEnabled, FileManager.default.fileExists(atPath: watchdogPlistURL.path) {
                bootstrap(watchdogPlistURL)
            }
            return
        }

        do {
            try setEnabled(true)
            defaults.set(true, forKey: defaultConfiguredKey)
        } catch {
            logger.error("Could not enable launch at login by default: \(error.localizedDescription, privacy: .public)")
        }
    }

    func setEnabled(_ enabled: Bool) throws {
        if enabled {
            try installLaunchAgents()
        } else {
            uninstallLaunchAgents()
        }
        refresh()
    }

    func refresh() {
        isEnabled = FileManager.default.fileExists(atPath: appPlistURL.path)
    }

    private func installLaunchAgents() throws {
        guard let executablePath = Bundle.main.executablePath else {
            throw LaunchAgentError.missingExecutable
        }

        let bundlePath = Bundle.main.bundlePath
        let watchdogPath = URL(fileURLWithPath: bundlePath)
            .appendingPathComponent("Contents/Library/Helpers/LidlessWatchdog")
            .path

        try FileManager.default.createDirectory(
            at: launchAgentsDirectory,
            withIntermediateDirectories: true
        )

        try writeLaunchAgent(
            label: appLabel,
            programArguments: [executablePath],
            keepAlive: false,
            to: appPlistURL
        )

        if FileManager.default.fileExists(atPath: watchdogPath) {
            try writeLaunchAgent(
                label: watchdogLabel,
                programArguments: [watchdogPath],
                keepAlive: true,
                to: watchdogPlistURL
            )
        }

        if FileManager.default.fileExists(atPath: watchdogPlistURL.path) {
            bootstrap(watchdogPlistURL)
        }
    }

    private func uninstallLaunchAgents() {
        bootout(appPlistURL, label: appLabel)
        bootout(watchdogPlistURL, label: watchdogLabel)
        try? FileManager.default.removeItem(at: appPlistURL)
        try? FileManager.default.removeItem(at: watchdogPlistURL)
    }

    private func writeLaunchAgent(
        label: String,
        programArguments: [String],
        keepAlive: Bool,
        to url: URL
    ) throws {
        let plist: [String: Any] = [
            "Label": label,
            "ProgramArguments": programArguments,
            "RunAtLoad": true,
            "KeepAlive": keepAlive,
            "ProcessType": "Interactive"
        ]
        let data = try PropertyListSerialization.data(
            fromPropertyList: plist,
            format: .xml,
            options: 0
        )
        try data.write(to: url, options: [.atomic])
    }

    private func bootstrap(_ plistURL: URL) {
        runLaunchctl(["bootstrap", guiDomain, plistURL.path])
    }

    private func bootout(_ plistURL: URL, label: String? = nil) {
        runLaunchctl(["bootout", guiDomain, plistURL.path])
        if let label {
            runLaunchctl(["bootout", "\(guiDomain)/\(label)"])
        }
    }

    private var guiDomain: String {
        "gui/\(getuid())"
    }

    private func runLaunchctl(_ arguments: [String]) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        process.arguments = arguments
        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            logger.debug("launchctl failed: \(arguments.joined(separator: " "), privacy: .public)")
        }
    }
}

enum LaunchAgentError: LocalizedError {
    case missingExecutable

    var errorDescription: String? {
        switch self {
        case .missingExecutable:
            return "The app executable path is unavailable."
        }
    }
}
