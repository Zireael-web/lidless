import AppKit
import Combine
import CoreGraphics
import Foundation
import OSLog

private func lidlessDisplayReconfigurationCallback(
    display: CGDirectDisplayID,
    flags: CGDisplayChangeSummaryFlags,
    userInfo: UnsafeMutableRawPointer?
) {
    guard let userInfo else { return }
    let supervisor = Unmanaged<DisplaySupervisor>.fromOpaque(userInfo).takeUnretainedValue()
    DispatchQueue.main.async {
        supervisor.handleDisplayConfigurationChanged(flags: flags)
    }
}

final class DisplaySupervisor: ObservableObject {
    static let shared = DisplaySupervisor()

    @Published private(set) var snapshot = DisplaySnapshot(displays: [])
    @Published private(set) var isInternalOff = false
    @Published private(set) var appEnabled = true
    @Published private(set) var autoMode = true
    @Published private(set) var reapplyAfterWake = true
    @Published private(set) var needsConfirmation = false
    @Published private(set) var confirmationDeadline: Date?
    @Published private(set) var lastError: String?
    @Published private(set) var statusMessage = "Ready"
    @Published private(set) var uiTick = Date()

    private let logger = Logger(subsystem: "app.lidless.Lidless", category: "DisplaySupervisor")
    private let store = StateStore.shared
    private let privateAPI = PrivateDisplayAPI.shared
    private var state = PersistedAppState.fresh
    private var registeredCallback = false
    private var heartbeatTimer: Timer?
    private var rollbackTimer: Timer?
    private var uiTimer: Timer?
    private var safetyTimer: Timer?
    private var reconfigurationWorkItem: DispatchWorkItem?
    private var autoDisableWorkItem: DispatchWorkItem?
    private var notificationObservers: [(NotificationCenter, NSObjectProtocol)] = []
    private var autoDisableSuppressedUntil: Date?
    private var lastDisableRequestedAt: Date?

    var canDisable: Bool {
        appEnabled &&
        !isInternalOff &&
        privateAPI.isAvailable &&
        snapshot.canDisableInternal
    }

    var trustedExternalCount: Int {
        snapshot.trustedExternalDisplays.count
    }

    var internalDisplayID: CGDirectDisplayID? {
        snapshot.activeBuiltIn?.id ?? state.internalDisplayID ?? store.loadCachedInternalDisplayID()
    }

    var confirmationSecondsRemaining: Int {
        guard let confirmationDeadline else { return 0 }
        return max(0, Int(ceil(confirmationDeadline.timeIntervalSinceNow)))
    }

    var internalDisplayStateLabel: String {
        if isInternalOff || state.internalDisabledByApp || state.internalDisablePendingByApp {
            return "Off"
        }
        if snapshot.activeBuiltIn != nil {
            return "On"
        }
        return "Unknown"
    }

    var diagnosticsText: String {
        #if arch(arm64)
        let architecture = "arm64"
        #elseif arch(x86_64)
        let architecture = "x86_64"
        #else
        let architecture = "unknown"
        #endif

        let frameworks = privateAPI.loadedFrameworkPaths.isEmpty
            ? "none"
            : privateAPI.loadedFrameworkPaths.joined(separator: ", ")

        let displays = snapshot.displays.map { display in
            """
            - id: \(display.id)
              name: \(display.name)
              builtIn: \(display.isBuiltIn)
              active: \(display.isActive)
              online: \(display.isOnline)
              main: \(display.isMain)
              nsScreen: \(display.hasNSScreen)
              trustedExternal: \(display.isTrustedExternal)
              frame: \(display.frame)
              bounds: \(display.bounds)
              mode: \(display.modeDescription)
            """
        }.joined(separator: "\n")

        return """
        Lidless Diagnostics

        System
        - macOS: \(ProcessInfo.processInfo.operatingSystemVersionString)
        - architecture: \(architecture)

        Private API
        - available: \(privateAPI.isAvailable)
        - resolvedSymbol: \(privateAPI.resolvedSymbolName ?? "none")
        - lastSuccessfulPath: \(privateAPI.lastSuccessfulPath ?? "none")
        - loadedFrameworks: \(frameworks)

        State
        - appEnabled: \(appEnabled)
        - autoMode: \(autoMode)
        - reapplyAfterWake: \(reapplyAfterWake)
        - internalDisplayID: \(internalDisplayID.map(String.init) ?? "none")
        - internalDisabledByApp: \(state.internalDisabledByApp)
        - internalDisablePendingByApp: \(state.internalDisablePendingByApp)
        - wasDisabledBeforeSleep: \(state.wasDisabledBeforeSleep)
        - lastCleanShutdown: \(state.lastCleanShutdown)
        - trustedExternalCount: \(trustedExternalCount)
        - lastError: \(lastError ?? "none")

        Displays
        \(displays.isEmpty ? "none" : displays)
        """
    }

