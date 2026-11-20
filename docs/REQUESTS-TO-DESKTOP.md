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

Status: done on the server (axyom-backend d186d36, sync/PROTOCOL.md "Mobile
push"). Reply is `pushTokenRegistered { deviceId, pushConfigured }`;
`environment` "production" | "sandbox"; pushes on hasPendingPrompt false→true
(kind "waiting") and isExecuting true→false (kind "finished"), one per session
and kind per 60 s, never to the author or to a phone open right now. Ricardo added the APNs key and turned Push on for com.axyom.remote
(18 Nov 2026). The phone sends `registerPushToken` on every connect and
`unregisterPushToken` on unpair; tapping the alert opens its sessionId. Not
yet tested on a device.

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

## 7. Azure neural voice for the iPhone, through the sync server

Ricardo created an Azure Speech key (18 Nov 2026) so the phone can speak
replies with the same neural voice as AVA instead of the iPhone system voice.
The key must stay on the server (this repo is public and an app binary can be
unpacked), so the phone needs a small authenticated endpoint on axyom-sync.

Proposal:
- Worker secrets `AZURE_SPEECH_KEY` and `AZURE_SPEECH_REGION` (Ricardo pastes
  them; never in a repo).
- `POST /voice/tts` with the same personal JWT the WebSocket uses (header
  `Authorization: Bearer …`), body `{ text, voice?, rate? }`, text capped at
  ~3000 chars, a sensible per-user rate limit.
- The Worker calls Azure TTS (`audio-24khz-48kbitrate-mono-mp3`, default voice
  `pt-BR-FranciscaNeural` or whatever AVA uses) and streams the MP3 back.
- `GET /voice/status` → `{ configured: bool, voices: [...] }` so the phone can
  show the option only when it works.
- Optional later: `POST /voice/stt` for Azure recognition (the phone keeps
  Apple recognition until then).

The phone will fall back to the system voice whenever the endpoint is
missing, unconfigured or fails.

Status: DONE on the server (axyom-backend 898cc23, deployed 18 Nov 2026).
Exact contract in axyom-backend/sync/PROTOCOL.md, "Voice". Auth on both:
`Authorization: Bearer <same personal JWT as the WebSocket>`.

    GET  /voice/status
    → { "configured": bool, "defaultVoice": "pt-BR-MacerioMultilingualNeural",
        "voices": [ { "id", "lang", "label" } ], "maxChars": 3000,
        "format": "audio-24khz-48kbitrate-mono-mp3", "month": "YYYY-MM",
        "usedChars": n, "monthlyCharCap": 200000 }

    POST /voice/tts  { "text": "...", "voice"?: "en-GB-RyanNeural", "rate"?: 10 | "+10%" }
    → 200 audio/mpeg (streamed MP3)

- Default voice is pt-BR-MacerioMultilingualNeural (what Ricardo picked on the
  desktop, not Francisca); listed voices: Macerio, Francisca, en-GB Ryan,
  en-GB Sonia. Any `xx-YY-NameNeural` is accepted; language comes from it.
- Errors are JSON `{ "error" }`: 400 text_required | text_too_long | bad_voice |
  bad_rate | bad_json; 401; 429 rate_limited (30/min, Retry-After) |
  monthly_cap | azure_busy; 503 not_configured; 502 azure_auth | azure_error.
  Fall back to the system voice on anything but 200.
- `/voice/stt` is not implemented yet.
Secrets AZURE_SPEECH_KEY / AZURE_SPEECH_REGION: Ricardo pastes them with the
"AXYOM - chave Azure no servidor" script on his desktop. Until then
/voice/status says configured: false. Tests: 6 unit tests
(`node --test test/voice.test.ts`) and the live smoke test; the real MP3 check
runs once the key is in.

## 8. Azure speech recognition for the iPhone (`/voice/stt`)

Ricardo chose Azure for listening too (18 Nov 2026): better Portuguese and
technical names than Apple's dictation. Same rules as #7 (key on the server,
same JWT, same secrets `AZURE_SPEECH_KEY` / `AZURE_SPEECH_REGION`).

