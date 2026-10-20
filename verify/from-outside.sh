#!/usr/bin/env bash
# LIVE check, run from OUTSIDE the VNet (your laptop): the public path must be closed.
# Sends one anonymous request. A closed public path is expected to be refused with HTTP 403
# and error code "AuthorizationFailure". Anything else means public network access is open.
# Exact status/code per variant is a hypothesis until confirmed live (verify/expected-results.md).
# Usage: ./from-outside.sh <storage-account-name>
set -uo pipefail

ACCOUNT="${1:?usage: $0 <storage-account-name>}"
HOST="$ACCOUNT.blob.core.windows.net"
echo "Target: https://$HOST/?comp=list (anonymous)"
DNS_OUT=$(getent hosts "$HOST" 2>/dev/null | awk '{print $1}' | tr '\n' ' ')
echo "DNS from here: $DNS_OUT (a public IP is normal outside the VNet)"
[ -n "$DNS_OUT" ] || { echo "ERROR: $HOST does not resolve. Wrong account name? Not a valid test result."; exit 2; }

BODY=$(mktemp)
STATUS=$(curl -sS -m 20 -o "$BODY" -w '%{http_code}' "https://$HOST/?comp=list" 2>/dev/null) || STATUS=000
if [ "$STATUS" = 000 ]; then
  echo "PASS: no HTTP response (connection refused/timed out)."; rm -f "$BODY"; exit 0
fi
CODE=$(sed -n 's:.*<Code>\([^<]*\)</Code>.*:\1:p' "$BODY" | head -n1); rm -f "$BODY"
echo "HTTP $STATUS, error code: ${CODE:-(none)}"
if [ "$STATUS" = 403 ] && [ "$CODE" = AuthorizationFailure ]; then
  echo "PASS: refused at the network layer (public path closed)."; exit 0
fi
echo "FAIL: the request reached storage authorization, so the public endpoint is reachable."
exit 1
