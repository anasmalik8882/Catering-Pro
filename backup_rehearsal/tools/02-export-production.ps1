param(
  [Parameter(Mandatory=$true)][string]$BucketName,
  [Parameter(Mandatory=$true)][string]$ConfirmProductionExport
)
$ErrorActionPreference = 'Stop'
$project = 'catering-pro-b001d'
if ($ConfirmProductionExport -cne 'EXPORT-catering-pro-b001d') { throw 'Confirmation mismatch. No export started.' }
if ($BucketName -notmatch '^[a-z0-9][a-z0-9._-]{1,220}[a-z0-9]$') { throw 'Enter an existing GCS bucket name, without gs:// or path.' }
# Confirm the target bucket exists; do not create buckets automatically.
gcloud storage buckets describe "gs://$BucketName" --format='value(name)'
if ($LASTEXITCODE -ne 0) { throw 'Bucket missing or inaccessible. No export started.' }
$stamp = (Get-Date).ToUniversalTime().ToString('yyyyMMddTHHmmssZ')
$dest = "gs://$BucketName/caterer-pro-backups/$stamp"
Write-Host "Exporting FULL default Firestore DB from $project to $dest" -ForegroundColor Yellow
Write-Host 'This is a billable read/export operation; no production documents are modified.'
gcloud firestore export $dest --database='(default)' --project=$project
if ($LASTEXITCODE -ne 0) { throw 'Export failed. Do not import until successful completion is verified.' }
Write-Host "Export command succeeded. Record the EXACT export folder from the output/Cloud Console: $dest" -ForegroundColor Green
Write-Host 'Verify the operation completed in Firestore Import/Export history. The export folder may contain a timestamped child depending on service behavior.'
