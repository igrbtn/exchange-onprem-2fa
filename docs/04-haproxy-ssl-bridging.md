# 04 - HAProxy (SSL bridging)

HAProxy terminates TLS with the multi-SAN certificate, routes by Host header to Exchange /
AD FS / Keycloak, and re-encrypts to each backend. L7 mode is what makes the WAF and the
`/common/sso/*` fix possible.

Full config: [../config/haproxy/haproxy.cfg](../config/haproxy/haproxy.cfg).

## Certificate

Build a PEM (cert chain + private key) for HAProxy from your multi-SAN certificate:

```bash
openssl pkcs12 -in haproxy.pfx -nodes -out /etc/haproxy/certs/lab.pem
chmod 600 /etc/haproxy/certs/lab.pem
```

SAN must cover `mail`, `autodiscover`, `sts`, `kc`, `owa`, `ecp` under your domain.

## Routing

- `Host: sts.corp.example` -> AD FS backend (re-encrypt, SNI `sts.corp.example`).
- `Host: kc.corp.example` -> Keycloak backend (`:8080`, add `X-Forwarded-Host`).
- everything else -> Exchange backend (re-encrypt, SNI `mail.corp.example`).

Backends need `sni str(...)` and `check-sni` - AD FS and Exchange http.sys require SNI or
they answer HTTP 400 "Invalid Hostname".

## The `/common/sso/*` fix (remove the 404 flash)

After a successful rich-client login the MSAL/WAM broker navigates to
`sts.corp.example/common/sso/final` - an Azure-AD endpoint AD FS does not have, so IIS returns
404, which flashes in the Outlook popup. The broker only reads the auth code from the URL, so
authentication is not affected; return a blank 200 to hide the flash:

```
http-request return status 200 content-type "text/html" string "<!doctype html><title>ok</title>" \
    if { hdr(host) -i sts.corp.example } { path_beg /common/sso/ }
```

## Coraza WAF hook

The config wires the Coraza SPOE filter and deny rules. The WAF runs DetectionOnly first; see
[05-browser-owa-ecp.md](05-browser-owa-ecp.md) and
[../config/coraza/](../config/coraza/). WAF inspection is scoped to `/owa` and `/ecp` only -
do not inspect the binary MAPI/EAS streams (flood of false positives).

## Validate and reload

```bash
haproxy -c -f /etc/haproxy/haproxy.cfg && systemctl reload haproxy
```

Always validate before reload. Stats page on `:9000/stats`.
