<#
.SYNOPSIS
    Create AD FS Relying Party Trusts for Exchange OWA and ECP (browser 2FA, layer 1).
.DESCRIPTION
    One RP trust per WS-Fed passive endpoint - OWA and ECP are separate. Issuance rules pass
    the UPN and resolve the AD primarysid by DOMAIN\user (the AD store query needs that format).
.NOTES
    Run on the AD FS server as admin. Adjust the FQDN / domain parameters.
#>
param(
    [string]$MailFqdn    = 'mail.corp.example',
    [string]$AdDnsDomain = 'corp.example',
    [string]$NetBios     = 'CORP'
)

$ErrorActionPreference = 'Stop'

$rules = @"
@RuleName = "Passthrough UPN"
c:[Type == "http://schemas.xmlsoap.org/ws/2005/05/identity/claims/upn"] => issue(claim = c);

@RuleName = "PrimarySID from AD by UPN"
c:[Type == "http://schemas.xmlsoap.org/ws/2005/05/identity/claims/upn"]
 => issue(store = "Active Directory",
    types = ("http://schemas.microsoft.com/ws/2008/06/identity/claims/primarysid"),
    query = ";objectSid;{0}",
    param = RegExReplace(c.Value, "^(.*)@$($AdDnsDomain -replace '\.','\.')`$", "$NetBios\`$1"));
"@

$authRule = '=> issue(Type = "http://schemas.microsoft.com/authorization/claims/permit", Value = "true");'

foreach ($vdir in @('owa','ecp')) {
    $id  = "https://$MailFqdn/$vdir/"
    $name = "Exchange $($vdir.ToUpper())"
    if (Get-AdfsRelyingPartyTrust -Name $name -ErrorAction SilentlyContinue) {
        Write-Host "RP trust '$name' already exists - skipping."
        continue
    }
    Add-AdfsRelyingPartyTrust -Name $name -Identifier $id -WSFedEndpoint $id `
        -IssuanceTransformRules $rules -IssuanceAuthorizationRules $authRule -Enabled $true
    Write-Host "Created RP trust '$name' ($id)"
}