    private init() {}

    func start() {
        let loadedState = store.loadAppState()
        let lease = store.readLease()
        let needsStartupRecovery = loadedState.internalDisabledByApp ||
            loadedState.internalDisablePendingByApp ||
            loadedState.lastCleanShutdown == false ||
            lease?.desiredInternalOff == true

        applyState(loadedState)
        persistState { $0.lastCleanShutdown = false }

        if let id = state.internalDisplayID {
            store.saveCachedInternalDisplayID(id)
        }

        if needsStartupRecovery {
            _ = forceRestoreCachedInternalDisplay(reason: "Startup recovery")
        }

        refreshDisplayInfo()
        registerObservers()
        startSafetyTimer()
        scheduleAutoDisableIfNeeded(reason: "Launch", delay: 2.0)
    }

    func stop(restore: Bool) {
        autoDisableWorkItem?.cancel()
        reconfigurationWorkItem?.cancel()
        rollbackTimer?.invalidate()
        heartbeatTimer?.invalidate()
        uiTimer?.invalidate()
        safetyTimer?.invalidate()

        if registeredCallback {
            let pointer = Unmanaged.passUnretained(self).toOpaque()
            CGDisplayRemoveReconfigurationCallback(lidlessDisplayReconfigurationCallback, pointer)
            registeredCallback = false
        }

        for (center, observer) in notificationObservers {
            center.removeObserver(observer)
        }
        notificationObservers.removeAll()

        let restored = restore && internalRestoreNeeded
            ? restoreInternalDisplay(reason: "App quit", suppressAuto: false)
            : true
        persistState {
            $0.lastCleanShutdown = restored
            $0.wasDisabledBeforeSleep = false
            if restored {
                $0.internalDisabledByApp = false
                $0.internalDisablePendingByApp = false
            }
        }
    }

    func toggleInternalDisplay() {
        if isInternalOff {
            _ = restoreInternalDisplay(reason: "Manual toggle")
        } else {
            disableInternalDisplay(reason: "Manual toggle", requiresConfirmation: true)
        }
    }

    func disableInternalDisplay(reason: String = "Manual request", requiresConfirmation: Bool = true) {
        autoDisableWorkItem?.cancel()
        refreshDisplayInfo()

        guard appEnabled else {
            fail("App is paused. Resume auto mode first.")
            return
        }

        guard privateAPI.isAvailable else {
            fail("Private display API is unavailable on this macOS build.")
            return
        }

        guard let builtIn = snapshot.activeBuiltIn else {
            fail("Built-in display is not currently active.")
            return
        }

        guard !snapshot.trustedExternalDisplays.isEmpty else {
            fail("Connect a physical external display first.")
            return
        }

        rememberInternalDisplayID(builtIn.id)
        persistState {
            $0.internalDisablePendingByApp = true
            $0.internalDisabledByApp = false
        }
        store.renewLease(internalDisplayID: builtIn.id)
        lastDisableRequestedAt = Date()

        do {
            try privateAPI.setDisplay(builtIn.id, enabled: false)
            isInternalOff = true
            needsConfirmation = requiresConfirmation
            lastError = nil
            statusMessage = requiresConfirmation ? "Built-in display disabled" : "Auto-disabled built-in display"
            persistState {
                $0.internalDisabledByApp = true
                $0.internalDisablePendingByApp = false
            }
            startHeartbeat(internalID: builtIn.id)
            if requiresConfirmation {
                startRollbackCountdown(seconds: 15)
            } else {
                rollbackTimer?.invalidate()
                rollbackTimer = nil
                uiTimer?.invalidate()
                uiTimer = nil
                confirmationDeadline = nil
            }
            scheduleVerification()
            warpCursorToTrustedExternal()
            logger.info("Disabled internal display. Reason: \(reason, privacy: .public)")
        } catch {
            store.clearLease()
            persistState {
                $0.internalDisabledByApp = false
                $0.internalDisablePendingByApp = false
            }
            fail(error.localizedDescription)
        }
    }

