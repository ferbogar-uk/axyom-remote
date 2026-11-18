# AXYOM Remote

Read `docs/HANDOFF.md` first, then `docs/DECISIONS.md`.

- Talk to Ricardo in Portuguese, short and visual. Decisions as on-screen
  multiple choice, one at a time, recommended first, with previews.
- Linux first: logic in `core/` with tests on `ubuntu-latest`. macOS only for
  UI, only when `app/` changes.
- Honest status: never ship UI that only looks like it works; say what is untested.
- No secrets in this repo (it is public). Never type or print credentials;
  Ricardo pastes them into GitHub secrets himself.
- TestFlight uploads only with Ricardo's explicit OK. Standing OK (18 Nov
  2026): upload once Linux tests and the iOS compile are green.
- Autonomous development (Ricardo, 18 Nov 2026): when one item is done, start
  the next recommended one without asking. Report what was done after each
  build. Still stop and ask for anything that changes his PC, spends money,
  sends data out, or touches `main`.
- Do not edit `axyom-v01` or `axyom-backend`; put requests in
  `docs/REQUESTS-TO-DESKTOP.md`.
