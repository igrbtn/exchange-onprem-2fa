<#
.SYNOPSIS
    Configure the AD FS Claims Provider Trust that delegates authentication to Keycloak.
.DESCRIPTION
    Assumes the CPT was already created from Keycloak's SAML descriptor:
      https://kc.corp.example/realms/corp/protocol/saml/descriptor
    This script sets the acceptance transform rules (keep NameID, emit UPN) and the anchor
    claim type - the anchor is REQUIRED for OAuth id_token construction (missing it -> MSIS9642).
.NOTES
    Run on the AD FS server as an admin. Edit the parameters for your environment.
#>
param(
    [string]$TrustName  = 'Keycloak-corp',
    [string]$AdDnsDomain = 'corp.example'
)

$ErrorActionPreference = 'Stop'

$acceptanceRules = @'
@RuleName = "Passthrough NameID"
c:[Type == "http://schemas.xmlsoap.org/ws/2005/05/identity/claims/nameidentifier"]
 => issue(claim = c);

@RuleName = "NameID as UPN"
c:[Type == "http://schemas.xmlsoap.org/ws/2005/05/identity/claims/nameidentifier"]
 => issue(Type = "http://schemas.xmlsoap.org/ws/2005/05/identity/claims/upn", Value = c.Value);
'@

Set-AdfsClaimsProviderTrust -TargetName $TrustName -AcceptanceTransformRules $acceptanceRules

# CRITICAL: without an anchor claim, AD FS cannot build the id_token subject for OAuth clients.
Set-AdfsClaimsProviderTrust -TargetName $TrustName `
    -AnchorClaimType 'http://schemas.xmlsoap.org/ws/2005/05/identity/claims/upn' `
    -SigningCertificateRevocationCheck None

Write-Host "Claims Provider Trust '$TrustName' configured. If you hit ID4037, re-create the"
Write-Host "trust with the Keycloak signing cert supplied, then: Restart-Service adfssrv"
