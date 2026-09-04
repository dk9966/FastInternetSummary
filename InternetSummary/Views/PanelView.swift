import SwiftUI

enum PanelMetrics {
    static let width: CGFloat = 340
    static let padding: CGFloat = 16
}

struct RootPanel: View {
    @Bindable var state: AppState

    var body: some View {
        Group {
            if state.isShowingSettings {
                SettingsView(state: state)
            } else {
                PanelView(state: state)
            }
        }
        .frame(width: PanelMetrics.width)
        .preferredColorScheme(nil)
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
            Text("Internet Summary")
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
            SectionLabel(title: "Last Speed Test")
            if let result = state.speedTest.lastResult {
                HStack(spacing: 12) {
                    SpeedMetricText(
                        text: result.downloadMbps.map { "\(ThroughputFormat.mbps($0)) down" } ?? "— down",
                        isStale: state.speedTest.isDownloadStale
                    )
                    SpeedMetricText(
                        text: result.uploadMbps.map { "\(ThroughputFormat.mbps($0)) up" } ?? "— up",
                        isStale: state.speedTest.isUploadStale
                    )
                    SpeedMetricText(
                        text: result.latencyMs.map { ThroughputFormat.latency($0) } ?? "— ms",
                        isStale: state.speedTest.isLatencyStale
                    )
                }
                .font(.system(size: 12.5, weight: .medium, design: .rounded))
                .minimumScaleFactor(0.85)
                .lineLimit(1)

                if !state.speedTest.isRunning {
                    TimelineView(.periodic(from: .now, by: 15)) { timeline in
                        Text(RelativeTimeFormat.checkedPhrase(from: result.testedAt, now: timeline.date))
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                }
            } else if state.speedTest.isRunning {
                HStack(spacing: 12) {
                    Text("— down")
                    Text("— up")
                    Text("— ms")
                }
                .font(.system(size: 12.5, weight: .medium, design: .rounded))
                .foregroundStyle(.primary)
            } else {
                Text("No test yet")
                    .font(.system(size: 12.5))
                    .foregroundStyle(.secondary)
            }

            if case .failed(let message) = state.speedTest.phase {
                Text(message)
                    .font(.system(size: 11))
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(PanelCardBackground())
    }

    @ViewBuilder
    private var runButton: some View {
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
        } else {
            Button {
                state.speedTest.run()
            } label: {
                Text("Run again")
                    .font(.system(size: 13, weight: .semibold))
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .controlSize(.regular)
            .disabled(state.speedTest.isRunning)
        }
    }
}

private struct SpeedMetricText: View {
    var text: String
    var isStale: Bool

    var body: some View {
        Text(text)
            .foregroundStyle(isStale ? .secondary : .primary)
            .opacity(isStale ? 0.45 : 1)
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
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.system(size: 16, weight: .semibold, design: .rounded))
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

private struct PanelCardBackground: View {
    var body: some View {
        RoundedRectangle(cornerRadius: 10, style: .continuous)
            .fill(Color.primary.opacity(0.045))
    }
}
