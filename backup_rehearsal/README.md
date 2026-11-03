# Caterer Pro — production Firestore backup & isolated restore rehearsal

Based on latest uploaded ZIP: `catering_pro(20261026-091219).zip`.

**This package does not contain a backup and does not itself perform any cloud operation.** It includes deliberately separate guarded scripts. No production writes are permitted by these scripts. Run only when ready to incur Firebase/GCP charges and after checking access.

## Critical prerequisites

- `gcloud` installed and authenticated; use `gcloud auth login` for CLI if needed. The previously configured `gcloud auth application-default login` is for SDKs, not necessarily the gcloud CLI identity.
- Production project: `catering-pro-b001d`; default Firestore database (Asia region as configured).
- Real **independent** staging GCP/Firebase project (must be created separately) with an **empty** default Firestore database; do **not** use `demo-caterer-stage` for managed import.
- Production project must have billing enabled (Firebase Blaze). Export/import and bucket storage incur charges.
- A private GCS bucket accessible to the production Firestore service agent; cross-project import also requires staging Firestore service agent bucket read permissions. Use least privilege; avoid granting roles at the entire project level.
- Record retention and privacy plan: the full export contains all customer/business information, not just synthetic test data. Protect staging access and delete staging copies after testing.
- Export can contain changes made during execution. To establish a consistent restore baseline for financial migration, use a planned maintenance window/write freeze or a suitable point-in-time strategy; do not blindly assume live export is a transactionally consistent snapshot.
- Cloud export does not automatically recreate all indexes, security rules, authentication users, storage files, or application configuration. These must be handled separately. The audit verifier below is limited to selected business subcollections.

## Step A — read-only checks (PowerShell at project root)

`powershell -ExecutionPolicy Bypass -File .\backup_rehearsal\tools\01-preflight.ps1`

In Google Cloud Console: verify Firestore database location and billing; provision a private bucket in a supported nearby region, make sure appropriate Firestore service agent can access it.

## Step B — export production (read-only to Firestore but billed)

`powershell -ExecutionPolicy Bypass -File .\backup_rehearsal\tools\02-export-production.ps1 -BucketName 'YOUR_PRIVATE_BUCKET' -ConfirmProductionExport 'EXPORT-catering-pro-b001d'`

Wait for the gcloud export operation to complete successfully; record the **exact** `gs://` export directory printed by gcloud or Cloud Console. Verify exported metadata exists before restore. Do not just assume success because an operation was started.

## Step C — read-only production business verifier

Run from `functions` (must have `npm install` complete):

`node ../backup_rehearsal/tools/verify-business.js --project catering-pro-b001d --business aY8cWeFOjGBgJtxCc7Fk --output ../backup_rehearsal/production-verification.json`

This writes a local file containing counts and SHA-256 fingerprints for the `bookings`, `payments`, `capacityDays`, and `paymentBalances` subcollections. It does **not** dump customer data. It reads *current* Firestore values, so if production was modified after the export, a fingerprint mismatch can be expected. To compare correctly, freeze writes before export and keep them frozen until the production verifier completes, or use a time-correlated validation technique.

## Step D — import to a separate real staging project

Create or select a new staging project with an **empty** default Firestore database, correct access to the export bucket, and matching relevant database setup. The script cannot prove the database is empty; check this manually first.

`powershell -ExecutionPolicy Bypass -File .\backup_rehearsal\tools\03-import-staging.ps1 -StagingProjectId 'YOUR-REAL-STAGING-PROJECT' -ExportFolder 'gs://BUCKET/EXACT_EXPORT_FOLDER' -ConfirmImport 'IMPORT-YOUR-REAL-STAGING-PROJECT'`

This is a write to the *staging* project only. It is not performed by the package automatically. Be aware imports may overwrite matching documents; they do not delete unrelated documents.

## Step E — compare selected records (read-only)

`node ../backup_rehearsal/tools/verify-business.js --project YOUR-REAL-STAGING-PROJECT --business aY8cWeFOjGBgJtxCc7Fk --output ../backup_rehearsal/staging-verification.json`

`node ../backup_rehearsal/tools/compare-verifications.js ../backup_rehearsal/production-verification.json ../backup_rehearsal/staging-verification.json`

**This checks only four business subcollections; it is not a comprehensive restore validation.** For a real disaster-recovery test, also inspect unrelated businesses and collections, child subcollections, indexes, rules, auth users, storage and restore permissions.

## Step F — staging migration rehearsal (after successful verification)

Use staging project credentials and point reconcile.js ONLY to the staging project. Never supply `ALLOW_LIVE_MIGRATION=YES` for an unreviewed project. For an *audit* first:

`$env:GCLOUD_PROJECT='YOUR-REAL-STAGING-PROJECT'`

`node scripts/reconcile.js --business 'aY8cWeFOjGBgJtxCc7Fk' --max-guests 500`

Do not run `--apply` yet. Require a reviewed plan and explicitly validated guest capacity. The existing script refuses applying when trusted counter/gate docs exist.

## Safety and limitations

- No data has been backed up or restored merely by generating this ZIP.
- `--max-guests 500` is a sample, NOT your actual capacity.
- Migration of the live database remains blocked until backup, restore, reconciliation and write-freeze plan are verified.
- Avoid committing generated `*-verification.json` files, GCP credentials or any export metadata containing private information.
