#!/usr/bin/env bash
# LIVE check, run ON a VM inside vnet-harbor-prod (see scripts/run-live.ps1).
# Uses the VM's managed identity (IMDS token) - no account keys, no secrets.
#
# Usage: ./from-inside.sh <storage-account-name> [<app-ip> <allow|deny>]
#   1. DNS:  the blob hostname must resolve to 10.40.3.x (the private endpoint)
#   2. Blob: list container 'probe' over the private path with an Entra token -> HTTP 200
#   3. NSG (optional): TCP 443 to <app-ip> must be allowed or denied as stated
#      Add a 4th argument "nsg-only" to skip steps 1-2 (used on the VM that has no blob role).
set -uo pipefail

ACCOUNT="${1:?usage: $0 <storage-account-name> [<app-ip> <allow|deny> [nsg-only]]}"
APP_IP="${2:-}"; EXPECT="${3:-}"; MODE="${4:-}"
HOST="$ACCOUNT.blob.core.windows.net"
FAIL=0
pass() { echo "PASS  $*"; }
fail() { echo "FAIL  $*"; FAIL=1; }

if [ "$MODE" != nsg-only ]; then
IP=$(getent ahostsv4 "$HOST" | awk 'NR==1{print $1}')
echo "INFO  $HOST resolves to: ${IP:-<nothing>}"
if [[ "$IP" == 10.40.3.* ]]; then pass "DNS returns the private endpoint address";
else fail "DNS did not return 10.40.3.x (see docs/dns-troubleshooting.md)"; fi

TOKEN=$(curl -sS -m 10 -H Metadata:true \
  "http://169.254.169.254/metadata/identity/oauth2/token?api-version=2018-02-01&resource=https%3A%2F%2Fstorage.azure.com%2F" \
  | sed -n 's/.*"access_token":"\([^"]*\)".*/\1/p')
if [ -z "$TOKEN" ]; then
  fail "could not get a managed identity token (is the VM identity enabled?)"
else
  BODY=$(mktemp)
  STATUS=$(curl -sS -m 20 -o "$BODY" -w '%{http_code}' \
    -H "Authorization: Bearer $TOKEN" -H "x-ms-version: 2023-11-03" \
    "https://$HOST/probe?restype=container&comp=list") || STATUS=000
  CODE=$(sed -n 's:.*<Code>\([^<]*\)</Code>.*:\1:p' "$BODY" | head -n1); rm -f "$BODY"
  if [ "$STATUS" = 200 ]; then pass "blob list over the private path returned 200"
  else fail "blob list returned HTTP $STATUS ${CODE:+($CODE)}"; fi
fi
fi

if [ -n "$APP_IP" ]; then
  if timeout 5 bash -c "exec 3<>/dev/tcp/$APP_IP/443" 2>/dev/null; then REACHED=allow; else REACHED=deny; fi
  if [ "$REACHED" = "$EXPECT" ]; then pass "TCP 443 to $APP_IP was '$REACHED' as expected"
  else fail "TCP 443 to $APP_IP was '$REACHED', expected '$EXPECT'"; fi
fi

exit $FAIL
