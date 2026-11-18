# Handoff: how AVA's voice works and how another app can use it (17 Nov 2026)

For the Claude/Codex session of the OTHER app. Written from AVA's code and its CLAUDE.md. No keys are in this file; the values live in AVA's `.env.local` and Ricardo pastes them himself.

## 1. What "AVA's voice" is (three separate parts)

| Part | What it does | Service | Where in AVA |
|---|---|---|---|
| Speaking (text to speech) | Text in, MP3 out | Azure AI Speech (default) or ElevenLabs (English only on the free plan) | `app/server/azure-speech.mjs`, `app/server/eleven-speech.mjs`, route `POST /api/speech` in `app/server/local.mjs` |
| Listening (speech to text) | Microphone to text | Azure Speech SDK in the browser, with a 10-minute token from the server. Edge's own recognition is the fallback | `POST /api/speech/token`, `app/public/voice-web.js` |
| Realtime voice call | OpenAI Realtime over WebRTC | `gpt-realtime-2.1`, voice `marin` | `app/server/voice.mjs`, routes `/api/voice/config` and `/api/voice/session`. Needs `OPENAI_API_KEY`; the everyday AVA voice does NOT use this |

The voice she normally speaks with is **Azure neural voices**: `pt-BR-FranciscaNeural` (Brazilian Portuguese) and `en-GB-SoniaNeural` (British English).

## 2. Speaking: the exact recipe

**Azure (default, free tier F0, 500,000 characters a month; AVA caps itself at 450,000)**
- Endpoint: `POST https://<region>.tts.speech.microsoft.com/cognitiveservices/v1`
- Headers: `Ocp-Apim-Subscription-Key: <AZURE_SPEECH_KEY>`, `Content-Type: application/ssml+xml`, `X-Microsoft-OutputFormat: audio-24khz-48kbitrate-mono-mp3`, `User-Agent: <any name>`
- Body (SSML, text XML-escaped): `<speak version='1.0' xml:lang='pt-BR'><voice name='pt-BR-FranciscaNeural'>TEXT</voice></speak>`
- Voices accepted by AVA: `pt-BR-*Neural` and `en-GB-*Neural`. Defaults: `pt-BR-FranciscaNeural`, `en-GB-SoniaNeural`.
- Max 1,000 characters per request. AVA sends ONE SENTENCE at a time and plays the MP3s strictly in order (so speech starts early).
- Errors: 401/403 = bad key or region (stop calling until fixed); 429 = rest 60 s; anything else = fall back to the device's own voice.
- Env names (values are Ricardo's): `AZURE_SPEECH_KEY`, `AZURE_SPEECH_REGION`, `AZURE_SPEECH_MONTHLY_CHARS`.

**ElevenLabs (optional second voice)**
- `POST https://api.elevenlabs.io/v1/text-to-speech/<voiceId>?output_format=mp3_44100_64`, header `xi-api-key`, body `{"text","model_id":"eleven_flash_v2_5","language_code":"en"|"pt"}`.
- Free plan cannot use library voices through the API (402). AVA falls back to Azure per sentence. Env names: `ELEVENLABS_API_KEY`, `ELEVENLABS_MONTHLY_CHARS` (default 9,000).

**AVA's own wrapper (what the other app would call if it talks to AVA)**
- `POST http://127.0.0.1:3001/api/speech` with JSON `{ "text": "...", "lang": "pt-BR" | "en-GB", "voice"?: "...", "engine"?: "azure" | "eleven" }`.
- Answers raw `audio/mpeg`; headers `X-AVA-Voice` (which voice spoke) and `X-AVA-Fallback` (why it fell back).
- Related: `GET /api/speech/status`, `GET /api/speech/voices`, `GET /api/speech/eleven-voices`.

## 3. How another app can connect (pick one)

**Option A: call AVA's server (simplest, no keys in the other app)**
- Works only on the same PC: AVA listens on `127.0.0.1:3001` and refuses anything that is not loopback with a same-origin request. Writes must be JSON with an `Origin` equal to `http://127.0.0.1:3001` (cross-site is refused with 403).
- So a separate app on the same PC must either (1) be served from AVA's own origin, or (2) have AVA add a small allowed route for it. That is a change inside AVA and needs Ricardo's yes. The phone/other devices reach AVA only through Tailscale with his login (`AVA_REMOTE_HOST`, `AVA_REMOTE_USERS`).
- Switches matter: if "speech" is off in AVA's Connections, her speech routes refuse.

**Option B: the other app calls Azure itself (cleanest for a separate app)**
- Use the Azure recipe above with the SAME Speech resource, or better a NEW key made for that app, so usage and the free allowance are tracked separately. Keep the key on the other app's server only, never in the browser.
- For listening, the server hands the browser a short token (`POST` to `https://<region>.api.cognitive.microsoft.com/sts/v1.0/issueToken`, header `Ocp-Apim-Subscription-Key`; valid 10 minutes) and the browser uses the Microsoft Speech SDK (AVA vendors v1.51.0 in `app/public/vendor/`). AVA runs pt-BR and en-GB recognisers in parallel and picks the transcript by words first, confidence second, because Azure's automatic language detection mis-reads accented English.

**Option C: realtime OpenAI voice (only if that app wants a live call)**
- Browser makes a WebRTC offer; server forwards `sdp` plus a `session` JSON to `https://api.openai.com/v1/realtime/calls` with `Authorization: Bearer <OPENAI_API_KEY>`; returns the SDP answer. Session settings in `voice.mjs`: model `gpt-realtime-2.1`, voice `marin`, `semantic_vad`, transcription `gpt-4o-mini-transcribe`, tools `focus_knowledge_map`, `get_workspace_context`, `propose_action`. Never relay upstream error bodies to the browser.

## 4. Behaviour rules worth copying (learned the hard way, 27 Sep to 1 Oct)

- One voice per reply: the first clear sentence picks pt or en; change only after two clearly other-language sentences of 6+ words. Otherwise names and English terms make the voice flip.
- Strip markdown, links and ids before speaking. Do not speak `---` rules.
- Stopping must silence the rest of the reply, not just the queue (Esc, Stop, mic).
- Her own echo gets picked up by the mic. Voice interruption needs a wake/stop word she is not saying ("AVA", "espera", "pára", "stop"). Do not use "answer anything you hear".
- Listening ends after 2.5 s of silence (not 1.4 s); 8 s if nothing was said.
- Any Azure failure: speak that sentence with the device voice and pause Azure (20 s, 60 s, 10 min).
- Keep the keys server-side; the browser only ever gets audio or a 10-minute token. Never print or log a key.
- Wake phrase ("Olá AVA") is off by default because it keeps the microphone open.

## 5. What to ask Ricardo before building

1. Same PC only, or also his iPhone? (iPhone means going through Tailscale.)
2. Reuse AVA's Azure resource or make a new key for the other app?
3. Which languages: pt-BR and en-GB only, or more?
4. Does the other app only SPEAK, or also LISTEN?
5. Where should the other app's code live; may AVA be changed to expose a route for it?

## 6. Not verified here

This was written from reading `voice.mjs`, `eleven-speech.mjs`, the first lines of `azure-speech.mjs`, the speech routes in `local.mjs`, and AVA's CLAUDE.md. I did not run any voice call, did not check that the Azure key is currently valid, and did not read `voice-web.js` line by line.