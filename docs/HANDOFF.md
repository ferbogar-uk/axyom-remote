# AXYOM Remote — handoff (2026-11-18)

You are taking over the **iPhone app** for AXYOM. Another session keeps
working on the AXYOM desktop app and the sync server. This file is the
contract between the two sessions.

## 1. What the app is

An iPhone app to watch and control AXYOM (Ricardo's Electron agent OS, a fork
of Nimbalyst) from anywhere: what needs him, what is running, all projects,
full chat per session, plan usage, voice commands, and starting sessions on
the PC.

Home screen = **option A "Comando"** (chosen 2026-11-18): plan-usage strip,
project chips, "À espera de ti" cards (approve / deny / answer), "A
trabalhar" with progress, "+ Nova sessão em…", voice button. Tapping a
session opens the full chat (option B). Mockups (Claude Design canvas):
https://claude.ai/artifact/8mc18qBeoVA7xjSLrpMwwx — artboard "A · Comando dos agentes".

## 2. Ricardo's rules for this app (non-negotiable)

1. **Linux first.** All logic in `core/` (Swift, no Apple-only frameworks),
   built and tested on `ubuntu-latest`. Only UI (SwiftUI, microphone,
   camera, notifications) is built on macOS, and only when the UI changes.
   macOS minutes cost ~10× Linux.
2. **Formetra is the reference** for layout and CI
   (github.com/ferbogar-uk/formetra: `core-tests.yml`, `ios-compile.yml`,
   `ios-testflight.yml`; Apple-managed signing with 4 secrets). Not MURY.
3. **Voice commands.** Apple's on-device speech recognizer in the app;
   `VoiceCommandParser` in the core turns the text into an action.
4. **Design** with the `impeccable` (it has native iOS guidance),
   `design-taste-frontend` and `frontend-design` skills. ("ui-ux pro max"
   was requested but is not installed — say so if asked.)
5. **Everything new**: new bundle id, new App Store Connect API key, new CI
   secrets. Reuse nothing from MURY/Formetra. Same Apple Developer account.

Working style: talk to Ricardo in **Portuguese**, visually, short. Ask
decisions as on-screen multiple choice (AskUserQuestion), one at a time,
recommended first, with previews. Be honest: never ship a UI that only looks
like it works; say plainly what is untested. Do the work yourself; ask only
for what he must do (Apple account steps, secrets). Never enter credentials
yourself; he pastes them. Never print secret values.

## 3. Repo and CI

