import Foundation

@MainActor
final class ReadAloudPipeline {
    enum State: Equatable, Sendable {
        case idle
        case loading
        case warmingUp
        case synthesizing(current: Int, total: Int)
        case playing
        case finished
        case failed(String)
    }

    enum Event: Sendable {
        case state(State)
        case modelLoaded(seconds: Double)
        case chunkStarted(
            index: Int,
            total: Int,
            bucketSeconds: Int
        )
        case chunkReady(
            index: Int,
            total: Int,
            bucketSeconds: Int,
            synthesisSeconds: Double,
            audioDurationSeconds: Double,
            realTimeFactor: Double,
            firstAudioLatencySeconds: Double?,
            underrun: Bool
        )
        case queueChanged(
            queuedBuffers: Int,
            queuedDurationSeconds: Double
        )
        case warmUpFinished(seconds: Double)
        case stopped
    }

    enum PipelineError: LocalizedError {
        case emptyText
        case cancelled

        var errorDescription: String? {
            switch self {
            case .emptyText:
                return "Enter text to read aloud."
            case .cancelled:
                return "Read-aloud playback was cancelled."
            }
        }
    }

    private let engine: KokoroEngine
    private let playback: SpeechPlaybackQueue
    private let scheduler: SpeechChunkScheduler
    private let maxQueuedBuffers = 2

    private var readingTask: Task<Void, Error>?
    private var activeOperationID: UUID?

    private(set) var state: State = .idle
    var onEvent: ((Event) -> Void)?

    init() {
        let playback = SpeechPlaybackQueue()

        self.engine = KokoroEngine()
        self.playback = playback
        self.scheduler = SpeechChunkScheduler()

        playback.onSnapshotChange = { [weak self] snapshot in
            self?.onEvent?(
                .queueChanged(
                    queuedBuffers: snapshot.queuedBuffers,
                    queuedDurationSeconds: snapshot.queuedDurationSeconds
                )
            )
        }
    }

    func read(
        text: String,
        voice: KokoroEngine.Voice = .heart,
        speed: Float = 1.0
    ) async throws {
        resetActiveOperation()

        let chunks = scheduler.chunks(
            for: text,
            speed: speed
        )

        guard !chunks.isEmpty else {
            throw PipelineError.emptyText
        }

        let operationID = UUID()
        let readStart = ContinuousClock().now

        activeOperationID = operationID
        setState(.loading)

        let task = Task { @MainActor [weak self] in
            guard let self else {
                return
            }

            try await self.run(
                chunks: chunks,
                voice: voice,
                speed: speed,
                readStart: readStart,
                operationID: operationID
            )
        }

        readingTask = task

        do {
            try await withTaskCancellationHandler {
                try await task.value
            } onCancel: {
                Task { @MainActor [weak self] in
                    self?.stop()
                }
            }

            try requireActiveOperation(operationID)

            readingTask = nil
            activeOperationID = nil
            setState(.finished)
        } catch is CancellationError {
            finishCancellation(operationID)
            throw PipelineError.cancelled
        } catch PipelineError.cancelled {
            finishCancellation(operationID)
            throw PipelineError.cancelled
        } catch KokoroEngine.EngineError.cancelled {
            finishCancellation(operationID)
            throw PipelineError.cancelled
        } catch {
            if activeOperationID == operationID {
                playback.stop()
                readingTask = nil
                activeOperationID = nil
                setState(.failed(Self.message(for: error)))
            }

            throw error
        }
    }

