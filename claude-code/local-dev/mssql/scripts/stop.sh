#!/usr/bin/env bash
#
# Stop and remove the container. Pass --purge to delete the data volume as well.
#
# Thin wrapper over ./local-env so the layout matches
# docs/mssql-podman-schema-cloning.md. The logic lives in the provisioner CLI.

set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
exec "$ROOT/local-env" down "$@"