The phone already sends this (azure-listen branch, build 22) and uses it only
when `/voice/status` says `"stt": true`:

    POST /voice/stt?lang=pt-BR
    Authorization: Bearer <jwt>
    Content-Type: audio/wav; codecs=audio/pcm; samplerate=16000
    body: WAV, 16 kHz mono 16-bit PCM, at most 60 s (~1.9 MB)
    → 200 { "text": "Olá, corre os testes." }   ("" when nothing was understood)

Proposal for the server:
- Forward the body to Azure short-audio recognition:
  `https://<region>.stt.speech.microsoft.com/speech/recognition/conversation/cognitiveservices/v1?language=<lang>&format=simple`
  with `Ocp-Apim-Subscription-Key` and the same Content-Type. Map
  `RecognitionStatus: "Success"` → `{ text: DisplayText }`, `NoMatch` /
  `InitialSilenceTimeout` → `{ text: "" }`, anything else → the error codes
  used by `/voice/tts`.
- `lang` allowlist: `pt-BR`, `pt-PT`, `en-GB`, `en-US` (default `pt-BR`).
- Reject bodies over 2 MB (413) or not starting with `RIFF…WAVE` (400).
- Count seconds per user and month (WAV bytes / 32000) with a cap var, e.g.
  `VOICE_MONTHLY_STT_SECONDS` default 18000 (5 h); 429 `monthly_cap` when over.
  Same 30 requests a minute limit.
- `/voice/status` gains `"stt": true` when configured, plus `usedSttSeconds`
  and `monthlySttSeconds`.

The phone gives up after 8 s and keeps Apple's live text, so a slow or
missing endpoint never blocks a message.

Status: waiting for the desktop/server session.

## 9. Worktree/branch and PC file previews for the iPhone

Ricardo wants each conversation short and visual (18 Nov 2026): what the
agent is doing in one line, code hidden, and links to everything relevant,
with thumbnails of photos and screenshots. The phone now folds steps and
code and shows cards for links and PC paths, but two things need the desktop:

1. **Worktree and branch per session.** Add to the session index entry
   (inside the encrypted metadata, like the title): `worktreeName`
   (e.g. "azure-listen"), `branch`, and `worktreePath`. The phone shows them
   under the session title only when the session runs in a worktree.
2. **Preview of PC files the agent mentions.** When the agent's reply names
   an image or a document on the PC (a screenshot, a PNG, a PDF), the phone
   can only show the name and copy the path today. Proposal: a sessionControl
   `messageType: "file_preview"`, `payload: { path }`. The desktop checks the
   path is inside the session's workspace or worktree (never elsewhere),
   makes a small JPEG (max 800 px, first page for a PDF), encrypts it like an
   attachment and answers in the session room with
   `{ type: "filePreview", path, encryptedImage, iv }`. Nothing is sent unless
   the phone asks, and only for paths the agent itself mentioned.

Status: waiting for the desktop session.

## 10. Push that says who, what and where

Ricardo (19 Nov 2026): "Um agente terminou" is too vague; the alert must say
which agent, which conversation and what it is about, still short.

The phone now has a notification extension (build 23) that rewrites the
alert to, for example:

    Claude · Análise do repositório
    Terminou · axyom-remote
    Toca para ver a resposta.

It takes the title, agent and project from what the app last saw, and
decrypts extra fields when present. It only runs if the push asks for it.

**Server (axyom-backend, pushPolicy/apns):**
1. Add `"mutable-content": 1` inside `aps`. Without it iOS never runs the
   extension and the generic text stays.
2. Copy the session's stored encrypted title into the payload as
   `encryptedTitle` + `titleIv` (the same ciphertext as the index entry; the
   server still never reads it), so new sessions are named too.
3. Pass through `encryptedSummary` + `summaryIv` when the desktop's
   `requestMobilePush` carries them. Keep the whole payload under 4 KB (drop
   the summary if it would not fit).
4. Keep the generic Portuguese title/body as they are: they are the fallback
   when the extension cannot run.

**Desktop (AXYOM, requestMobilePush):**
- Add `encryptedSummary`/`summaryIv`: one line, at most 160 characters,
  encrypted with the session key, saying what it is about:
  - waiting: the question or permission ("Quer permissão para editar AuthView.swift")
  - finished: the first sentence of the agent's last reply
  - error: the error in plain words
