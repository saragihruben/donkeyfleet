# Build a distribution bundle of the DonkeyFleet standalone stack: exactly the files a
# recipient needs to `docker login` and `docker compose up` a published image — no source,
# no build override. Output: dist\donkeyfleet-standalone.zip
#
#   powershell -ExecutionPolicy Bypass -File deploy\standalone\make-bundle.ps1
$ErrorActionPreference = 'Stop'

$here  = $PSScriptRoot
$out   = Join-Path $here 'dist'
$stage = Join-Path $out 'donkeyfleet-standalone'
$zip   = Join-Path $out 'donkeyfleet-standalone.zip'

if (Test-Path $stage) { Remove-Item -Recurse -Force $stage }
if (Test-Path $zip)   { Remove-Item -Force $zip }
New-Item -ItemType Directory -Force -Path (Join-Path $stage 'keycloak') | Out-Null

Copy-Item (Join-Path $here 'docker-compose.yml')         (Join-Path $stage 'docker-compose.yml')
Copy-Item (Join-Path $here 'keycloak\realm-export.json') (Join-Path $stage 'keycloak\realm-export.json')
Copy-Item (Join-Path $here 'README.md')                  (Join-Path $stage 'README.md')
# Ship a ready-to-run .env from the template (dev-mode values only — no real secrets).
Copy-Item (Join-Path $here '.env.example')               (Join-Path $stage '.env')

Compress-Archive -Path $stage -DestinationPath $zip -Force

Write-Host "Bundle ready: $zip"
Write-Host "Contains: docker-compose.yml, keycloak/realm-export.json, README.md, .env"
