#!/usr/bin/env bash
# Create the SAML client in Keycloak that AD FS delegates to (Claims Provider Trust target).
#
# Prereqs: kcadm.sh on PATH, KC admin credentials in env (do NOT hardcode secrets):
#   export KC_URL=https://kc.corp.example
#   export KC_ADMIN=admin
#   export KC_ADMIN_PASSWORD=...      # provide via your secret store, not in the repo
#   export KC_REALM=corp
#   export STS_FQDN=sts.corp.example
#
# The key detail: xmlSigKeyInfoKeyNameTransformer=CERT_SUBJECT (default KEY_ID breaks AD FS
# signature validation -> ID4037).

set -euo pipefail

: "${KC_URL:?set KC_URL}"
: "${KC_ADMIN:?set KC_ADMIN}"
: "${KC_ADMIN_PASSWORD:?set KC_ADMIN_PASSWORD}"
: "${KC_REALM:?set KC_REALM}"
: "${STS_FQDN:?set STS_FQDN}"

CLIENT_ID="http://${STS_FQDN}/adfs/services/trust"

kcadm.sh config credentials --server "$KC_URL" --realm master \
    --user "$KC_ADMIN" --password "$KC_ADMIN_PASSWORD"

kcadm.sh create clients -r "$KC_REALM" -f - <<JSON
{
  "clientId": "${CLIENT_ID}",
  "protocol": "saml",
  "enabled": true,
  "frontchannelLogout": true,
  "attributes": {
    "saml.server.signature": "true",
    "saml.assertion.signature": "true",
    "saml_name_id_format": "username",
    "saml.server.signature.keyinfo.xmlSigKeyInfoKeyNameTransformer": "CERT_SUBJECT"
  },
  "redirectUris": ["https://${STS_FQDN}/adfs/ls/*"]
}
JSON

echo "SAML client '${CLIENT_ID}' created in realm '${KC_REALM}'."
echo "Now add it to AD FS as a Claims Provider Trust from:"
echo "  ${KC_URL}/realms/${KC_REALM}/protocol/saml/descriptor"
echo "Then run scripts/adfs/setup-claims-provider-trust.ps1"
