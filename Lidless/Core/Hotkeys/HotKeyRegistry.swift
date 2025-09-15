import Carbon
import Foundation
import OSLog

final class HotKeyRegistry {
    private enum HotKeyID: UInt32 {
        case toggle = 1
        case restore = 2
    }

    private let logger = Logger(subsystem: "app.lidless.Lidless", category: "HotKeys")
    private let toggle: () -> Void
    private let restoreAndPause: () -> Void
    private var toggleRef: EventHotKeyRef?
    private var restoreRef: EventHotKeyRef?
    private var handlerRef: EventHandlerRef?

    init(toggle: @escaping () -> Void, restoreAndPause: @escaping () -> Void) {
        self.toggle = toggle
        self.restoreAndPause = restoreAndPause
    }

    func register() {
        let eventSpec = [
            EventTypeSpec(
                eventClass: OSType(kEventClassKeyboard),
                eventKind: UInt32(kEventHotKeyPressed)
            )
        ]

        let selfPointer = Unmanaged.passUnretained(self).toOpaque()
        let handler: EventHandlerUPP = { _, event, userData in
            guard let event, let userData else { return noErr }
            var hotKeyID = EventHotKeyID()
            GetEventParameter(
                event,
                UInt32(kEventParamDirectObject),
                UInt32(typeEventHotKeyID),
                nil,
                MemoryLayout<EventHotKeyID>.size,
                nil,
                &hotKeyID
            )

            let registry = Unmanaged<HotKeyRegistry>
                .fromOpaque(userData)
                .takeUnretainedValue()

            DispatchQueue.main.async {
                switch HotKeyID(rawValue: hotKeyID.id) {
                case .toggle:
                    registry.toggle()
                case .restore:
                    registry.restoreAndPause()
                case .none:
                    break
                }
            }

            return noErr
        }

        let handlerStatus = InstallEventHandler(
            GetApplicationEventTarget(),
            handler,
            1,
            eventSpec,
            selfPointer,
            &handlerRef
        )
        guard handlerStatus == noErr else {
            logger.error("Could not install hotkey handler: \(handlerStatus)")
            return
        }

        let signature = OSType(0x4C646C73) // "Ldls"
        let toggleStatus = RegisterEventHotKey(
            UInt32(kVK_ANSI_D),
            UInt32(cmdKey | controlKey),
            EventHotKeyID(signature: signature, id: HotKeyID.toggle.rawValue),
            GetApplicationEventTarget(),
            0,
            &toggleRef
        )
        let restoreStatus = RegisterEventHotKey(
            UInt32(kVK_ANSI_R),
            UInt32(cmdKey | optionKey | controlKey),
            EventHotKeyID(signature: signature, id: HotKeyID.restore.rawValue),
            GetApplicationEventTarget(),
            0,
            &restoreRef
        )

        if toggleStatus != noErr {
            logger.error("Could not register toggle hotkey: \(toggleStatus)")
        }
        if restoreStatus != noErr {
            logger.error("Could not register restore hotkey: \(restoreStatus)")
        }
        if toggleStatus == noErr && restoreStatus == noErr {
            logger.info("Registered hotkeys")
        } else {
            logger.warning("Hotkeys registered partially")
        }
    }

    func unregister() {
        if let toggleRef {
            UnregisterEventHotKey(toggleRef)
        }
        if let restoreRef {
            UnregisterEventHotKey(restoreRef)
        }
        if let handlerRef {
            RemoveEventHandler(handlerRef)
        }
    }
}
