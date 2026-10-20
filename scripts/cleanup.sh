#!/usr/bin/env bash
# Deletes the resource group created for the live checks (and everything in it).
# Usage: ./cleanup.sh <resource-group> [--yes]
set -euo pipefail
RG="${1:?usage: $0 <resource-group> [--yes]}"
if [ "${2:-}" != "--yes" ]; then
  read -r -p "Delete resource group '$RG' and everything in it? (type the name to confirm) " A
  [ "$A" = "$RG" ] || { echo "Aborted."; exit 1; }
fi
az group delete -n "$RG" --yes --no-wait --only-show-errors
echo "Deletion of '$RG' started (asynchronous). Check: az group exists -n $RG"