- Repo: **github.com/ferbogar-uk/axyom-remote** (PUBLIC — it was made public
  so Actions is free; the account's private-repo Actions billing is blocked).
  Never commit keys. Apple secrets go in GitHub encrypted secrets only.
- Local clone on Ricardo's PC: `C:\Users\ricar\PROJECTS\axyom-remote`
  (git + `gh` authenticated there; commit as Ricardo Bueno
  <ferbogar.uk@gmail.com>; branch `main`).
- CI: `.github/workflows/core-tests.yml` (Linux) — green, **27 tests**.
- Swift is NOT installed on the PC or in the cloud workspace: CI is the test
  runner. Push, then `gh run watch`.
- Commit trailer used in this project:
  `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`

## 4. What exists in `core/AxyomRemoteCore` (all tested on Linux)

| File | Does |
|---|---|
| `SyncCrypto.swift` | PBKDF2-SHA256 100 000 rounds, salt `nimbalyst:<member>`, AES-256-GCM 12-byte IV, base64(ciphertext‖tag). Bit-identical to the desktop (vectors in `docs/test-vectors.json`, made with the desktop's own WebCrypto). |
| `PersonalJWT.swift` | HS256 JWT `{sub, organization_id, iat, exp}` (5 min) minted from the personal key. |
| `Pairing.swift` | QR payload `axyom-pair:1:<base64url(JSON)>`, 10-minute validity, https only; `RoomIds` (`org:<org>:user:<member>:index` / `…:session:<id>`), socket URL with `?token=`. |
| `WireTypes.swift` | Codable subset of the CollabV3 protocol (ServerMessage decode, ClientMessage encode, SessionIndexEntry, DeviceInfo, CreateSessionRequest, JSONValue). |
| `Fleet.swift` | `FleetSession.from(entry, crypto)` (decrypts title/project/client metadata; hides rows under another key) and `FleetBoard.build` (waiting / working / recent, project chips with counts). |
| `VoiceCommand.swift` | pt/en sentences → `.newSession(agent, project, prompt)`, `.reply`, `.approve`, `.deny`, `.status`. |
| `RemoteClient.swift` | actor: index room (announce device, list sessions, devices, deletes), reconnect with backoff, ping 30 s, `createSession` (encrypted, waits for the PC's answer, 30 s timeout), `loadTranscript` (all pages), best-effort readable text. |
| `URLSessionSyncSocket.swift` | the real WebSocket for the app. **Never run against the live server yet.** |

## 5. The server (owned by the other session — do not change it)

- `https://axyom-sync.axyom.workers.dev` (Cloudflare Worker + Durable
  Objects/SQLite, Ricardo's account). Source: github.com/ferbogar-uk/axyom-backend
  (`sync/`, notes in `sync/PROTOCOL.md`). Single owner: org `axyom`, member `owner`.
- Auth: HS256 JWT signed with the personal key; `sub` must equal the room's
  user. The raw key is refused.
- Server assigns message `sequence` (clients send 0). History pages of 200
  (`syncRequest {sinceSeq}` → `syncResponse {hasMore, cursor}`).
- `indexPageRequest` (v2) is answered with `unknown_message_type` on purpose
  → use the legacy `indexSyncRequest`.
- Relayed (not stored): createSession*, createWorktree*, voiceTool*,
  sessionControl, sessionContext, settingsSync, readReceipt,
  trackerPersonalState. `requestMobilePush` → `accepted:false` (no APNs yet).
- Verified end to end with the real desktop on 2026-11-17: 25 sessions
  indexed, live messages, devices online/offline.

## 6. Split of work between the sessions

| This session (iPhone) owns | The other session (desktop/server) owns |
|---|---|
| everything in `axyom-remote` | AXYOM desktop (`axyom-v01`), the sync server (`axyom-backend`) |
| SwiftUI app, design, voice, camera QR scan | the **pairing QR screen** in the desktop (it will emit exactly the `axyom-pair:1:` format in `Pairing.swift`) |
| CI (`ios-compile`, later `ios-testflight`) | publishing plan usage over sync (new message; will be added to this file when defined) |
| how prompts/approvals are sent from the phone (see open questions) | any server change; ask there first |

If you need a protocol or server change, write it in
`docs/REQUESTS-TO-DESKTOP.md` and tell Ricardo; do not edit the other repos.

## 7. Next steps (in order)

1. **Design pass** (no macOS minutes): use `impeccable` (native iOS refs),
   `design-taste-frontend`, `frontend-design` to define the visual system
   and the screens (Comando, session chat, new session sheet, voice,
   pairing, settings). Show Ricardo mockups and get approval.
2. **App skeleton** in `app/` like Formetra (`project.yml` for XcodeGen,
   SwiftUI views on top of `AxyomRemoteCore`). Keep views thin; anything
   testable goes to `core/` with Linux tests.
3. **`ios-compile.yml`** (macOS, unsigned, only when `app/**` changes), copied
   in spirit from Formetra.
4. Ricardo's Apple steps (tell him exactly, one at a time): create the app in
   App Store Connect with a NEW bundle id (suggest `uk.co.ferbogar.axyomremote`
   or ask), create a NEW App Store Connect API key, add `ASC_KEY_P8`,
   `ASC_KEY_ID`, `ASC_ISSUER_ID`, `APPLE_TEAM_ID` as repo secrets.
5. **`ios-testflight.yml`** — upload **only with Ricardo's explicit OK**, each
   build number higher than the last.

## 8. Open questions (resolve with Ricardo or the protocol)

- **Sending a prompt / approving from the phone.** The desktop reads
  queued prompts from session metadata (`encryptedQueuedPrompts` in
  `updateMetadata` / index entries) and approvals via `sessionControl`
  (`messageType` + payload). The exact payloads are in the AXYOM repo:
  `packages/runtime/src/sync/CollabV3Sync.ts` (search `encryptedQueuedPrompts`,
  `sessionControl`) and the old Nimbalyst iOS app in
  `packages/ios/NimbalystNative/Sources/Sync/SyncManager.swift`. Read them
  (Ricardo can share the files) before implementing; add core tests first.
- Rich transcript rendering (tool calls, diffs, code). The old Nimbalyst app
  used a WKWebView bundle (`packages/ios/src/transcript`); decide native vs web.
- Voice: speak answers back (TTS)? Wake word? Ask Ricardo.
- Push notifications need APNs keys and a server change: later, via the other session.
