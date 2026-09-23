import Foundation\nimport SwiftUI

struct MetricsView: View {
    let metrics: PerformanceMetrics

    private let columns = [
        GridItem(.flexible(), alignment: .leading),
        GridItem(.flexible(), alignment: .leading),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Live Metrics")
                .font(.headline)

            LazyVGrid(columns: columns, spacing: 10) {
                metric("Model load", seconds(metrics.modelLoadSeconds))
                metric("First audio", seconds(metrics.firstAudioLatencySeconds))
                metric("Synthesis", seconds(metrics.latestSynthesisSeconds))
                metric("Audio", seconds(metrics.latestAudioDurationSeconds))
                metric("RTF", ratio(metrics.latestRealTimeFactor))
                metric(
                    "Scheduled bucket",
                    metrics.latestBucketSeconds.map { "\($0)s" } ?? "—"
                )
                metric(
                    "Chunk",
                    metrics.totalChunks > 0
                        ? "\(metrics.currentChunk)/\(metrics.totalChunks)"
                        : "—"
                )
                metric(
                    "Queue",
                    "\(metrics.queuedBuffers) · \(String(format: "%.1fs", metrics.queuedDurationSeconds))"
                )
                metric("Underruns", "\(metrics.underrunCount)")
                metric("Thermal", metrics.thermalState)
                metric("Warm up", seconds(metrics.warmUpSeconds))
            }
        }
    }

    @ViewBuilder
    private func metric(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)

            Text(value)
                .font(.system(.body, design: .monospaced))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func seconds(_ value: Double?) -> String {
        guard let value else {
            return "—"
        }

        return String(format: "%.3fs", value)
    }

    private func ratio(_ value: Double?) -> String {
        guard let value else {
            return "—"
        }

        return String(format: "%.2f×", value)
    }
}
