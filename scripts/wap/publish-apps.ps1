<#
.SYNOPSIS
    Publish Exchange, Autodiscover and Keycloak through WAP as pass-through applications.
.DESCRIPTION
    Pass-through (no AD FS pre-auth): Keycloak is not an AD FS relying party, and rich-client
    OAuth needs pass-through. /adfs/* is proxied natively by the federation role.
.NOTES
    Run on the WAP server as local admin, after install-wap.ps1.
#>
param(
    [Parameter(Mandatory=$true)][string]$CertificateThumbprint,
    [string]$Domain = 'corp.example',
    [int]$KcPort    = 8080
)
$ErrorActionPreference = 'Stop'

$apps = @(
    @{ Name='Exchange';     Ext="https://mail.$Domain/";          Back="https://mail.$Domain/" },
    @{ Name='Autodiscover'; Ext="https://autodiscover.$Domain/";  Back="https://autodiscover.$Domain/" },
    @{ Name='Keycloak';     Ext="https://kc.$Domain/";            Back="http://kc.$Domain`:$KcPort/" }
)

foreach ($a in $apps) {
    $ex = Get-WebApplicationProxyApplication -ErrorAction SilentlyContinue | Where-Object { $_.Name -eq $a.Name }
    if ($ex) { Write-Host "skip (exists): $($a.Name)"; continue }
    Add-WebApplicationProxyApplication -Name $a.Name -ExternalPreauthentication PassThrough `
        -ExternalUrl $a.Ext -BackendServerUrl $a.Back -ExternalCertificateThumbprint $CertificateThumbprint
    Write-Host "published: $($a.Name)"
}

Get-WebApplicationProxyApplication | ForEach-Object { "{0,-14} {1} -> {2}" -f $_.Name, $_.ExternalUrl, $_.BackendServerUrl }
