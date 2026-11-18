# AXYOM Remote

iPhone app to watch and control AXYOM (the desktop agent OS) from anywhere:
what needs you, what is running, every project, a full chat per session,
plan usage, and voice commands.

```
core/   AxyomRemoteCore — Swift, no Apple-only frameworks → tested on Linux
app/    SwiftUI shell (screens, microphone, notifications) → needs macOS
docs/   decisions, test vectors
```

## How it connects

```
iPhone ──WebSocket──► axyom-sync (owner's Cloudflare) ◄──── AXYOM desktop
          JWT minted on the phone from the personal key (HS256, 5 min)
          content end-to-end encrypted (AES-256-GCM); the server sees ciphertext
```

Pairing: the desktop shows a QR (`axyom-pair:1:…`) with the server, the
personal key and the encryption seed. It is valid for 10 minutes.

## Build and test

- Core: `cd core && swift test` (Linux or macOS). CI: `core-tests.yml` on
  `ubuntu-latest`, every push that touches `core/`.
- App: macOS only, added in a later phase (XcodeGen + unsigned compile check,
  then TestFlight with a new App Store Connect API key).

See `docs/DECISIONS.md`.
