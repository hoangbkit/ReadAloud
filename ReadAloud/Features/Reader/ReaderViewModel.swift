import Foundation
import Observation

@MainActor
@Observable
final class ReaderViewModel {
    var text = ReaderSample.all.first?.text ?? ""
    var selectedVoiceID = KokoroEngine.Voice.heart.id
    var selectedSpeed: Float = 1.0
    var metrics = PerformanceMetrics()
    var eventLog: [String] = []
    var statusText = "Stopped"
    var isBusy = false

    @ObservationIgnored
    private let pipeline = ReadAloudPipeline()

    @ObservationIgnored
    private var actionTask: Task<Void, Never>?

    let speedOptions: [Float] = [0.8, 1.0, 1.2]

    init() {
        metrics.thermalState = PerformanceMetrics.currentThermalState

        pipeline.onEvent = { [weak self] event in
            self?.handle(event)
        }
    }

    var voices: [KokoroEngine.Voice] {
        KokoroEngine.Voice.all
    }

    var samples: [ReaderSample] {
        ReaderSample.all
    }

    var canRead: Bool {
        !isBusy && !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var canStop: Bool {
        isBusy
    }

    func read() {
        actionTask?.cancel()

        metrics.resetForRead()
        eventLog.removeAll()
        appendEvent("Read requested")
        isBusy = true

        let text = text
        let voice = selectedVoice
        let speed = selectedSpeed

        actionTask = Task { [weak self] in
            guard let self else {
                return
            }

            do {
                try await pipeline.read(
                    text: text,
                    voice: voice,
                    speed: speed
                )
            } catch ReadAloudPipeline.PipelineError.cancelled {
                // Stop is an expected control path.
            } catch {
                statusText = "Error: \(Self.message(for: error))"
                appendEvent("Error: \(Self.message(for: error))")
            }

            if !Task.isCancelled {
                isBusy = false
            }
        }
    }

    func stop() {
        actionTask?.cancel()
        actionTask = nil

        pipeline.stop()

        isBusy = false
        statusText = "Stopped"
    }

    func warmUp() {
        actionTask?.cancel()

        metrics.warmUpSeconds = nil
        metrics.thermalState = PerformanceMetrics.currentThermalState
        appendEvent("Warm up requested")
        isBusy = true

        let voice = selectedVoice
        let speed = selectedSpeed

        actionTask = Task { [weak self] in
            guard let self else {
                return
            }

            do {
                _ = try await pipeline.warmUp(
                    voice: voice,
                    speed: speed
                )
            } catch ReadAloudPipeline.PipelineError.cancelled {
                // Stop is an expected control path.
            } catch {
                statusText = "Error: \(Self.message(for: error))"
                appendEvent("Error: \(Self.message(for: error))")
            }

            if !Task.isCancelled {
                isBusy = false
            }
        }
    }

    func loadSample(_ sample: ReaderSample) {
        guard !isBusy else {
            return
        }

        text = sample.text
        appendEvent("Loaded sample: \(sample.title)")
    }

    private var selectedVoice: KokoroEngine.Voice {
        voices.first { $0.id == selectedVoiceID } ?? .heart
    }

    private func handle(_ event: ReadAloudPipeline.Event) {
        metrics.thermalState = PerformanceMetrics.currentThermalState

        switch event {
        case .state(let state):
            statusText = Self.statusText(for: state)

        case .modelLoaded(let seconds):
            metrics.modelLoadSeconds = seconds
            appendEvent(
                "Models ready in \(Self.format(seconds))"
            )

        case .chunkStarted(
            let index,
            let total,
            let bucketSeconds
        ):
            metrics.currentChunk = index
            metrics.totalChunks = total
            metrics.latestBucketSeconds = bucketSeconds

            appendEvent(
                "Chunk \(index)/\(total) · \(bucketSeconds)s bucket"
            )

        case .chunkReady(
            let index,
            let total,
            let bucketSeconds,
            let synthesisSeconds,
            let audioDurationSeconds,
            let realTimeFactor,
            let queuedBuffers,
            let queuedDurationSeconds,
            let firstAudioLatencySeconds,
            let underrun
        ):
            metrics.currentChunk = index
            metrics.totalChunks = total
            metrics.latestBucketSeconds = bucketSeconds
            metrics.latestSynthesisSeconds = synthesisSeconds
            metrics.latestAudioDurationSeconds = audioDurationSeconds
            metrics.latestRealTimeFactor = realTimeFactor
            metrics.queuedBuffers = queuedBuffers
            metrics.queuedDurationSeconds = queuedDurationSeconds

            if let firstAudioLatencySeconds {
                metrics.firstAudioLatencySeconds = firstAudioLatencySeconds
            }

            if underrun {
                metrics.underrunCount += 1
            }

            appendEvent(
                "Ready \(index)/\(total) · synth \(Self.format(synthesisSeconds)) · audio \(Self.format(audioDurationSeconds)) · RTF \(String(format: "%.2f", realTimeFactor))"
            )

            if underrun {
                appendEvent("Underrun before chunk \(index)")
            }

        case .queueChanged(
            let queuedBuffers,
            let queuedDurationSeconds
        ):
            metrics.queuedBuffers = queuedBuffers
            metrics.queuedDurationSeconds = queuedDurationSeconds

        case .warmUpFinished(let seconds):
            metrics.warmUpSeconds = seconds
            appendEvent("Warm up finished in \(Self.format(seconds))")

        case .stopped:
            statusText = "Stopped"
            metrics.queuedBuffers = 0
            metrics.queuedDurationSeconds = 0
        }
    }

    private func appendEvent(_ message: String) {
        eventLog.append(message)

        if eventLog.count > 30 {
            eventLog.removeFirst(eventLog.count - 30)
        }
    }

    private static func statusText(
        for state: ReadAloudPipeline.State
    ) -> String {
        switch state {
        case .idle:
            return "Stopped"
        case .loading:
            return "Loading models…"
        case .warmingUp:
            return "Warming up…"
        case .synthesizing(let current, let total):
            return "Synthesizing \(current)/\(total)…"
        case .playing:
            return "Playing"
        case .finished:
            return "Finished"
        case .failed(let message):
            return "Error: \(message)"
        }
    }

    private static func message(for error: Error) -> String {
        if let localized = error as? LocalizedError,
           let description = localized.errorDescription {
            return description
        }

        return String(describing: error)
    }

    private static func format(_ seconds: Double) -> String {
        String(format: "%.3fs", seconds)
    }
}
