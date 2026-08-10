#!/usr/bin/env bash
#
# Wait for readiness, then run the full validation suite.
#
# Thin wrapper over ./local-env so the layout matches
# docs/mssql-podman-schema-cloning.md. The logic lives in the provisioner CLI.

set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
"$ROOT/local-env" wait --timeout "${HEALTHCHECK_TIMEOUT:-60}"
exec "$ROOT/local-env" validate
