# Contributing

## Setup

```bash
git clone https://github.com/calebynhan/orbit
cd orbit
swift test
scripts/build-app.sh && open build/Orbit.app
```

Xcode 16+, macOS 15+.

Windows and Linux app:

```bash
cd desktop
npm ci
npm test
npm start
```

Node 22+. On Linux you can run the whole record → edit → export flow headless with a fake camera:

```bash
xvfb-run -a -s "-screen 0 1600x900x24" npm run smoke
```

## Rules of thumb

- Logic goes in `OrbitCore` with a test. UI goes in `Orbit`.
- Desktop logic goes in `desktop/src/core` with a test. If you change the project file or the geometry, change both apps.
- Keep files under ~400 lines. Prefer `struct` and `let`.
- No `print`; use `os.Logger`.
- One change per PR. Describe what you tested on a real recording.

## Reporting bugs

Include your OS and version, computer model, and the steps. If a recording failed, attach the `project.json` from the recording folder (`~/Movies/Orbit` on Mac, `Videos\Orbit` on Windows, `~/Videos/Orbit` on Linux).
