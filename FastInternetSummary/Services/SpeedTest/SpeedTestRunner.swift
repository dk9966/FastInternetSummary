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

    private(set) var providerName = "networkQuality"
    private var inFlight = false
    private var savedResult: SpeedTestResult?
    private var receivedDownloadThisRun = false
    private var receivedUploadThisRun = false
    private var receivedLatencyThisRun = false
    private var receivedDownloadLatencyThisRun = false
    private var receivedUploadLatencyThisRun = false
    private var downloadFlows = 0
    private var uploadFlows = 0
    private var startedAt: Date?
    private var runID = UUID()
    private var runningTask: Task<Void, Never>?
    private var progressTimer: Timer?
    private var sequentialThisRun = false
    private var reportedFraction: Double?
    private var liveStage: SpeedTestLiveStage?
    private var finishedAt: Date?

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
    var isDownloadLatencyStale: Bool { isRunning && !receivedDownloadLatencyThisRun }
    var isUploadLatencyStale: Bool { isRunning && !receivedUploadLatencyThisRun }

    /// Time of the last finished test. Stays on the previous result while a new run is in flight.
    var lastCheckedAt: Date? {
        if isRunning {
            return savedResult?.testedAt
        }
        return lastResult?.testedAt
    }

    var progressPercent: Int {
        Int((percentComplete * 100).rounded(.down))
    }

    var stageLine: String {
        if !receivedLatencyThisRun {
            return "Measuring idle latency"
        }
        if progressPercent >= 100 {
            return "Finished"
        }
        if sawFinalSummary || percentComplete >= 0.97 {
            return "Finishing up"
        }
        // Download samples start arriving while download is still running.
        // Upload samples (or an explicit upload stage) mean upload has started.
        if sequentialThisRun {
            let uploadStarted = liveStage == .upload
                || receivedUploadThisRun
                || (reportedFraction ?? 0) > 0.52
            return uploadStarted ? "Measuring upload" : "Measuring download"
        }
        switch liveStage {
        case .download:
            return "Measuring download"
        case .upload:
            return "Measuring upload"
        case .both:
            return "Measuring download and upload"
        case nil:
            if receivedDownloadThisRun || receivedUploadThisRun {
                return "Measuring download and upload"
            }
            return "Starting test"
        }
    }

    init() {
        lastResult = SpeedTestResult.load()
        savedResult = lastResult
    }

    func run(sequential: Bool = false, using provider: any SpeedTestProvider = NetworkQualityProvider()) {
        guard !inFlight else { return }
        providerName = provider.name
        sequentialThisRun = sequential
        inFlight = true
        receivedDownloadThisRun = false
        receivedUploadThisRun = false
        receivedLatencyThisRun = false
        receivedDownloadLatencyThisRun = false
        receivedUploadLatencyThisRun = false
        sawFinalSummary = false
        finishedAt = nil
        downloadFlows = 0
        uploadFlows = 0
        reportedFraction = nil
        liveStage = nil
        savedResult = SpeedTestResult.load() ?? lastResult
        let id = UUID()
        runID = id
        startedAt = .now
        percentComplete = 0.04
        phase = .starting
        startProgressTicker()

        runningTask = Task { [weak self] in
            guard let self else { return }
            await self.executeTest(id: id, provider: provider)
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
        finishedAt = nil
        phase = .idle
    }

    private func executeTest(id: UUID, provider: any SpeedTestProvider) async {
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
            markFinished()
            stopProgressTicker()
            try await holdFinishedDisplay(id: id)
            guard runID == id else { return }
            phase = .idle
        } catch is CancellationError {
            guard runID == id else { return }
            lastResult = savedResult
            stopProgressTicker()
            percentComplete = 0
            phase = .idle
        } catch SpeedTestError.skipped {
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
            phase = .idle
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
            source: providerName
        )
        if let download = progress.downloadMbps {
            next.downloadMbps = download
            if !receivedDownloadThisRun {
                next.downloadLatencyMs = progress.downloadLatencyMs
            }
            receivedDownloadThisRun = true
        }
        if let upload = progress.uploadMbps {
            next.uploadMbps = upload
            if !receivedUploadThisRun {
                next.uploadLatencyMs = progress.uploadLatencyMs
            }
            receivedUploadThisRun = true
        }
        if let latency = progress.latencyMs {
            next.latencyMs = latency
            receivedLatencyThisRun = true
        }
        if let downloadLatency = progress.downloadLatencyMs {
            next.downloadLatencyMs = downloadLatency
            receivedDownloadLatencyThisRun = true
        }
        if let uploadLatency = progress.uploadLatencyMs {
            next.uploadLatencyMs = uploadLatency
            receivedUploadLatencyThisRun = true
        }
        if let flows = progress.downloadFlows {
            downloadFlows = max(downloadFlows, flows)
        }
        if let flows = progress.uploadFlows {
            uploadFlows = max(uploadFlows, flows)
        }
        if let fraction = progress.fractionComplete {
            reportedFraction = fraction
        }
        if let stage = progress.liveStage {
            let alreadyUploading = sequentialThisRun && liveStage == .upload
            if !alreadyUploading {
                liveStage = stage
            }
        }
        next.source = providerName
        if progress.isFinal {
            next.testedAt = .now
            sawFinalSummary = true
        }
        lastResult = next
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

    private func markFinished() {
        percentComplete = 1
        if finishedAt == nil {
            finishedAt = .now
        }
    }

    private func holdFinishedDisplay(id: UUID) async throws {
        let minimumVisible: TimeInterval = 0.7
        let elapsed = finishedAt.map { Date().timeIntervalSince($0) } ?? 0
        let remaining = minimumVisible - elapsed
        guard remaining > 0 else { return }
        try await Task.sleep(for: .seconds(remaining))
        guard runID == id else { throw CancellationError() }
    }

    private func refreshPercent(isFinal: Bool) {
        guard isRunning else { return }
        if isFinal {
            markFinished()
            return
        }
        if let reportedFraction {
            percentComplete = min(0.96, max(0.04, reportedFraction))
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
