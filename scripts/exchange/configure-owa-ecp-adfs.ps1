<#
.SYNOPSIS
    Point Exchange OWA and ECP at AD FS for claims-based auth (browser 2FA, layer 1).
.DESCRIPTION
    Requires the AD FS token-signing certificate to be imported into the Trusted Root store on
    the Exchange server first. Set the thumbprint parameter to that certificate's thumbprint.
.NOTES
    Run in the Exchange Management Shell as an Organization admin.
#>
param(
    [string]$StsFqdn  = 'sts.corp.example',
    [string]$MailFqdn = 'mail.corp.example',
    [Parameter(Mandatory=$true)][string]$AdfsSignCertificateThumbprint
)

$ErrorActionPreference = 'Stop'

Set-OrganizationConfig `
    -AdfsIssuer "https://$StsFqdn/adfs/ls/" `
    -AdfsAudienceUris "https://$MailFqdn/owa/","https://$MailFqdn/ecp/" `
    -AdfsSignCertificateThumbprint $AdfsSignCertificateThumbprint

Get-OwaVirtualDirectory | Set-OwaVirtualDirectory -AdfsAuthentication $true `
    -BasicAuthentication $false -FormsAuthentication $false -WindowsAuthentication $false
Get-EcpVirtualDirectory | Set-EcpVirtualDirectory -AdfsAuthentication $true `
    -BasicAuthentication $false -FormsAuthentication $false -WindowsAuthentication $false

Write-Host "OWA/ECP set to AD FS auth. Running iisreset..."
iisreset
