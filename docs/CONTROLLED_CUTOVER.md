# Caterer Pro — Production cutover (operator checklist)

**Source reviewed:** `catering_pro(20261101-164530).zip` uploaded Nov 1, 2026. This plan is for the single historical **development** tenant `aY8cWeFOjGBgJtxCc7Fk`. It does NOT release the whole three-interface SaaS product.

## A. Local validation only (safe)

1. Preserve previously established external source backup and three ruleset backups. Keep original `firebase.json` untouched.
2. Copy `tools/preflight_cutover.ps1` from this package to the project, then run `powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\preflight_cutover.ps1`. Stop if any assertion fails.
3. Confirm that the only production app user has closed all app instances, and that no Admin SDK scripts or other privileged clients are running. Firestore rules do **not** block Admin SDK writes.
4. Confirm previously-run emulator tests passed 4/4 for maintenance rules, and rollback emulator startup was successful.
5. Optionally capture a current screenshot of the production Firestore Rules page and publication history. Be ready to restore the previous version via the console if CLI deployment fails.

## B. Freeze (FIRST live change — explicit operator decision)

Run each operation manually; stop on any error. The production deploy command is:

```powershell
firebase deploy --project catering-pro-b001d --config firebase.maintenance.json --only firestore:rules
```

Check Firebase's deploy summary says **`catering-pro-b001d`** and rules-only; do not continue if not. This denies client writes, including new-business onboarding. Keep production app sessions closed.

Before any probe, wait for propagation; an existing active listener may take **up to 10 minutes** to pick up changed rules. Validate the live probe's Firebase Auth account belongs to the demo tenant and has `owner`, `manager`, or `sales` membership. The probe uses normal client credentials in LOCAL environment variables; **never paste a password into a chat or command transcript**. Set `$env:PROBE_EMAIL` and `$env:PROBE_PASSWORD` locally using `Read-Host` as appropriate. Read the script before executing. The probe writes a uniquely named disposable customer only if the freeze FAILS; this is a real write attempt.

```powershell
$env:CONFIRM_LIVE_RULES_PROBE='YES'
node tools/verify_live_maintenance_client.js --run-live
Remove-Item Env:CONFIRM_LIVE_RULES_PROBE -ErrorAction SilentlyContinue
Remove-Item Env:PROBE_PASSWORD -ErrorAction SilentlyContinue
```

Require explicit `PASS: production Firestore rejected ... permission-denied`. If output is `INCONCLUSIVE` or `FAIL: CLIENT WRITE SUCCEEDED`, **STOP**, do not export or migrate yet. Any created probe document must be investigated/cleaned by an authorized process. A single rejected operation is evidence for that route, not a comprehensive privilege freeze.

## C. Fresh post-freeze backup (ONLY after verified freeze)

- Run the existing **read-only** production inventory and migration verifier again, capture expected booking/payment counts.
- Create a NEW uniquely named GCS export using the Google Cloud Firestore export command (never reuse the prior path). For instance, after checking the syntax/version with `gcloud firestore export --help`:

```powershell
$stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$dest = "gs://caterer-pro-firestore-backup-b001d/exports/post-freeze-$stamp"
gcloud firestore export $dest --project catering-pro-b001d --database='(default)' --async
```

- **Do not proceed** merely because the command returned an operation name: use `gcloud firestore operations describe OPERATION_NAME --project catering-pro-b001d --database='(default)'` (verify command availability with `--help`) until `done:true` AND export operation success are confirmed. Check the new export's metadata and data files in Cloud Storage. If the CLI command differs in your installed version, stop and review; do not improvise in production.
- Record the export destination and operation ID outside the project. This backup covers Firestore only, not Auth, Storage or rules.

## D. Guarded migration (ONLY after verified fresh export)

- Rerun `node tools/verify_production_migration.js --business aY8cWeFOjGBgJtxCc7Fk` with explicit `GCLOUD_PROJECT=catering-pro-b001d` and `NODE_PATH` pointing to `functions/node_modules` as needed. Expect exactly 2 historical bookings, 3 payments, no initialized counters, absent trusted state, and no issues. If any differences, stop.
- Use **500 as a development tenant's demo capacity only**. Rerun `functions/scripts/reconcile.js` in audit mode with `--max-guests 500`, validate no issues, then invoke its guarded `--apply` once with exact project, business confirmation and env opt-ins. Do not run this step until the post-freeze backup operation is confirmed successful.
- Verify afterward with `tools/verify_production_migration.js`: exact historical day reservations, booking payment balances, initialized settings and trusted state, no issues. If mismatch, stop; don't blindly rerun apply.

## E. Trusted backend cutover and re-open

- The three trusted functions were validated in staging; **production Cloud Functions and Cloud Run APIs are currently disabled**, so expect first production deployment to require API enablement, IAM/billing checks, and possibly additional setup. Perform this only after migration success, while maintenance rules remain deployed.
- Deploy intended functions explicitly to production after reviewing function names, runtime, region, and account. Verify deployment health/permissions and production callable behavior. `updateDailyCapacity` is also needed for owner-managed limits.
- Deploy intended **final trusted** Firestore rules with explicit project and rule-only selection; do not deploy the old permissive rules as normal restoration after migration. Verify business workflows with limited production smoke tests and monitor logs. Never open writes before functions are healthy.
- In emergency, restoring the old published rules is a **security regression** (it permits legacy direct booking/payment writes). Use it only with informed rollback judgment; rolling back rules alone does not reverse migrated counters or function behavior. Data rollback requires its own reviewed plan.

## STOP triggers

- Wrong target project, local config/hash mismatch, unexpected rule change, unexpected writer, probe success/inconclusive, export not successful, changed historical counts, migration verifier issue, missing production functions permissions, smoke test failure.

## Limitations

- This package makes **no production calls or changes**. The prior manual console rules copy is not equivalent to an API-verified version identifier; keep the version-history screenshot and exact source. The client probe requires a locally available Firebase Auth password and will reject if account membership cannot be read. All three product interfaces remain in the roadmap; only the owner-app backend is in this cutover.
