import Foundation

struct SpeechChunk: Identifiable, Equatable, Sendable {
    let id: Int
    let text: String
    let targetBucketSeconds: Int
    let estimatedDurationSeconds: Double
}

struct SpeechChunkScheduler: Sendable {
    private let availableBuckets = KokoroResources.buckets

    private var firstBucketSeconds: Int {
        availableBuckets.first ?? 3
    }

    private var steadyBucketSeconds: Int {
        availableBuckets.dropFirst().first ?? firstBucketSeconds
    }

    func chunks(
        for text: String,
        speed: Float = 1.0
    ) -> [SpeechChunk] {
        let normalizedSpeed = speed.isFinite ? max(Double(speed), 0.1) : 1.0
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

            // Bucket targets are soft: retain a complete sentence or clause
            // even when that means using the next larger bucket.
            if estimate > Double(preferredBucket) {
                let pieces = split(
                    unit,
                    targetDurationSeconds: Double(preferredBucket),
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
        // A line wrap, decimal point, or abbreviation is not by itself the
        // end of a sentence. Let Foundation find linguistic boundaries.
        let text = normalize(text)
        var units: [String] = []
        text.enumerateSubstrings(
            in: text.startIndex..<text.endIndex,
            options: .bySentences
        ) { sentence, _, _, _ in
            if let sentence {
                let unit = normalize(sentence)
                if !unit.isEmpty {
                    units.append(unit)
                }
            }
        }
        return units.isEmpty && !text.isEmpty ? [text] : units
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
        // Match the SDK's TextChunker so it does not re-split a sentence
        // solely because our duration estimate selected too small a bucket.
        let characterEstimate = Double(characters) / 14.0
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
        targetDurationSeconds: Double,
        speed: Double
    ) -> [String] {
        let maximum = Double(availableBuckets.last ?? 30)
        var clauses: [String] = []
        var words: [String] = []

        for word in text.split(whereSeparator: { $0.isWhitespace }) {
            words.append(String(word))
            // Keep closing quotes/brackets attached to their clause. Looking
            // at word endings also protects numbers such as 1,000 and 10:30.
            let ending = word.reversed().first { !"\"'”’)]}".contains($0) }
            if let ending, ",;:—–".contains(ending) {
                clauses.append(words.joined(separator: " "))
                words.removeAll(keepingCapacity: true)
            }
        }
        if !words.isEmpty {
            clauses.append(words.joined(separator: " "))
        }

        var pieces: [String] = []
        var current = ""
        for clause in clauses {
            if estimatedDuration(of: clause, speed: speed) > maximum {
                if !current.isEmpty {
                    pieces.append(current)
                    current = ""
                }
                // Only the model's largest bucket forces a word boundary.
                pieces.append(contentsOf: splitByWords(
                    clause,
                    maxDurationSeconds: maximum,
                    speed: speed
                ))
                continue
            }

            let candidate = current.isEmpty ? clause : current + " " + clause
            if !current.isEmpty,
               estimatedDuration(of: candidate, speed: speed) > targetDurationSeconds {
                pieces.append(current)
                current = clause
            } else {
                current = candidate
            }
        }
        if !current.isEmpty {
            pieces.append(current)
        }
        return pieces
    }

    private func splitByWords(
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
