# ReadAloud

Minimal iOS prototype for local Kokoro Core ML text-to-speech.

## Project configuration

- Bundle ID: `com.hoangbkit.readaloud`
- Development team: `J458WW3452`
- Minimum iOS: 18.0
- Project generation: XcodeGen
- Generated Xcode project is intentionally not committed.

## Generate the project

```bash
xcodegen generate
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

The prototype currently selects all five Kokoro speech buckets (3, 7, 10, 15,
and 30 seconds) and three English voices: `af_heart`, `af_bella`, and
`am_michael`.

Downloaded assets are written under `Resources/Kokoro/` and ignored by Git.

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

Phase 0 provides the SwiftUI/XcodeGen application scaffold. Phase 1 provides the
reproducible Kokoro model and voice asset pipeline. Runtime integration,
bundling, playback, and metrics are added in later phases. See `PLAN.md`.
