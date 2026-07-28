# 00 - Overview

## The problem

On-premises Exchange Server has no native multi-factor authentication. The supported way to
add MFA is claims-based (OWA/ECP) and OAuth 2.0 (rich clients) via **AD FS** - but AD FS has
no built-in TOTP. This build chains **Keycloak** behind AD FS as a Claims Provider Trust, so
Keycloak becomes the place where the password and the TOTP second factor are checked.

## Authentication flows

### Browser (OWA / ECP)

```
Browser -> https://mail.corp.example/owa
        -> 302 to AD FS (sts.corp.example/adfs/ls)
        -> AD FS delegates to Keycloak (SAML)
        -> Keycloak: password (LDAP to AD) + TOTP
        -> back to AD FS -> WS-Fed token -> Exchange OWA -> mailbox
```

### Rich client (Outlook desktop / EWS / MAPI / EAS / OAB)

```
Outlook -> Autodiscover finds the on-prem AuthServer (AD FS)
        -> OAuth 2.0 auth code flow, browser popup to AD FS
        -> AD FS delegates to Keycloak (SAML) -> password + TOTP
        -> AD FS issues access token (Bearer) for the Exchange resource
        -> Outlook calls MAPI/EWS with Bearer token -> mailbox
```

## Components

| Component | Role |
| --- | --- |
| Active Directory | user directory, source of truth |
| AD FS (2019+) | STS: WS-Fed for OWA/ECP, OAuth for rich clients; delegates auth to Keycloak |
| Keycloak (26.x) | external IdP behind AD FS; LDAP federation to AD; enforces TOTP |
| Exchange (2019 CU13+) | mailbox server; modern auth enabled per protocol |
| HAProxy | reverse proxy, SSL bridging, host-based routing, WAF integration |
| Coraza WAF | OWASP CRS v4 inspection on the OWA/ECP web surface |

## Why Keycloak behind AD FS (and not "just AD FS")

AD FS can do MFA adapters, but a maintained TOTP adapter is awkward to source and operate.
Keycloak is a first-class, actively maintained IdP with built-in TOTP, a good admin UI, LDAP
federation, and themeable login pages. AD FS stays as the protocol broker Exchange trusts
(WS-Fed + OAuth), and Keycloak owns the actual credential + second-factor check.

## Reading order

1. [01-prerequisites.md](01-prerequisites.md) - versions and hard requirements.
2. [02-adfs-keycloak.md](02-adfs-keycloak.md) - AD FS, Keycloak, the trust between them.
3. [03-exchange-modern-auth.md](03-exchange-modern-auth.md) - AuthServer, OAuth per protocol.
4. [04-haproxy-ssl-bridging.md](04-haproxy-ssl-bridging.md) - the reverse proxy.
5. [05-browser-owa-ecp.md](05-browser-owa-ecp.md) - layer 1.
6. [06-rich-client-outlook.md](06-rich-client-outlook.md) - layer 3.
7. [07-eas-mobile.md](07-eas-mobile.md) - mobile EAS.
8. [08-keycloak-login-theme.md](08-keycloak-login-theme.md) - login page customization.
9. [09-troubleshooting.md](09-troubleshooting.md) - every error we hit and its fix.
