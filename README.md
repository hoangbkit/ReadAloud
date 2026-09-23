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

The source `.mlpackage` directories are bundled intact. A later runtime phase
will let the upstream Kokoro SDK compile/cache them in a writable app cache
instead of writing compiled artifacts into the read-only application bundle.

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

Phases 0-2 now provide the SwiftUI/XcodeGen scaffold, reproducible Kokoro asset
download, and app-bundle resource wiring. Kokoro runtime integration, playback,
and live metrics are added in later phases. See `PLAN.md`.
