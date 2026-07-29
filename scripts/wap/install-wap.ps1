<#
.SYNOPSIS
    Install the Web Application Proxy role and establish the trust with AD FS.
.NOTES
    Run on the WAP server (workgroup) as local admin. The federation trust credential is a
    domain admin, used ONCE over the network to establish the proxy trust.
.PARAMETER CertificateThumbprint
    Thumbprint of the multi-SAN cert imported by import-certs.ps1.
#>
param(
    [string]$FederationServiceName = 'sts.corp.example',
    [Parameter(Mandatory=$true)][string]$CertificateThumbprint
)
$ErrorActionPreference = 'Stop'

$f = Install-WindowsFeature Web-Application-Proxy -IncludeManagementTools
Write-Host ("WAP feature: success={0} restartNeeded={1}" -f $f.Success, $f.RestartNeeded)

$cred = Get-Credential -Message 'Domain admin (federation service trust credential)'

try {
    Install-WebApplicationProxy `
        -FederationServiceName $FederationServiceName `
        -CertificateThumbprint $CertificateThumbprint `
        -FederationServiceTrustCredential $cred -ErrorAction Stop
    Write-Host "WAP installed and trusted with AD FS."
} catch {
    Write-Warning "Install-WebApplicationProxy failed: $($_.Exception.Message)"
    Write-Warning "If this is 'Could not establish trust relationship for the SSL/TLS secure channel',"
    Write-Warning "AD FS is presenting a self-signed SSL cert. Fix: give AD FS a CA-issued cert, or"
    Write-Warning "(lab) import the AD FS cert into Cert:\LocalMachine\Root on this box, then retry."
    return
}

Get-Service appproxysvc,appproxyctrl | ForEach-Object { "{0}={1}" -f $_.Name, $_.Status }
Get-WebApplicationProxyConfiguration | Select-Object ADFSUrl,ConnectedServersName
