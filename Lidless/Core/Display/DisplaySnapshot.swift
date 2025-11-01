import AppKit
import CoreGraphics
import Foundation

struct DisplayState: Identifiable, Equatable {
    let id: CGDirectDisplayID
    let name: String
    let isBuiltIn: Bool
    let isActive: Bool
    let isOnline: Bool
    let isMain: Bool
    let hasNSScreen: Bool
    let frame: CGRect
    let bounds: CGRect
    let modeDescription: String
    let isTrustedExternal: Bool

    var label: String {
        if isBuiltIn { return "Built-in" }
        return name.isEmpty ? "External Display" : name
    }
}

struct DisplaySnapshot: Equatable {
    let displays: [DisplayState]

    var activeBuiltIn: DisplayState? {
        displays.first { $0.isBuiltIn && $0.isActive }
    }

    var trustedExternalDisplays: [DisplayState] {
        displays.filter(\.isTrustedExternal)
    }

    var canDisableInternal: Bool {
        activeBuiltIn != nil && !trustedExternalDisplays.isEmpty
    }

    static func capture() -> DisplaySnapshot {
        let activeIDs = Set(displayIDs(from: CGGetActiveDisplayList))
        let onlineIDs = Set(displayIDs(from: CGGetOnlineDisplayList))
        let screens = NSScreen.screens
        let screenPairs: [(CGDirectDisplayID, NSScreen)] = screens.compactMap { screen in
            guard let id = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID else {
                return nil
            }
            return (id, screen)
        }
        var screenByID: [CGDirectDisplayID: NSScreen] = [:]
        for (id, screen) in screenPairs where screenByID[id] == nil {
            screenByID[id] = screen
        }

        let ids = Array(activeIDs.union(onlineIDs).union(screenByID.keys)).sorted()
        let states = ids.map { id -> DisplayState in
            let screen = screenByID[id]
            let name = screen?.localizedName.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let isBuiltIn = CGDisplayIsBuiltin(id) != 0
            let isActive = activeIDs.contains(id) || CGDisplayIsActive(id) != 0
            let isOnline = onlineIDs.contains(id) || CGDisplayIsOnline(id) != 0
            let isMain = CGDisplayIsMain(id) != 0
            let frame = screen?.frame ?? CGDisplayBounds(id)
            let bounds = CGDisplayBounds(id)
            let displayName = name.isEmpty ? (isBuiltIn ? "Built-in Display" : "Unknown External Display") : name
            let modeDescription = Self.modeDescription(for: id)
            let trusted = Self.isTrustedExternal(
                id: id,
                name: name,
                isBuiltIn: isBuiltIn,
                isActive: isActive,
                screen: screen,
                frame: frame
            )

            return DisplayState(
                id: id,
                name: displayName,
                isBuiltIn: isBuiltIn,
                isActive: isActive,
                isOnline: isOnline,
                isMain: isMain,
                hasNSScreen: screen != nil,
                frame: frame,
                bounds: bounds,
                modeDescription: modeDescription,
                isTrustedExternal: trusted
            )
        }

        return DisplaySnapshot(displays: states)
    }

    private static func displayIDs(
        from function: (UInt32, UnsafeMutablePointer<CGDirectDisplayID>?, UnsafeMutablePointer<UInt32>?) -> CGError
    ) -> [CGDirectDisplayID] {
        var count: UInt32 = 0
        guard function(0, nil, &count) == .success, count > 0 else { return [] }

        var ids = [CGDirectDisplayID](repeating: 0, count: Int(count))
        guard function(count, &ids, &count) == .success else { return [] }
        return Array(ids.prefix(Int(count)))
    }

    private static func isTrustedExternal(
        id: CGDirectDisplayID,
        name: String,
        isBuiltIn: Bool,
        isActive: Bool,
        screen: NSScreen?,
        frame: CGRect
    ) -> Bool {
        guard !isBuiltIn, isActive, screen != nil, frame.width > 0, frame.height > 0 else {
            return false
        }

        guard CGDisplayMirrorsDisplay(id) == kCGNullDirectDisplay else {
            return false
        }

        let lowercasedName = name.lowercased()
        guard !lowercasedName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return false
        }

        let untrustedFragments = [
            "airplay",
            "sidecar",
            "ipad",
            "displaylink",
            "dummy",
            "virtual",
            "betterdummy"
        ]

        return !untrustedFragments.contains { lowercasedName.contains($0) }
    }

    private static func modeDescription(for id: CGDirectDisplayID) -> String {
        guard let mode = CGDisplayCopyDisplayMode(id) else { return "unknown" }
        let width = mode.width
        let height = mode.height
        let refreshRate = mode.refreshRate
        if refreshRate > 0 {
            return "\(width)x\(height) @ \(String(format: "%.0f", refreshRate))Hz"
        }
        return "\(width)x\(height)"
    }
}
