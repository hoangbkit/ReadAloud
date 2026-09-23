import Foundation

struct PerformanceMetrics: Equatable {
    var modelLoadSeconds: Double?
    var warmUpSeconds: Double?
    var firstAudioLatencySeconds: Double?
    var latestSynthesisSeconds: Double?
    var latestAudioDurationSeconds: Double?
    var latestRealTimeFactor: Double?
    var latestBucketSeconds: Int?
    var currentChunk = 0
    var totalChunks = 0
    var queuedBuffers = 0
    var queuedDurationSeconds = 0.0
    var underrunCount = 0
    var thermalState = "Nominal"

    mutating func resetForRead() {
        modelLoadSeconds = nil
        firstAudioLatencySeconds = nil
        latestSynthesisSeconds = nil
        latestAudioDurationSeconds = nil
        latestRealTimeFactor = nil
        latestBucketSeconds = nil
        currentChunk = 0
        totalChunks = 0
        queuedBuffers = 0
        queuedDurationSeconds = 0
        underrunCount = 0
        thermalState = Self.currentThermalState
    }

    static var currentThermalState: String {
        switch ProcessInfo.processInfo.thermalState {
        case .nominal:
            return "Nominal"
        case .fair:
            return "Fair"
        case .serious:
            return "Serious"
        case .critical:
            return "Critical"
        @unknown default:
            return "Unknown"
        }
    }
}
