# Security

Orbit has access to your screen, camera, and microphone, so security reports get priority.

## Reporting a vulnerability

Please don't open a public issue. Use [private vulnerability reporting](https://github.com/calebynhan/orbit/security/advisories/new) instead, with the steps to reproduce and the macOS version. You'll get a reply within a week.

## What Orbit does to stay small

- No network code, accounts, or uploads. Recordings stay in `~/Movies/Orbit`, readable only by you.
- Opening a recording folder only reads files directly inside it. `project.json` can't point anywhere else, including through symlinks.
- Built with the hardened runtime. The only entitlements are camera and microphone.
- Each release ships with a `.sha256` file for checking the DMG.
