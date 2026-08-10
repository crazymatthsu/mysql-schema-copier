#!/usr/bin/env bash
#
# Publish a DACPAC into the local container (needs sqlpackage).
#
# Thin wrapper over ./local-env so the layout matches
# docs/mssql-podman-schema-cloning.md. The logic lives in the provisioner CLI.

set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
exec "$ROOT/local-env" dacpac-publish "$@"
