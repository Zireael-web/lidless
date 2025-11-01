import CoreGraphics
import Darwin
import Foundation
import OSLog

enum PrivateDisplayAPIError: LocalizedError {
    case symbolUnavailable
    case beginConfigurationFailed(String, CGError)
    case configureFailed(String, CGError)
    case completeFailed(String, CGError)

    var errorDescription: String? {
        switch self {
        case .symbolUnavailable:
            return "Display enable/disable API is unavailable on this macOS build."
        case .beginConfigurationFailed(let path, let error):
            return "Could not begin display configuration via \(path): \(error.rawValue)."
        case .configureFailed(let path, let error):
            return "Could not change display state via \(path): \(error.rawValue)."
        case .completeFailed(let path, let error):
            return "Could not commit display configuration via \(path): \(error.rawValue)."
        }
    }
}

final class PrivateDisplayAPI {
    static let shared = PrivateDisplayAPI()

    private typealias BeginDisplayConfiguration = @convention(c) (
        UnsafeMutablePointer<CGDisplayConfigRef?>?
    ) -> CGError
    private typealias CompleteDisplayConfiguration = @convention(c) (
        CGDisplayConfigRef?,
        CGConfigureOption
    ) -> CGError
    private typealias CancelDisplayConfiguration = @convention(c) (
        CGDisplayConfigRef?
    ) -> CGError
    private typealias ConfigureDisplayEnabledInt = @convention(c) (
        CGDisplayConfigRef?,
        CGDirectDisplayID,
        Int32
    ) -> CGError
    private typealias ConfigureDisplayEnabledBool = @convention(c) (
        CGDisplayConfigRef?,
        CGDirectDisplayID,
        Bool
    ) -> CGError

    private enum ConfigureSignature: String {
        case int32 = "Int32"
        case bool = "Bool"
    }

    private struct TransactionAPI {
        let name: String
        let begin: BeginDisplayConfiguration
        let complete: CompleteDisplayConfiguration
        let cancel: CancelDisplayConfiguration
    }

    private struct ConfigureCandidate {
        let symbolName: String
        let frameworkPath: String
        let symbol: UnsafeMutableRawPointer
    }

    private let logger = Logger(subsystem: "app.lidless.Lidless", category: "PrivateDisplayAPI")
    private var transactionAPIs: [TransactionAPI] = []
    private var configureCandidates: [ConfigureCandidate] = []
    private(set) var resolvedSymbolName: String?
    private(set) var loadedFrameworkPaths: [String] = []
    private(set) var lastSuccessfulPath: String?

    var isAvailable: Bool {
        !transactionAPIs.isEmpty && !configureCandidates.isEmpty
    }

    private init() {
        let handles = loadFrameworks()
        resolveTransactionAPIs(handles: handles)
        resolveConfigureCandidates(handles: handles)
    }

    func setDisplay(_ displayID: CGDirectDisplayID, enabled: Bool) throws {
        guard isAvailable else {
            throw PrivateDisplayAPIError.symbolUnavailable
        }

        var lastError: PrivateDisplayAPIError?

        for transactionAPI in transactionAPIs {
            for candidate in configureCandidates {
                for signature in [ConfigureSignature.int32, .bool] {
                    let path = "\(transactionAPI.name)/\(candidate.symbolName)/\(signature.rawValue)"
                    do {
                        try apply(
                            displayID,
                            enabled: enabled,
                            transactionAPI: transactionAPI,
                            candidate: candidate,
                            signature: signature,
                            path: path
                        )
                        resolvedSymbolName = candidate.symbolName
                        lastSuccessfulPath = path
                        logger.info("Display state changed via \(path, privacy: .public)")
                        return
                    } catch let error as PrivateDisplayAPIError {
                        lastError = error
                        logger.debug("Display state path failed: \(path, privacy: .public) \(error.localizedDescription, privacy: .public)")
                    }
                }
            }
        }

        throw lastError ?? PrivateDisplayAPIError.symbolUnavailable
    }

    private func loadFrameworks() -> [(path: String, handle: UnsafeMutableRawPointer)] {
        let frameworkPaths = [
            "/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight",
            "/System/Library/Frameworks/CoreGraphics.framework/CoreGraphics",
            "/System/Library/Frameworks/CoreDisplay.framework/CoreDisplay",
            "/System/Library/PrivateFrameworks/CoreDisplay.framework/CoreDisplay",
            "/System/Library/PrivateFrameworks/DisplayServices.framework/DisplayServices"
        ]

        return frameworkPaths.compactMap { path in
            guard let handle = dlopen(path, RTLD_LAZY) else { return nil }
            loadedFrameworkPaths.append(path)
            logger.info("Loaded display framework: \(path, privacy: .public)")
            return (path, handle)
        }
    }

