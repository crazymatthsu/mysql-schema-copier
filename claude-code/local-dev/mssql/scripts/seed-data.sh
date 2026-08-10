#!/usr/bin/env bash
#
# Load seed data into the already-provisioned databases.
#
# Thin wrapper over ./local-env so the layout matches
# docs/mssql-podman-schema-cloning.md. The logic lives in the provisioner CLI.

set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
exec "$ROOT/local-env" seed "$@"
