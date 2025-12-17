import AppKit
import Carbon
import Combine
import OSLog

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let logger = Logger(subsystem: "app.lidless.Lidless", category: "AppDelegate")
    private let supervisor = DisplaySupervisor.shared
    private var statusBarController: StatusBarController?
    private var hotKeyRegistry: HotKeyRegistry?
    private var isDuplicateInstance = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        if terminateIfAnotherInstanceIsRunning() {
            isDuplicateInstance = true
            return
        }

        supervisor.start()
        statusBarController = StatusBarController(supervisor: supervisor)
        hotKeyRegistry = HotKeyRegistry(
            toggle: { DisplaySupervisor.shared.toggleInternalDisplay() },
            restoreAndPause: { DisplaySupervisor.shared.restoreAndPauseApp() }
        )
        hotKeyRegistry?.register()

        LaunchAgentController.shared.enableByDefaultIfNeeded()
        logger.info("Lidless launched")
    }

    func applicationWillTerminate(_ notification: Notification) {
        guard !isDuplicateInstance else { return }
        hotKeyRegistry?.unregister()
        supervisor.stop(restore: true)
        logger.info("Lidless terminated")
    }

    private func terminateIfAnotherInstanceIsRunning() -> Bool {
        guard let bundleIdentifier = Bundle.main.bundleIdentifier else { return false }

        let currentPID = ProcessInfo.processInfo.processIdentifier
        let otherInstances = NSRunningApplication
            .runningApplications(withBundleIdentifier: bundleIdentifier)
            .filter { $0.processIdentifier != currentPID }

        guard !otherInstances.isEmpty else { return false }
        logger.warning("Another Lidless instance is already running; terminating duplicate")
        isDuplicateInstance = true
        NSApp.terminate(nil)
        return true
    }
}
