# Contributing

## Setup

```bash
git clone https://github.com/calebynhan/orbit
cd orbit
swift test
scripts/build-app.sh && open build/Orbit.app
```

Xcode 16+, macOS 15+.

## Rules of thumb

- Logic goes in `OrbitCore` with a test. UI goes in `Orbit`.
- Keep files under ~400 lines. Prefer `struct` and `let`.
- No `print`; use `os.Logger`.
- One change per PR. Describe what you tested on a real recording.

## Reporting bugs

Include macOS version, Mac model, and the steps. If a recording failed, attach the `project.json` from the recording folder in `~/Movies/Orbit`.
