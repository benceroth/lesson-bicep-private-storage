<#
.SYNOPSIS
  LIVE, COSTS MONEY (opt-in): deploys main.bicep or one variant, three tiny test VMs
  (no public IPs), runs every verify script, and prints the results.

.DESCRIPTION
  Needs `az login` and a subscription you may deploy to. Creates one resource group.
  Billed items: private endpoint (hourly + data), three B1s VMs with Standard_LRS disks,
  the storage account. Run scripts/cleanup.ps1 when done (or pass -Cleanup).
  Auth to blob uses the VM's managed identity (Storage Blob Data Reader). No keys are
  created, read or printed. Never commit the output if it contains subscription IDs.

.PARAMETER SshPublicKeyPath  Path to an SSH PUBLIC key (.pub). Required by the VM template.
#>
[CmdletBinding()]
param(
  [Parameter(Mandatory)] [string] $ResourceGroup,
  [Parameter(Mandatory)] [string] $SshPublicKeyPath,
  [ValidateSet('main', 'no-public-access-disable', 'no-dns-zone', 'empty-nsg')]
  [string] $Variant = 'main',
  [string] $Location = 'westeurope',
  [switch] $Cleanup
)

$ErrorActionPreference = 'Stop'
$root = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$template = if ($Variant -eq 'main') { Join-Path $root 'main.bicep' } else { Join-Path $root "variants/$Variant.bicep" }
$key = (Get-Content $SshPublicKeyPath -Raw).Trim()
if ($key -notmatch '^ssh-') { throw 'SshPublicKeyPath must point to a PUBLIC key (starts with ssh-).' }

function Step([string] $m) { Write-Host "`n=== $m" -ForegroundColor Cyan }
function Deploy-Vm([string] $name, [string] $subnet, [bool] $reader, [bool] $listen) {
  az deployment group create -g $ResourceGroup -n "vm-$name" --only-show-errors `
    --template-file (Join-Path $root 'test-vm/vm.bicep') `
    --parameters vmName=$name subnetName=$subnet sshPublicKey="$key" grantBlobReader=$($reader.ToString().ToLower()) listenOn443=$($listen.ToString().ToLower()) location=$Location `
    --query 'properties.outputs.privateIpAddress.value' -o tsv
}
function Run-Inside([string] $vm, [string[]] $scriptArgs) {
  $json = az vm run-command invoke -g $ResourceGroup -n $vm --command-id RunShellScript `
    --scripts "@$(Join-Path $root 'verify/from-inside.sh')" --parameters @scriptArgs --only-show-errors -o json
  ($json | ConvertFrom-Json).value[0].message
}

Step "Resource group $ResourceGroup ($Location)"
az group create -n $ResourceGroup -l $Location --only-show-errors -o none

try {
  Step "Deploy $Variant"
  az deployment group create -g $ResourceGroup -n "harbor-$Variant" --template-file $template --parameters location=$Location --only-show-errors -o none
  $account = (az storage account list -g $ResourceGroup --query "[?starts_with(name,'stharbor')].name | [0]" -o tsv --only-show-errors).Trim()

  Step 'Deploy test VMs (no public IP)'
  $appIp = Deploy-Vm 'vm-app' 'snet-app' $false $true
  Deploy-Vm 'vm-int' 'snet-integration' $true $false | Out-Null
  Deploy-Vm 'vm-denied' 'snet-private-endpoints' $false $false | Out-Null

  Step 'assert-config (resource configuration)'
  & (Join-Path $root 'verify/assert-config.ps1') -ResourceGroup $ResourceGroup -Variant $Variant

  Step 'from-outside (public path)'
  & (Join-Path $root 'verify/from-outside.ps1') -StorageAccountName $account

  Step 'from-inside on vm-int (DNS, blob via private path, TCP 443 to app should be ALLOWED)'
  Run-Inside 'vm-int' @($account, $appIp, 'allow')

  Step 'from-inside on vm-denied (TCP 443 to app should be DENIED by the NSG)'
  Run-Inside 'vm-denied' @($account, $appIp, 'deny', 'nsg-only')
}
finally {
  if ($Cleanup) { & (Join-Path $PSScriptRoot 'cleanup.ps1') -ResourceGroup $ResourceGroup -Yes }
  else { Write-Host "`nRemember: scripts/cleanup.ps1 -ResourceGroup $ResourceGroup" -ForegroundColor Yellow }
}
