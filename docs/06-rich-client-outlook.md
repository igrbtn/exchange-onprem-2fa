# 06 - Rich-client 2FA (Outlook / EWS / MAPI / EAS / OAB)

Layer 3: desktop and native mail clients use OAuth 2.0. Autodiscover points them at the AD FS
AuthServer; the browser popup goes to AD FS -> Keycloak -> password + TOTP; AD FS issues a
Bearer token for the Exchange resource.

Prereqs recap: **Windows 11 22H2+** client, Outlook M365 Apps / 2021 Retail 2304+. See
[01-prerequisites.md](01-prerequisites.md).

## 1. Exchange + AD FS

Done in [03-exchange-modern-auth.md](03-exchange-modern-auth.md): AuthServer registered and set
as default authorization endpoint, Application Group for the Outlook native client + Web APIs,
Extended Protection relaxed on the virtual directories.

## 2. Client registry (Windows 11)

Run [../scripts/client/enable-modern-auth-client.ps1](../scripts/client/enable-modern-auth-client.ps1)
on the client. It sets:

```powershell
# HKLM: trust the on-prem AD FS domain (both forms - with and without trailing slash)
New-Item 'HKLM:\SOFTWARE\Policies\Microsoft\AAD\AuthTrustedDomains' -Force | Out-Null
$k = [Microsoft.Win32.Registry]::LocalMachine.OpenSubKey('SOFTWARE\Policies\Microsoft\AAD\AuthTrustedDomains', $true)
$k.CreateSubKey('https://sts.corp.example/')  | Out-Null
$k.CreateSubKey('https://sts.corp.example')   | Out-Null

# HKCU: Office identity - prefer on-prem, do not jump to O365
Set-ItemProperty 'HKCU:\SOFTWARE\Microsoft\Office\16.0\Common\Identity' -Name EnableExchangeOnPremModernAuth -Value 1 -Type DWord
Set-ItemProperty 'HKCU:\SOFTWARE\Microsoft\Office\16.0\Common\Identity' -Name ExcludeExplicitO365Endpoint -Value 1 -Type DWord
Set-ItemProperty 'HKCU:\SOFTWARE\Microsoft\Office\16.0\Outlook\Autodiscover' -Name ExcludeExplicitO365Endpoint -Value 1 -Type DWord
Set-ItemProperty 'HKCU:\SOFTWARE\Microsoft\Exchange' -Name AlwaysUseMSOAuthForAutoDiscover -Value 1 -Type DWord
```

## 3. Add the account

Fully close Outlook. Add the mailbox again - a browser popup opens to AD FS, redirects to
Keycloak, prompts for password + TOTP, and Outlook reports "Account successfully added".

## 4. Verify

- EWS HttpProxy log (`...\Logging\HttpProxy\Ews\*.LOG`) shows
  `Bearer ... 200 ... ActAsUserVerified=True`.
- MAPI works (send/receive), EWS features (free/busy, OOF) work.

## Common failure modes (see full list in [09-troubleshooting.md](09-troubleshooting.md))

| Symptom | Cause | Fix |
| --- | --- | --- |
| `[7q6ck]` before AD FS even opens | client is not Win11 22H2+ (no WAM broker) | use Win11 22H2+ |
| `[2605]` after TOTP, token never reaches Exchange | Extended Protection behind bridging proxy, or MSIS9642 | relax EP; set CPT AnchorClaimType |
| client drifts to Office 365 | AuthServer not default endpoint | `Set-AuthServer -IsDefaultAuthorizationEndpoint $true` |
| 404 flashes after login | broker hits `/common/sso/final` on AD FS | HAProxy returns 200 for `/common/sso/*` |
