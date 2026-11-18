# Design: AXYOM Remote (approved 2026-11-18)

Mockups (Claude Design canvases, both approved by Ricardo):
- Comando, Chat, Painel: https://claude.ai/artifact/8mc18qBeoVA7xjSLrpMwwx
- Nova sessão, Voz, Emparelhar, Definições, PC offline: https://claude.ai/artifact/2yqyVNJeq7iVw28Q54Dbqa

Skills used for the design pass: impeccable (iOS guidance), design-taste-frontend,
frontend-design. The world is inherited from the first mockups, not reinvented.

## Look

| Role | Value |
|---|---|
| Ground | #0E0F12 |
| Surface / border | #16181D / #262930 (strong border #3A3D45) |
| Text / soft / muted | #ECEDEF / #D4D6DA / #A3A7AE |
| Action (amber) | #F5A524, light #FFC35C, tinted surface #1A1508, fill #2A1E08, border #5C4410, text on amber #1A1206 |
| OK (green) | #3DD68C |
| Danger | #FF8A80 |

- **Dark only.** The approved mockups have no light variant; the app sets
  `UIUserInterfaceStyle = Dark`. A light mode is a separate design job.
- **Type.** The mockups use Inter and Space Grotesk as stand-ins. The app uses the
  system font (SF) with Dynamic Type text styles. The wordmark "AXYOM" is a system
  bold for now; bundling Space Grotesk for the wordmark and numbers is optional.
- **Touch targets** 44 pt or more. Radius: 16 to 18 for cards and buttons, capsule for chips.
- **Voice** always shows what was understood and asks for confirmation before anything is sent.

## Built in the skeleton (app/AxyomRemote)

Pairing (QR scan or pasted code, secret kept in the Keychain), Comando (waiting,
working, recent, project chips, PC offline banner), read-only session transcript,
new session on the PC, voice with on-device recognition and confirmation, settings.

## Not built yet, on purpose (never show it if it does not work)

- **Approve / Deny buttons and replying from the phone.** Needs the desktop's exact
  `sessionControl` / queued-prompt payloads (HANDOFF section 8). The session screen has no input box until then.
- **Plan usage strip** (Claude 31%, Codex 33%...). The desktop does not publish it over
  sync yet (HANDOFF section 6, other session).
- **Progress bars and "A correr os testes 19/24"** on working sessions. The index only says
  whether a session is executing.
- **Pending request text** ("Quer correr pnpm test") on waiting cards. The index only
  says a prompt is pending.
