# 11 - Variant: Native AD FS TOTP (no external IdP)

This replaces the Keycloak IdP entirely. Instead of AD FS delegating authentication to Keycloak
(SAML), **AD FS does the password check itself (local Active Directory) and enforces TOTP through
an AD FS MFA adapter**. No external IdP, no SAML Claims Provider Trust. The reverse-proxy layer
(HAProxy or WAP) is unchanged.

```
Client -> AD FS (local forms: AD password) -> AD FS MFA adapter (TOTP) -> token -> Exchange
```

AD FS has no built-in on-prem TOTP (only Azure MFA, which is cloud). So this uses a third-party
adapter. Fully on-prem options:

| Adapter | License | TOTP | Secret storage | Notes |
| --- | --- | --- | --- | --- |
| **adfsmfa** (redhook62) | MIT, open-source | yes | AD attributes or SQL | This guide. Self-contained with AD storage. MMC + PowerShell. |
| SecureMFA MFA-OTP | commercial (free tier) | yes | AD attributes | Closed source, simple native adapter. |
| privacyIDEA / OpenOTP | open / commercial | yes | own server | Need a separate auth server (closer to an external IdP - excluded here). |

This doc uses **adfsmfa** with **AD attribute storage** = zero external components.

## Prerequisites

- adfsmfa MSI on **each** AD FS server (not the proxy), .NET Framework 4.7.2.
- The AD FS service account (often a gMSA) identity - you delegate two things to it below.

## 1. Install and register

Install the MSI (`msiexec /i adfsmfa.<ver>.msi /qn`). Then register the system.

> **Gotcha - the `*-MFA*` cmdlets are NOT remotable** (`PS0033: This Cmdlet is not remotable`).
> Run them in a **local** session on the AD FS server (RDP, or a scheduled task running as a
> local admin / the domain admin). PowerShell remoting / WinRM will refuse them.

```powershell
Register-MFASystem          # registers the AD FS provider + config; default storage = AD (ADDS)
Enable-MFASystem
```

This registers an AD FS additional-authentication provider named
`MultiFactorAuthenticationProvider` and stores TOTP secrets in AD attributes
(`msDS-cloudExtensionAttribute10..18` by default).

## 2. Grant the AD FS service account access (two places)

Both are required or the provider fails to initialize / enrollment can't save:

```powershell
# a) Write access to the AD attributes that hold the TOTP secret (run on the AD FS / DC).
$acct = 'CORP\adfsgmsa$'   # the AD FS service account
$dn   = 'DC=corp,DC=example'
'msDS-cloudExtensionAttribute10','msDS-cloudExtensionAttribute11','msDS-cloudExtensionAttribute12','msDS-cloudExtensionAttribute13','msDS-cloudExtensionAttribute14','msDS-cloudExtensionAttribute15','msDS-cloudExtensionAttribute16','msDS-cloudExtensionAttribute17','msDS-cloudExtensionAttribute18','otherMailBox' |
  ForEach-Object { dsacls $dn /I:S /G ("${acct}:RPWP;$_;user") | Out-Null }

# b) Modify access to the adfsmfa program/config dir (config.db). If config is changed by a
#    different account, config.db gets an ACL the AD FS service can't read -> provider init fails
#    ("Access to the path 'C:\Program Files\MFA\Config\config.db' is denied").
icacls "C:\Program Files\MFA" /grant ("${acct}:(OI)(CI)M") /T
```

Script: [../scripts/adfs-mfa/grant-permissions.ps1](../scripts/adfs-mfa/grant-permissions.ps1).

## 3. Switch AD FS back to local authentication

If you were running the Keycloak variant, re-enable the local claims provider so AD FS does the
password check itself:

```powershell
Set-AdfsProperties -IntranetUseLocalClaimsProvider $true
Set-AdfsProperties -EnableLocalAuthenticationTypes $true
```

Pin the Exchange relying-party trusts to the local AD claims provider (no home-realm-discovery):

```powershell
Get-AdfsRelyingPartyTrust | Where-Object { $_.Name -like 'Exchange*' } |
  ForEach-Object { Set-AdfsRelyingPartyTrust -TargetName $_.Name -ClaimsProviderName @('Active Directory') }
```

## 4. Enforce MFA (the part that actually triggers it)

