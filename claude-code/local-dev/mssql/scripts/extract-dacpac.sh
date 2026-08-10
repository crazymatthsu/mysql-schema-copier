#!/usr/bin/env bash
#
# Extract a schema-only DACPAC from an upstream SQL Server (needs sqlpackage).
#
# Thin wrapper over ./local-env so the layout matches
# docs/mssql-podman-schema-cloning.md. The logic lives in the provisioner CLI.

set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
exec "$ROOT/local-env" dacpac-extract "$@"
