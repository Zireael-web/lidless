import CoreGraphics
import Foundation
import OSLog

@main
struct LidlessWatchdog {
    private static let logger = Logger(subsystem: "app.lidless.Lidless", category: "Watchdog")

    static func main() {
        logger.info("Watchdog started")

        while true {
            autoreleasepool {
                restoreIfLeaseExpired()
            }
            sleep(5)
        }
    }

    private static func restoreIfLeaseExpired() {
        guard let lease = StateStore.shared.readLease(),
              lease.desiredInternalOff,
              lease.leaseExpiresAt < Date() else {
            return
        }

        if lease.updatedByPID > 0, kill(lease.updatedByPID, 0) == 0 {
            // Owner process is still alive (e.g. right after system sleep);
            // it renews the lease and reconciles state itself.
            return
        }

        let id = lease.internalDisplayID ?? StateStore.shared.loadCachedInternalDisplayID()
        guard let id else {
            StateStore.shared.clearLease()
            logger.error("Lease expired, but no cached internal display ID exists")
            return
        }

        do {
            try PrivateDisplayAPI.shared.setDisplay(id, enabled: true)
            StateStore.shared.clearLease()
            logger.warning("Restored built-in display after stale lease")
        } catch {
            logger.error("Failed to restore built-in display after stale lease: \(error.localizedDescription, privacy: .public)")
        }
    }
}
