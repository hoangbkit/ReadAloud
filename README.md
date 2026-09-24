# ReadAloud

Minimal iOS prototype for local Kokoro Core ML text-to-speech.

## Project configuration

- Bundle ID: `com.hoangbkit.readaloud`
- Development team: `J458WW3452`
- Minimum iOS: 18.0
- Minimum macOS: 15.0
- Project generation: XcodeGen
- Generated Xcode project is intentionally not committed.

## Kokoro SDK

ReadAloud consumes the `KokoroTTS` product from the sibling local
`KokoroCoreML` Swift package.

Keep the repositories next to each other:

```text
Developer/
├── KokoroCoreML/
└── ReadAloud/
```

Prepare the verified Kokoro assets with:

```bash
bash scripts/bootstrap.sh
```

XcodeGen consumes the local package at:

```text
../KokoroCoreML
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

After verification, the downloader also writes a schema-valid custom
`Resources/Kokoro/KokoroRuntimeManifest.json` containing only the exact
models and voices bundled by ReadAloud. The custom manifest preserves the
upstream provenance fields unchanged and records ReadAloud's verified source
manifest digest separately. Downloaded assets and the generated runtime
manifest remain ignored by Git.

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
resource set is incomplete or declares an SDK commit different from the vendored
source pin. `KokoroResources` provides app-side URLs for the
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
AVAudioEngine / AVAudioPlayerNode (connected at Kokoro's PCM format)
```

The scheduler keeps the first chunk intentionally short with a 3-second target,
then uses 7 seconds for normal steady-state chunks and moves to 10, 15, or 30
seconds only when a larger sentence requires it. Long sentences are split on
word boundaries before synthesis instead of synthesizing the full document at
once.

`ReadAloudPipeline` keeps up to two scheduled PCM buffers. It synthesizes the
next chunk while the current buffer is playing, which provides one-buffer
read-ahead without letting memory usage grow with document length. Playback
queue changes are emitted directly by `SpeechPlaybackQueue`, so live metrics
continue to update as buffers drain rather than only when synthesis completes.

Calling `stop()` cancels the active synthesis task and immediately flushes
scheduled playback. The loaded Kokoro engine stays alive between reads so
already-loaded/compiled model state can be reused. `unload()` explicitly drops
the engine when needed.

## Reader prototype UI

The reader screen now drives the complete local pipeline. It includes:

- editable text input;
- bundled voice selection;
- 0.8×, 1.0×, and 1.2× speed choices;
- Read, Stop, and Warm Up controls;
- three built-in repeatable sample passages;
- live pipeline status;
- a compact rolling event log.

The live metrics panel reports model load time, first-audio latency, latest
chunk synthesis time, generated audio duration, RTF, scheduled bucket,
chunk progress, queued audio depth/duration, underrun count, warm-up time, and
the current iOS thermal state.

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

Phases 0-5, consolidation, and the static correctness pass are implemented.
The correctness pass aligns the vendored SDK with the pinned runtime manifest,
enforces that relationship during asset/build validation, and connects
AVAudioPlayerNode using Kokoro's actual PCM format. See `PLAN.md` for the
implementation breakdown.
