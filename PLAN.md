# ReadAloud Kokoro Core ML Prototype Plan

## Goal

Build a minimal iOS prototype whose only purpose is to answer one question:

> Can Kokoro 82M Core ML sustain smooth real-time read-aloud playback on an iPhone SE (2nd generation, A13) without audio underruns, excessive startup delay, memory pressure, or thermal degradation?

This is a benchmark/prototype app, not a production reader. Keep the implementation intentionally small and measurable.

## Fixed project configuration

- Repository: `hoangbkit/ReadAloud`
- App name: `ReadAloud`
- Bundle identifier: `com.hoangbkit.readaloud`
- Apple development team: `J458WW3452`
- Project generation: XcodeGen
- Signing: automatic
- Primary test device: iPhone SE (2nd generation / A13)
- TTS: Kokoro 82M, Core ML staged iPhone pipeline
- Audio: 24 kHz mono PCM
- Initial language scope: English only
- Minimum OS: iOS 18.0 unless an upstream dependency forces a higher target

## Upstream baseline

Use the current staged Core ML implementation and Swift SDK from:

- https://github.com/mattmireles/kokoro-coreml
- https://huggingface.co/mattmireles/kokoro-coreml

Pin the model/runtime revision used by the prototype. Do not download from a moving `main` revision at build time.

The current upstream SDK already owns raw-text preparation, Misaki phonemization, chunking, model loading, and AVFoundation-compatible PCM creation. Prefer using that path before writing custom G2P or Kokoro inference code.

---

## Phase 0 — Repository and XcodeGen scaffold

Create the smallest buildable SwiftUI iOS app.

### Deliverables

- `project.yml`
- `ReadAloud/App/ReadAloudApp.swift`
- `ReadAloud/Features/Reader/ReaderView.swift`
- `ReadAloud/Features/Reader/ReaderViewModel.swift`
- `ReadAloud/TTS/`
- `ReadAloud/Benchmark/`
- `Resources/Kokoro/`
- `scripts/`
- `.gitignore`
- short `README.md`

### XcodeGen requirements

Configure the application target with:

```yaml
PRODUCT_BUNDLE_IDENTIFIER: com.hoangbkit.readaloud
DEVELOPMENT_TEAM: J458WW3452
CODE_SIGN_STYLE: Automatic
```

Use XcodeGen as the source of truth. Do not manually maintain or commit hand-edited Xcode project settings.

The generated app must build and install on the SE2 before any Kokoro work begins.

### Acceptance criteria

- `xcodegen generate` succeeds.
- App builds from CLI.
- App installs and launches on the SE2.
- Bundle ID and team ID are correct in the generated project.

---

## Phase 1 — Reproducible Kokoro asset download

Add a Bash-based asset pipeline so a clean checkout can obtain the exact Kokoro resources used by the benchmark.

### Files

- `scripts/download-kokoro-assets.sh`
- `scripts/kokoro-checksums.sha256`
- optionally `scripts/verify-kokoro-assets.sh`

### Script requirements

The downloader must:

1. pin an immutable upstream revision;
2. download only the model buckets and voices selected for this prototype;
3. download into a temporary directory first;
4. verify SHA-256 for every downloaded artifact;
5. fail immediately on a missing file or checksum mismatch;
6. move verified files into `Resources/Kokoro/` only after the whole set passes;
7. be idempotent;
8. support a verification-only mode;
9. print the pinned revision and verified asset list;
10. never silently replace a mismatched local file.

Use macOS-provided tools where possible: `curl`, `shasum -a 256`, `mktemp`.

Do not depend on "latest" assets. Keep the expected hashes in the repository so a future upstream change cannot silently alter benchmark results.

### Initial asset scope

Bundle the fixed-duration Core ML paths needed to test:

- 3 s
- 7 s
- 10 s
- 15 s
- 30 s

Start with a very small voice set so voice assets do not distort app-size or memory measurements. Suggested benchmark voices:

- `af_heart`
- one additional female English voice
- one male English voice

The exact three voices should be pinned in the checksum manifest.

### Git policy

Large downloaded model binaries should not need to be committed to Git if the download script can recreate them exactly. The local resource directory may be ignored while its directory structure/manifest remains tracked.

### Acceptance criteria

A fresh clone can run one command and produce a byte-for-byte verified Kokoro resource bundle.

---

## Phase 2 — Bundle models and voices with XcodeGen

Make the downloaded resources part of the generated application bundle.

### Resource layout

Target a predictable structure such as:

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

The exact layout may follow the upstream Swift SDK bundle contract if that avoids adaptation code.

### XcodeGen behavior

- Declare the Kokoro resource directory in `project.yml`.
- Ensure model files and voice embeddings are present in the built app.
- Prefer precompiled `.mlmodelc` resources when the upstream tooling supports them reliably, to reduce first-run compilation work.
- If raw `.mlpackage` files must be bundled, compile/copy them in a deterministic way and keep writable compiled artifacts outside the read-only app bundle.
- Add a build-time validation step that fails with a clear message when required assets are missing.

### Acceptance criteria

On the physical SE2, the app can enumerate every expected model bucket and voice directly from its own bundle with airplane mode enabled.

---

## Phase 3 — Minimal Kokoro Core ML runtime

Integrate the upstream Swift runtime with as little custom inference code as possible.

### Components

Create a small wrapper layer, for example:

```text
KokoroEngine
├── load()
├── prewarm(text:voice:)
├── synthesize(text:voice:)
└── unload()
```

The wrapper should expose timing information without hiding upstream errors.

### Runtime rules

