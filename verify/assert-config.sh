#!/usr/bin/env bash
# LIVE check (needs `az login` and a deployed resource group). Bash twin of assert-config.ps1.
# Usage: ./assert-config.sh <resource-group> [main|no-public-access-disable|no-dns-zone|empty-nsg]
# Configuration only: does not prove DNS answers or reachability (see from-inside.sh / from-outside.sh).
set -uo pipefail

RG="${1:?usage: $0 <resource-group> [variant]}"
VARIANT="${2:-main}"
VNET=vnet-harbor-prod; PE=pe-harbor-blob-prod; NSG=nsg-harbor-app-prod
ZONE=privatelink.blob.core.windows.net

case "$VARIANT" in
  main) EXPECT_FAIL=" " ;;
  no-public-access-disable) EXPECT_FAIL=" C1 " ;;
  no-dns-zone) EXPECT_FAIL=" C4 C5 C6 C7 " ;;
  empty-nsg) EXPECT_FAIL=" C8 C9 " ;;
  *) echo "unknown variant: $VARIANT" >&2; exit 2 ;;
esac

azq() { az "$@" --only-show-errors -o tsv 2>/dev/null; }

SA=$(azq storage account list -g "$RG" --query "[?starts_with(name,'stharbor')].name | [0]")
[ -n "$SA" ] || { echo "No stharbor* storage account in $RG (or not logged in)." >&2; exit 2; }

PE_NIC=$(azq network private-endpoint show -g "$RG" -n "$PE" --query "networkInterfaces[0].id")
PE_IP=""; [ -n "$PE_NIC" ] && PE_IP=$(azq network nic show --ids "$PE_NIC" --query "ipConfigurations[0].privateIPAddress")

MISMATCH=0
report() { # id name ok(0/1)
  local id="$1" name="$2" ok="$3" state=FAIL note="" flag=""
  [ "$ok" = 1 ] && state=PASS
  local should_fail=0; [[ "$EXPECT_FAIL" == *" $id "* ]] && should_fail=1
  [ "$should_fail" = 1 ] && note=" (expected to fail for this variant)"
  if [ "$ok" = "$should_fail" ]; then flag="  <-- UNEXPECTED"; MISMATCH=1; fi
  printf '%-4s %-4s %s%s%s\n' "$id" "$state" "$name" "$note" "$flag"
}
b() { [ "$1" = "$2" ] && echo 1 || echo 0; }
nonempty() { [ -n "$1" ] && echo 1 || echo 0; }

report C1 "storage publicNetworkAccess = Disabled" "$(b "$(azq storage account show -g "$RG" -n "$SA" --query publicNetworkAccess)" Disabled)"
report C2 "storage allowBlobPublicAccess = false" "$(b "$(azq storage account show -g "$RG" -n "$SA" --query allowBlobPublicAccess)" false)"
report C3 "private endpoint to blob exists and is Approved" "$(b "$(azq network private-endpoint show -g "$RG" -n "$PE" --query 'privateLinkServiceConnections[0].privateLinkServiceConnectionState.status')" Approved)"
report C4 "private DNS zone $ZONE exists" "$(b "$(azq network private-dns zone show -g "$RG" -n "$ZONE" --query name)" "$ZONE")"
LINK=$(azq network private-dns link vnet list -g "$RG" -z "$ZONE" --query "[0].virtualNetwork.id")
[[ "$LINK" == *"$VNET" ]] && L=1 || L=0
report C5 "zone linked to $VNET" "$L"
report C6 "private endpoint has a DNS zone group" "$(nonempty "$(azq network private-endpoint dns-zone-group list -g "$RG" --endpoint-name "$PE" --query '[0].name')")"
AREC=$(azq network private-dns record-set a list -g "$RG" -z "$ZONE" --query "[?name=='$SA'].aRecords[0].ipv4Address | [0]")
[ -n "$AREC" ] && [ "$AREC" = "$PE_IP" ] && [[ "$AREC" == 10.40.3.* ]] && A=1 || A=0
report C7 "zone has A record for the account = endpoint private IP" "$A"
report C8 "NSG allow 100: 10.40.1.0/24 -> 10.40.2.0/24 TCP 443" "$(nonempty "$(azq network nsg rule list -g "$RG" --nsg-name "$NSG" --query "[?priority==\`100\` && access=='Allow' && direction=='Inbound' && destinationPortRange=='443' && sourceAddressPrefix=='10.40.1.0/24' && destinationAddressPrefix=='10.40.2.0/24'].name | [0]")")"
report C9 "NSG deny 4000: VirtualNetwork -> 10.40.2.0/24" "$(nonempty "$(azq network nsg rule list -g "$RG" --nsg-name "$NSG" --query "[?priority==\`4000\` && access=='Deny' && direction=='Inbound' && sourceAddressPrefix=='VirtualNetwork' && destinationAddressPrefix=='10.40.2.0/24'].name | [0]")")"
[[ "$(azq network vnet subnet show -g "$RG" --vnet-name "$VNET" -n snet-app --query networkSecurityGroup.id)" == *"$NSG" ]] && N=1 || N=0
report C10 "NSG attached to snet-app" "$N"

echo "INFO allowSharedKeyAccess = $(azq storage account show -g "$RG" -n "$SA" --query allowSharedKeyAccess) (not set by the post's template; see docs/limits.md)"
if [ "$MISMATCH" = 1 ]; then echo "Result for '$VARIANT': UNEXPECTED"; exit 1; fi
echo "Result for '$VARIANT': matches expectation"
