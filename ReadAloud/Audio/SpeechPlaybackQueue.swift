import AVFoundation
import Foundation
import KokoroTTS

@MainActor
final class SpeechPlaybackQueue {
    struct Snapshot: Equatable, Sendable {
        let queuedBuffers: Int
        let queuedDurationSeconds: Double
        let isPlaying: Bool
    }

    enum PlaybackError: LocalizedError {
        case invalidBuffer

        var errorDescription: String? {
            switch self {
            case .invalidBuffer:
                return "Kokoro produced an invalid PCM buffer."
            }
        }
    }

    private struct DepthWaiter {
        let limit: Int
        let continuation: CheckedContinuation<Void, Never>
    }

    private let audioEngine = AVAudioEngine()
    private let playerNode = AVAudioPlayerNode()

    private var pendingDurations: [UUID: Double] = [:]
    private var depthWaiters: [DepthWaiter] = []
    private var drainWaiters: [CheckedContinuation<Void, Never>] = []
    private var generation = 0
    private var queuedDurationSeconds = 0.0

    init() {
        audioEngine.attach(playerNode)
        audioEngine.connect(
            playerNode,
            to: audioEngine.mainMixerNode,
            format: nil
        )
    }

    var snapshot: Snapshot {
        Snapshot(
            queuedBuffers: pendingDurations.count,
            queuedDurationSeconds: queuedDurationSeconds,
            isPlaying: playerNode.isPlaying && !pendingDurations.isEmpty
        )
    }

    func prepare() throws {
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(
            .playback,
            mode: .spokenAudio,
            options: []
        )
        try session.setActive(true)

        guard !audioEngine.isRunning else {
            return
        }

        audioEngine.prepare()
        try audioEngine.start()
    }

    func enqueue(_ audio: KokoroAudio) throws {
        guard !audio.samples.isEmpty else {
            throw PlaybackError.invalidBuffer
        }

        let buffer = try audio.makePCMBuffer()
        let itemID = UUID()
        let itemGeneration = generation

        pendingDurations[itemID] = audio.durationSeconds
        queuedDurationSeconds += audio.durationSeconds

        playerNode.scheduleBuffer(
            buffer,
            completionCallbackType: .dataPlayedBack
        ) { [weak self] _ in
            Task { @MainActor in
                self?.didFinish(
                    itemID: itemID,
                    generation: itemGeneration
                )
            }
        }

        if !playerNode.isPlaying {
            playerNode.play()
        }
    }

    func waitUntilQueueDepthBelow(_ limit: Int) async {
        guard pendingDurations.count >= limit else {
            return
        }

        await withCheckedContinuation { continuation in
            depthWaiters.append(
                DepthWaiter(
                    limit: limit,
                    continuation: continuation
                )
            )
        }
    }

    func waitUntilDrained() async {
        guard !pendingDurations.isEmpty else {
            return
        }

        await withCheckedContinuation { continuation in
            drainWaiters.append(continuation)
        }
    }

    func stop() {
        generation += 1
        playerNode.stop()

        pendingDurations.removeAll()
        queuedDurationSeconds = 0

        resumeDepthWaiters()
        resumeDrainWaiters()

        if audioEngine.isRunning {
            audioEngine.stop()
        }

        try? AVAudioSession.sharedInstance().setActive(
            false,
            options: .notifyOthersOnDeactivation
        )
    }

    private func didFinish(
        itemID: UUID,
        generation itemGeneration: Int
    ) {
        guard itemGeneration == generation,
              let duration = pendingDurations.removeValue(forKey: itemID)
        else {
            return
        }

        queuedDurationSeconds = max(
            0,
            queuedDurationSeconds - duration
        )

        resumeDepthWaiters()

        if pendingDurations.isEmpty {
            resumeDrainWaiters()
        }
    }

    private func resumeDepthWaiters() {
        guard !depthWaiters.isEmpty else {
            return
        }

        var remaining: [DepthWaiter] = []

        for waiter in depthWaiters {
            if pendingDurations.count < waiter.limit {
                waiter.continuation.resume()
            } else {
                remaining.append(waiter)
            }
        }

        depthWaiters = remaining
    }

    private func resumeDrainWaiters() {
        let waiters = drainWaiters
        drainWaiters.removeAll()

        for waiter in waiters {
            waiter.resume()
        }
    }
}
