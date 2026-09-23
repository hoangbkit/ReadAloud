import Foundation
import Observation

@MainActor
@Observable
final class ReaderViewModel {
    var text = """
    ReadAloud is a local text-to-speech prototype for testing Kokoro Core ML on iPhone.
    """
}
