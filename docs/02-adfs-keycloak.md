# 02 - AD FS + Keycloak

This is the core of the design: Keycloak becomes an external IdP behind AD FS via a **Claims
Provider Trust (SAML)**. AD FS stays the STS Exchange trusts (WS-Fed for OWA/ECP, OAuth for
rich clients); Keycloak does the actual credential check and enforces TOTP.

```
Exchange --trusts--> AD FS --Claims Provider Trust (SAML)--> Keycloak --LDAP--> Active Directory
                                                                 |
                                                            password + TOTP
```

## 1. Install AD FS

AD FS must run on a domain-joined Windows Server 2019+ that is **not** the Exchange server.

**Prerequisites:**

- A server-authentication certificate whose subject/SAN is your federation service name
  (`sts.corp.example`). Issue it from your internal CA and import it into the machine's
  personal store. Note its thumbprint.
- A group Managed Service Account (gMSA) for the AD FS service (recommended), or a domain
  service account. To use a gMSA the forest needs a KDS root key:
  `Add-KdsRootKey -EffectiveTime (Get-Date).AddHours(-10)` (once per forest).

**Install and create the farm:**

```powershell
Install-WindowsFeature ADFS-Federation -IncludeManagementTools

Import-Module ADFS
$cert = Get-ChildItem Cert:\LocalMachine\My |
        Where-Object { $_.Subject -like '*sts.corp.example*' } | Select-Object -First 1

Install-AdfsFarm `
  -CertificateThumbprint $cert.Thumbprint `
  -FederationServiceName 'sts.corp.example' `
  -FederationServiceDisplayName 'Corp SSO' `
  -GroupServiceAccountIdentifier 'CORP\adfsgmsa$'
```

**Set the primary authentication to Forms** so the modern-auth popup renders a form that then
bounces to Keycloak:

```powershell
Set-AdfsGlobalAuthenticationPolicy `
  -PrimaryIntranetAuthenticationProvider FormsAuthentication `
  -PrimaryExtranetAuthenticationProvider FormsAuthentication
```

