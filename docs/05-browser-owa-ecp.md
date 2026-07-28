# 05 - Browser 2FA (OWA / ECP) + Coraza WAF

Layer 1: OWA and ECP use claims-based auth (WS-Federation) to AD FS, which delegates to
Keycloak for password + TOTP. Layer 2: Coraza WAF inspects the OWA/ECP web surface.

Script: [../scripts/exchange/configure-owa-ecp-adfs.ps1](../scripts/exchange/configure-owa-ecp-adfs.ps1),
[../scripts/adfs/add-relying-party-owa-ecp.ps1](../scripts/adfs/add-relying-party-owa-ecp.ps1).

## 1. AD FS Relying Party Trusts

Create **one RP trust per WS-Fed endpoint** - OWA and ECP are separate (one RP trust = one
passive endpoint). Issuance rules must pass the UPN and resolve the AD `primarysid` by
`DOMAIN\user`:

```powershell
$rules = @'
@RuleName = "Passthrough UPN"
c:[Type == "http://schemas.xmlsoap.org/ws/2005/05/identity/claims/upn"] => issue(claim = c);
@RuleName = "PrimarySID from AD by UPN"
c:[Type == "http://schemas.xmlsoap.org/ws/2005/05/identity/claims/upn"]
 => issue(store = "Active Directory",
    types = ("http://schemas.microsoft.com/ws/2008/06/identity/claims/primarysid"),
    query = ";objectSid;{0}",
    param = RegExReplace(c.Value, "^(.*)@corp\.example$", "CORP\$1"));
'@
$auth = '=> issue(Type = "http://schemas.microsoft.com/authorization/claims/permit", Value = "true");'

Add-AdfsRelyingPartyTrust -Name 'Exchange OWA' -Identifier 'https://mail.corp.example/owa/' `
  -WSFedEndpoint 'https://mail.corp.example/owa/' -IssuanceTransformRules $rules `
  -IssuanceAuthorizationRules $auth -Enabled $true
Add-AdfsRelyingPartyTrust -Name 'Exchange ECP' -Identifier 'https://mail.corp.example/ecp/' `
  -WSFedEndpoint 'https://mail.corp.example/ecp/' -IssuanceTransformRules $rules `
  -IssuanceAuthorizationRules $auth -Enabled $true
```

> The `RegExReplace(...)` turns the UPN into `DOMAIN\user` - the AD store query
> `;objectSid;{0}` requires that format, not the UPN (otherwise POLICY3826).

## 2. Point Exchange at AD FS

Import the AD FS token-signing certificate into the Trusted Root store on Exchange, then:

```powershell
Set-OrganizationConfig `
  -AdfsIssuer 'https://sts.corp.example/adfs/ls/' `
  -AdfsAudienceUris 'https://mail.corp.example/owa/','https://mail.corp.example/ecp/' `
  -AdfsSignCertificateThumbprint '<ADFS_TOKEN_SIGNING_THUMBPRINT>'

Get-OwaVirtualDirectory | Set-OwaVirtualDirectory -AdfsAuthentication $true `
  -BasicAuthentication $false -FormsAuthentication $false -WindowsAuthentication $false
Get-EcpVirtualDirectory | Set-EcpVirtualDirectory -AdfsAuthentication $true `
  -BasicAuthentication $false -FormsAuthentication $false -WindowsAuthentication $false
iisreset
```

## 3. Coraza WAF (layer 2)

Coraza-spoa runs in Docker on the HAProxy host (`127.0.0.1:9001`), OWASP CRS v4, in
**DetectionOnly** mode. Config templates:
[../config/coraza/coraza.cfg](../config/coraza/coraza.cfg),
[../config/coraza/coraza-spoa.yaml](../config/coraza/coraza-spoa.yaml),
[../config/coraza/docker-compose.yml](../config/coraza/docker-compose.yml).

```bash
cd /etc/haproxy/coraza && docker compose up -d
haproxy -c -f /etc/haproxy/haproxy.cfg && systemctl reload haproxy
```

WAF messages in HAProxy are scoped to `/owa` and `/ecp` only. Run DetectionOnly, collect false
positives, then flip `SecRuleEngine DetectionOnly` to `On` in coraza.cfg.

## 4. Verify

- `https://mail.corp.example/owa` redirects to AD FS -> Keycloak -> TOTP -> mailbox.
- `https://mail.corp.example/ecp` behaves the same.
- A benign LFI/XSS probe against `/owa` produces CRS detections (930/932/941, anomaly 949110)
  in the WAF log without blocking (DetectionOnly).
