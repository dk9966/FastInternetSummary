import Foundation

enum SpeedTestPhase: Equatable {
    case idle
    case starting
    case measuring
    case failed(String)
}

@MainActor
@Observable
final class SpeedTestRunner {
    private let maxFlows = 16.0

    private(set) var lastResult: SpeedTestResult?
    private(set) var phase: SpeedTestPhase = .idle
    private(set) var percentComplete: Double = 0
    private(set) var sawFinalSummary = false

    private let provider: any SpeedTestProvider
    private var inFlight = false
    private var savedResult: SpeedTestResult?
    private var receivedDownloadThisRun = false
    private var receivedUploadThisRun = false
    private var receivedLatencyThisRun = false
    private var receivedResponsivenessThisRun = false
    private var downloadFlows = 0
    private var uploadFlows = 0
    private var startedAt: Date?
    private var runID = UUID()
    private var runningTask: Task<Void, Never>?
    private var progressTimer: Timer?
    private var sequentialThisRun = false

    private var typicalDuration: TimeInterval {
        sequentialThisRun ? 30 : 16
    }

    var isRunning: Bool {
        switch phase {
        case .starting, .measuring: true
        default: false
        }
    }

    var isDownloadStale: Bool { isRunning && !receivedDownloadThisRun }
    var isUploadStale: Bool { isRunning && !receivedUploadThisRun }
    var isLatencyStale: Bool { isRunning && !receivedLatencyThisRun }

    var progressPercent: Int {
        Int((percentComplete * 100).rounded(.down))
    }

    var stageLine: String {
        if !receivedLatencyThisRun {
            return "Measuring idle latency"
        }
        if sawFinalSummary || percentComplete >= 0.97 {
            return "Finishing up"
        }
        if sequentialThisRun {
            if !receivedDownloadThisRun {
                return "Measuring download"
            }
            if !receivedUploadThisRun {
                return "Measuring upload"
            }
            return "Settling the numbers"
        }
        if !receivedDownloadThisRun {
            return "Starting test"
        }
        if !receivedUploadThisRun {
            return "Measuring download"
        }
        if !receivedResponsivenessThisRun {
            return "Measuring upload"
        }
        if downloadFlows < 10, uploadFlows < 10 {
            return "Stressing the connection"
        }
        return "Settling the numbers"
    }

    init(provider: any SpeedTestProvider = NetworkQualityProvider()) {
        self.provider = provider
        lastResult = SpeedTestResult.load()
        savedResult = lastResult
    }

    func run(sequential: Bool = false) {
        guard !inFlight else { return }
        sequentialThisRun = sequential
        inFlight = true
        receivedDownloadThisRun = false
        receivedUploadThisRun = false
        receivedLatencyThisRun = false
        receivedResponsivenessThisRun = false
        sawFinalSummary = false
        downloadFlows = 0
        uploadFlows = 0
        savedResult = SpeedTestResult.load() ?? lastResult
        let id = UUID()
        runID = id
        startedAt = .now
        percentComplete = 0.04
        phase = .starting
        startProgressTicker()

        runningTask = Task { [weak self] in
            guard let self else { return }
            await self.executeTest(id: id)
        }
    }

    func cancel() {
        guard inFlight else { return }
        runID = UUID()
        runningTask?.cancel()
        runningTask = nil
        stopProgressTicker()
        inFlight = false
        lastResult = savedResult
        percentComplete = 0
        startedAt = nil
        phase = .idle
    }

    private func executeTest(id: UUID) async {
        do {
            let result = try await provider.run(sequential: sequentialThisRun) { progress in
                await MainActor.run { [weak self] in
                    self?.apply(progress, id: id)
                }
            }
            guard runID == id else { return }
            lastResult = result
            result.save()
            savedResult = result
            percentComplete = 1
            stopProgressTicker()
            phase = .idle
        } catch is CancellationError {
            guard runID == id else { return }
            lastResult = savedResult
            stopProgressTicker()
            percentComplete = 0
            phase = .idle
        } catch {
            guard runID == id else { return }
            if lastResult?.isComplete != true {
                lastResult = savedResult
            }
            stopProgressTicker()
            percentComplete = 0
            phase = .failed(error.localizedDescription)
        }

        if runID == id {
            inFlight = false
            runningTask = nil
            startedAt = nil
        }
    }

    private func apply(_ progress: SpeedTestProgress, id: UUID) {
        guard runID == id else { return }

        var next = lastResult ?? SpeedTestResult(
            downloadMbps: nil,
            uploadMbps: nil,
            latencyMs: nil,
            testedAt: .now,
            source: provider.name
        )
        if let download = progress.downloadMbps {
            next.downloadMbps = download
            receivedDownloadThisRun = true
        }
        if let upload = progress.uploadMbps {
            next.uploadMbps = upload
            receivedUploadThisRun = true
        }
        if let latency = progress.latencyMs {
            next.latencyMs = latency
            receivedLatencyThisRun = true
        }
        if progress.hasLoadedRoundTrip {
            receivedResponsivenessThisRun = true
        }
        if let flows = progress.downloadFlows {
            downloadFlows = max(downloadFlows, flows)
        }
        if let flows = progress.uploadFlows {
            uploadFlows = max(uploadFlows, flows)
        }
        next.testedAt = .now
        lastResult = next
        if progress.isFinal {
            sawFinalSummary = true
        }
        phase = .measuring
        refreshPercent(isFinal: progress.isFinal)

        if progress.isFinal, next.isComplete {
            next.save()
        }
    }

    private func startProgressTicker() {
        stopProgressTicker()
        let timer = Timer(timeInterval: 0.2, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.refreshPercent(isFinal: false)
            }
        }
        timer.tolerance = 0.05
        RunLoop.main.add(timer, forMode: .common)
        progressTimer = timer
    }

    private func stopProgressTicker() {
        progressTimer?.invalidate()
        progressTimer = nil
    }

    private func refreshPercent(isFinal: Bool) {
        guard isRunning else { return }
        if isFinal {
            percentComplete = 1
            return
        }

        let elapsed = startedAt.map { Date().timeIntervalSince($0) } ?? 0
        let timeShare = min(0.88, elapsed / typicalDuration)
        let flowShare = ((Double(downloadFlows) + Double(uploadFlows)) / (2 * maxFlows)) * 0.9

        var floor = 0.04
        if receivedLatencyThisRun { floor = max(floor, 0.10) }
        if sequentialThisRun {
            if receivedDownloadThisRun { floor = max(floor, 0.48) }
            if receivedUploadThisRun { floor = max(floor, 0.78) }
        } else {
            if receivedDownloadThisRun { floor = max(floor, 0.22) }
            if receivedUploadThisRun { floor = max(floor, 0.38) }
            if downloadFlows >= 8 || uploadFlows >= 8 { floor = max(floor, 0.7) }
        }

        percentComplete = min(0.96, max(floor, max(timeShare, flowShare)))
    }
}
