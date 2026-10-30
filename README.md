# Orbit

An open-source, local-only screen recorder for macOS with a draggable face-cam bubble, in the spirit of Loom.

- Press **⌘⇧5** to get a toolbar like the macOS screenshot bar, with an extra **Face Cam** button.
- Record the **Entire Screen** or a **Selected Portion**: drag to draw a frame, drag inside it to move it, or drag its edges to resize. A label shows the exact output size.
- Records at **1080p, 60 fps** by default. The **Options** menu has Native/720p/1080p/1440p, a 16:9 or freeform frame, and 30/60 fps. A 16:9 frame at 1080p comes out at exactly **1920×1080**.
- Your camera shows up in a **circle you can drag anywhere** on screen (scroll/pinch or right-click to resize).
- Press **⌘⇧5** again, or click the red stop button in the menu bar, to stop.
- An editor opens where you can **move, resize, mirror, hide, or replace the face cam after recording**, then export an MP4.

Nothing leaves your Mac. Recordings live in `~/Movies/Orbit/`.

## How it works

The screen and the camera are recorded as **separate files**, and Orbit's own windows are excluded from the screen capture. While you record, Orbit samples where the bubble is 30×/sec. The editor composites the two at export, so the face cam is never burned in:

| Editor option | What it does |
| --- | --- |
| **Follow my recording** | Replays the path you dragged the bubble along while recording |
| **Pinned** / drag in preview | Puts the bubble in one spot for the whole video |
| **Size**, **Mirror**, **Face cam** on/off | Change the look at any time, before export |
| **Record Face Cam** | Didn't turn the camera on? Plays the recording back (muted) and records your camera + mic over it |
| **Add Video…** | Use a face clip you already have |

A recording folder holds `screen.mov`, `camera.mov` (if any), and `project.json` (overlay settings and bubble path). Reopen it any time with **Open Recording…** in the menu bar.

## Requirements

- macOS 15 Sequoia or later
- Xcode 16+ (Swift 6 toolchain)

## Build and run

```bash
scripts/build-app.sh
open build/Orbit.app
```

Orbit runs from the menu bar (⏺ icon). On first use macOS asks for **Camera**, **Microphone**, and **Screen & System Audio Recording** permission. After granting screen recording, macOS may ask you to quit and reopen Orbit.

### Using ⌘⇧5

macOS handles ⌘⇧5 itself (its screenshot toolbar) before any app sees the keystroke. On first launch Orbit asks **"Make ⌘⇧5 open Orbit?"** If you click **Use ⌘⇧5 for Orbit**, it turns off macOS's "Screenshot and recording options" shortcut and applies the change right away, so ⌘⇧5 opens Orbit's toolbar instead. ⌘⇧3 and ⌘⇧4 screenshots keep working.

- To undo it: Orbit menu → **Give ⌘⇧5 Back to macOS**.
- If you clicked "Not Now", you can switch later from the Orbit menu.
- You can also do it yourself in System Settings → Keyboard → Keyboard Shortcuts… → Screenshots.

## Development

```bash
swift build          # build
swift test           # unit tests for the timeline, geometry, and project file logic
```

| Path | What lives there |
| --- | --- |
| `Sources/OrbitCore` | Pure logic: bubble path recording/interpolation, coordinate conversions, camera/screen sync, `project.json` |
| `Sources/Orbit/Capture` | ScreenCaptureKit screen recorder, AVFoundation camera, the recording flow |
| `Sources/Orbit/UI` | The ⌘⇧5-style toolbar and the circular camera bubble |
| `Sources/Orbit/Editor` | Preview, Core Image compositor for the circle, export |

## Frame accuracy

- The 16:9 frame snaps to whole points in exact 16:9 steps, so the crop lines up with the pixel grid and scales to 1920×1080 with no black bars or stretching.
- Named resolutions set the short side: a 16:10 MacBook screen at 1080p records at 1728×1080.
- ScreenCaptureKit only writes a frame when the screen changes. The editor and export render at the frame rate you chose, so the MP4 has a constant 60 (or 30) fps.

## Not yet supported

- Recording a single window
- Choosing among several cameras (it uses the system default camera)
- Trimming, and sharing links

## License

AGPL-3.0. The source is free to use and modify; if you distribute a modified version or run it as a service, you must share your changes under the same license. A ready-built, signed app is sold separately.
