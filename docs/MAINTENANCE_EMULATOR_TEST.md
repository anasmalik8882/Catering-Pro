# Milestone 8 — Maintenance rules emulator validation

This patch **adds only** `tests/security/firestore.maintenance.test.cjs`. It does not alter the currently deployed project or production rules.

## Run in Windows PowerShell, from project root

```powershell
cd C:\flutter_projects\catering_pro
node tools/verify_maintenance_rules.js
node --check tests/security/firestore.maintenance.test.cjs
firebase emulators:exec --config firebase.staging.json --only firestore --project demo-caterer-maintenance "node --test tests/security/firestore.maintenance.test.cjs"
```

Expected: four passing tests, zero failures. Existing security tests also remain relevant and must not be replaced with the maintenance test. Firestore emulator requires Java; if it does not start, fix the local toolchain rather than using production for testing.

## Scope and cautions

- Tests load `firebase/firestore.maintenance.rules` explicitly into the local emulator; the normal staging rules configuration is not changed.
- Emulator data is ephemeral and separate from both staging and production.
- This proves client Firestore SDK permissions only. Admin SDK/Cloud Functions and other privileged server processes bypass security rules and need separate write-freeze controls.
- A production deployment is **not** authorized by this test. Independently export/backup the *currently deployed* production rules and compare their source and release/version against the local base rules before any cutover.
- Only after verifying freeze, server writers, and recovery readiness should a fresh Firestore export and migration be scheduled.