- **Dictating into the new-session prompt**, **"connect another PC"**, **notifications** (needs APNs and a server change).
- App icon, bundle id registration, export-compliance answer (Ricardo's decisions, HANDOFF step 4).

## Untested

Nothing in `app/` has been compiled or run yet: there is no Swift toolchain on this PC
or in the cloud workspace. The first compile happens on the macOS runner
(`ios-compile.yml`, manual). Camera, microphone, speech and the live WebSocket have
never been run on a device.

## Brand update (2026-11-18)

The app now uses the AXYOM brand pack (Corrected edition, direction 01): dark tokens from tokens.json (graphite #0B0F14, navy #0F1B2D, raised #17283D, amber #FF9F3D, text #E5E7EB, muted #AAB6C5), the app icon (1024 px, flattened to an opaque square), the flat symbol in the Comando header and the white lockup on the pairing screen. Fonts: Sora and Inter are not bundled (licence files needed), so the app still uses the system font. The pack says it is a design candidate, not trademark-cleared. Not yet checked on a device: icon at small sizes, contrast of the new colours on screen.

Logo update (2026-11-18): Ricardo wants the dimensional (3D/metallic) logo in the app, not the flat one. The Comando header uses axyom-symbol-dark and the pairing screen uses axyom-lockup-dark from the brand pack. The brand guide recommends flat artwork at small sizes and the dimensional version only above 240 px wide; the header symbol is small, so check how it reads on the iPhone.

Update (2026-11-18): the session screen now has Approve once / Deny for tool-permission prompts and a Stop button. They send the same sessionControl messages the desktop handles (prompt_response, cancel) and are covered by core tests. Not tested against a real desktop yet. Still not built: replying with text (needs the queued-prompt index write), plan approval, question answers, voice conversation, notifications.

Update (2026-11-18, later): the session screen is now complete for everyday use.
- Reply by text: `RemoteClient.sendPrompt` writes one encrypted queued prompt on
  the session's index entry (`indexUpdate`, same shape as the desktop's own iOS
  client in packages/ios SessionIndexUpdates.prompt) and then sends a `prompt`
  sessionControl to nudge the desktop. Works with the PC offline (it runs when it connects).
- Answer the agent's questions (AskUserQuestion, options, multi-select) and
  approve/reject plans (ExitPlanMode, optional feedback).
- New messages arrive every 4 s (incremental syncRequest after the last sequence).
- Voice conversation (decided: tap button, no wake word, iPhone system voice):
  the waveform button turns it on; you tap the mic and talk, it stops after
  ~1.8 s of silence, sends, and reads the agent's reply aloud (AVSpeechSynthesizer, pt-PT).
- The home voice button can now reply, approve and deny (it targets the
  session waiting for you, shown before you confirm).
- Local notification when a session starts waiting, only while the app is running.
Not tested against a real desktop yet. Still not built: real push with the
phone locked (needs the server, request #2), plan usage (request #3),
attachments/images in replies, git commit prompt, Azure voice.
Update (2026-11-18, morning): completed from the cloud session.
- Agent badges (original monograms in AXYOM colours, not the companies' logos)
  on every session row, waiting card and the session title.
- Plan usage strip on the home screen, from the desktop's `planUsageBroadcast`
  (decrypted on the phone; shows % per plan, reset time, "atualizado há X").
- New sessions and replies go to the PC that holds the project
  (`DeviceInfo.syncedProjectIds`), falling back to any online PC.
- Reply with images: "+" next to the text box (photos or camera); images are
  shrunk to 1024 px JPEG and sent as encrypted attachments on the queued prompt,
  the format the desktop's `decryptMobileAttachments` reads.
- Git commit proposals as a card: tick files, edit the message, commit or cancel.
- Chat cleaned for Codex (exec and app-server), Gemini, Claude, Cursor and Grok,
  following the desktop's raw parsers; system reminders hidden.
- Voice: replies are read in pt-BR; the loop reopens the mic only after the last
  sentence has been read (the old check could leave it stuck).
All covered by Linux core tests where it is logic; none of it tested on a device yet.

Update (2026-11-18, 11:00): look matched to the desktop and the Claude app, as Ricardo asked.
- Light and dark themes following the iPhone setting: near-black / greys in
  dark, white / light grey / ice in light. Orange only on the two actions:
  send and start voice.
- Session screen: floating composer (text on top; + attach, model chip,
  dictate, orange action at the bottom). The orange button starts a voice
  conversation when the box is empty and turns into "send" once you type.
- Function icons at the top, outside the conversation: stop and a "..." menu
  (refresh, voice conversation, stop).
- Home: floating bar with "Nova sessão em…" (neutral) and the orange voice button.
- Model chip shows the session's model; switching needs desktop request #4.

Update (2026-11-18, 12:40): Settings in the style of the Claude app.
Computers (online/offline, project count), plan usage, appearance picker
(Light / Dark / System with previews), voice language (pt-BR / pt-PT), reading
speed, silence before sending (1.5 / 1.8 / 2.5 s), notifications on/off, haptic
tap on send, link to iPhone permissions, version and server, unpair. All stored
on the phone (UserDefaults) and used by the app; nothing in it is decoration.

Update (2026-11-18, 13:00):
- Offline: one red line "Sem ligação à internet. Volto a ligar sozinho." instead
  of the raw NSURLError, which also printed the request URL with the 5-minute
  access token on screen. Core never stores raw errors now (ConnectionMessage).
- Agent activity line with three animated dots: "A correr um comando…",
  "A ler ficheiros…", "A pensar…", from the newest transcript row.
- Model chip shows the exact model from the transcript's init row ("Opus 5.5")
  and opens a menu with the desktop's effort levels, greyed out until request #4.
- Queue / send now: while the agent works, tapping send queues the message
  (shown above the composer with "Enviar agora"); holding the send button offers
  "Pôr na fila" or "Enviar agora". Send now = stop the turn, then run the queue,
  as the desktop's own send-now does. No "undo send": once the PC has the
  prompt in its queue the phone cannot remove it (would need a desktop change).
