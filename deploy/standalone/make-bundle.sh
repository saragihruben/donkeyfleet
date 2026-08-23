#!/usr/bin/env bash
# Build a distribution bundle of the DonkeyFleet standalone stack: exactly the files a
# recipient needs to `docker login` and `docker compose up` a published image — no source,
# no build override. Output: dist/donkeyfleet-standalone.zip
#
#   ./deploy/standalone/make-bundle.sh
#
# On Windows (Git Bash usually has no `zip`), use make-bundle.ps1 instead.
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
out="$here/dist"
stage="$out/donkeyfleet-standalone"
zip_path="$out/donkeyfleet-standalone.zip"

rm -rf "$stage" "$zip_path"
mkdir -p "$stage/keycloak"

cp "$here/docker-compose.yml"         "$stage/docker-compose.yml"
cp "$here/keycloak/realm-export.json" "$stage/keycloak/realm-export.json"
cp "$here/README.md"                  "$stage/README.md"
# Ship a ready-to-run .env from the template (dev-mode values only — no real secrets).
cp "$here/.env.example"               "$stage/.env"

if ! command -v zip >/dev/null 2>&1; then
  echo "This script needs 'zip', which isn't installed. On Windows run make-bundle.ps1 instead." >&2
  echo "Staged (unzipped) files are in: $stage" >&2
  exit 1
fi
( cd "$out" && zip -r -q donkeyfleet-standalone.zip donkeyfleet-standalone )

echo "Bundle ready: $zip_path"
echo "Contains: docker-compose.yml, keycloak/realm-export.json, README.md, .env"