Optional - route ALL logins through Keycloak (suppress the local AD FS credential prompt so
the only login form the user ever sees is Keycloak's):

```powershell
Set-AdfsProperties -IntranetUseLocalClaimsProvider $false
Set-AdfsProperties -EnableLocalAuthenticationTypes $false
```

Verify AD FS is up: `https://sts.corp.example/adfs/ls/idpinitiatedsignon.aspx` (enable it
temporarily with `Set-AdfsProperties -EnableIdPInitiatedSignonPage $true` if needed) or
`https://sts.corp.example/FederationMetadata/2007-06/FederationMetadata.xml` should return XML.

## 2. Install and run Keycloak

Keycloak 26.x needs JDK 21. Minimal start behind the HAProxy reverse proxy (TLS terminates at
HAProxy; Keycloak listens HTTP on 8080):

```bash
kc.sh start \
  --http-enabled=true --http-port=8080 \
  --hostname=https://kc.corp.example --hostname-strict=false \
  --proxy-headers=xforwarded
```

Set the bootstrap admin credentials out-of-band (`KC_BOOTSTRAP_ADMIN_USERNAME` /
`KC_BOOTSTRAP_ADMIN_PASSWORD` env vars on first start), never on the command line. For a
Windows host, run `kc.bat` under a service/scheduled task; while iterating on the login theme
add `--spi-theme-cache-themes=false --spi-theme-cache-templates=false` (see
[08-keycloak-login-theme.md](08-keycloak-login-theme.md)).

## 3. Keycloak realm

Create a realm (e.g. `corp`): admin console -> **Create realm** -> name `corp`.

### 3.1 LDAP federation to AD

Realm -> **User federation** -> **Add Ldap provider**:

| Field | Value |
| --- | --- |
| Vendor | Active Directory |
| Connection URL | `ldaps://dc.corp.example:636` (or `ldap://...:389`) |
| Bind type | simple |
| Bind DN | a read account, e.g. `CORP\svc-kc-ldap` |
| Bind credential | (set out-of-band) |
| Users DN | `OU=Users,DC=corp,DC=example` |
| **Username LDAP attribute** | **`userPrincipalName`** |
| RDN LDAP attribute | `cn` |
| UUID LDAP attribute | `objectGUID` |
| User object classes | `person, organizationalPerson, user` |

**Setting `usernameLDAPAttribute = userPrincipalName`** (not `cn`, not `sAMAccountName`) makes
the login identifier the UPN and the SAML `NameID` equal to the UPN - which is exactly what the
AD FS claim rules downstream expect. After changing this attribute on an existing provider,
**Remove imported users** then **Sync all users** (Action menu), or the old records keep the
wrong username.

> Gotcha: when you create realm sub-components via REST/kcadm, the `parentId` must be the
> **realm UUID** (`GET /admin/realms/corp` -> `.id`), NOT the realm name. Using the name
> orphans the component - the LDAP sync reports "0 imported" and login silently fails.

### 3.2 TOTP (the second factor)

Realm -> **Authentication** -> **Required actions** -> enable **Configure OTP** and set it as
**Default action**. Every user is then forced to enrol an authenticator (Google Authenticator,
Microsoft Authenticator, etc.) on first login. Tune the algorithm/digits under Realm settings
-> tokens if needed (default TOTP / SHA1 / 6 digits interoperates with all common apps).

### 3.3 SAML client for AD FS

Realm -> **Clients** -> **Create client** -> type **SAML**:

| Setting | Value |
| --- | --- |
| Client ID | `http://sts.corp.example/adfs/services/trust` |
| Valid redirect URIs | `https://sts.corp.example/adfs/ls/*` |
| Name ID format | `username` |
| Sign documents | On |
| Sign assertions | On |
| Signature key name (advanced) | **`CERT_SUBJECT`** |

The last row is the one people miss: set
`saml.server.signature.keyinfo.xmlSigKeyInfoKeyNameTransformer = CERT_SUBJECT`. The Keycloak
default (`KEY_ID`) puts a key id in the SAML `KeyInfo` that AD FS cannot map to the trust's
signing certificate, and every login fails with **ID4037** (see
[09-troubleshooting.md](09-troubleshooting.md)).

Helper that creates this client with the right attributes:
[../scripts/keycloak/create-saml-client.sh](../scripts/keycloak/create-saml-client.sh).

## 4. Claims Provider Trust (AD FS -> Keycloak)

In the AD FS management console: **Claims Provider Trusts** -> **Add Claims Provider Trust** ->
import from the federation metadata URL
`https://kc.corp.example/realms/corp/protocol/saml/descriptor`. Name it `Keycloak-corp`.

Then configure its rules and anchor with
[../scripts/adfs/setup-claims-provider-trust.ps1](../scripts/adfs/setup-claims-provider-trust.ps1):

```powershell
$name = 'Keycloak-corp'

# Acceptance transform rules: keep the NameID (anchor for the id_token) and emit it as UPN.
$rules = @'
@RuleName = "Passthrough NameID"
c:[Type == "http://schemas.xmlsoap.org/ws/2005/05/identity/claims/nameidentifier"] => issue(claim = c);
@RuleName = "NameID as UPN"
c:[Type == "http://schemas.xmlsoap.org/ws/2005/05/identity/claims/nameidentifier"]
 => issue(Type = "http://schemas.xmlsoap.org/ws/2005/05/identity/claims/upn", Value = c.Value);
'@
Set-AdfsClaimsProviderTrust -TargetName $name -AcceptanceTransformRules $rules

# CRITICAL for OAuth id_token construction (otherwise MSIS9642, see troubleshooting):
Set-AdfsClaimsProviderTrust -TargetName $name `
  -AnchorClaimType 'http://schemas.xmlsoap.org/ws/2005/05/identity/claims/upn' `
  -SigningCertificateRevocationCheck None
```

The Keycloak token-signing certificate must be present on the trust. If you hit **ID4037**
("key could not be resolved") even after `CERT_SUBJECT`, remove and re-add the trust with the
certificate supplied at add time, then restart the AD FS service (`Restart-Service adfssrv`).

## 5. Verify the chain

Browse to `https://mail.corp.example/owa` (after wiring layer 1 in
[05-browser-owa-ecp.md](05-browser-owa-ecp.md)). You should be redirected to AD FS, then to the
Keycloak login page, prompted for password + TOTP, and land in OWA. If the browser stops at
AD FS with a credential form instead of bouncing to Keycloak, re-check the Forms auth policy
(step 1) and, optionally, the "route ALL logins through Keycloak" settings.
