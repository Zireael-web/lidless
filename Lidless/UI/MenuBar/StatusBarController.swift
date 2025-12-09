import AppKit
import Combine
import SwiftUI

final class StatusBarController: NSObject, NSPopoverDelegate {
    private let supervisor: DisplaySupervisor
    private let statusItem: NSStatusItem
    private let popover = NSPopover()
    private let popoverInset: CGFloat = 8
    private var cancellables = Set<AnyCancellable>()

    init(supervisor: DisplaySupervisor) {
        self.supervisor = supervisor
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        super.init()

        setupStatusItem()
        setupPopover()
        bindState()
    }

    private func setupStatusItem() {
        guard let button = statusItem.button else { return }
        button.target = self
        button.action = #selector(togglePopover)
        button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        updateStatusIcon()
    }

    private func setupPopover() {
        popover.behavior = .transient
        popover.animates = true
        popover.delegate = self
    }

    private func bindState() {
        supervisor.objectWillChange
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                DispatchQueue.main.async {
                    self?.updateStatusIcon()
                    self?.clampPopoverToVisibleScreen()
                }
            }
            .store(in: &cancellables)
    }

    @objc private func togglePopover() {
        if popover.isShown {
            popover.performClose(nil)
            return
        }

        supervisor.refreshDisplayInfo()
        LaunchAgentController.shared.refresh()
        popover.contentViewController = NSHostingController(
            rootView: PopoverView(
                supervisor: supervisor,
                launchAgent: LaunchAgentController.shared,
                quit: { NSApp.terminate(nil) },
                reposition: { [weak self] in
                    self?.schedulePopoverClamp()
                }
            )
        )

        if let button = statusItem.button {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            schedulePopoverClamp()
        }
    }

    func popoverDidClose(_ notification: Notification) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            self.popover.contentViewController = nil
        }
    }

    private func updateStatusIcon() {
        guard let button = statusItem.button else { return }
        button.image = MenuBarIcon.make(isOff: supervisor.isInternalOff, canDisable: supervisor.canDisable)
        if !supervisor.appEnabled {
            button.toolTip = "Lidless: paused"
        } else {
            button.toolTip = supervisor.isInternalOff
                ? "Lidless: built-in display off"
                : "Lidless: built-in display on"
        }
    }

    private func schedulePopoverClamp() {
        DispatchQueue.main.async { [weak self] in
            self?.clampPopoverToVisibleScreen()
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
            self?.clampPopoverToVisibleScreen()
        }
    }

    private func clampPopoverToVisibleScreen() {
        guard popover.isShown,
              let window = popover.contentViewController?.view.window else {
            return
        }

        let screen = window.screen ?? statusItem.button?.window?.screen ?? NSScreen.main
        guard let screen else { return }

        let visibleFrame = screen.visibleFrame.insetBy(dx: popoverInset, dy: popoverInset)
        var frame = window.frame

        if frame.width > visibleFrame.width {
            frame.size.width = visibleFrame.width
        }
        if frame.height > visibleFrame.height {
            frame.size.height = visibleFrame.height
        }

        frame.origin.x = min(max(frame.origin.x, visibleFrame.minX), visibleFrame.maxX - frame.width)
        frame.origin.y = min(max(frame.origin.y, visibleFrame.minY), visibleFrame.maxY - frame.height)

        if window.frame != frame {
            window.setFrame(frame, display: true, animate: false)
        }
    }
}

enum MenuBarIcon {
    static func make(isOff: Bool, canDisable: Bool) -> NSImage {
        let size = NSSize(width: 18, height: 18)
        let image = NSImage(size: size)
        image.lockFocus()
        defer { image.unlockFocus() }

        NSColor.clear.setFill()
        NSRect(origin: .zero, size: size).fill()

        let stroke = NSColor.labelColor
        stroke.setStroke()

        let screen = NSBezierPath(roundedRect: NSRect(x: 3, y: 7, width: 12, height: 8), xRadius: 1.5, yRadius: 1.5)
        screen.lineWidth = 1.5
        screen.stroke()

        let base = NSBezierPath()
        base.move(to: NSPoint(x: 2, y: 5))
        base.line(to: NSPoint(x: 16, y: 5))
        base.lineWidth = 1.5
        base.stroke()

        let stem = NSBezierPath()
        stem.move(to: NSPoint(x: 9, y: 7))
        stem.line(to: NSPoint(x: 9, y: 5))
        stem.lineWidth = 1.2
        stem.stroke()

        if isOff {
            NSColor.systemRed.setStroke()
            let slash = NSBezierPath()
            slash.move(to: NSPoint(x: 4, y: 15))
            slash.line(to: NSPoint(x: 14, y: 4))
            slash.lineWidth = 2
            slash.stroke()
        } else if canDisable {
            NSColor.systemGreen.setFill()
            NSBezierPath(ovalIn: NSRect(x: 12.5, y: 12.5, width: 4, height: 4)).fill()
        }

        image.isTemplate = false
        return image
    }
}
