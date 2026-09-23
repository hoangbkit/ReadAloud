# ReadAloud Kokoro Core ML Prototype Plan

## Goal

Build a minimal iOS app that can read text continuously with Kokoro 82M Core ML and expose enough runtime metrics to judge real-time performance on-device.

## Fixed project configuration

- Repository: `hoangbkit/ReadAloud`
- App name: `ReadAloud`
- Bundle identifier: `com.hoangbkit.readaloud`
- Apple development team: `J458WW3452`
- Project generation: XcodeGen
- Signing: automatic
- TTS: Kokoro 82M, Core ML staged iPhone pipeline
- Phonemization: upstream/native Misaki Swift path
- Audio: 24 kHz mono PCM
- Initial language scope: English only
- Minimum OS: iOS 18.0 unless an upstream dependency forces a higher target

## Upstream baseline

Use the current staged Core ML implementation and Swift SDK from:

- https://github.com/mattmireles/kokoro-coreml
- https://huggingface.co/mattmireles/kokoro-coreml

Pin the model/runtime revision used by the app. Do not download from a moving `main` revision at build time.

Prefer the upstream pipeline for text preparation, Misaki phonemization, chunking/model inputs, model loading, and Kokoro inference. Keep our code focused on app integration, streaming, playback, and metrics.

---

## Phase 0 — XcodeGen app scaffold

Create the minimal SwiftUI iOS app and repository structure.

### Deliverables

- `project.yml`
- `ReadAloud/App/ReadAloudApp.swift`
- `ReadAloud/Features/Reader/ReaderView.swift`
- `ReadAloud/Features/Reader/ReaderViewModel.swift`
- `ReadAloud/TTS/`
- `ReadAloud/Audio/`
- `ReadAloud/Metrics/`
- `Resources/Kokoro/`
- `scripts/`
- `.gitignore`
- short `README.md`

### XcodeGen requirements

```yaml
PRODUCT_BUNDLE_IDENTIFIER: com.hoangbkit.readaloud
DEVELOPMENT_TEAM: J458WW3452
CODE_SIGN_STYLE: Automatic
```

Use XcodeGen as the source of truth. Do not maintain a hand-edited Xcode project.

### Done when

- `xcodegen generate` succeeds.
- App builds from CLI.
- App launches on a physical iPhone.
- Bundle ID and team ID are correct.

---

## Phase 1 — Reproducible Kokoro assets

Add a Bash pipeline that downloads the exact model and voice assets required by the app.

### Files

- `scripts/download-kokoro-assets.sh`
- `scripts/verify-kokoro-assets.sh`
- `scripts/kokoro-checksums.sha256`

### Requirements

The script must:

1. pin an immutable upstream revision;
2. download only required model buckets and voices;
3. download to a temporary directory first;
4. verify SHA-256 for every artifact;
5. fail on missing files or checksum mismatch;
6. move files into `Resources/Kokoro/` only after all verification succeeds;
7. be idempotent;
8. support verification-only use;
9. print the pinned revision and verified files;
10. never silently replace a mismatched local file.

Use standard macOS tools where possible: `curl`, `shasum -a 256`, and `mktemp`.

### Initial asset scope

Bundle the Core ML duration buckets used by the upstream iPhone pipeline:

- 3 s
- 7 s
- 10 s
- 15 s
- 30 s

Bundle a small fixed voice set initially:

- `af_heart`
- one additional female English voice
- one male English voice

Pin all voice assets in the checksum manifest.

### Done when

A clean checkout can run one command and recreate the exact verified Kokoro resource set.

---

## Phase 2 — XcodeGen model and voice bundling

Make all verified Kokoro assets available from the application bundle.

### Resource layout

```text
Resources/
└── Kokoro/
    ├── Models/
    │   ├── 3s/
    │   ├── 7s/
    │   ├── 10s/
    │   ├── 15s/
    │   └── 30s/
    ├── Voices/
    └── manifest.json
```

Follow the upstream SDK resource layout instead if doing so removes adaptation code.

### Requirements

- Declare Kokoro resources in `project.yml`.
- Ensure all required models and voices are copied into the built app.
- Prefer precompiled `.mlmodelc` assets when the upstream flow supports them reliably.
- Add a clear build-time failure when expected assets are missing.
- Add a small resource loader that resolves model and voice URLs from `Bundle.main`.

### Done when

The app can enumerate and resolve every bundled model bucket and voice with no network access.

---

## Phase 3 — Kokoro Core ML engine

Integrate the upstream Kokoro Swift/Core ML pipeline behind a thin app-owned wrapper.

### App-owned wrapper

```text
KokoroEngine
├── load()
├── warmUp(text:voice:)
├── synthesize(text:voice:)
├── availableVoices
└── unload()
```