- Never more than that line (no code, no paths beyond a file name).

Status: waiting for the desktop/server session. Until then the phone shows
the better text only in its own local notifications (app open or just in
the background).

## 11. Live reply text for the phone (`sessionStreamText`)

Ricardo (19 Nov 2026): in a voice conversation the phone waits for the whole
reply before it shows or reads anything. It should appear as the agent
writes, and the phone should start reading the first sentence right away.

Checked in axyom-v01: the desktop syncs persisted transcript rows only
(`appendMessage`), so the phone first sees the reply when the assistant
message is complete. Streaming deltas never leave the PC.

The phone is ready (branch live-reply, build 35): it shows the live text in
the conversation, reads each sentence as soon as it is complete, does not
read again what it already read when the final row arrives, and only opens
the microphone once the agent has finished.

**Server (axyom-backend, one line):** add to `RELAYS` in sync/src/index.ts

    sessionStreamText: { out: 'sessionStreamBroadcast', field: 'stream' },

so the frame is forwarded to the user's other devices in the index room and
never stored. Document it in PROTOCOL.md next to `sessionContextUpdate`.

**Desktop (AXYOM):** while an agent streams the text of an assistant
message (Claude Code `stream_event` text deltas, Codex `agent_message`
deltas, the others where they exist), send on the index socket:

    { "type": "sessionStreamText",
      "stream": { "sessionId": "...",
                  "encryptedText": "<whole text of this message so far>",
                  "iv": "...",
                  "seq": 17,
                  "done": false } }

- Encrypt with the same key and helper used for index fields
  (`encryptData`, AES-256-GCM); send the **whole text so far**, not the delta,
  so a lost frame costs nothing.
- At most one frame every 250 ms per session, plus one right away when a
  sentence ends (`.`, `!`, `?`, new line) so speech starts sooner.
- `seq` increases per session; `done: true` (empty text allowed) when the
  message completes, when a tool call starts, or when the turn is cancelled.
- Only while some phone is connected to the index room (skip otherwise).
- Text only: no thinking, no tool input/output.

Status: done on the server and the desktop (19 Nov 2026).
- Server: `sessionStreamText` is in `RELAYS` (relayed as `sessionStreamBroadcast`,
  never stored), documented in sync/PROTOCOL.md; deployed (axyom-backend 5f788d3,
  version 1839410e). Smoke test checks the relay and that the sender gets no echo.
- Desktop (AXYOM, branch axyom-redesign-backup, build release20): while an agent
  writes, the whole text of the current assistant message goes out encrypted with
  the index key, at most every 250 ms and at once when a sentence ends (`.` `!` `?`
  `…` or new line), with a per-session rising `seq`; `done: true` when the message
  completes, a tool call starts, or the turn errors or is cancelled. Sent only while
  a phone or tablet is in the index room. Text only.
- Claude Code now streams partial text (`includePartialMessages`) used only for
  these frames; Codex and the other agents use their existing text deltas.
- Not yet seen end to end on the iPhone: please confirm on build 35.

## 12. Tell the agent which session it is in and that Ricardo is on the phone

Ricardo (19 Nov 2026): asked "do you know which session you are in?" from
the iPhone, the agent answered that it does not know the session's name, its
place on the session board, or that he is talking from the phone by voice.
The phone only sends his text, so the agent has no way to know.

Proposal for AXYOM (desktop): when a queued prompt comes from the phone
(`source: "mobile"`), add a short context block for the agent, not shown in
the transcript as Ricardo's words:

    [AXYOM] Session: "01 Aion | AXYOM Development" (id …), project
    "AXYOM - AI Development OS", worktree "<name>" on branch "<branch>"
    (only when it runs in a worktree). Ricardo is on the iPhone app (AXYOM
    Remote), talking by voice: the reply is read aloud, so answer in short
    spoken Portuguese, no tables or code unless he asks.

- "talking by voice" only when the prompt's options say it came from the
  voice conversation (the phone can add `options.voice = true`; tell me the
  field name you prefer and the phone will send it).
