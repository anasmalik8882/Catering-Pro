# Production client-write verification (preparation, not deployment)

This optional script is designed for the **Caterer Pro demo production tenant only**, using Firebase Auth + the Firebase **client** Firestore SDK. Never run it until maintenance rules have been deployed, the maintenance window is established, and you are ready to test the freeze.

## Local preflight — no network or write

From `C:\flutter_projects\catering_pro`:

```powershell
node --check tools/verify_live_maintenance_client.js
node tools/verify_live_maintenance_client.js --preflight
```

## Live operation — DO NOT RUN during preparation

After explicit decision to deploy the maintenance rules, and after propagation, execute using the production **owner** login for the historical demo tenant. Supply credentials only locally. A secure PowerShell prompt avoids exposing the password in shell history; for this process the password is transiently placed in a process environment variable. Do not share or capture the credentials in logs/screenshots.

```powershell
$env:PROBE_EMAIL = Read-Host 'Production owner login email'
$pw = Read-Host 'Production owner password' -AsSecureString
$env:PROBE_PASSWORD = [System.Net.NetworkCredential]::new('', $pw).Password
Remove-Variable pw
$env:CONFIRM_LIVE_RULES_PROBE = 'YES'
try { node tools/verify_live_maintenance_client.js --run-live }
finally {
  Remove-Item Env:PROBE_PASSWORD,Env:PROBE_EMAIL,Env:CONFIRM_LIVE_RULES_PROBE -ErrorAction SilentlyContinue
}
```

Expected: `PASS: production Firestore rejected ... permission-denied`.

If the create unexpectedly succeeds, the script exits with status 2 and prints the generated path; that **disposable** document may exist, and maintenance is unsafe. Stop migration and investigate. If authentication fails or another error occurs, results are inconclusive, not proof of a freeze.

## Critical operational notes

- Firestore rules **do not restrict Admin SDK**, service-account, or other privileged server-side writers.
- Client SDK can only test its own request; this is not evidence that every write path is blocked.
- Avoid running before deploying maintenance rules; a successful write is then likely.
- Use the independently saved production rules backup and rollback configuration for recovery; verify deployed rules in Firebase Console, and monitor propagation.
- Never copy passwords, Firebase tokens, or service-account keys into chat or project files.