> **Gotcha - the legacy "additional authentication rule" alone often does NOT trigger MFA in
> AD FS 2019.** The reliable mechanism is the **Access Control Policy** on the relying party:

```powershell
Get-AdfsRelyingPartyTrust | Where-Object { $_.Name -like 'Exchange*' } |
  ForEach-Object { Set-AdfsRelyingPartyTrust -TargetName $_.Name -AccessControlPolicyName 'Permit everyone and require MFA' }
```

Script: [../scripts/adfs-mfa/enforce-mfa-adfs.ps1](../scripts/adfs-mfa/enforce-mfa-adfs.ps1).

## 5. Make enrollment TOTP-only with self-registration

By default the enrollment wizard walks every enabled method (email, biometrics...) and requires a
verified email (needs SMTP). For a clean TOTP-only self-enrollment, run these **locally**
(the TOTP provider is called **`Code`** in adfsmfa's enum; use `-Confirm:$false` or `Set-MFAConfig`
hangs on a prompt in a non-interactive session):

```powershell
# Enable ONLY the TOTP (Code) provider; disable the others.
Set-MFAProvider -ProviderType Code       -ForceWizard Enabled -Confirm:$false
'Email','Azure','Biometrics' | ForEach-Object { Set-MFAProvider -ProviderType $_ -Enabled:$false -Confirm:$false }

# TOTP is the default; allow self-registration; skip the "provide email/phone" step.
Set-MFAConfig -DefaultProviderMethod Code -Confirm:$false
Set-MFAConfig -UserFeatures 'AllowUnRegistered, AllowChangePassword, AllowManageOptions, AllowEnrollment' -Confirm:$false
Update-MFAConfigurationCache
```

`AllowUnRegistered` here means "let unregistered users **self-register**" (the QR wizard), not
"bypass". Combined with the require-MFA Access Control Policy and `ForceWizard=Enabled`, a new
user is forced through TOTP enrollment on first login. Restart AD FS after config changes
(`Restart-Service adfssrv`).

Script: [../scripts/adfs-mfa/configure-adfsmfa.ps1](../scripts/adfs-mfa/configure-adfsmfa.ps1) (run locally on the AD FS server).

## 6. (Optional) Decommission Keycloak

With native TOTP live, stop and disable the Keycloak service. The Claims Provider Trust can be
left in place (unused) or removed.

## Verify

`https://mail.corp.example/owa/` -> local AD FS **Sign In** form (username + password, no redirect
to Keycloak) -> first login shows the **TOTP QR enrollment** (scan with Microsoft/Google
Authenticator) -> code -> mailbox. Subsequent logins prompt only for the code.

## Troubleshooting (native-TOTP-specific)

| Symptom | Cause | Fix |
| --- | --- | --- |
| Password logs in, no TOTP | require-MFA not enforced | set the **Access Control Policy** "Permit everyone and require MFA" on the RP (step 4) |
| `PS0033: not remotable` | running `*-MFA*` over WinRM/remoting | run in a local session / scheduled task on the AD FS server |
| Provider init error `Id=105`; `config.db is denied` | AD FS service account can't access `C:\Program Files\MFA` | `icacls ... /grant "<svc-acct>:(OI)(CI)M" /T` (step 2b) |
| Goes straight to "enter code", no QR | user pre-provisioned with a key (treated as enrolled) | let users self-register (don't pre-create), or `Set-MFAUsers -ResetKey` |
| "not activated, contact support" | `AllowUnRegistered` removed -> self-registration blocked | keep `AllowUnRegistered` in UserFeatures |
| Email step then "account invalid" | wizard requires a verified email; no SMTP | drop `AllowProvideInformations`; disable the Email provider (step 5) |
| Biometric-device prompt / WebAuthn error | Biometrics provider enabled | disable it; leave only `Code` (step 5) |
| `Set-MFAConfig` hangs | confirmation prompt in a non-interactive session | add `-Confirm:$false` |

## A note on OWA and the reverse proxy

The second factor works with either front-end. But **OWA in a browser through WAP pass-through
hangs on "Starting..."** because WAP does not upgrade OWA's notification **WebSocket**; OWA waits
out the timeout repeatedly. HAProxy handles the WebSocket (`timeout tunnel`), so front the browser
path with HAProxy (or the hybrid) - see [10-wap-variant.md](10-wap-variant.md). Rich clients
(Outlook/EAS) are unaffected.
