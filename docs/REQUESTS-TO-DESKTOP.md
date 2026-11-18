# Requests from the iPhone session to the desktop/server session

## 1. Pairing QR in the AXYOM desktop (blocks pairing on the iPhone)

Found on 2026-11-18 with the first TestFlight build. The QR shown today
(Settings > Sync, `generateQRPairingPayload` in `CredentialService.ts`) is the
old Nimbalyst payload: JSON with `version: 5`, `serverUrl`, `encryptionKeySeed`,
`expiresAt` (ms), `analyticsId`, `syncEmail`, `personalOrgId`, `personalUserId`.
It carries no personal sync key, so the phone cannot mint its own JWT, and the
old app signed in through Stytch. Nothing in the desktop code emits `axyom-pair:`.

What the iPhone app reads (see `core/Sources/AxyomRemoteCore/Pairing.swift`):

    axyom-pair:1:<base64url(JSON)>
    JSON: { server, key, seed, org, member, desktopName?, issuedAt }
      server      https://axyom-sync.axyom.workers.dev
      key         personal sync key (HS256 secret used to mint the 5-minute JWT)
      seed        encryption key seed (same value as encryptionKeySeed today)
      org         "axyom"
      member      "owner"
      issuedAt    unix SECONDS (the app refuses codes older than 10 minutes)

Please add a "Pair AXYOM Remote (iPhone)" QR/text code that emits exactly this,
shown only on request and for a few minutes (whoever reads it has full access).
The iPhone session does not edit axyom-v01.
Status: done on the desktop (commit d68cd0a, AxyomPairingModal.tsx).

## 2. Push notifications when a session waits for you

The iPhone app now raises a local notification when a session flips to
"waiting for you" (hasPendingPrompt), but only while the app is running: iOS
suspends the WebSocket shortly after the app goes to the background, so with
the phone in the pocket nothing arrives.

Needed for real push:
- The sync server (Cloudflare Worker) sends an APNs push when a session index
  entry changes `hasPendingPrompt` false -> true (or a permission_request /
  ask_user_question_request / exit_plan_mode_request row is written).
- A way for the phone to register its APNs device token, e.g. a
  `registerPushToken { deviceId, token, platform: "ios", environment }` message
  on the index room, stored per member.
- An APNs auth key (.p8) for team Z6HU7P866U kept as a Worker secret (Ricardo
  creates it; never in a repo). Payload with no plaintext from the session
  (title is encrypted): e.g. "A session is waiting for you", plus sessionId.
The iPhone side (token registration, Push capability, opening the session from
the notification) will be done once the server message exists.

## 3. Plan usage / progress on the iPhone

Status: delivered by the desktop (planUsageBroadcast, HANDOFF 6a); the phone
shows it on the home screen since 18 Nov 2026.

The home screen design has a plan usage bar (Claude/Codex limits, % used, reset
time). Nothing on the sync wire carries it today. Proposal: the desktop
publishes an encrypted `usage` blob in the index room (like encryptedClientMetadata),
e.g. `{ providers: [{ id, label, usedPct, resetsAt, window: "5h"|"week" }], updatedAt }`,
refreshed when it changes. The phone decrypts and shows it. Until then the app
shows no usage rather than an invented number.