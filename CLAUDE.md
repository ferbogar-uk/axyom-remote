# AXYOM Remote

Read `docs/HANDOFF.md` first, then `docs/DECISIONS.md`.

- Talk to Ricardo in Portuguese, short and visual. Decisions as on-screen
  multiple choice, one at a time, recommended first, with previews.
- Linux first: logic in `core/` with tests on `ubuntu-latest`. macOS only for
  UI, only when `app/` changes.
- Honest status: never ship UI that only looks like it works; say what is untested.
- No secrets in this repo (it is public). Never type or print credentials;
  Ricardo pastes them into GitHub secrets himself.
- TestFlight uploads only with Ricardo's explicit OK.
- Do not edit `axyom-v01` or `axyom-backend`; put requests in
  `docs/REQUESTS-TO-DESKTOP.md`.
