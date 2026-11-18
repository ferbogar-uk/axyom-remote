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

## 2. Push notifications when a session waits for you (DONE on the server)

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

Status: DONE on the server (axyom-backend d186d36, Worker axyom-sync 0.2.0,
deployed 18 Nov 2026). APNs key 4TVQFVRMCH (team Z6HU7P866U, topic
com.axyom.remote) is stored as Worker secrets APNS_KEY_P8 / APNS_KEY_ID /
APNS_TEAM_ID. Tests: 7 policy tests (`node --test test/pushPolicy.test.ts`)
and 38 live checks (`node test/smoke.mjs`); a fake token got BadDeviceToken
from Apple, which proves the key is accepted. Full contract:
axyom-backend/sync/PROTOCOL.md, "Mobile push (APNs)". No desktop change.

Exact messages (index room of the member):

    → { "type": "registerPushToken", "deviceId": "<same id as deviceAnnounce>",
        "token": "<APNs device token, hex>", "platform": "ios",
        "environment": "production" | "sandbox" }
    ← { "type": "pushTokenRegistered", "deviceId": "...", "pushConfigured": true }
    ← { "type": "error", "code": "bad_message" | "too_many_devices", "message": "..." }

    → { "type": "unregisterPushToken", "deviceId": "..." }    (no reply)

A new token for the same deviceId replaces the old one. Send
registerPushToken after deviceAnnounce on every connect (tokens can change).
`environment` absent = production (TestFlight). A token from the other
environment is retried once on the other APNs host.

Pushes are sent when:
- `kind: "waiting"`: plaintext `hasPendingPrompt` goes false/absent → true;
- `kind: "finished"`: `isExecuting` goes true → false;
- the desktop's own `requestMobilePush` (already sent) maps to the same kinds,
  plus `"error"` (agent error) and `"update"` (anything else).
At most one push per session and kind every 60 s (shared by both triggers, so
never doubled), at most 6 per minute in total. Never to the device that caused
the change, nor to a phone that is present: socket open AND a message in the
last 60 s, so keep pinging while in the foreground.

Payload:

    { "aps": { "alert": { "title": "AXYOM", "body": "Uma sessão está à tua espera" },
               "sound": "default", "thread-id": "<sessionId>" },
      "sessionId": "<sessionId>", "kind": "waiting" }

Bodies: waiting "Uma sessão está à tua espera", finished "Um agente terminou",
error "Um agente teve um erro", update "Há novidades numa sessão".

Still to do on the iPhone: `aps-environment` entitlement + Push capability in
project.yml, ask permission, registerForRemoteNotifications, send
registerPushToken, open `sessionId` on tap. Ricardo was asked to tick Push
Notifications on the App ID com.axyom.remote (not confirmed yet).
Not tested on a real phone yet.

## 3. Plan usage / progress on the iPhone

Status: delivered by the desktop (planUsageBroadcast, HANDOFF 6a); the phone
shows it on the home screen since 18 Nov 2026.

The home screen design has a plan usage bar (Claude/Codex limits, % used, reset
time). Nothing on the sync wire carries it today. Proposal: the desktop
publishes an encrypted `usage` blob in the index room (like encryptedClientMetadata),
e.g. `{ providers: [{ id, label, usedPct, resetsAt, window: "5h"|"week" }], updatedAt }`,
refreshed when it changes. The phone decrypts and shows it. Until then the app
shows no usage rather than an invented number.
## 4. Change model and effort from the iPhone

Ricardo wants to switch model and effort per session from the phone (chip in
the composer, like the Claude app). The wire already carries it:
`IndexEncryptedQueuedPrompt.options = { mode?, model?, effortLevel? }`, and the
desktop-to-desktop mirror (RemoteSessionMirror.ts) sends it. But the mobile
ingest (`mobileQueuedPromptIngest.ts`) drops `options`: the prompt runs with the
session's current model/effort.

Needed: in `ingestQueuedPrompts`, pass `prompt.options` through to the queued
row and, when the prompt runs, apply `model` / `effortLevel` / `mode` to the
session (same as choosing them in the desktop composer), then publish the new
`model` on the index entry. Also publish the session's `effortLevel` somewhere
the phone can read (e.g. in encryptedClientMetadata) so the chip shows it.
The phone will send `options` and enable the picker once this lands; until then
the chip only shows the current model and says it cannot switch yet.

Status: done on the desktop (axyom-redesign-backup 0fc3587, 18 Nov 2026).
- Send `options: { model?, effortLevel?, mode? }` on the queued prompt as
  today. The desktop keeps them on the queued row and applies them right
  before that prompt runs (never under a running turn): `session.model`,
  `metadata.effortLevel` (clamped to the model's ceiling), `mode`. A model
  from another provider is ignored on a session that already has messages
  (same rule as the desktop); effort is still applied.
- Current effort: index entries now carry plaintext `effortLevel` (absent =
  the desktop default, see `defaultEffort` below). `model` was already there.
- What to offer in the chip: the decrypted `planUsageBroadcast` JSON now has
  `models: [{ id, name, provider, providerLabel, efforts: [..] }]` (exactly
  the desktop pickers' enabled list; `efforts` empty = no effort control for
  that model; send `id` back as `options.model`) and `defaultEffort`.
  Refreshed every 10 min. Verified live: 52 models, 25 with efforts.
- Not tested end to end from a phone yet.

## 5. Gemini (Antigravity) shell commands time out on Windows

Seen 18 Nov 2026: asked "what day is today", Gemini ran `date`, which on Windows
cmd waits for a new date to be typed, so the command hung until its timeout and
the reply took very long. Suggest: on Windows, tell the agent (system prompt /
tool hint) that `date` and `time` are interactive and to use `date /t`,
`Get-Date` or the date already in its context. Not an iPhone issue.

Status: done on the desktop (18 Nov 2026). run_command now closes stdin, so
`date` and any other prompting command return at once (measured 0.13 s
instead of hanging), and the tool description points to `date /t` / Get-Date.

## 6. Remove a queued prompt from the iPhone ("undo send")

Ricardo wants "Undo send" like the Claude app: a queued prompt can be taken
back before it runs. Once the desktop ingests a mobile prompt into
`queued_prompts`, nothing the phone can send removes it (ingest only adds).

Proposal: a sessionControl `messageType: "remove_queued"` with
`payload: { promptId }`. The desktop marks that row cancelled if it is still
`pending`, publishes the queue state again (so the phone's tray updates), and
ignores it if the prompt already started. The phone will show "Anular" next to
each queued prompt once this exists.

Status: done on the desktop (axyom-redesign-backup d08b509, 18 Nov 2026).
Send it exactly as proposed: sessionControl `remove_queued`, `payload:
{ promptId }` (the queued prompt's id, max 200 chars). What the desktop does:
- still `pending` → the row becomes `failed` with "Removed from AXYOM Remote
  before it started" (rows are never deleted, so a late replay of the phone's
  queue cannot bring it back), then the queue is published again without it;
- already started → nothing changes, but the queue is published again so
  the tray shows the truth;
- not on the desktop yet (the control beat the queue sync) → the id is
  remembered and skipped when it arrives (memory only, lost if AXYOM restarts);
- a prompt from another session → ignored.
There is no reply message: the phone learns the result from the next
`queuedPrompts` publish. Not tested with a real phone yet.
