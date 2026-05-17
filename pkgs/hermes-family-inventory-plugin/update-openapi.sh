#!/usr/bin/env bash
# Sync src/openapi.yaml from the family-inventory repo.
#
# Usage:
#   ./update-openapi.sh                  # uses the default path below
#   ./update-openapi.sh /path/to/openapi.yaml
#
# After syncing, rebuild the plugin (or the host that consumes it):
#   nix build --no-link --print-out-paths \
#     .#packages.x86_64-linux.hermes-family-inventory-plugin
#
set -euo pipefail

DEFAULT_SRC="${HOME}/dev/src/github.com/narinari/family-inventory/apps/api/openapi.yaml"
SRC="${1:-$DEFAULT_SRC}"
DEST="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/src/openapi.yaml"

if [[ ! -f $SRC ]]; then
	echo "ERROR: source openapi.yaml not found: $SRC" >&2
	echo "       Run 'pnpm openapi:generate' in the family-inventory repo first." >&2
	exit 1
fi

cp "$SRC" "$DEST"
echo "Synced openapi.yaml:"
echo "  from: $SRC"
echo "  to:   $DEST"
