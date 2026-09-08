import AppKit
import SwiftUI

enum PanelMetrics {
    static let width: CGFloat = 340
    static let padding: CGFloat = 16
}

struct RootPanel: View {
    @Bindable var state: AppState
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.controlActiveState) private var controlActiveState

    private var isParked: Bool { controlActiveState != .key }

    var body: some View {
        Group {
            if state.isShowingSettings {
                SettingsView(state: state)
            } else {
                PanelView(state: state)
            }
        }
        .id(state.isShowingSettings)
        .frame(width: PanelMetrics.width)
        .fixedSize(horizontal: false, vertical: true)
        .background {
            Color.black.opacity(isParked ? parkedTint : 0)
        }
        .background(PopoverChromeLock())
        .environment(\.controlActiveState, .key)
        .preferredColorScheme(nil)
    }

    private var parkedTint: Double {
        colorScheme == .dark ? 0.06 : 0.03
    }
}

struct PanelView: View {
    @Bindable var state: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header
            connectionBlock
            liveActivityBlock
            speedTestBlock
            runButton
        }
        .padding(PanelMetrics.padding)
    }

    private var header: some View {
        HStack(spacing: 8) {
            Text("Fast Internet Summary")
                .font(.system(size: 15, weight: .semibold, design: .rounded))
            Button {
                state.isShowingSettings = true
            } label: {
                Image(systemName: "gearshape")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .help("Settings")
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

    private var connectionBlock: some View {
        let ordered = state.snapshot.ordered
        return VStack(alignment: .leading, spacing: 12) {
            ConnectionRow(info: ordered.primary, emphasized: true)
            ConnectionRow(info: ordered.secondary, emphasized: false)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(PanelCardBackground())
    }

    private var liveActivityBlock: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionLabel(title: "Live Activity")
            HStack(alignment: .firstTextBaseline) {
                RateColumn(
                    symbol: "arrow.down",
                    value: ByteRateFormat.string(bytesPerSecond: state.rates.downloadBytesPerSecond)
                )
                Spacer()
                RateColumn(
                    symbol: "arrow.up",
                    value: ByteRateFormat.string(bytesPerSecond: state.rates.uploadBytesPerSecond),
                    alignment: .trailing
                )
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(PanelCardBackground())
    }

    private var speedTestBlock: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionLabel(title: speedTestMethodTitle)
            if state.speedTest.lastResult != nil || state.speedTest.isRunning {
                SpeedMetricsRow(speedTest: state.speedTest)

                if let checkedAt = state.speedTest.lastCheckedAt {
                    TimelineView(.periodic(from: .now, by: 15)) { timeline in
                        Text(RelativeTimeFormat.checkedPhrase(from: checkedAt, now: timeline.date))
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                }
            } else {
                Text("No test yet")
                    .font(.system(size: 12.5))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(PanelCardBackground())
    }

    private var speedTestMethodTitle: String {
        if state.speedTest.isRunning {
            return SpeedTestResult.methodTitle(for: state.speedTest.providerName)
        }
        if let source = state.speedTest.lastResult?.source {
            return SpeedTestResult.methodTitle(for: source)
        }
        return SpeedTestResult.methodTitle(
            for: state.settings.useOoklaSpeedTest ? "speedtest" : "networkQuality"
        )
    }

    @ViewBuilder
    private var runButton: some View {
        Group {
            if state.speedTest.isRunning {
                VStack(spacing: 8) {
                    Text("\(state.speedTest.progressPercent)% complete")
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)

                    ProgressView(value: state.speedTest.percentComplete)
                        .progressViewStyle(.linear)

                    Text(state.speedTest.stageLine)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                        .animation(.easeInOut(duration: 0.2), value: state.speedTest.stageLine)
                }
                .padding(.vertical, 2)
                .transition(.opacity)
            } else {
                Button {
                    state.runSpeedTest()
                } label: {
                    Text("Run again")
                        .font(.system(size: 13, weight: .semibold))
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .controlSize(.regular)
                .disabled(state.speedTest.isRunning)
                .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.25), value: state.speedTest.isRunning)
    }
}

private struct SpeedMetricsRow: View {
    var speedTest: SpeedTestRunner

    var body: some View {
        let result = speedTest.lastResult
        Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 2) {
            GridRow {
                metricLabel("Download")
                metricLabel("Upload")
                Color.clear.gridCellUnsizedAxes(.vertical)
            }
            GridRow(alignment: .firstTextBaseline) {
                speedFigure(
                    result?.downloadMbps.map(ThroughputFormat.mbpsValue) ?? "—",
                    isStale: result != nil && speedTest.isDownloadStale
                )
                speedFigure(
                    result?.uploadMbps.map(ThroughputFormat.mbpsValue) ?? "—",
                    isStale: result != nil && speedTest.isUploadStale
                )
                Color.clear.gridCellUnsizedAxes(.vertical)
            }
            GridRow {
                pingFigure(
                    result?.downloadLatencyMs.map(ThroughputFormat.latency) ?? "— ms",
                    isStale: result?.downloadLatencyMs == nil || speedTest.isDownloadLatencyStale
                )
                pingFigure(
                    result?.uploadLatencyMs.map(ThroughputFormat.latency) ?? "— ms",
                    isStale: result?.uploadLatencyMs == nil || speedTest.isUploadLatencyStale
                )
                pingFigure(
                    result?.latencyMs.map(ThroughputFormat.latency) ?? "— ms",
                    isStale: result != nil && speedTest.isLatencyStale
                )
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func metricLabel(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 11, weight: .medium, design: .rounded))
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func speedFigure(_ value: String, isStale: Bool) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 4) {
            SpeedMetricText(text: value, isStale: isStale)
                .font(.system(size: 22, weight: .semibold, design: .rounded))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text("Mbps")
                .font(.system(size: 11, weight: .medium, design: .rounded))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func pingFigure(_ value: String, isStale: Bool) -> some View {
        SpeedMetricText(text: value, isStale: isStale)
            .font(.system(size: 14, weight: .medium, design: .rounded))
            .lineLimit(1)
            .padding(.top, 6)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct SpeedMetricText: View {
    var text: String
    var isStale: Bool

    var body: some View {
        Text(text)
            .monospacedDigit()
            .fontWeight(isStale ? .regular : .semibold)
            .foregroundStyle(.primary)
            .opacity(isStale ? 0.32 : 1)
            .compositingGroup()
    }
}

private struct ConnectionRow: View {
    var info: InterfaceInfo
    var emphasized: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            StatusDot(status: info.status)
                .padding(.top, 4)

            VStack(alignment: .leading, spacing: 2) {
                Text(info.kind.title)
                    .font(.system(size: 13, weight: emphasized ? .semibold : .medium))
                    .foregroundStyle(emphasized ? .primary : .secondary)
                Text(info.detailLine())
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .opacity(emphasized ? 1 : 0.78)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct StatusDot: View {
    var status: LinkStatus

    var body: some View {
        Circle()
            .fill(color)
            .frame(width: 7, height: 7)
            .shadow(color: color.opacity(status == .disconnected ? 0 : 0.45), radius: 2)
            .accessibilityLabel(Text(accessibilityName))
    }

    private var color: Color {
        switch status {
        case .inUse: Color.green
        case .connected: Color.secondary.opacity(0.55)
        case .noInternet: Color.orange
        case .disconnected: Color.secondary.opacity(0.28)
        }
    }

    private var accessibilityName: String {
        switch status {
        case .inUse: "In use"
        case .connected: "Connected"
        case .noInternet: "No internet"
        case .disconnected: "Disconnected"
        }
    }
}

private struct RateColumn: View {
    var symbol: String
    var value: String
    var alignment: HorizontalAlignment = .leading

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: symbol)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.system(size: 13, weight: .medium, design: .rounded))
                .monospacedDigit()
        }
        .frame(maxWidth: .infinity, alignment: alignment == .leading ? .leading : .trailing)
    }
}

private struct SectionLabel: View {
    var title: String

    var body: some View {
        Text(title)
            .font(.system(size: 10, weight: .semibold))
            .tracking(0.6)
            .foregroundStyle(.secondary)
            .textCase(.uppercase)
    }
}

struct PanelCardBackground: View {
    var body: some View {
        RoundedRectangle(cornerRadius: 10, style: .continuous)
            .fill(Color.primary.opacity(0.09))
    }
}

private struct PopoverChromeLock: NSViewRepresentable {
    func makeNSView(context: Context) -> LockView {
        LockView()
    }

    func updateNSView(_ nsView: LockView, context: Context) {
        nsView.lock()
    }

    final class LockView: NSView {
        private var observers: [NSObjectProtocol] = []

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            observers.forEach { NotificationCenter.default.removeObserver($0) }
            observers = []
            guard let window else { return }
            lock()
            let center = NotificationCenter.default
            let names: [Notification.Name] = [
                NSWindow.didResignKeyNotification,
                NSWindow.didBecomeKeyNotification,
                NSApplication.didResignActiveNotification,
                NSApplication.didBecomeActiveNotification,
            ]
            observers = names.map { name in
                let object: Any? = name == NSWindow.didResignKeyNotification || name == NSWindow.didBecomeKeyNotification
                    ? window
                    : NSApp
                return center.addObserver(forName: name, object: object, queue: .main) { [weak self] _ in
                    self?.lock()
                }
            }
        }

        func lock() {
            guard let window else { return }
            let appearance = NSApp.effectiveAppearance
            window.appearance = appearance
            func visit(_ view: NSView) {
                view.appearance = appearance
                if let effect = view as? NSVisualEffectView {
                    effect.state = .active
                }
                view.subviews.forEach(visit)
            }
            visit(window.contentView?.superview ?? window.contentView ?? self)
        }
    }
}