    func confirmInternalOff() {
        guard isInternalOff else { return }
        rollbackTimer?.invalidate()
        rollbackTimer = nil
        uiTimer?.invalidate()
        uiTimer = nil
        needsConfirmation = false
        confirmationDeadline = nil
        statusMessage = "Built-in display stays off"
    }

    @discardableResult
    func restoreInternalDisplay(reason: String, suppressAuto: Bool = true) -> Bool {
        autoDisableWorkItem?.cancel()
        rollbackTimer?.invalidate()
        rollbackTimer = nil
        uiTimer?.invalidate()
        uiTimer = nil
        needsConfirmation = false
        confirmationDeadline = nil

        if suppressAuto {
            autoDisableSuppressedUntil = Date().addingTimeInterval(4)
        }

        if !internalRestoreNeeded, snapshot.activeBuiltIn != nil {
            markInternalAsRestored(status: "Built-in display restored")
            return true
        }

        guard let id = internalDisplayID else {
            fail("Could not find the cached built-in display ID.")
            return false
        }

        return restoreDisplay(id, reason: reason)
    }

    func restoreAndPauseApp() {
        autoDisableWorkItem?.cancel()
        let restored = restoreInternalDisplay(reason: "Restore and pause", suppressAuto: false)
        guard restored else { return }
        updateAppSettings(appEnabled: false, autoMode: false)
        statusMessage = "App paused"
    }

    func resumeAutoMode() {
        updateAppSettings(appEnabled: true, autoMode: true)
        lastError = nil
        statusMessage = "Auto mode enabled"
        refreshDisplayInfo()
        scheduleAutoDisableIfNeeded(reason: "Resume auto mode", delay: 1.0)
    }

    func setAutoMode(_ enabled: Bool) {
        autoDisableWorkItem?.cancel()
        updateAppSettings(appEnabled: enabled ? true : appEnabled, autoMode: enabled)
        statusMessage = enabled ? "Auto mode enabled" : "Auto mode disabled"
        if enabled {
            scheduleAutoDisableIfNeeded(reason: "Auto mode enabled", delay: 1.0)
        }
    }

    func setReapplyAfterWake(_ enabled: Bool) {
        updateAppSettings(reapplyAfterWake: enabled)
    }

    func refreshDisplayInfo() {
        snapshot = DisplaySnapshot.capture()

        if let builtIn = snapshot.activeBuiltIn {
            store.saveCachedInternalDisplayID(builtIn.id)
            persistState { $0.internalDisplayID = builtIn.id }
        }

        if (isInternalOff || state.internalDisabledByApp) && snapshot.trustedExternalDisplays.isEmpty {
            if snapshot.activeBuiltIn?.hasNSScreen == true {
                markInternalAsRestored(status: "Built-in display restored")
            } else {
                _ = restoreInternalDisplay(reason: "No trusted external display", suppressAuto: false)
            }
        }

        if isInternalOff,
           !recentlyRequestedDisable,
           !state.internalDisablePendingByApp,
           !snapshot.trustedExternalDisplays.isEmpty,
           snapshot.activeBuiltIn?.hasNSScreen == true {
            markInternalAsRestored(status: "Built-in display re-enabled outside the app")
        }
    }

