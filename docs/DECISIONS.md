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

## 2026-11-18 - Voice conversation (Ricardo, by voice call)

- **Talk mode, not a command box.** Tap the mic button and the app holds a spoken conversation, like a voice call with Claude: it listens, answers aloud, listens again. No wake word, and the microphone is open only while the conversation is open (not always listening, like Siri but only inside the app).
- **First version uses the iPhone's own speech** (on-device recognition, system voice). Ricardo agreed to start there. Swapping to Azure neural voices (as AVA does, see docs/VOICE-FROM-AVA.md) is a possible later step if the system voice sounds too robotic; that needs a new Azure key kept on a server, never in this public repo.
- **Honest limit for now:** the conversation can answer what is waiting or running and start new sessions on the PC. Approving and replying to a session need the desktop payloads (HANDOFF section 8) and are not available yet.
- Not built yet: the speaking side (text to speech) and the back-and-forth loop. Today the voice screen only listens, shows what it understood, and asks to confirm.
