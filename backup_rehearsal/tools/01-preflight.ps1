$ErrorActionPreference = 'Stop'
$project = 'catering-pro-b001d'
Write-Host 'Caterer Pro backup preflight (read only)' -ForegroundColor Cyan
foreach ($command in @('gcloud','firebase')) {
  if (-not (Get-Command $command -ErrorAction SilentlyContinue)) { throw "$command not found in PATH" }
}
Write-Host "Expected production project: $project"
gcloud auth list --filter='status:ACTIVE' --format='table(account,status)'
if ($LASTEXITCODE -ne 0) { throw 'Cannot list Cloud CLI credentials' }
gcloud projects describe $project --format='table(projectId,projectNumber,lifecycleState)'
if ($LASTEXITCODE -ne 0) { throw 'Cannot inspect production project; verify permissions' }
gcloud firestore databases describe --database='(default)' --project=$project --format='table(name,locationId,type)'
if ($LASTEXITCODE -ne 0) { throw 'Cannot read production Firestore database; verify permissions and database ID' }
Write-Host 'Preflight completed; no export or import has been initiated.' -ForegroundColor Green
