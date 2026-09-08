import AppKit
import Carbon
import SwiftUI

struct SettingsView: View {
    @Bindable var state: AppState
    @State private var isRecordingShortcut = false
    @State private var loginError: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header
            options
            speedTest
            shortcut
            if LoginItemService.needsApproval {
                Text("Allow Fast Internet Summary in System Settings → General → Login Items.")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let loginError {
                Text(loginError)
                    .font(.system(size: 11))
                    .foregroundStyle(.orange)
            }
            Button {
                NSApp.terminate(nil)
            } label: {
                Text("Quit Fast Internet Summary")
                    .font(.system(size: 13, weight: .semibold))
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .controlSize(.regular)
        }
        .padding(PanelMetrics.padding)
        .fixedSize(horizontal: false, vertical: true)
        .onAppear {
            state.refreshLoginItem()
        }
    }

    private var header: some View {
        HStack {
            Button {
                state.isShowingSettings = false
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 11, weight: .semibold))
                    Text("Settings")
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                }
            }
            .buttonStyle(.plain)
            Spacer()
            Button {
                state.closePanel()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .help("Close")
        }
    }

    private var options: some View {
        VStack(alignment: .leading, spacing: 10) {
            Toggle("Launch at login", isOn: launchAtLoginBinding)
            Toggle("Show live rates in menu bar", isOn: $state.settings.showLiveRatesInMenuBar)

            VStack(alignment: .leading, spacing: 6) {
                Text("Update interval")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                Picker("Update interval", selection: intervalBinding) {
                    Text("1s").tag(1.0)
                    Text("2s").tag(2.0)
                    Text("5s").tag(5.0)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(PanelCardBackground())
        .font(.system(size: 13))
    }

    private var speedTest: some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 4) {
                Toggle(
                    "Use Speedtest (Ookla)",
                    isOn: Binding(
                        get: { state.settings.useOoklaSpeedTest },
                        set: { state.setUseOoklaSpeedTest($0) }
                    )
                )
                    .disabled(!OoklaCLI.isAvailable && !state.settings.useOoklaSpeedTest)
                Text(ooklaCaption)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if !state.settings.useOoklaSpeedTest {
                VStack(alignment: .leading, spacing: 4) {
                    Toggle("Download and upload together", isOn: $state.settings.simultaneousSpeedTest)
                    Text("Both directions at once. Results can differ from Speedtest.")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(PanelCardBackground())
        .font(.system(size: 13))
    }

    private var ooklaCaption: String {
        if OoklaCLI.isAvailable {
            return "Same engine as the Speedtest app. Uses the official CLI on this Mac."
        }
        if state.settings.useOoklaSpeedTest {
            return "Speedtest CLI is not installed. Turn this off, or install it with brew tap teamookla/speedtest && brew install speedtest."
        }
        return "Optional. Install with brew tap teamookla/speedtest && brew install speedtest."
    }

    private var shortcut: some View {
        VStack(alignment: .leading, spacing: 12) {
            shortcutRow(
                title: "Open / toggle",
                isRecording: isRecordingShortcut,
                display: HotkeyDisplay.string(keyCode: state.settings.hotkeyKeyCode, modifiers: state.settings.hotkeyModifiers),
                hint: "Default is Option-Command-Period (⌥⌘.). Escape closes the panel."
            ) {
                isRecordingShortcut.toggle()
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(PanelCardBackground())
        .background {
            if isRecordingShortcut {
                ShortcutCatcher { keyCode, modifiers in
                    state.setHotkey(keyCode: keyCode, modifiers: modifiers)
                    isRecordingShortcut = false
                } onCancel: {
                    isRecordingShortcut = false
                }
                .frame(width: 0, height: 0)
            }
        }
    }

    private func shortcutRow(title: String, isRecording: Bool, display: String, hint: String, toggle: @escaping () -> Void) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)

            HStack {
                Text(isRecording ? "Press a shortcut…" : display)
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .monospaced()
                    .frame(maxWidth: .infinity, alignment: .leading)

                Button(isRecording ? "Cancel" : "Change") {
                    toggle()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }

            Text(hint)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var launchAtLoginBinding: Binding<Bool> {
        Binding(
            get: { state.launchAtLogin },
            set: { enabled in
                state.setLaunchAtLogin(enabled)
                if LoginItemService.needsApproval {
                    loginError = "macOS needs approval before launch at login can turn on."
                } else {
                    loginError = nil
                }
            }
        )
    }

    private var intervalBinding: Binding<Double> {
        Binding(
            get: { state.settings.sampleInterval },
            set: { state.setSampleInterval($0) }
        )
    }
}

private struct ShortcutCatcher: NSViewRepresentable {
    var onCapture: (UInt32, UInt32) -> Void
    var onCancel: () -> Void

    func makeNSView(context: Context) -> CatcherView {
        let view = CatcherView()
        view.onCapture = onCapture
        view.onCancel = onCancel
        DispatchQueue.main.async {
            view.window?.makeFirstResponder(view)
        }
        return view
    }

    func updateNSView(_ nsView: CatcherView, context: Context) {
        nsView.onCapture = onCapture
        nsView.onCancel = onCancel
        DispatchQueue.main.async {
            nsView.window?.makeFirstResponder(nsView)
        }
    }

    final class CatcherView: NSView {
        var onCapture: ((UInt32, UInt32) -> Void)?
        var onCancel: (() -> Void)?

        override var acceptsFirstResponder: Bool { true }

        override func keyDown(with event: NSEvent) {
            if event.keyCode == 53 {
                onCancel?()
                return
            }

            let modifiers = HotkeyDisplay.carbonModifiers(from: event.modifierFlags)
            let hasStickyModifier = modifiers & UInt32(cmdKey | controlKey) != 0
            guard hasStickyModifier else { return }
            onCapture?(UInt32(event.keyCode), modifiers)
        }
    }
}