    private func resolveTransactionAPIs(handles: [(path: String, handle: UnsafeMutableRawPointer)]) {
        if let skyLight = handles.first(where: { $0.path.contains("SkyLight.framework") })?.handle,
           let beginSymbol = dlsym(skyLight, "SLSBeginDisplayConfiguration"),
           let completeSymbol = dlsym(skyLight, "SLSCompleteDisplayConfiguration"),
           let cancelSymbol = dlsym(skyLight, "SLSCancelDisplayConfiguration") {
            transactionAPIs.append(TransactionAPI(
                name: "SLS",
                begin: unsafeBitCast(beginSymbol, to: BeginDisplayConfiguration.self),
                complete: unsafeBitCast(completeSymbol, to: CompleteDisplayConfiguration.self),
                cancel: unsafeBitCast(cancelSymbol, to: CancelDisplayConfiguration.self)
            ))
        }

        transactionAPIs.append(TransactionAPI(
            name: "CG",
            begin: CGBeginDisplayConfiguration,
            complete: CGCompleteDisplayConfiguration,
            cancel: CGCancelDisplayConfiguration
        ))
    }

    private func resolveConfigureCandidates(handles: [(path: String, handle: UnsafeMutableRawPointer)]) {
        let symbolNames = ["SLSConfigureDisplayEnabled", "CGSConfigureDisplayEnabled"]
        var seen = Set<String>()

        for symbolName in symbolNames {
            for (path, handle) in handles {
                guard let symbol = dlsym(handle, symbolName) else { continue }
                let key = "\(symbolName)@\(path)"
                guard seen.insert(key).inserted else { continue }
                configureCandidates.append(ConfigureCandidate(
                    symbolName: symbolName,
                    frameworkPath: path,
                    symbol: symbol
                ))
                if resolvedSymbolName == nil {
                    resolvedSymbolName = symbolName
                }
                logger.info("Resolved private display API: \(symbolName, privacy: .public) in \(path, privacy: .public)")
            }

            if let symbol = dlsym(nil, symbolName) {
                let key = "\(symbolName)@process"
                guard seen.insert(key).inserted else { continue }
                configureCandidates.append(ConfigureCandidate(
                    symbolName: symbolName,
                    frameworkPath: "process",
                    symbol: symbol
                ))
                if resolvedSymbolName == nil {
                    resolvedSymbolName = symbolName
                }
                logger.info("Resolved private display API from process: \(symbolName, privacy: .public)")
            }
        }

        if configureCandidates.isEmpty {
            logger.error("No private display enable/disable symbol was found")
        }
    }

    private func apply(
        _ displayID: CGDirectDisplayID,
        enabled: Bool,
        transactionAPI: TransactionAPI,
        candidate: ConfigureCandidate,
        signature: ConfigureSignature,
        path: String
    ) throws {
        var config: CGDisplayConfigRef?
        var result = transactionAPI.begin(&config)
        guard result == .success, let config else {
            if displayAlreadyMatches(displayID, enabled: enabled) {
                return
            }
            throw PrivateDisplayAPIError.beginConfigurationFailed(path, result)
        }

        switch signature {
        case .int32:
            let fn = unsafeBitCast(candidate.symbol, to: ConfigureDisplayEnabledInt.self)
            result = fn(config, displayID, enabled ? 1 : 0)
        case .bool:
            let fn = unsafeBitCast(candidate.symbol, to: ConfigureDisplayEnabledBool.self)
            result = fn(config, displayID, enabled)
        }

        guard result == .success else {
            _ = transactionAPI.cancel(config)
            if displayAlreadyMatches(displayID, enabled: enabled) {
                return
            }
            throw PrivateDisplayAPIError.configureFailed(path, result)
        }

        result = transactionAPI.complete(config, .forSession)
        guard result == .success else {
            _ = transactionAPI.cancel(config)
            if displayAlreadyMatches(displayID, enabled: enabled) {
                return
            }
            throw PrivateDisplayAPIError.completeFailed(path, result)
        }
    }

    private func displayAlreadyMatches(_ displayID: CGDirectDisplayID, enabled: Bool) -> Bool {
        let isActive = CGDisplayIsActive(displayID) != 0
        if enabled {
            return isActive
        }
        return !isActive
    }
}
