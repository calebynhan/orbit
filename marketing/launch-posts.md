# Launch posts (drafts — nothing posted until you approve)

Order: Show HN first (Tuesday–Thursday, 8–10am ET gets the most eyes), r/macapps the same day,
X the day after with the demo video, Product Hunt a week later once a few bugs from HN are fixed.
Reply to every comment within the first two hours; that decides whether a post climbs.

---

## Show HN

**Title** (80 chars max, no pitch, no exclamation marks):

Show HN: Orbit – open-source Mac screen recorder where you can move your face after

(Alternative: `Show HN: Orbit – Loom-style Mac recorder, local-only, face cam movable after recording`)

**URL:** https://github.com/calebynhan/orbit

**First comment** (post it yourself immediately after submitting):

I built this because every time I recorded a Loom, my face ended up covering the thing I was pointing at, and the only fix was to re-record.

Orbit records the screen and the camera as separate files and remembers where the face circle was. After you stop, you can replay the path, pin the circle somewhere else, resize it, or re-record just the camera over the playback. Then it exports one MP4.

Other things I cared about:
- ⌘⇧5 opens it, like the macOS screenshot bar (it asks before taking over the shortcut, and can give it back)
- Nothing is uploaded. No account. Recordings go to ~/Movies/Orbit.
- Selected-area recording with a 16:9 lock that snaps to an exact 1920×1080 at 1080p, constant 60 fps.

Swift, ScreenCaptureKit, AVFoundation, Core Image for the circle. AGPL-3.0. macOS 15+.

It's a beta and not notarized yet (I'll pay Apple's $99 once I know people want it), so macOS makes you click "Open Anyway" once. No share links, no analytics, no Windows version — if you need those, Loom or Cap will serve you better.

Site: https://calebynhan.github.io/orbit/

I'd love to hear what breaks.

---

## r/macapps

Check the sidebar first: it allows developer posts if flaired "Developer" / self-promotion and you stay in the thread. Don't crosspost the same text to r/apple.

**Title:** I made a free, open-source screen recorder where you can move your face cam after recording (⌘⇧5, local-only)

**Body:**

Hi r/macapps. I've been building Orbit, a menu-bar screen recorder, because I was tired of re-recording Looms whenever my face landed on top of the thing I was demoing.

What it does:
- ⌘⇧5 opens a bar like the macOS one, with a Face Cam button. Your camera goes in a circle you can drag anywhere and resize.
- After you stop, an editor opens. The screen and camera are separate files, so you can move the circle, resize it, mirror it, hide it, or re-record it over the playback. Export one MP4.
- Entire screen or a selected area. The 16:9 lock gives you an exact 1920×1080 at 1080p.
- No account, no upload, no subscription. Recordings stay in ~/Movies/Orbit.

It's a free beta, open source (AGPL), macOS 15+. Not notarized yet, so you have to click "Open Anyway" once in Privacy & Security; instructions are on the site.

Site: https://calebynhan.github.io/orbit/
Source: https://github.com/calebynhan/orbit

Honest gaps: no share links, no viewer analytics, Mac only. I'll be in the comments all day — tell me what's broken or missing.

---

## r/SideProject (optional, a day later)

**Title:** Loom charges $18/user/month. I built an open-source Mac alternative that keeps everything local and lets you fix the face cam after recording.

Body: same as r/macapps, trimmed to 6 lines.

---

## X / Twitter (post with the demo video attached)

Tweet 1:
Loom bakes your face into the video. If it covers something, you re-record.

So I built Orbit: an open-source Mac recorder where the face cam is separate, so you can move it, resize it, or re-record it *after* you stop.

Free beta, nothing uploaded, no subscription. ⬇️

Tweet 2 (reply):
⌘⇧5 opens it, like the macOS screenshot bar. Selected-area recording snaps to an exact 1920×1080 at 60 fps.

Swift + ScreenCaptureKit + Core Image. AGPL.

Site: https://calebynhan.github.io/orbit/
Code: https://github.com/calebynhan/orbit

Tweet 3 (reply):
Not notarized yet (Apple's $99/yr comes after I know people want it), so macOS asks you to click Open Anyway once. Mac only, macOS 15+. Tell me what breaks.

---

## Product Hunt (a week after HN)

**Tagline (60 chars):** Screen recording with your face anywhere — even after you stop
**Description:** Orbit is a free, open-source Mac screen recorder. Press ⌘⇧5, put your camera in a draggable circle, and move it again after recording. No account, no upload, no subscription.
**Topics:** Mac, Open Source, Productivity, Video
**First comment:** adapt the Show HN comment; add "Launching here after a week of Hacker News feedback — here's what changed: …"
