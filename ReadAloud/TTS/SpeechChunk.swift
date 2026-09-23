import Foundation

struct SpeechChunk: Identifiable, Equatable, Sendable {
    let id: Int
    let text: String
    let targetBucketSeconds: Int
    let estimatedDurationSeconds: Double
}

struct SpeechChunkScheduler: Sendable {
    private let firstBucketSeconds = 3
    private let steadyBucketSeconds = 7
    private let availableBuckets = [3, 7, 10, 15, 30]

    func chunks(
        for text: String,
        speed: Float = 1.0
    ) -> [SpeechChunk] {
        let normalizedSpeed = max(Double(speed), 0.1)
        var pending = sentenceUnits(from: text)

        guard !pending.isEmpty else {
            return []
        }

        var result: [SpeechChunk] = []
        var index = 0
        var isFirstChunk = true

        while !pending.isEmpty {
            let preferredBucket = isFirstChunk
                ? firstBucketSeconds
                : steadyBucketSeconds

            var unit = pending.removeFirst()
            var estimate = estimatedDuration(
                of: unit,
                speed: normalizedSpeed
            )

            if isFirstChunk, estimate > Double(firstBucketSeconds) {
                let pieces = split(
                    unit,
                    maxDurationSeconds: Double(firstBucketSeconds),
                    speed: normalizedSpeed
                )

                if let first = pieces.first {
                    unit = first
                    estimate = estimatedDuration(
                        of: first,
                        speed: normalizedSpeed
                    )

                    if pieces.count > 1 {
                        pending.insert(
                            contentsOf: pieces.dropFirst(),
                            at: 0
                        )
                    }
                }
            } else if estimate > Double(availableBuckets.last ?? 30) {
                let pieces = split(
                    unit,
                    maxDurationSeconds: Double(availableBuckets.last ?? 30),
                    speed: normalizedSpeed
                )

                if let first = pieces.first {
                    unit = first
                    estimate = estimatedDuration(
                        of: first,
                        speed: normalizedSpeed
                    )

                    if pieces.count > 1 {
                        pending.insert(
                            contentsOf: pieces.dropFirst(),
                            at: 0
                        )
                    }
                }
            }

            var bucket = smallestBucket(
                fitting: estimate,
                minimum: preferredBucket
            )

            if estimate <= Double(preferredBucket) {
                var combined = unit

                while let next = pending.first {
                    let candidate = combined + " " + next
                    let candidateEstimate = estimatedDuration(
                        of: candidate,
                        speed: normalizedSpeed
                    )

                    guard candidateEstimate <= Double(preferredBucket) else {
                        break
                    }

                    combined = candidate
                    pending.removeFirst()
                }

                unit = combined
                estimate = estimatedDuration(
                    of: unit,
                    speed: normalizedSpeed
                )
                bucket = preferredBucket
            }

            result.append(
                SpeechChunk(
                    id: index,
                    text: unit,
                    targetBucketSeconds: bucket,
                    estimatedDurationSeconds: estimate
                )
            )

            index += 1
            isFirstChunk = false
        }

        return result
    }

    private func sentenceUnits(from text: String) -> [String] {
        var units: [String] = []
        var current = ""

        func flush() {
            let normalized = normalize(current)
            if !normalized.isEmpty {
                units.append(normalized)
            }
            current = ""
        }

        for character in text {
            current.append(character)

            if character == "."
                || character == "!"
                || character == "?"
                || character == "\n"
            {
                flush()
            }
        }

        flush()
        return units
    }

    private func normalize(_ text: String) -> String {
        text
            .split(whereSeparator: { $0.isWhitespace })
            .joined(separator: " ")
    }

    private func estimatedDuration(
        of text: String,
        speed: Double
    ) -> Double {
        let words = text.split(whereSeparator: { $0.isWhitespace }).count
        let characters = text.count

        let wordEstimate = Double(words) / 2.6
        let characterEstimate = Double(characters) / 16.0
        let base = max(wordEstimate, characterEstimate, 0.25)

        return base / speed
    }

    private func smallestBucket(
        fitting duration: Double,
        minimum: Int
    ) -> Int {
        availableBuckets.first {
            $0 >= minimum && Double($0) >= duration
        } ?? (availableBuckets.last ?? 30)
    }

    private func split(
        _ text: String,
        maxDurationSeconds: Double,
        speed: Double
    ) -> [String] {
        let words = text.split(whereSeparator: { $0.isWhitespace })

        guard !words.isEmpty else {
            return []
        }

        var pieces: [String] = []
        var currentWords: [Substring] = []

        for word in words {
            let candidateWords = currentWords + [word]
            let candidate = candidateWords.joined(separator: " ")

            if !currentWords.isEmpty,
               estimatedDuration(
                   of: candidate,
                   speed: speed
               ) > maxDurationSeconds
            {
                pieces.append(currentWords.joined(separator: " "))
                currentWords = [word]
            } else {
                currentWords = candidateWords
            }
        }

        if !currentWords.isEmpty {
            pieces.append(currentWords.joined(separator: " "))
        }

        return pieces
    }
}
