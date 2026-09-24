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
        case inconsistentFormat

        var errorDescription: String? {
            switch self {
            case .invalidBuffer:
                return "Kokoro produced an invalid PCM buffer."
            case .inconsistentFormat:
                return "Kokoro produced PCM with an unexpected playback format."
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
    private var connectedSampleRate: Double?
    private var connectedChannelCount: AVAudioChannelCount?

    var onSnapshotChange: ((Snapshot) -> Void)?

    init() {
        audioEngine.attach(playerNode)
    }

    var snapshot: Snapshot {
        Snapshot(
            queuedBuffers: pendingDurations.count,
            queuedDurationSeconds: queuedDurationSeconds,
            isPlaying: playerNode.isPlaying && !pendingDurations.isEmpty
        )
    }

    func prepare() throws {
        #if os(iOS)
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(
            .playback,
            mode: .spokenAudio,
            options: []
        )
        try session.setActive(true)
        #endif
    }

    func enqueue(_ audio: KokoroAudio) throws {
        guard !audio.samples.isEmpty else {
            throw PlaybackError.invalidBuffer
        }

        let buffer = try audio.makePCMBuffer()
        try ensureEngineReady(for: buffer.format)

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

        notifySnapshotChange()
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

        #if os(iOS)
        try? AVAudioSession.sharedInstance().setActive(
            false,
            options: .notifyOthersOnDeactivation
        )
        #endif

        notifySnapshotChange()
    }

    private func ensureEngineReady(for format: AVAudioFormat) throws {
        if let connectedSampleRate,
           let connectedChannelCount
        {
            guard connectedSampleRate == format.sampleRate,
                  connectedChannelCount == format.channelCount
            else {
                throw PlaybackError.inconsistentFormat
            }
        } else {
            audioEngine.connect(
                playerNode,
                to: audioEngine.mainMixerNode,
                format: format
            )
            connectedSampleRate = format.sampleRate
            connectedChannelCount = format.channelCount
        }

        guard !audioEngine.isRunning else {
            return
        }

        audioEngine.prepare()
        try audioEngine.start()
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

        notifySnapshotChange()
        resumeDepthWaiters()

        if pendingDurations.isEmpty {
            resumeDrainWaiters()
        }
    }

    private func notifySnapshotChange() {
        onSnapshotChange?(snapshot)
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
