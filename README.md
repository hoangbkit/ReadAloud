# ReadAloud

Minimal iOS prototype for local Kokoro Core ML text-to-speech.

## Project configuration

- Bundle ID: `com.hoangbkit.readaloud`
- Development team: `J458WW3452`
- Minimum iOS: 18.0
- Project generation: XcodeGen
- Generated Xcode project is intentionally not committed.

## Kokoro SDK

ReadAloud uses the upstream `KokoroTTS` Swift SDK from
`mattmireles/kokoro-coreml`. The source checkout is intentionally not
committed into this repository.

Fetch the pinned SDK source before generating the Xcode project:

```bash
bash scripts/download-kokoro-sdk.sh
```

The script pins upstream commit
`0594fcca424fa4228f4627ee399fbfd3e066eac6` and checks out only the upstream
`swift/` and `swift-tts/` package trees under `Vendor/kokoro-coreml/`.
The upstream `swift-tts` package owns Misaki phonemization and pins its own
MisakiSwift dependency.

XcodeGen consumes the local package at:

```text
Vendor/kokoro-coreml/swift-tts
```

## Kokoro assets

Kokoro model and voice binaries are not committed to Git. Download the pinned,
checksum-verified asset set with:

```bash
bash scripts/download-kokoro-assets.sh
```

Verify an existing local asset set without replacing files:

```bash
bash scripts/verify-kokoro-assets.sh
```

The asset pipeline pins the upstream Hugging Face revision and first verifies
the full-profile runtime manifest against `scripts/kokoro-checksums.sha256`.
Every selected model file, voice, vocab file, and hn-NSF weight file is then
verified against the per-file SHA-256 and byte count from that trusted manifest.

The prototype selects all five Kokoro speech buckets (3, 7, 10, 15, and 30
seconds) and three English voices: `af_heart`, `af_bella`, and
`am_michael`.

After verification, the downloader also writes a
`Resources/Kokoro/KokoroRuntimeManifest.json` containing only the exact
models and voices bundled by ReadAloud. Downloaded assets and the generated
runtime manifest remain ignored by Git.

## App resource bundling

XcodeGen copies `Resources/Kokoro` into the app as a folder resource named
`Kokoro`, preserving the upstream SDK layout:

```text
Kokoro/
├── KokoroRuntimeManifest.json
├── coreml/
│   ├── kokoro_duration_t128.mlpackage
│   └── bucket-specific .mlpackage directories
├── voices/
│   ├── af_heart.bin
│   ├── af_bella.bin
│   └── am_michael.bin
└── runtime/
    ├── kokoro-vocab.json
    └── hnsf_weights.json
```

A pre-build validation script fails with a direct message if the downloaded
resource set is incomplete. `KokoroResources` provides app-side URLs for the
manifest, model packages, voices, vocab, and hn-NSF weights.

The source `.mlpackage` directories are bundled intact. The upstream SDK
compiles and caches Core ML models in its writable manifest-keyed cache rather
than attempting to write compiled artifacts into the application bundle.

## Kokoro engine

`KokoroEngine` is the app-owned boundary around the upstream SDK. It exposes:

```text
load()
warmUp(text:voice:speed:)
synthesize(text:voice:speed:maxChunkSeconds:)
unload()
```

ReadAloud owns lifecycle, bundled-resource selection, cancellation/error
mapping, and synthesis timing. The upstream SDK owns raw-text preparation,
Misaki phonemization, chunk preparation, voice embeddings, staged Core ML
inference, and 24 kHz mono PCM generation.

The engine currently exposes the three bundled voices and returns synthesis
duration plus real-time factor with each generated `KokoroAudio`.

## Continuous read-aloud pipeline

Phase 4 adds the streaming reader path:

```text
text
  ↓
SpeechChunkScheduler
  ↓
KokoroEngine
  ↓
SpeechPlaybackQueue
  ↓
AVAudioEngine / AVAudioPlayerNode
```

The scheduler keeps the first chunk intentionally short with a 3-second target,
then uses 7 seconds for normal steady-state chunks and moves to 10, 15, or 30
seconds only when a larger sentence requires it. Long sentences are split on
word boundaries before synthesis instead of synthesizing the full document at
once.

`ReadAloudPipeline` keeps up to two scheduled PCM buffers. It synthesizes the
next chunk while the current buffer is playing, which provides one-buffer
read-ahead without letting memory usage grow with document length.

Calling `stop()` cancels the active synthesis task and immediately flushes
scheduled playback. The loaded Kokoro engine stays alive between reads so
already-loaded/compiled model state can be reused. `unload()` explicitly drops
the engine when needed.

The existing reader screen is intentionally not wired to this pipeline yet.
Phase 5 owns the prototype controls and live metrics UI.

## Generate the project

After fetching the SDK and model assets:

```bash
xcodegen generate
```

## Build from the command line

Simulator build:

```bash
xcodebuild \
  -project ReadAloud.xcodeproj \
  -scheme ReadAloud \
  -configuration Debug \
  -sdk iphonesimulator \
  CODE_SIGNING_ALLOWED=NO \
  build
```

For a physical iPhone, generate the project and build the `ReadAloud` scheme with automatic signing.

## Current scope

Phases 0-4 now provide the SwiftUI/XcodeGen scaffold, reproducible Kokoro
assets, app-bundle resource wiring, the local Kokoro Core ML engine, and the
continuous read-ahead playback pipeline. Phase 5 adds the prototype reader
controls and live metrics UI. See `PLAN.md`.
