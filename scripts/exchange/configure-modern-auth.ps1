<#
.SYNOPSIS
    Enable OAuth 2.0 modern auth on Exchange and register AD FS as the authorization server.
.NOTES
    Run in the Exchange Management Shell as an Organization admin. Adjust the STS FQDN.
    Do NOT store real secrets here - this script contains none by design.
#>
param(
    [string]$StsFqdn = 'sts.corp.example'
)

$ErrorActionPreference = 'Stop'
$metadata = "https://$StsFqdn/FederationMetadata/2007-06/FederationMetadata.xml"

if (-not (Get-AuthServer -Identity ADFS -ErrorAction SilentlyContinue)) {
    New-AuthServer -Type ADFS -Name ADFS -AuthMetadataUrl $metadata
}

# Without this the Bearer challenge omits authorization_uri and clients drift to Office 365.
Set-AuthServer -Identity ADFS -IsDefaultAuthorizationEndpoint $true

Set-OrganizationConfig -OAuth2ClientProfileEnabled $true

Write-Host "Modern auth enabled. Next: add the AD FS Application Group (add-application-group-outlook.ps1)"
Write-Host "and set the client registry (enable-modern-auth-client.ps1). Extended Protection can stay at Require."