### Responsibilities

Upstream owns:

- text preparation;
- Misaki phonemization;
- Kokoro token/model input preparation;
- staged Core ML inference;
- voice embedding handling;
- raw PCM generation.

ReadAloud owns:

- lifecycle;
- resource lookup;
- async execution;
- cancellation;
- error mapping;
- timing capture;
- interface consumed by the reader pipeline.

### Runtime rules

- Use the upstream staged iPhone compute policy.
- Keep model instances loaded and reusable.
- Keep inference off the main actor.
- Keep UI state changes on the main actor.
- Do not rewrite G2P or model inference unless an upstream limitation requires it.

### Done when

The app can turn typed English text into audible Kokoro speech completely offline.

---

## Phase 4 — Continuous read-aloud pipeline

Build the actual reader behavior around Kokoro.

### Pipeline

```text
Text
  ↓
sentence-aware chunk scheduler
  ↓
KokoroEngine
  ↓
PCM buffer
  ↓
read-ahead queue
  ↓
AVAudioEngine / AVAudioPlayerNode
```

### Requirements

- Start with a short first chunk for low startup latency.
- Generate the next chunk while the current chunk is playing.
- Keep at least one ready-ahead buffer when possible.
- Select the smallest suitable upstream duration bucket for each chunk.
- Preserve sentence boundaries where practical.
- Support immediate cancellation.
- Flush pending synthesis/audio cleanly on Stop.
- Reuse already-loaded models between reads.
- Never synthesize the full article before playback begins.

A reasonable initial bucket policy:

- first chunk → 3 s;
- normal short chunk → 7 s;
- larger sentence group → 10 s or 15 s;
- 30 s only when the text genuinely requires it.

### Done when

A multi-minute text can be read continuously, with synthesis and playback operating concurrently and Stop working immediately.

---

## Phase 5 — Reader UI and live performance metrics

Finish the prototype UI and expose the measurements needed while using it.

### Single-screen UI

Include:

- editable text area;
- bundled voice picker;
- `Read`;
- `Stop`;
- optional `Warm Up`;
- current state: loading / synthesizing / playing / stopped / error;
- live metrics panel;
- compact event log;
- a few built-in long sample passages for repeatable use.

### Live metrics

Capture and display at minimum:

- model load time;
- first-audio latency;
- synthesis time per chunk;
- generated audio duration;
- real-time factor;
- selected duration bucket;
- current/ready queue depth;
- underrun count;
- current thermal state.

Use:

```text
RTF = synthesis wall time / generated audio duration
```

Use a monotonic clock such as `ContinuousClock` for latency measurements.

Keep the UI diagnostic rather than polished; this is still a prototype.

### Done when

The app is a complete standalone prototype: launch it, type or select text, choose a voice, tap Read, hear continuous local Kokoro speech, stop at any time, and observe live performance metrics.

---

## Phase 6 — Consolidation

Consolidate the completed prototype so the phases behave as one coherent app rather than a stack of isolated additions.

### Requirements

- preserve upstream Kokoro manifest provenance when generating the ReadAloud subset;
- use the schema-valid `custom` runtime bundle profile;
- prevent cancelled or superseded async operations from publishing stale state;
- publish playback queue changes directly as buffers are enqueued and drained;
- keep scheduled bucket configuration shared with the bundled Kokoro resources;
- remove duplicated queue-metric plumbing from synthesis events;
- provide one bootstrap command for the pinned SDK and verified model assets;
- keep the pass implementation-only with no CI or runtime validation work.

### Done when

The asset, engine, streaming, metrics, and UI layers have clear ownership boundaries and no known cross-phase inconsistencies remain in static review.

---

## Suggested repository shape

```text
ReadAloud/
├── project.yml
├── README.md
├── PLAN.md
├── scripts/
│   ├── download-kokoro-assets.sh
│   ├── verify-kokoro-assets.sh
│   └── kokoro-checksums.sha256
├── Resources/
│   └── Kokoro/
└── ReadAloud/
    ├── App/
    │   └── ReadAloudApp.swift
    ├── Features/
    │   └── Reader/
    │       ├── ReaderView.swift
    │       └── ReaderViewModel.swift
    ├── TTS/
    │   ├── KokoroEngine.swift
    │   ├── KokoroResources.swift
    │   └── SpeechChunk.swift
    ├── Audio/
    │   └── SpeechPlaybackQueue.swift
    └── Metrics/
        ├── PerformanceMetrics.swift
        └── MetricsView.swift
```

## Non-goals

Do not add these to this prototype:

- document import;
- EPUB/PDF extraction;
- cloud TTS;
- accounts;
- purchases/paywall;
- persistence/database;
- analytics;
- broad localization;
- model download UI;
- production-level settings architecture.
