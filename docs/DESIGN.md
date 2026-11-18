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
