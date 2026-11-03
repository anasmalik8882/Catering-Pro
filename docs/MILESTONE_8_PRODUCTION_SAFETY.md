# Caterer Pro — Milestone 8: Production safety and migration

## Scope and status
This patch adds a **read-only** verifier. No Firebase project has been modified. Do not run `reconcile.js --apply` yet.

Production project: `catering-pro-b001d`.
Production historical demo business ID: `aY8cWeFOjGBgJtxCc7Fk`.
Staging project: `caterer-pro-staging` (must not be confused with production).

## Before executing any migration
1. Inventory ALL existing production business IDs and connected users. The reconcile script accepts a single business ID; don't assume one demo business is the entire database.
2. Verify the existing successful historical export at `gs://caterer-pro-firestore-backup-b001d/exports/pre-production-migration-20261027-170620` using gcloud. Exports are point-in-time snapshots, not proof there have been no new writes since October 27.
3. Coordinate a verified write freeze across every legacy Flutter client, scheduled job, and administrator, so no one can write directly during migration. The existing reconciliation script does not implement a server-enforced write freeze.
4. After freeze, create and verify a NEW Firestore export. Consider Auth, Rules, indexes and Storage backups separately.
5. Run a new historical audit and separate read-only verification **after** freeze. Address any changes or discrepancies.
6. Make a deliberate decision about the demo business capacity (e.g. 500 as a demo-only number); ensure it covers existing reservations. Other businesses must configure their own limit.
7. Review the atomic migration and rollback plan, then explicitly authorize a live migration. Do not run live `--apply` before approvals and freeze evidence.
8. After apply, rerun this read-only verifier. The old `reconcile.js` audit intentionally flags already-existing trusted state, so it is NOT a post-migration verifier.
9. Deploy production Cloud Functions/rules/indexes in a planned, verified sequence; inspect old-client compatibility. Only then lift write freeze.
10. Run production smoke checks with controlled test records, review logs and monitor.

## Read-only verification commands (safe to run now)
Open PowerShell from the project root after copying `tools/verify_production_migration.js` there:

```powershell
cd C:\flutter_projects\catering_pro
Remove-Item Env:FIRESTORE_EMULATOR_HOST -ErrorAction SilentlyContinue
Remove-Item Env:CONFIRM_MAINTENANCE -ErrorAction SilentlyContinue
Remove-Item Env:ALLOW_LIVE_MIGRATION -ErrorAction SilentlyContinue
$env:GCLOUD_PROJECT = 'catering-pro-b001d'
node tools/verify_production_migration.js --business 'aY8cWeFOjGBgJtxCc7Fk'
```

Expected **before migration**: `readOnly:true`, `trustedState:"absent"`, historical counts generally 2 bookings/3 payments, and `issues:[]`. If production has changed, counts can differ. If it prints errors, stop and share the output (omit user private details). This script uses `firebase-admin` installed inside `functions/node_modules`; from the project root ensure dependencies are available by invoking `node` with module search path set:

```powershell
$env:NODE_PATH = (Resolve-Path .\functions\node_modules).Path
node tools/verify_production_migration.js --business 'aY8cWeFOjGBgJtxCc7Fk'
Remove-Item Env:NODE_PATH -ErrorAction SilentlyContinue
```

If the first invocation fails with `Cannot find module firebase-admin`, use the second one. The script performs Firestore read operations only.

## Security reminder
Google Application Default Credentials give admin-level access; keep credential files and the archive private. This script is defensive and read-only, but never run unreviewed third-party scripts with privileged credentials.
