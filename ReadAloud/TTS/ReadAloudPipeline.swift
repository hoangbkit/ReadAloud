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
            queuedBuffers: Int,
            queuedDurationSeconds: Double,
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
    private var sessionID: UUID?

    private(set) var state: State = .idle
    var onEvent: ((Event) -> Void)?

    init() {
        self.engine = KokoroEngine()
        self.playback = SpeechPlaybackQueue()
        self.scheduler = SpeechChunkScheduler()
    }

    func read(
        text: String,
        voice: KokoroEngine.Voice = .heart,
        speed: Float = 1.0
    ) async throws {
        stop()

        let chunks = scheduler.chunks(
            for: text,
            speed: speed
        )

        guard !chunks.isEmpty else {
            throw PipelineError.emptyText
        }

        let id = UUID()
        let readStart = ContinuousClock().now

        sessionID = id
        setState(.loading)

        let task = Task { @MainActor [weak self] in
            guard let self else {
                return
            }

            try await self.run(
                chunks: chunks,
                voice: voice,
                speed: speed,
                readStart: readStart
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

            guard sessionID == id else {
                throw PipelineError.cancelled
            }

            readingTask = nil
            sessionID = nil
            setState(.finished)
        } catch is CancellationError {
            if sessionID == id {
                playback.stop()
                readingTask = nil
                sessionID = nil
                setState(.idle)
            }

            throw PipelineError.cancelled
        } catch KokoroEngine.EngineError.cancelled {
            if sessionID == id {
                playback.stop()
                readingTask = nil
                sessionID = nil
                setState(.idle)
            }

            throw PipelineError.cancelled
        } catch {
            if sessionID == id {
                playback.stop()
                readingTask = nil
                sessionID = nil
                setState(.failed(Self.message(for: error)))
            }

            throw error
        }
    }

    func warmUp(
        voice: KokoroEngine.Voice = .heart,
        speed: Float = 1.0
    ) async throws -> Double {
        stop()
        setState(.loading)

        let clock = ContinuousClock()
        let loadStart = clock.now

        do {
            try await engine.load()

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

            onEvent?(.warmUpFinished(seconds: result.elapsedSeconds))
            setState(.idle)
            return result.elapsedSeconds
        } catch is CancellationError {
            setState(.idle)
            throw PipelineError.cancelled
        } catch KokoroEngine.EngineError.cancelled {
            setState(.idle)
            throw PipelineError.cancelled
        } catch {
            setState(.failed(Self.message(for: error)))
            throw error
        }
    }

    func stop() {
        sessionID = nil

        readingTask?.cancel()
        readingTask = nil

        playback.stop()
        setState(.idle)
        onEvent?(.stopped)
    }

    func unload() async {
        stop()
        await engine.unload()
    }

    var playbackSnapshot: SpeechPlaybackQueue.Snapshot {
        playback.snapshot
    }

    private func run(
        chunks: [SpeechChunk],
        voice: KokoroEngine.Voice,
        speed: Float,
        readStart: ContinuousClock.Instant
    ) async throws {
        try Task.checkCancellation()

        let clock = ContinuousClock()
        let loadStart = clock.now

        try await engine.load()

        onEvent?(
            .modelLoaded(
                seconds: Self.seconds(loadStart.duration(to: clock.now))
            )
        )

        try Task.checkCancellation()
        try playback.prepare()

        for (offset, chunk) in chunks.enumerated() {
            try Task.checkCancellation()

            await playback.waitUntilQueueDepthBelow(
                maxQueuedBuffers
            )

            try Task.checkCancellation()

            let beforeSynthesis = playback.snapshot
            onEvent?(
                .queueChanged(
                    queuedBuffers: beforeSynthesis.queuedBuffers,
                    queuedDurationSeconds: beforeSynthesis.queuedDurationSeconds
                )
            )

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

            try Task.checkCancellation()

            let underrun = offset > 0 && playback.snapshot.queuedBuffers == 0

            try playback.enqueue(result.audio)

            let afterEnqueue = playback.snapshot
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
                    queuedBuffers: afterEnqueue.queuedBuffers,
                    queuedDurationSeconds: afterEnqueue.queuedDurationSeconds,
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
        try Task.checkCancellation()

        let drained = playback.snapshot
        onEvent?(
            .queueChanged(
                queuedBuffers: drained.queuedBuffers,
                queuedDurationSeconds: drained.queuedDurationSeconds
            )
        )
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
