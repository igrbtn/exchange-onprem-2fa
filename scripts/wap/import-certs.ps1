<#
.SYNOPSIS
    Trust the internal root CA and import the multi-SAN cert (with private key) on the WAP box,
    plus the split-brain hosts entries. Run on the WAP server (workgroup) as local admin.
.NOTES
    Copy rootca.cer and the multi-SAN lab.pfx to the box first (out-of-band). The PFX password
    is prompted - never hardcode it.
#>
param(
    [string]$RootCaCer = 'C:\wap\rootca.cer',
    [string]$Pfx       = 'C:\wap\lab.pfx',
    [string]$AdfsIp    = '10.0.0.10',
    [string]$KcIp      = '10.0.0.10',
    [string]$ExchIp    = '10.0.0.20',
    [string]$Domain    = 'corp.example'
)
$ErrorActionPreference = 'Stop'

# Trust the internal root CA so WAP validates the AD FS / Exchange / Keycloak backend certs.
Import-Certificate -FilePath $RootCaCer -CertStoreLocation Cert:\LocalMachine\Root | Out-Null
Write-Host "Root CA trusted."

# Import the multi-SAN cert with private key (used for the AD FS proxy + all published apps).
$pw  = Read-Host -AsSecureString -Prompt 'PFX password'
$imp = Import-PfxCertificate -FilePath $Pfx -CertStoreLocation Cert:\LocalMachine\My -Password $pw -Exportable
Write-Host ("Imported multi-SAN cert: {0}  SANs: {1}" -f $imp.Thumbprint, (($imp.DnsNameList | ForEach-Object { $_.Unicode }) -join ','))

# Split-brain hosts: WAP resolves the published names to the REAL backends.
$hosts = "$env:WINDIR\System32\drivers\etc\hosts"
$lines = @(
    "$AdfsIp sts.$Domain",
    "$KcIp kc.$Domain",
    "$ExchIp mail.$Domain",
    "$ExchIp autodiscover.$Domain"
)
$cur = Get-Content $hosts -ErrorAction SilentlyContinue
foreach ($l in $lines) { if ($cur -notcontains $l) { Add-Content -Path $hosts -Value $l } }
Write-Host "Split-brain hosts entries added. Thumbprint for the next steps: $($imp.Thumbprint)"
