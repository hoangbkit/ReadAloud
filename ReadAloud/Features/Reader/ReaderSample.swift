import Foundation

struct ReaderSample: Identifiable, Sendable {
    let id: String
    let title: String
    let text: String

    static let all: [ReaderSample] = [
        ReaderSample(
            id: "morning",
            title: "Morning Walk",
            text: """
            The city was already awake when I stepped outside, but the street still felt calm. A delivery bicycle rolled past the corner, a coffee shop lifted its shutters, and the first buses moved through the intersection with only a handful of passengers. I started walking without a destination. The air was warm, the trees were almost still, and every few minutes a breeze carried the smell of breakfast from a nearby kitchen.

            At the river, the pace changed. Runners followed the path beside the water while older couples sat on benches and talked quietly. I stopped for a moment and watched the sunlight move across the buildings on the opposite bank. Nothing unusual happened, which was exactly why the walk felt useful. It gave the morning enough space to begin before messages, code, meetings, and small decisions filled the rest of the day.
            """
        ),
        ReaderSample(
            id: "technology",
            title: "Local Computing",
            text: """
            A useful local application does not need to imitate a cloud service. It can make different tradeoffs. The model can live beside the interface, the user can keep private data on the device, and common actions can continue when the network is slow or completely unavailable. The difficult part is not simply shrinking a model until it fits. The entire product has to respect the limits of the hardware.

            Latency matters because people notice the delay before the first result. Throughput matters because a fast first response is not enough if later work falls behind. Memory matters because mobile operating systems protect the rest of the device aggressively. Thermal behavior matters because a benchmark collected during the first minute may look very different after ten minutes of continuous work.

            Good on-device software therefore behaves like a pipeline. It starts with the smallest useful piece of work, produces something the user can consume immediately, and prepares the next piece while the current one is still being used. When each stage is bounded and observable, a surprisingly capable experience can run on modest hardware.
            """
        ),
        ReaderSample(
            id: "long-form",
            title: "Long-form Reading",
            text: """
            Long-form reading sounds simple until a speech engine has to perform it continuously. A single sentence is forgiving. The application can prepare the text, run the model, allocate an audio buffer, and play the result. A chapter is different. If the application waits for the entire chapter before playback begins, startup becomes frustrating and memory usage grows with the document. If it creates pieces that are too small, the voice can sound fragmented and the system spends too much time switching between stages.

            A practical reader works incrementally. The first piece should be short enough to begin quickly. While that audio is playing, the next piece can move through phonemization and synthesis. The playback queue only needs a small amount of audio in reserve; storing minutes of generated speech is unnecessary when the model can stay ahead of the listener.

            Sentence boundaries are useful because they usually preserve natural phrasing, but they are not absolute. Some sentences are long enough to exceed the model's preferred duration, so the scheduler needs a fallback that can split them safely. Other sentences are tiny and can be combined without changing their meaning. The goal is not to predict the exact spoken duration perfectly. The scheduler only needs estimates that are good enough to choose a reasonable model bucket and keep the pipeline moving.

            The most revealing signal is what happens between chunks. If synthesis finishes before the queued audio runs out, playback remains continuous. If the queue reaches zero while another chunk is still being generated, the listener hears a gap. That underrun is more informative than a single isolated benchmark because it captures the behavior of the complete system: text preparation, model execution, scheduling, and playback all working together over time.
            """
        ),
    ]
}
