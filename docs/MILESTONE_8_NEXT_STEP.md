# Milestone 8 — tenant inventory before production migration

This patch adds only a read-only Firebase Admin script. It does not migrate data, deploy functions, edit security rules, or freeze writes.

## Preconditions
- Run from the Caterer Pro project root on a trusted machine with appropriate Google Application Default Credentials.
- Ensure the production project ID is correct. Do not paste credentials into chat.
- The script lists business document IDs and counts, not email addresses or customer details.

## PowerShell
```powershell
cd C:\flutter_projects\catering_pro
node --check tools/inventory_production_tenants.js
Remove-Item Env:FIRESTORE_EMULATOR_HOST -ErrorAction SilentlyContinue
Remove-Item Env:CONFIRM_MAINTENANCE -ErrorAction SilentlyContinue
Remove-Item Env:ALLOW_LIVE_MIGRATION -ErrorAction SilentlyContinue
$env:GCLOUD_PROJECT = 'catering-pro-b001d'
$env:NODE_PATH = (Resolve-Path .\functions\node_modules).Path
node tools/inventory_production_tenants.js
Remove-Item Env:NODE_PATH -ErrorAction SilentlyContinue
```

## Interpretation
- Check each `businessId` and its bookings, payments and trusted state.
- If there are other businesses in production, they need their own migration readiness assessment. Do not run one-business migration as though it were global.
- For the historical demo business, the earlier read-only verifier found two bookings, three payments, no trusted counters, and no issues.
- Do not execute `reconcile.js --apply` until a server-enforced write freeze, a fresh verified backup taken after freeze, and a cutover sequence have been separately reviewed.
