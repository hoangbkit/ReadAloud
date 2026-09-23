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

Phase 0 contains only the SwiftUI/XcodeGen application scaffold. Kokoro models, voices, inference, playback, and metrics are added in later phases. See `PLAN.md`.
