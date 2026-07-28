# 07 - Mobile EAS (macOS / iOS Mail)

Exchange ActiveSync modern auth is supported by **iOS Mail and macOS Mail** (Outlook mobile
and Gmail fall back to Basic). The flow is the same OAuth path as desktop: the native mail
account setup opens a web login to AD FS -> Keycloak -> password + TOTP.

## Reaching an isolated Exchange from mobile

If your lab/Exchange sits on an isolated network the phone cannot reach, give HAProxy a second
interface on the reachable network and keep it as a pure L7 entry point.

### Second interface (dual-homed HAProxy)

On the hypervisor add a second vNIC on the external network. In the guest, match interfaces by
MAC and put the reachable network on DHCP **without** hijacking the default route (keep the
internal route as default):

```yaml
# netplan: internal NIC static (default route), external NIC DHCP without routes
network:
  version: 2
  ethernets:
    internal:
      match: {macaddress: "AA:BB:CC:00:00:01"}
      addresses: ["10.0.0.30/24"]
      nameservers: {addresses: [10.0.0.10], search: [corp.example]}
      dhcp4: false
      routes: [{to: "default", via: "10.0.0.1"}]
    external:
      match: {macaddress: "AA:BB:CC:00:00:02"}
      dhcp4: true
      dhcp4-overrides: {use-routes: false}
```

HAProxy already binds `*:443`, so it answers on both interfaces. No config change needed.

## On the device

1. Add hosts entries (or DNS) so `mail`, `autodiscover`, `sts`, `kc` resolve to HAProxy's
   reachable IP.
2. Install and trust your internal CA root (profile on iOS, Keychain on macOS).
3. Add an Exchange account. The web login opens AD FS -> Keycloak -> TOTP.

## Verify

- Mail syncs (inbox, send).
- EAS server readiness can be checked with a Bearer challenge:
  `curl -k -H "Authorization: Bearer x" https://mail.corp.example/Microsoft-Server-ActiveSync`
  should return a `WWW-Authenticate: Bearer authorization_uri=...` challenge pointing at AD FS.
