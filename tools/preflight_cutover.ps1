$ErrorActionPreference = 'Stop'
Set-Location 'C:\flutter_projects\catering_pro'
$project = 'catering-pro-b001d'
$backup = 'C:\flutter_projects\catering_pro_backups\production_rules_20261101'
function Check($ok,$message) { if (-not $ok) { throw "STOP: $message" }; Write-Host "PASS: $message" }
$m = Get-Content .\firebase.maintenance.json -Raw | ConvertFrom-Json
$r = Get-Content .\firebase.rollback.json -Raw | ConvertFrom-Json
Check ($m.firestore.rules -eq 'firebase/firestore.maintenance.rules') 'Maintenance config'
Check ($r.firestore.rules -eq 'firebase/firestore.production.deployed.rules') 'Rollback config'
Check ((Test-Path .\firebase\firestore.maintenance.rules) -and (Test-Path .\firebase\firestore.production.deployed.rules)) 'Rules files present'
Check ((Get-FileHash .\firebase\firestore.production.deployed.rules).Hash -eq (Get-FileHash "$backup\firestore.production.deployed.rules").Hash) 'Rollback hash matches saved production rules'
Check ((Get-Item "$backup\firestore.production.deployed.rules").Length -gt 1000) 'Rollback backup nonempty'
Check ((Test-Path .\tools\verify_live_maintenance_client.js) -and (Test-Path .\functions\scripts\reconcile.js) -and (Test-Path .\tools\verify_production_migration.js)) 'Verification and migration scripts present'
& node tools/verify_maintenance_rules.js
if ($LASTEXITCODE -ne 0) { throw 'STOP: maintenance static verifier failed' }
& node tools/verify_live_maintenance_client.js --preflight
if ($LASTEXITCODE -ne 0) { throw 'STOP: client probe preflight failed' }
Write-Host "READY FOR REVIEW: target $project. NO PRODUCTION CHANGES MADE."
