import SwiftUI

struct PopoverView: View {
    @ObservedObject var supervisor: DisplaySupervisor
    @ObservedObject var launchAgent: LaunchAgentController
    let quit: () -> Void
    let reposition: () -> Void

    @State private var showDiagnostics = false

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            statusGrid
            Divider()
            actionArea
            Divider()
            settingsArea
            Divider()
            displayList
            if showDiagnostics {
                Divider()
                diagnosticsArea
            }
            Divider()
            footer
        }
        .frame(width: 340)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var header: some View {
        HStack(spacing: 10) {
            ZStack {
                RoundedRectangle(cornerRadius: 7)
                    .fill(headerColor.opacity(0.16))
                Image(systemName: headerIcon)
                    .font(.system(size: 19, weight: .semibold))
                    .foregroundStyle(headerColor)
            }
            .frame(width: 38, height: 38)

            VStack(alignment: .leading, spacing: 3) {
                Text("Lidless")
                    .font(.system(size: 16, weight: .semibold))
                Text(supervisor.statusMessage)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()
        }
        .padding(14)
    }

    private var statusGrid: some View {
        Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 7) {
            statusRow("App", supervisor.appEnabled ? "Enabled" : "Paused")
            statusRow("Auto Mode", supervisor.autoMode ? "On" : "Off")
            statusRow("Internal Display", supervisor.internalDisplayStateLabel)
            statusRow("External Displays", "\(supervisor.trustedExternalCount) active")
        }
        .font(.system(size: 12))
        .padding(14)
    }

    private func statusRow(_ label: String, _ value: String) -> some View {
        GridRow {
            Text(label)
                .foregroundStyle(.secondary)
            Text(value)
                .fontWeight(.medium)
        }
    }

    @ViewBuilder
    private var actionArea: some View {
        VStack(spacing: 10) {
            if supervisor.needsConfirmation {
                HStack(spacing: 8) {
                    Button {
                        supervisor.confirmInternalOff()
                    } label: {
                        Label("Keep Off", systemImage: "checkmark.circle.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .keyboardShortcut(.defaultAction)

                    Button {
                        supervisor.restoreAndPauseApp()
                    } label: {
                        Label("Restore & Pause", systemImage: "pause.circle.fill")
                            .frame(maxWidth: .infinity)
                    }
                }

                Text("Auto-restore in \(supervisor.confirmationSecondsRemaining)s")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
                    .id(supervisor.uiTick)
            } else if supervisor.isInternalOff {
                HStack(spacing: 8) {
                    Button {
                        _ = supervisor.restoreInternalDisplay(reason: "Manual restore")
                    } label: {
                        Label("Restore", systemImage: "display")
                            .frame(maxWidth: .infinity)
                    }
                    .controlSize(.large)

                    Button {
                        supervisor.restoreAndPauseApp()
                    } label: {
                        Label("Pause", systemImage: "pause.circle")
                            .frame(maxWidth: .infinity)
                    }
                    .controlSize(.large)
                }
            } else if supervisor.appEnabled {
                Button {
                    supervisor.disableInternalDisplay()
                } label: {
                    Label("Turn Off Built-in Now", systemImage: "power.circle.fill")
                        .frame(maxWidth: .infinity)
                }
                .controlSize(.large)
                .disabled(!supervisor.canDisable)

                Button {
                    supervisor.restoreAndPauseApp()
                } label: {
                    Label("Restore & Pause App", systemImage: "pause.circle")
                        .frame(maxWidth: .infinity)
                }
            } else {
                Button {
                    supervisor.resumeAutoMode()
                } label: {
                    Label("Resume Auto Mode", systemImage: "play.circle.fill")
                        .frame(maxWidth: .infinity)
                }
                .controlSize(.large)
            }

            if let error = supervisor.lastError {
                Text(error)
                    .font(.system(size: 12))
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(14)
    }

    private var settingsArea: some View {
        VStack(spacing: 9) {
            Toggle(isOn: Binding(
                get: { supervisor.autoMode },
                set: { supervisor.setAutoMode($0) }
            )) {
                Label("Auto-disable on external display", systemImage: "bolt.display")
            }
            .toggleStyle(.switch)
            .disabled(!supervisor.appEnabled && !supervisor.autoMode)

            Toggle(isOn: Binding(
                get: { supervisor.reapplyAfterWake },
                set: { supervisor.setReapplyAfterWake($0) }
            )) {
                Label("Re-apply after wake", systemImage: "moon.zzz")
            }
            .toggleStyle(.switch)

            Toggle(isOn: Binding(
                get: { launchAgent.isEnabled },
                set: { value in
                    try? launchAgent.setEnabled(value)
                }
            )) {
                Label("Launch at Login", systemImage: "arrow.clockwise.circle")
            }
            .toggleStyle(.switch)
        }
        .font(.system(size: 13))
        .padding(14)
    }

    private var displayList: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Displays")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                Text("\(supervisor.trustedExternalCount) external")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }

            ForEach(supervisor.snapshot.displays) { display in
                HStack(spacing: 9) {
                    Image(systemName: display.isBuiltIn ? "laptopcomputer" : "display")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(display.isTrustedExternal ? .green : .secondary)
                        .frame(width: 18)

                    Text(display.label)
                        .font(.system(size: 13))
                        .lineLimit(1)

                    Spacer()

                    Text(display.isActive ? "Active" : "Online")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(display.isActive ? .primary : .secondary)
                }
            }
        }
        .padding(14)
    }

    private var diagnosticsArea: some View {
        VStack(alignment: .leading, spacing: 8) {
            ScrollView {
                Text(supervisor.diagnosticsText)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
            }
            .frame(maxHeight: 180)

            Button {
                supervisor.copyDiagnosticsToPasteboard()
            } label: {
                Label("Copy Diagnostics", systemImage: "doc.on.doc")
                    .frame(maxWidth: .infinity)
            }
        }
        .padding(14)
    }

    private var footer: some View {
        HStack(spacing: 8) {
            Button {
                supervisor.refreshDisplayInfo()
            } label: {
                Image(systemName: "arrow.clockwise")
                    .frame(width: 20)
            }
            .help("Refresh")

            Button {
                showDiagnostics.toggle()
                reposition()
            } label: {
                Image(systemName: "stethoscope")
                    .frame(width: 20)
            }
            .help("Diagnostics")

            Button {
                supervisor.restoreAndPauseApp()
            } label: {
                Image(systemName: "cross.case")
                    .frame(width: 20)
            }
            .help("Restore & Pause")

            Spacer()

            Button {
                quit()
            } label: {
                Label("Quit & Restore", systemImage: "power")
            }
        }
        .padding(14)
    }

    private var headerIcon: String {
        if !supervisor.appEnabled { return "pause.circle" }
        return supervisor.isInternalOff ? "laptopcomputer.slash" : "laptopcomputer"
    }

    private var headerColor: Color {
        if !supervisor.appEnabled { return .orange }
        return supervisor.isInternalOff ? .red : .green
    }
}