    func copyDiagnosticsToPasteboard() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(diagnosticsText, forType: .string)
        statusMessage = "Diagnostics copied"
    }

    func handleDisplayConfigurationChanged(flags: CGDisplayChangeSummaryFlags) {
        if flags.contains(.beginConfigurationFlag) {
            return
        }

        reconfigurationWorkItem?.cancel()

        let workItem = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.refreshDisplayInfo()

            if (self.isInternalOff || self.state.internalDisabledByApp) &&
                self.snapshot.trustedExternalDisplays.isEmpty {
                _ = self.restoreInternalDisplay(reason: "Display configuration changed", suppressAuto: false)
                return
            }

            self.scheduleAutoDisableIfNeeded(reason: "Display configuration changed", delay: 1.2)
        }

        reconfigurationWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8, execute: workItem)
    }

    private var recentlyRequestedDisable: Bool {
        guard let lastDisableRequestedAt else { return false }
        return Date().timeIntervalSince(lastDisableRequestedAt) < 6.0
    }

    private var internalRestoreNeeded: Bool {
        isInternalOff || state.internalDisabledByApp || state.internalDisablePendingByApp || store.readLease()?.desiredInternalOff == true
    }

    private func registerObservers() {
        guard !registeredCallback else { return }

        let pointer = Unmanaged.passUnretained(self).toOpaque()
        CGDisplayRegisterReconfigurationCallback(lidlessDisplayReconfigurationCallback, pointer)
        registeredCallback = true

        let appScreenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.handleDisplayConfigurationChanged(flags: [])
        }
        notificationObservers.append((NotificationCenter.default, appScreenObserver))

        let workspaceCenter = NSWorkspace.shared.notificationCenter
        let willSleepObserver = workspaceCenter.addObserver(
            forName: NSWorkspace.willSleepNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.handleWillSleep()
        }
        notificationObservers.append((workspaceCenter, willSleepObserver))

        let didWakeObserver = workspaceCenter.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.handleWake()
        }
        notificationObservers.append((workspaceCenter, didWakeObserver))
    }

    private func handleWillSleep() {
        let wasOff = isInternalOff || state.internalDisabledByApp || state.internalDisablePendingByApp
        persistState { $0.wasDisabledBeforeSleep = wasOff }
        statusMessage = "Sleeping"
    }

    private func handleWake() {
        statusMessage = "Wake settling"
        let shouldReapply = state.wasDisabledBeforeSleep && appEnabled && autoMode && reapplyAfterWake

        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
            self.refreshDisplayInfo()

            if self.snapshot.trustedExternalDisplays.isEmpty {
                _ = self.restoreInternalDisplay(reason: "Wake without external display", suppressAuto: false)
                self.persistState { $0.wasDisabledBeforeSleep = false }
                return
            }

            if shouldReapply {
                self.scheduleAutoDisableIfNeeded(reason: "Wake reapply", delay: 0.5)
            }

            self.persistState { $0.wasDisabledBeforeSleep = false }
        }
    }

    private func scheduleAutoDisableIfNeeded(reason: String, delay: TimeInterval) {
        autoDisableWorkItem?.cancel()

        guard appEnabled, autoMode, !isInternalOff else { return }
        guard autoDisableSuppressedUntil.map({ Date() >= $0 }) ?? true else { return }
        guard privateAPI.isAvailable else {
            if snapshot.canDisableInternal {
                fail("Private display API is unavailable on this macOS build.")
            }
            return
        }
        guard snapshot.canDisableInternal else { return }

        statusMessage = "External display detected"
        let workItem = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.refreshDisplayInfo()
            guard self.appEnabled, self.autoMode, !self.isInternalOff else { return }
            guard self.autoDisableSuppressedUntil.map({ Date() >= $0 }) ?? true else { return }
            guard self.snapshot.canDisableInternal else { return }
            self.disableInternalDisplay(reason: reason, requiresConfirmation: false)
        }

        autoDisableWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: workItem)
    }

    private func makeTimer(interval: TimeInterval, repeats: Bool, block: @escaping (Timer) -> Void) -> Timer {
        let timer = Timer(timeInterval: interval, repeats: repeats, block: block)
        RunLoop.main.add(timer, forMode: .common)
        return timer
    }

    private func startRollbackCountdown(seconds: TimeInterval) {
        rollbackTimer?.invalidate()
        uiTimer?.invalidate()

        confirmationDeadline = Date().addingTimeInterval(seconds)
        uiTimer = makeTimer(interval: 1, repeats: true) { [weak self] _ in
            self?.uiTick = Date()
        }

        rollbackTimer = makeTimer(interval: seconds, repeats: false) { [weak self] _ in
            _ = self?.restoreInternalDisplay(reason: "Confirmation timeout", suppressAuto: false)
        }
    }

    private func startHeartbeat(internalID: CGDirectDisplayID) {
        heartbeatTimer?.invalidate()
        store.renewLease(internalDisplayID: internalID)
        heartbeatTimer = makeTimer(interval: 5, repeats: true) { [weak self] _ in
            guard let self, self.isInternalOff else { return }
            self.store.renewLease(internalDisplayID: internalID)
        }
    }

    private func stopHeartbeat() {
        heartbeatTimer?.invalidate()
        heartbeatTimer = nil
    }

    private func startSafetyTimer() {
        safetyTimer?.invalidate()
        safetyTimer = makeTimer(interval: 5, repeats: true) { [weak self] _ in
            guard let self else { return }
            guard self.isInternalOff || self.state.internalDisabledByApp || self.state.internalDisablePendingByApp else {
                return
            }
            self.refreshDisplayInfo()
        }
    }

    private func scheduleVerification() {
        for (delay, isFinalCheck) in [(0.7, false), (1.8, false), (3.2, true)] {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                guard self.isInternalOff else { return }
                self.refreshDisplayInfo()

                if self.snapshot.trustedExternalDisplays.isEmpty {
                    _ = self.restoreInternalDisplay(reason: "Post-disable verification failed", suppressAuto: false)
                    return
                }

                if isFinalCheck,
                   self.snapshot.activeBuiltIn?.hasNSScreen == true {
                    self.markInternalAsRestored(status: "Built-in display restored")
                    self.fail("Built-in display still appears active after disable.")
                }
            }
        }
    }

    private func warpCursorToTrustedExternal() {
        guard let external = snapshot.trustedExternalDisplays.first else { return }
        let point = CGPoint(x: external.bounds.midX, y: external.bounds.midY)
        CGWarpMouseCursorPosition(point)
    }

    private func forceRestoreCachedInternalDisplay(reason: String) -> Bool {
        if !state.internalDisabledByApp,
           !state.internalDisablePendingByApp,
           store.readLease()?.desiredInternalOff != true,
           DisplaySnapshot.capture().activeBuiltIn != nil {
            markInternalAsRestored(status: "Startup recovery checked")
            return true
        }

        guard let id = state.internalDisplayID ?? store.loadCachedInternalDisplayID() else {
            store.clearLease()
            fail("Startup recovery could not find the cached built-in display ID.")
            return false
        }

        return restoreDisplay(id, reason: reason)
    }

    private func restoreDisplay(_ id: CGDirectDisplayID, reason: String) -> Bool {
        var lastFailure: Error?

        for attempt in 1...3 {
            do {
                try privateAPI.setDisplay(id, enabled: true)
                markInternalAsRestored(status: "Built-in display restored")
                logger.info("Restored internal display. Reason: \(reason, privacy: .public)")
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                    self.refreshDisplayInfo()
                }
                return true
            } catch {
                lastFailure = error
                logger.error("Restore attempt \(attempt) failed: \(error.localizedDescription, privacy: .public)")
            }
        }

        fail(lastFailure?.localizedDescription ?? "Could not restore built-in display.")
        persistState {
            $0.internalDisabledByApp = true
            $0.internalDisablePendingByApp = false
        }
        return false
    }

    private func markInternalAsRestored(status: String) {
        isInternalOff = false
        needsConfirmation = false
        confirmationDeadline = nil
        stopHeartbeat()
        store.clearLease()
        persistState {
            $0.internalDisabledByApp = false
            $0.internalDisablePendingByApp = false
        }
        lastError = nil
        statusMessage = status
    }

    private func rememberInternalDisplayID(_ id: CGDirectDisplayID) {
        store.saveCachedInternalDisplayID(id)
        persistState { $0.internalDisplayID = id }
    }

    private func updateAppSettings(
        appEnabled: Bool? = nil,
        autoMode: Bool? = nil,
        reapplyAfterWake: Bool? = nil
    ) {
        persistState {
            if let appEnabled {
                $0.appEnabled = appEnabled
            }
            if let autoMode {
                $0.autoMode = autoMode
            }
            if let reapplyAfterWake {
                $0.reapplyAfterWake = reapplyAfterWake
            }
        }
        applyPublishedSettings()
    }

    private func applyState(_ nextState: PersistedAppState) {
        state = nextState
        applyPublishedSettings()
        isInternalOff = nextState.internalDisabledByApp || nextState.internalDisablePendingByApp
    }

    private func applyPublishedSettings() {
        appEnabled = state.appEnabled
        autoMode = state.autoMode
        reapplyAfterWake = state.reapplyAfterWake
    }

    private func persistState(_ mutate: (inout PersistedAppState) -> Void) {
        mutate(&state)
        store.saveAppState(state)
    }

    private func fail(_ message: String) {
        lastError = message
        statusMessage = "Action failed"
        logger.error("\(message, privacy: .public)")
    }
}