- Same block for every provider (Claude, Codex, Gemini, Grok, Cursor,
  OpenCode), in the form each one accepts (system prompt append or a hidden
  preamble).
- Keep it to these facts; no extra instructions.

Status: done on the desktop (19 Nov 2026), AXYOM build release21.
- Field for "came from the voice conversation": `options.voice = true` (a real
  boolean, on the queued prompt next to mode/model/effortLevel). Anything else
  counts as typed.
- A queued prompt with `promptProvenance.origin = "mobile"` gets one line for the
  agent, in the hidden system-message block that every provider already uses
  (buildUserMessageAddition), so the transcript never shows it as your words:

      [AXYOM] Session: "<title>" (id <id>), project "<folder>", worktree "<name>"
      on branch "<branch>". Ricardo is on the iPhone app (AXYOM Remote), talking
      by voice: the reply is read aloud, so answer in short spoken Portuguese, no
      tables or code unless he asks.

  Worktree/branch only when the session runs in one; without `options.voice` the
  end reads "typing on the phone". Same block for Claude, Codex, Gemini, Grok,
  Cursor and OpenCode.
- Phone: please send `options.voice: true` for prompts from the voice conversation.

## 13. The agent introduces itself as AXYOM, not "Codex" / "Claude"

**Seen on the phone (20 Nov 2026):** asked "what's your name?", the agent answers
"I'm Codex." Ricardo wants every agent, whatever the provider, to answer as AXYOM.

**Ask:** in the system prompt the desktop adds to every session (all providers,
including `openai-codex`), add one line such as:

> You are AXYOM, Ricardo's development assistant. If asked your name or who you
> are, say you are AXYOM. Do not call yourself Codex, Claude or ChatGPT; you may
> name the underlying model only if he asks which model is running.

**Also:** Codex echoes the user's message back as an output event before the
reply. The phone now hides that echo (core `ChatLines`), but if the desktop can
skip the echoed `user_message` item when it writes Codex output rows, the PC
transcript gets cleaner too.

**Done when:** "what's your name?" from the phone gets "AXYOM" on Codex and Claude sessions.

Status: done on the desktop (release29, backup branch axyom-redesign-backup). One
`AXYOM_IDENTITY` line (the wording above) is now in every system prompt the
desktop builds: Claude Code, Codex, OpenCode, Copilot, headless CLIs, the
Orchestrator, chat providers and Antigravity; the old "be truthful about which
model you are" line is gone, and a display name is given as "the underlying
model is X". Codex: the echoed `userMessage` item (`item/completed`) is no
longer stored as an output row, so new turns have no echo to hide. Not yet
tested from the phone. A Codex thread started before release29 may keep its
old instructions; a new session gets the new line.

## 14. Live Activity updates over APNs (Dynamic Island)

**Why:** the phone will show a running session in the Dynamic Island and on the lock
screen. iOS only keeps it fresh when the app is closed if the server sends
`liveactivity` pushes.

**Privacy first:** a Live Activity's content is drawn by iOS itself, so it cannot be
decrypted on the phone. The phone puts the session title in the activity when it
starts it (locally). The server pushes **no text**, only state.

**Phone → server** (new message, same socket as `registerPushToken`):
```json
{ "type": "registerActivityToken", "sessionId": "<id>", "token": "<hex>", "deviceId": "<id>" }
{ "type": "endActivityToken", "sessionId": "<id>", "deviceId": "<id>" }
```

**Server → APNs** when that session's index entry changes (executing / pending prompt /
finished), at most one push per 15 s per session:
- topic `com.axyom.remote.push-type.liveactivity`, header `apns-push-type: liveactivity`, priority 10 when it starts waiting for Ricardo, else 5
- payload:
```json
{ "aps": { "timestamp": 1763650000, "event": "update",
  "content-state": { "phase": "working", "since": 1763649000, "waitingCount": 0 } } }
```
`phase` is `working`, `waiting` or `done`. On `done` send `"event": "end"` with
`"dismissal-date"` = now + 15 min, then forget the token.

**Done when:** with the app closed, the island switches to amber "À tua espera" within a
few seconds of the agent asking a question on the PC.
