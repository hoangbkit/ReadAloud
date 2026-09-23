import Foundation

@MainActor
final class ReadAloudPipeline {
    enum State: Equatable, Sendable {
        case idle
        case loading
        case synthesizing(current: Int, total: Int)
        case playing
        case finished
        case failed(String)
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
        sessionID = id
        state = .loading

        let task = Task { @MainActor [weak self] in
            guard let self else {
                return
            }

            try await self.run(
                chunks: chunks,
                voice: voice,
                speed: speed
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
            state = .finished
        } catch is CancellationError {
            if sessionID == id {
                playback.stop()
                readingTask = nil
                sessionID = nil
                state = .idle
            }

            throw PipelineError.cancelled
        } catch KokoroEngine.EngineError.cancelled {
            if sessionID == id {
                playback.stop()
                readingTask = nil
                sessionID = nil
                state = .idle
            }

            throw PipelineError.cancelled
        } catch {
            if sessionID == id {
                playback.stop()
                readingTask = nil
                sessionID = nil
                state = .failed(Self.message(for: error))
            }

            throw error
        }
    }

    func stop() {
        sessionID = nil

        readingTask?.cancel()
        readingTask = nil

        playback.stop()
        state = .idle
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
        speed: Float
    ) async throws {
        try Task.checkCancellation()

        try await engine.load()
        try Task.checkCancellation()

        try playback.prepare()

        for (offset, chunk) in chunks.enumerated() {
            try Task.checkCancellation()

            await playback.waitUntilQueueDepthBelow(
                maxQueuedBuffers
            )

            try Task.checkCancellation()

            state = .synthesizing(
                current: offset + 1,
                total: chunks.count
            )

            let result = try await engine.synthesize(
                text: chunk.text,
                voice: voice,
                speed: speed,
                maxChunkSeconds: Double(chunk.targetBucketSeconds)
            )

            try Task.checkCancellation()

            try playback.enqueue(result.audio)

            if offset == 0 {
                state = .playing
            }
        }

        state = .playing
        await playback.waitUntilDrained()
        try Task.checkCancellation()
    }

    private static func message(for error: Error) -> String {
        if let localized = error as? LocalizedError,
           let description = localized.errorDescription {
            return description
        }

        return String(describing: error)
    }
}
