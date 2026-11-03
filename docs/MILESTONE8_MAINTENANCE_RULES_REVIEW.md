# Caterer Pro Milestone 8 — maintenance rules (review package, NOT deployed)

## Scope verified from source
- Firebase production project: `catering-pro-b001d`.
- Active Firestore rules path in `firebase.json`: `firebase/firestore.rules`.
- `firebase/firestore.maintenance.rules` is a separate candidate rules file; it is NOT automatically deployed by firebase.json.
- The maintenance candidate preserves all original read conditions and forces all 36 create/update/delete/write grants to false, including user/bootstrap, tenant, sales, finance, and bookings writes.
- Admin SDK and Cloud Functions bypass security rules. Confirm no live privileged writers and pause all scripted/admin writes before relying on a maintenance window.
- Existing trusted Cloud Functions in staging are NOT evidence of production deployment. Never deploy the staging update function independently to production before verification.

## Safe local inspection only — now
Run from project root:
`node tools/verify_maintenance_rules.js`
`Get-FileHash firebase/firestore.rules -Algorithm SHA256`

## Before ANY live changes — hold point
1. Agree a maintenance window and stop app use, scripts, automated writes, and any privileged Admin SDK clients.
2. Export *currently active production* Firestore rules separately from local source (`firebase firestore:rules:get` is not a valid CLI command; use Firebase Console Rules tab or documented Firebase Rules API). Verify local source matches deployed rules before using this candidate. Do not assume Git/local files represent currently deployed rules.
3. Back up local source OUTSIDE the Flutter project, and save production rules version/text; plan restore and verification.
4. Test the candidate rules in a Firestore emulator with explicit denied-write tests and unchanged-read tests; manually check for unintended client writes.
5. Freeze all direct client writes by deploying a reviewed candidate rules file (not yet instructed here); verify with authenticated test client that writes fail and reads still work. This alone does NOT freeze Admin SDK writes.
6. Take and verify a NEW complete Firestore export AFTER freeze, then redo inventory/audit to rule out changes.
7. Check the migration guard and capacity 500 ONLY as demo configuration; execute guarded migration once, with explicit approval.
8. Verify counters and gate, deploy trusted functions and final rules, end maintenance, run smoke tests and monitor logs.

## Rollback
Do NOT restore an old permissive rules file during an incomplete migration. If a migration fails, keep write block active, diagnose and decide restore strategy from verified export. Once all invariants and production functions are verified, carefully restore reviewed final rules and test access. A backup export does not contain Auth accounts, Storage, or security rules.
