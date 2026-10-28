#!/usr/bin/env bash
set -euo pipefail

# Root convenience launcher — forwards all arguments to scripts/run.sh
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
exec "$SCRIPT_DIR/scripts/run.sh" "$@"
