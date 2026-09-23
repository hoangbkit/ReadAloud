import Foundation
import KokoroTTS

actor KokoroEngine {
    struct Voice: Identifiable, Equatable, Hashable, Sendable {
        let id: String
        let name: String

        static let heart = Voice(id: "af_heart", name: "Heart")
        static let bella = Voice(id: "af_bella", name: "Bella")
        static let michael = Voice(id: "am_michael", name: "Michael")

        static let all: [Voice] = [.heart, .bella, .michael]
    }

    struct SynthesisResult: Sendable {
        let audio: KokoroAudio
        let elapsedSeconds: Double

        var durationSeconds: Double {
            audio.durationSeconds
        }

        var realTimeFactor: Double {
            guard audio.durationSeconds > 0 else { return 0 }
            return elapsedSeconds / audio.durationSeconds
        }
    }

    struct WarmUpResult: Sendable {
        let elapsedSeconds: Double
    }

    enum EngineError: LocalizedError {
        case notLoaded
        case unsupportedVoice(String)
        case loadFailed(String)
        case warmUpFailed(String)
        case synthesisFailed(String)
        case cancelled

        var errorDescription: String? {
            switch self {
            case .notLoaded:
                return "Kokoro is not loaded."
            case .unsupportedVoice(let voice):
                return "Unsupported Kokoro voice: \(voice)"
            case .loadFailed(let message):
                return "Failed to load Kokoro: \(message)"
            case .warmUpFailed(let message):
                return "Failed to warm up Kokoro: \(message)"
            case .synthesisFailed(let message):
                return "Kokoro synthesis failed: \(message)"
            case .cancelled:
                return "Kokoro operation was cancelled."
            }
        }
    }

    private var tts: KokoroTTS?

    var isLoaded: Bool {
        tts != nil
    }

    var availableVoices: [Voice] {
        Voice.all
    }

    func load() async throws {
        guard tts == nil else { return }

        do {
            _ = try KokoroResources.manifestURL()

            let resources = KokoroResourceProvider.appBundle(
                .main,
                subdirectory: KokoroResources.bundleSubdirectory
            )

            tts = try await KokoroTTS.load(resources: resources)
        } catch is CancellationError {
            throw EngineError.cancelled
        } catch {
            throw EngineError.loadFailed(Self.message(for: error))
        }
    }

    func warmUp(
        text: String = "Hello world.",
        voice: Voice = .heart,
        speed: Float = 1.0
    ) async throws -> WarmUpResult {
        let tts = try loadedTTS()
        try validate(voice: voice)

        let options = KokoroSynthesisOptions(
            speed: speed,
            maxChunkSeconds: 15
        )

        let clock = ContinuousClock()
        let start = clock.now

        do {
            try await tts.prewarm(
                text: text,
                voice: KokoroVoiceID(voice.id),
                options: options
            )

            return WarmUpResult(
                elapsedSeconds: Self.seconds(start.duration(to: clock.now))
            )
        } catch let error as KokoroError where error == .synthesisCancelled {
            throw EngineError.cancelled
        } catch is CancellationError {
            throw EngineError.cancelled
        } catch {
            throw EngineError.warmUpFailed(Self.message(for: error))
        }
    }

    func synthesize(
        text: String,
        voice: Voice = .heart,
        speed: Float = 1.0,
        maxChunkSeconds: Double = 15
    ) async throws -> SynthesisResult {
        let tts = try loadedTTS()
        try validate(voice: voice)

        let options = KokoroSynthesisOptions(
            speed: speed,
            maxChunkSeconds: maxChunkSeconds
        )

        let clock = ContinuousClock()
        let start = clock.now

        do {
            let audio = try await tts.synthesize(
                text,
                voice: KokoroVoiceID(voice.id),
                options: options
            )

            return SynthesisResult(
                audio: audio,
                elapsedSeconds: Self.seconds(start.duration(to: clock.now))
            )
        } catch let error as KokoroError where error == .synthesisCancelled {
            throw EngineError.cancelled
        } catch is CancellationError {
            throw EngineError.cancelled
        } catch {
            throw EngineError.synthesisFailed(Self.message(for: error))
        }
    }

    func unload() {
        tts = nil
    }

    private func loadedTTS() throws -> KokoroTTS {
        guard let tts else {
            throw EngineError.notLoaded
        }
        return tts
    }

    private func validate(voice: Voice) throws {
        guard Voice.all.contains(voice) else {
            throw EngineError.unsupportedVoice(voice.id)
        }
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
