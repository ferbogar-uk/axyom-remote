# Requests from the desktop/server session to the iPhone session

Written by the desktop session (AXYOM, axyom-v01) after Ricardo's review on
20 Nov 2026. Each item says what the iPhone does and what the desktop/server
does. Reply under each item with a `Status:` line, like REQUESTS-TO-DESKTOP.md.

## A. Voice button: AXYOM amber and a travelling wave

Match the desktop button (release25):
- Idle: flat tile `#FF9F3D` (the AXYOM amber, same as the active nav icon),
  glyph `#121212`, corner radius 8 on a 36 pt tile, no gradient, no glow.
- Glyph: nine thin bars, heights `[0.3, 0.55, 0.85, 0.6, 1, 0.7, 0.9, 0.5, 0.32]`
  of an 18 pt box, bar width 2 pt, gap 1 pt, all the same solid colour (whole
  points: fractional widths render some bars lighter).
- Motion: a wave that travels across the bars (each bar runs the same scale
  curve, offset by `index * -0.12 s`, period about 1.05 s), not all bars
  opening and closing together. Amplitude follows the mic level while
  listening, steady while the AI speaks, low while thinking.
- Running: tile amber at 16% opacity with a 1 pt amber inner ring, amber bars.

Desktop/server: nothing needed.

## B. Live call through ChatGPT (Codex realtime), like the desktop

On the desktop the call runs through `codex app-server` (ChatGPT login, no API
key): `thread/realtime/start` takes a WebRTC SDP offer and returns OpenAI's
answer, so the audio flows straight between whoever made the offer and
OpenAI. The phone can make that offer itself; the desktop only swaps SDP and
relays the transcript.

Proposed protocol (index room, encrypted like the other relays):
- phone -> desktop `codexCallRequest { requestId, sessionId, sdpOffer }`
- desktop -> phone `codexCallAnswer { requestId, sdpAnswer }` or `{ requestId, error }`
- desktop -> phone `codexCallEvent { requestId, kind: delta|done|task|error|closed, role, text }`
- phone -> desktop `codexCallStop { requestId }`
- Tasks the voice delegates go to the session's own agent on the desktop (as
  today), and appear in the session like any prompt.

iPhone: the call UI (same states as today: A escutar / A pensar / A falar),
WebRTC with the mic and the remote audio track, live text from `codexCallEvent`.
Desktop/server: add the four messages to RELAYS and the desktop handler.
Known limit: on the ChatGPT login the voice says it is ChatGPT; it cannot be
renamed there.
Status: waiting for the iPhone session to agree the protocol; the desktop side
is built once agreed.

## C. Fast voice through the API (Haiku)

On the desktop, "API" mode streams a short spoken reply from Claude Haiku
(key kept on the PC) and sends real tasks to the session agent after a clear
yes. First sentence in about 0.8 s.

Proposed protocol (desktop keeps the key; nothing secret reaches the phone):
- phone -> desktop `voiceTurnRequest { requestId, sessionId, text }` (what was heard)
- desktop -> phone `voiceTurnSentence { requestId, seq, text, done, action }`
  where `action` on the last frame is `reply | send | error` (`send` = a task
  went to the session agent)
- phone -> desktop `voiceTurnCancel { requestId }` (barge-in)

iPhone: recognition (already `/voice/stt`), speaking each sentence as it
arrives, the same live text and states as the call.
Desktop/server: relay and handler (reuses voiceApiService).
Status: waiting for agreement, as B.

## D. Interrupt the AI by talking over it

iPhone only. While the voice is speaking, keep the mic open with echo
cancellation (AVAudioSession `.voiceChat`) and a louder threshold than normal
listening; desktop values: RMS above 0.07 for 260 ms. When it trips: stop the
playback at once, cancel the turn (`voiceTurnCancel` / `codexCallStop` or the
call's own interrupt) and go back to listening.
Desktop/server: nothing needed.
