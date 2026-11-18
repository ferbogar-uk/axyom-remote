# Decisions

## 2026-11-18 — Ricardo

1. **Linux first.** Everything that is calculation or protocol lives in
   `core/` and is built and tested on Linux (cheap CI). Only the interface
   (SwiftUI, microphone, notifications, camera for the QR) is built on macOS.
2. **Formetra is the reference** for repo layout and CI (core-tests on
   Linux, iOS compile check and TestFlight on macOS), not MURY.
3. **Voice commands** in the app. Speech-to-text is Apple's on-device
   recognizer (app layer); turning the sentence into an action is
   `VoiceCommandParser` in the core.
4. **Design** with the `impeccable`, `design-taste-frontend` and
   `frontend-design` skills. ("ui-ux pro max" was asked for but is not one of
   the installed skills.)
5. **Everything new.** New bundle id, new App Store Connect API key, new CI
   secrets. Nothing reused from MURY or Formetra. The Apple Developer account
   (and its Team ID) is the same account.

## Home screen: option A ("Comando")

Waiting for you · Working · Recent, project chips, plan usage strip,
"+ New session in…", voice button. Tapping a session opens the full chat.
Mockups: AXYOM iOS — 3 conceitos (Claude artifact).

## Protocol

The phone speaks the CollabV3 wire protocol of the AXYOM desktop against the
owner's sync server (`axyom-backend/sync`). Crypto parameters are pinned by
`docs/test-vectors.json`, generated with the desktop's own WebCrypto code.
