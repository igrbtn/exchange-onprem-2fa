# 02 - AD FS + Keycloak

This is the core of the design: Keycloak becomes an external IdP behind AD FS via a **Claims
Provider Trust (SAML)**. AD FS stays the STS Exchange trusts; Keycloak does the real login.

## 1. AD FS base

Install and configure AD FS (`sts.corp.example`). Set the primary authentication to Forms
(needed so the modern-auth popup renders a form that then bounces to Keycloak):

```powershell
Set-AdfsGlobalAuthenticationPolicy `
  -PrimaryIntranetAuthenticationProvider FormsAuthentication `
  -PrimaryExtranetAuthenticationProvider FormsAuthentication
```

Optional - route ALL logins through Keycloak (no local AD FS credential prompt):

```powershell
Set-AdfsProperties -IntranetUseLocalClaimsProvider $false
Set-AdfsProperties -EnableLocalAuthenticationTypes $false
```

## 2. Keycloak realm

Create a realm (e.g. `corp`). Configure:

### LDAP federation to AD

Add an LDAP user federation provider pointing at a domain controller. **Set
`usernameLDAPAttribute = userPrincipalName`** (not `cn`, not `sAMAccountName`). This makes
the login identifier the UPN and the SAML `NameID` equal to the UPN, which is what the AD FS
claim rules downstream expect. After changing the attribute, remove imported users and run a
full sync.

> Gotcha: when you create realm sub-components via REST/kcadm, the `parentId` must be the
> **realm UUID** (`GET /admin/realms/corp` -> `.id`), NOT the realm name. Using the name
> orphans the component - the LDAP sync reports "0 imported" and login silently fails.

### TOTP

Set **Configure OTP** as a default required action on the realm so every user is enrolled in
TOTP on first login (or pre-provision).

### SAML client for AD FS

Create a SAML client so AD FS can delegate to Keycloak:

- Client ID: `http://sts.corp.example/adfs/services/trust`
- Name ID format: `username`
- Sign Documents: On, Sign Assertions: On
- **`saml.server.signature.keyinfo.xmlSigKeyInfoKeyNameTransformer = CERT_SUBJECT`**
  (default `KEY_ID` breaks AD FS signature validation - see troubleshooting ID4037).

Helper: [../scripts/keycloak/create-saml-client.sh](../scripts/keycloak/create-saml-client.sh).

## 3. Claims Provider Trust (AD FS -> Keycloak)

Add Keycloak as a Claims Provider Trust in AD FS using its SAML descriptor
(`https://kc.corp.example/realms/corp/protocol/saml/descriptor`).

Then configure it - see [../scripts/adfs/setup-claims-provider-trust.ps1](../scripts/adfs/setup-claims-provider-trust.ps1):

```powershell
$name = 'Keycloak-corp'

# Acceptance transform rules: keep the NameID (anchor for id_token) and emit it as UPN.
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
("key could not be resolved"), re-create the trust with the certificate supplied at add time
and restart the AD FS service (`Restart-Service adfssrv`).

## 4. Verify the chain

Browse to `https://mail.corp.example/owa` (after wiring layer 1) - you should be redirected to
AD FS, then to the Keycloak login page, get prompted for password + TOTP, and land in OWA.
