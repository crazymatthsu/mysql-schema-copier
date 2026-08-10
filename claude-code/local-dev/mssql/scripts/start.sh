#!/usr/bin/env bash
#
# Start the local SQL Server container and wait until it accepts connections.
#
# Thin wrapper over ./local-env so the layout matches
# docs/mssql-podman-schema-cloning.md. The logic lives in the provisioner CLI.

set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
exec "$ROOT/local-env" up "$@"
