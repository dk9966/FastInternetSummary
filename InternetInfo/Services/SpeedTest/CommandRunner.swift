import Foundation

struct CommandOutput: Sendable {
    var stdout: Data
    var stderr: Data
    var status: Int32
}

enum CommandRunner {
    static func runStreaming(
        executable: String,
        arguments: [String],
        timeout: TimeInterval,
        onOutput: @escaping @Sendable (String) -> Void
    ) async throws -> CommandOutput {
        try Task.checkCancellation()

        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments

        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr

        let handle = ProcessHandle(process: process, stdout: stdout, stderr: stderr, onOutput: onOutput)

        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                do {
                    try handle.start(timeout: timeout, continuation: continuation)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        } onCancel: {
            handle.cancel()
        }
    }
}

private final class ProcessHandle: @unchecked Sendable {
    private let lock = NSLock()
    private let process: Process
    private let stdout: Pipe
    private let stderr: Pipe
    private let onOutput: @Sendable (String) -> Void
    private var continuation: CheckedContinuation<CommandOutput, Error>?
    private var timeoutWork: DispatchWorkItem?
    private var stopReason: StopReason = .none
    private var stdoutData = Data()
    private var stderrData = Data()
    private var didFinish = false

    private enum StopReason {
        case none
        case timeout
        case cancelled
    }

    init(process: Process, stdout: Pipe, stderr: Pipe, onOutput: @escaping @Sendable (String) -> Void) {
        self.process = process
        self.stdout = stdout
        self.stderr = stderr
        self.onOutput = onOutput
    }

    func start(timeout: TimeInterval, continuation: CheckedContinuation<CommandOutput, Error>) throws {
        lock.lock()
        if stopReason == .cancelled {
            lock.unlock()
            throw CancellationError()
        }
        self.continuation = continuation
        lock.unlock()

        stdout.fileHandleForReading.readabilityHandler = { [weak self] file in
            self?.ingest(file, isStdout: true)
        }
        stderr.fileHandleForReading.readabilityHandler = { [weak self] file in
            self?.ingest(file, isStdout: false)
        }

        let timeoutWork = DispatchWorkItem { [weak self] in
            self?.timeOut()
        }
        self.timeoutWork = timeoutWork
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + timeout, execute: timeoutWork)

        process.terminationHandler = { [weak self] proc in
            self?.finished(process: proc)
        }

        try process.run()

        lock.lock()
        let cancelledAfterLaunch = stopReason == .cancelled
        lock.unlock()
        if cancelledAfterLaunch {
            terminateIfRunning()
            return
        }

        if !process.isRunning {
            finished(process: process)
        }
    }

    func cancel() {
        lock.lock()
        if stopReason == .none {
            stopReason = .cancelled
        }
        lock.unlock()
        terminateIfRunning()
    }

    private func ingest(_ file: FileHandle, isStdout: Bool) {
        let data = file.availableData
        guard !data.isEmpty else { return }

        lock.lock()
        if isStdout {
            stdoutData.append(data)
        } else {
            stderrData.append(data)
        }
        lock.unlock()

        if let text = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1) {
            onOutput(text)
        }
    }

    private func timeOut() {
        lock.lock()
        if stopReason == .none {
            stopReason = .timeout
        }
        lock.unlock()
        terminateIfRunning()
    }

    private func terminateIfRunning() {
        if process.isRunning {
            process.terminate()
        }
    }

    private func finished(process: Process) {
        stdout.fileHandleForReading.readabilityHandler = nil
        stderr.fileHandleForReading.readabilityHandler = nil
        timeoutWork?.cancel()

        ingest(stdout.fileHandleForReading, isStdout: true)
        ingest(stderr.fileHandleForReading, isStdout: false)

        lock.lock()
        if didFinish {
            lock.unlock()
            return
        }
        didFinish = true
        let reason = stopReason
        let continuation = self.continuation
        self.continuation = nil
        let stdoutData = self.stdoutData
        let stderrData = self.stderrData
        lock.unlock()

        guard let continuation else { return }

        switch reason {
        case .cancelled:
            continuation.resume(throwing: CancellationError())
        case .timeout:
            continuation.resume(throwing: SpeedTestError.timedOut)
        case .none:
            continuation.resume(
                returning: CommandOutput(
                    stdout: stdoutData,
                    stderr: stderrData,
                    status: process.terminationStatus
                )
            )
        }
    }
}
