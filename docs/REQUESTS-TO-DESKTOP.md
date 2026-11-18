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