    func warmUp(
        voice: KokoroEngine.Voice = .heart,
        speed: Float = 1.0
    ) async throws -> Double {
        resetActiveOperation()

        let operationID = UUID()
        activeOperationID = operationID
        setState(.loading)

        let clock = ContinuousClock()
        let loadStart = clock.now

        do {
            try requireActiveOperation(operationID)
            try await engine.load()
            try requireActiveOperation(operationID)

            onEvent?(
                .modelLoaded(
                    seconds: Self.seconds(loadStart.duration(to: clock.now))
                )
            )

            setState(.warmingUp)

            let result = try await engine.warmUp(
                voice: voice,
                speed: speed
            )

            try requireActiveOperation(operationID)

            onEvent?(.warmUpFinished(seconds: result.elapsedSeconds))
            activeOperationID = nil
            setState(.idle)
            return result.elapsedSeconds
        } catch is CancellationError {
            finishCancellation(operationID)
            throw PipelineError.cancelled
        } catch PipelineError.cancelled {
            finishCancellation(operationID)
            throw PipelineError.cancelled
        } catch KokoroEngine.EngineError.cancelled {
            finishCancellation(operationID)
            throw PipelineError.cancelled
        } catch {
            if activeOperationID == operationID {
                activeOperationID = nil
                setState(.failed(Self.message(for: error)))
            }

            throw error
        }
    }

    func stop() {
        resetActiveOperation()
        setState(.idle)
        onEvent?(.stopped)
    }

    func unload() async {
        stop()
        await engine.unload()
    }

    private func run(
        chunks: [SpeechChunk],
        voice: KokoroEngine.Voice,
        speed: Float,
        readStart: ContinuousClock.Instant,
        operationID: UUID
    ) async throws {
        try requireActiveOperation(operationID)

        let clock = ContinuousClock()
        let loadStart = clock.now

        try await engine.load()
        try requireActiveOperation(operationID)

        onEvent?(
            .modelLoaded(
                seconds: Self.seconds(loadStart.duration(to: clock.now))
            )
        )

        try playback.prepare()

        for (offset, chunk) in chunks.enumerated() {
            try requireActiveOperation(operationID)

            await playback.waitUntilQueueDepthBelow(
                maxQueuedBuffers
            )

            try requireActiveOperation(operationID)

            let chunkNumber = offset + 1

            setState(
                .synthesizing(
                    current: chunkNumber,
                    total: chunks.count
                )
            )

            onEvent?(
                .chunkStarted(
                    index: chunkNumber,
                    total: chunks.count,
                    bucketSeconds: chunk.targetBucketSeconds
                )
            )

            let result = try await engine.synthesize(
                text: chunk.text,
                voice: voice,
                speed: speed,
                maxChunkSeconds: Double(chunk.targetBucketSeconds)
            )

            try requireActiveOperation(operationID)

            let underrun = offset > 0 && playback.snapshot.queuedBuffers == 0

            try playback.enqueue(result.audio)

            let firstAudioLatency = offset == 0
                ? Self.seconds(readStart.duration(to: clock.now))
                : nil

            onEvent?(
                .chunkReady(
                    index: chunkNumber,
                    total: chunks.count,
                    bucketSeconds: chunk.targetBucketSeconds,
                    synthesisSeconds: result.elapsedSeconds,
                    audioDurationSeconds: result.durationSeconds,
                    realTimeFactor: result.realTimeFactor,
                    firstAudioLatencySeconds: firstAudioLatency,
                    underrun: underrun
                )
            )

            if offset == 0 {
                setState(.playing)
            }
        }

        setState(.playing)
        await playback.waitUntilDrained()
        try requireActiveOperation(operationID)

        playback.stop()
    }

    private func resetActiveOperation() {
        activeOperationID = nil

        readingTask?.cancel()
        readingTask = nil

        playback.stop()
    }

    private func finishCancellation(_ operationID: UUID) {
        guard activeOperationID == operationID else {
            return
        }

        playback.stop()
        readingTask = nil
        activeOperationID = nil
        setState(.idle)
    }

    private func requireActiveOperation(_ operationID: UUID) throws {
        try Task.checkCancellation()

        guard activeOperationID == operationID else {
            throw PipelineError.cancelled
        }
    }

    private func setState(_ newState: State) {
        state = newState
        onEvent?(.state(newState))
    }

    private static func message(for error: Error) -> String {
        if let localized = error as? LocalizedError,
           let description = localized.errorDescription {
            return description
        }

        return String(describing: error)
    }

    private static func seconds(_ duration: Duration) -> Double {
        let components = duration.components
        return Double(components.seconds)
            + Double(components.attoseconds) / 1_000_000_000_000_000_000
    }
}
