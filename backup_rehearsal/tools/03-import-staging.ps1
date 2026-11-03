param(
  [Parameter(Mandatory=$true)][string]$StagingProjectId,
  [Parameter(Mandatory=$true)][string]$ExportFolder,
  [Parameter(Mandatory=$true)][string]$ConfirmImport
)
$ErrorActionPreference = 'Stop'
$production = 'catering-pro-b001d'
if ($StagingProjectId -eq $production -or $StagingProjectId -like 'demo-*' -or $StagingProjectId -notmatch '^[a-z][a-z0-9-]{4,28}[a-z0-9]$') { throw 'Target must be a REAL independent staging project, NOT production or an emulator demo-* project.' }
if ($ConfirmImport -cne "IMPORT-$StagingProjectId") { throw 'Confirmation mismatch. Import not started.' }
if ($ExportFolder -notmatch '^gs://[a-z0-9][a-z0-9._-]+/.+') { throw 'Provide the exact gs:// export directory from a completed Firestore export.' }
Write-Host 'CAUTION: Imports merge/overwrite matching document IDs, and do not delete unrelated existing documents.' -ForegroundColor Yellow
Write-Host 'Target project must have a separate EMPTY default Firestore database and correct IAM permissions.'
gcloud projects describe $StagingProjectId --format='value(projectId)'
if ($LASTEXITCODE -ne 0) { throw 'Staging project inaccessible. Import aborted.' }
gcloud firestore databases describe --database='(default)' --project=$StagingProjectId --format='table(name,locationId)'
if ($LASTEXITCODE -ne 0) { throw 'Staging default database not accessible. Import aborted.' }
Write-Host "RESTORE TARGET: $StagingProjectId"
Write-Host "RESTORE SOURCE: $ExportFolder"
Write-Host 'This is a billed WRITE operation on the staging project.'
gcloud firestore import $ExportFolder --database='(default)' --project=$StagingProjectId
if ($LASTEXITCODE -ne 0) { throw 'Import failed. Investigate operation state; do not repeat blindly.' }
Write-Host 'Import command completed. Verify in Firestore Import/Export operation history and run read-only verification.' -ForegroundColor Green
