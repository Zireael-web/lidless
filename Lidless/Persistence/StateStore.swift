import CoreGraphics
import Foundation

struct DisplayLease: Codable {
    var desiredInternalOff: Bool
    var internalDisplayID: UInt32?
    var leaseExpiresAt: Date
    var generation: Int
    var updatedByPID: Int32
}

struct PersistedAppState: Codable, Equatable {
    var appEnabled: Bool
    var autoMode: Bool
    var reapplyAfterWake: Bool
    var internalDisplayID: UInt32?
    var internalDisabledByApp: Bool
    var internalDisablePendingByApp: Bool
    var wasDisabledBeforeSleep: Bool
    var lastCleanShutdown: Bool

    static let fresh = PersistedAppState(
        appEnabled: true,
        autoMode: true,
        reapplyAfterWake: true,
        internalDisplayID: nil,
        internalDisabledByApp: false,
        internalDisablePendingByApp: false,
        wasDisabledBeforeSleep: false,
        lastCleanShutdown: true
    )
}

final class StateStore {
    static let shared = StateStore()

    private let defaults = UserDefaults.standard
    private let cachedInternalDisplayIDKey = "CachedInternalDisplayID"
    private let generationKey = "LeaseGeneration"
    private let stateFallbackActiveKey = "StateFallbackActive"

    private var supportDirectory: URL {
        FileManager.default
            .homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/Lidless", isDirectory: true)
    }

    private var leaseURL: URL {
        supportDirectory.appendingPathComponent("display-lease.json")
    }

    private var stateURL: URL {
        supportDirectory.appendingPathComponent("state.json")
    }

    private var internalIDBackupURL: URL {
        supportDirectory.appendingPathComponent("internal-display-id.txt")
    }

    private init() {}

    func saveCachedInternalDisplayID(_ id: CGDirectDisplayID) {
        defaults.set(Int(id), forKey: cachedInternalDisplayIDKey)
        try? ensureSupportDirectory()
        try? String(id).write(to: internalIDBackupURL, atomically: true, encoding: .utf8)
    }

    func saveAppState(_ state: PersistedAppState) {
        do {
            try ensureSupportDirectory()
            let data = try JSONEncoder.lidless.encode(state)
            try data.write(to: stateURL, options: [.atomic])
            if let id = state.internalDisplayID {
                saveCachedInternalDisplayID(CGDirectDisplayID(id))
            }
            defaults.set(false, forKey: stateFallbackActiveKey)
        } catch {
            defaults.set(true, forKey: stateFallbackActiveKey)
            defaults.set(state.appEnabled, forKey: "AppEnabled")
            defaults.set(state.autoMode, forKey: "AutoMode")
            defaults.set(state.reapplyAfterWake, forKey: "ReapplyAfterWake")
            defaults.set(state.internalDisabledByApp, forKey: "InternalDisabledByApp")
            defaults.set(state.internalDisablePendingByApp, forKey: "InternalDisablePendingByApp")
            defaults.set(state.wasDisabledBeforeSleep, forKey: "WasDisabledBeforeSleep")
            defaults.set(state.lastCleanShutdown, forKey: "LastCleanShutdown")
            if let id = state.internalDisplayID {
                defaults.set(Int(id), forKey: cachedInternalDisplayIDKey)
            }
        }
    }

    func loadAppState() -> PersistedAppState {
        if defaults.bool(forKey: stateFallbackActiveKey) == false,
           let data = try? Data(contentsOf: stateURL),
           var state = try? JSONDecoder.lidless.decode(PersistedAppState.self, from: data) {
            if state.internalDisplayID == nil {
                state.internalDisplayID = loadCachedInternalDisplayID()
            }
            return state
        }

        return loadDefaultsAppState()
    }

    private func loadDefaultsAppState() -> PersistedAppState {
        var state = PersistedAppState.fresh
        if defaults.object(forKey: "AppEnabled") != nil {
            state.appEnabled = defaults.bool(forKey: "AppEnabled")
        }
        if defaults.object(forKey: "AutoMode") != nil {
            state.autoMode = defaults.bool(forKey: "AutoMode")
        }
        if defaults.object(forKey: "ReapplyAfterWake") != nil {
            state.reapplyAfterWake = defaults.bool(forKey: "ReapplyAfterWake")
        }
        state.internalDisplayID = loadCachedInternalDisplayID()
        state.internalDisabledByApp = defaults.bool(forKey: "InternalDisabledByApp")
        state.internalDisablePendingByApp = defaults.bool(forKey: "InternalDisablePendingByApp")
        state.wasDisabledBeforeSleep = defaults.bool(forKey: "WasDisabledBeforeSleep")
        state.lastCleanShutdown = defaults.object(forKey: "LastCleanShutdown") as? Bool ?? true
        return state
    }

    @discardableResult
    func updateAppState(_ transform: (inout PersistedAppState) -> Void) -> PersistedAppState {
        var state = loadAppState()
        transform(&state)
        saveAppState(state)
        return state
    }

    func loadCachedInternalDisplayID() -> CGDirectDisplayID? {
        if let value = defaults.object(forKey: cachedInternalDisplayIDKey) as? Int {
            return CGDirectDisplayID(value)
        }

        guard let text = try? String(contentsOf: internalIDBackupURL, encoding: .utf8)
            .trimmingCharacters(in: .whitespacesAndNewlines),
              let value = UInt32(text) else {
            return nil
        }
        return CGDirectDisplayID(value)
    }

    @discardableResult
    func renewLease(internalDisplayID: CGDirectDisplayID?, ttl: TimeInterval = 30) -> DisplayLease? {
        let nextGeneration = defaults.integer(forKey: generationKey) + 1
        defaults.set(nextGeneration, forKey: generationKey)

        let lease = DisplayLease(
            desiredInternalOff: true,
            internalDisplayID: internalDisplayID,
            leaseExpiresAt: Date().addingTimeInterval(ttl),
            generation: nextGeneration,
            updatedByPID: ProcessInfo.processInfo.processIdentifier
        )

        do {
            try ensureSupportDirectory()
            let data = try JSONEncoder.lidless.encode(lease)
            try data.write(to: leaseURL, options: [.atomic])
            return lease
        } catch {
            return nil
        }
    }

    func readLease() -> DisplayLease? {
        guard let data = try? Data(contentsOf: leaseURL) else { return nil }
        return try? JSONDecoder.lidless.decode(DisplayLease.self, from: data)
    }

    func clearLease() {
        try? FileManager.default.removeItem(at: leaseURL)
    }

    private func ensureSupportDirectory() throws {
        try FileManager.default.createDirectory(
            at: supportDirectory,
            withIntermediateDirectories: true
        )
    }
}

private extension JSONEncoder {
    static var lidless: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }
}

private extension JSONDecoder {
    static var lidless: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