- Use the staged iPhone compute policy supported by the Core ML implementation.
- Do not force all stages onto `.all` / ANE just because it sounds faster.
- Keep loaded model instances reusable across utterances.
- Perform an explicit prewarm before warm benchmark runs.
- Keep synthesis off the main actor.
- Keep UI state updates on the main actor.
- Return raw timing data together with generated PCM.

### Acceptance criteria

The SE2 can synthesize a known sentence to audible speech locally with no network access.

---

## Phase 4 — Reader and streaming playback prototype

Build only enough UI to reproduce real read-aloud behavior.

### UI

Single-screen prototype:

- large editable text area;
- bundled voice picker;
- `Load Models`;
- `Warm Up`;
- `Read`;
- `Stop`;
- optional chunk strategy picker;
- live metrics panel;
- simple event log.

Ship a few long built-in sample passages so repeated benchmark runs use identical text.

### Reading pipeline

Use a producer/consumer design:

```text
long text
   ↓
sentence-aware chunker
   ↓
bucket selection
   ↓
Kokoro synthesis
   ↓
PCM queue
   ↓
AVAudioEngine / AVAudioPlayerNode
```

For the first experiment:

- make the first chunk intentionally short to minimize time-to-first-audio;
- synthesize later chunks while the current chunk is playing;
- maintain at least one ready-ahead PCM buffer when possible;
- never synthesize an entire article before playback begins.

Start with a policy roughly equivalent to:

- first utterance → 3 s bucket;
- steady-state short utterance → 7 s bucket;
- larger sentence group → 10 s or 15 s bucket;
- 30 s bucket only as a stress test, not the default reader path.

The upstream chunker should be the baseline. Only add a custom sentence/bucket policy if measurements show it is necessary.

### Acceptance criteria

A multi-minute passage plays continuously from local Kokoro output and can be stopped immediately.

---

## Phase 5 — Benchmark instrumentation

The app must measure performance rather than rely on subjective impressions.

### Record per synthesis

- input character count;
- token/phoneme count if available;
- selected model bucket;
- voice;
- synthesis wall time;
- generated audio duration;
- real-time factor;
- queue depth before synthesis;
- queue depth after synthesis;
- underrun occurrence;
- warm vs cold run.

Calculate:

```text
RTF = synthesis wall time / generated audio duration
```

Interpretation:

- RTF < 1.0: generation is faster than playback.
- RTF = 1.0: no performance headroom.
- RTF > 1.0: cannot sustain real-time playback without a growing initial buffer.

Also capture:

- model load time;
- prewarm time;
- tap-to-first-audio latency;
- peak/approximate process memory where practical;
- current `ProcessInfo.processInfo.thermalState`;
- audio underrun count;
- total test duration.

Use `ContinuousClock` or another monotonic clock for latency measurements.

### Output

Show a live summary in the app and emit a machine-readable result, preferably JSON, that can be copied or shared after each benchmark session.

---

## Phase 6 — SE2 benchmark matrix

Run all important measurements on the physical SE2 in Release configuration.

Debug builds are not valid for the final performance decision.

### A. Cold-start test

Measure:

- fresh process launch;
- model load;
- first prewarm;
- first speech.

Repeat after force-quitting the app.

### B. Warm single-utterance test

For each relevant bucket:

- 3 s;
- 7 s;
- 10 s;
- 15 s;
- 30 s;

run at least five warm iterations with the same voice and text class.

Report median and worst observed synthesis time and RTF.

### C. Real reading test

Read a fixed 10-minute passage using the streaming queue.

Measure:

- time to first audio;
- number of underruns;
- average and worst RTF;
- minimum observed ready-ahead audio;
- memory behavior;
- thermal state changes.

### D. Voice comparison

Repeat the steady-state test across the bundled voices to detect meaningful voice-specific cost.

### E. Chunk-policy comparison

Compare at least:

1. sentence-by-sentence;
2. short first chunk + 7 s steady-state;
3. short first chunk + 10/15 s adaptive steady-state.

Keep everything else constant.

---

## Phase 7 — Decision criteria and report

The prototype ends with a written benchmark report. Do not turn it into a production app before answering the performance question.

### Minimum pass

Kokoro is considered viable for real-time SE2 reading if a 10-minute Release-mode run:

- has zero playback underruns after playback begins;
- maintains sustained warm RTF below 1.0;
- does not trend toward an ever-growing synthesis backlog;
- avoids memory termination;
- remains usable as the device heats up.

### Preferred target

For enough safety margin to use in a real reader:

- steady-state median RTF <= 0.7;
- warm first-chunk synthesis around or below 1.5 s;
- no underruns in the 10-minute test;
- stable or bounded memory;
- no severe thermal-state-induced collapse.

Treat these as prototype targets, not marketing claims.

### Final report

Add `BENCHMARK.md` containing:

- exact SE2 model and iOS version;
- app commit SHA;
- Kokoro upstream revision;
- model checksum set;
- voice;
- Release build configuration;
- benchmark table;
- chosen chunk policy;
- cold-start result;
- 10-minute sustained result;
- memory/thermal observations;
- conclusion: viable, viable with buffering, or not viable on A13.

---

## Suggested repository shape

```text
ReadAloud/
├── project.yml
├── README.md
├── PLAN.md
├── BENCHMARK.md                 # added after measurements
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
    └── Benchmark/
        ├── BenchmarkRecorder.swift
        ├── BenchmarkResult.swift
        └── BenchmarkView.swift
```

## Non-goals

Do not add these until the SE2 benchmark is complete:

- document import;
- EPUB/PDF extraction;
- cloud TTS;
- accounts;
- purchases/paywall;
- persistence/database;
- background audio polish;
- production settings architecture;
- analytics;
- broad localization;
- model download UI.

The prototype should remain disposable. Its job is to produce trustworthy A13 measurements quickly.
