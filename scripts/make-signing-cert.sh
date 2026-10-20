#!/usr/bin/env bash
# Creates a self-signed code signing identity in the login keychain, used by build-app.sh.
# A stable identity keeps macOS privacy permissions (Accessibility) valid across rebuilds;
# ad-hoc signatures change with every build, so macOS treats each build as a new app.
set -euo pipefail

NAME="${1:-Clipmorph Self-Signed}"
KEYCHAIN="$HOME/Library/Keychains/login.keychain-db"

if security find-certificate -c "$NAME" "$KEYCHAIN" >/dev/null 2>&1; then
    echo "Identity \"$NAME\" already exists."
    exit 0
fi

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

cat > "$TMP/cert.cnf" <<EOF
[req]
distinguished_name = dn
x509_extensions = ext
prompt = no
[dn]
CN = $NAME
[ext]
basicConstraints = critical, CA:false
keyUsage = critical, digitalSignature
extendedKeyUsage = critical, codeSigning
EOF

openssl req -x509 -newkey rsa:2048 -nodes -days 3650 \
    -config "$TMP/cert.cnf" -keyout "$TMP/key.pem" -out "$TMP/cert.pem" 2>/dev/null

# macOS can only import PKCS#12 files using the older SHA1/3DES algorithms.
PASS="clipmorph"
openssl pkcs12 -export -inkey "$TMP/key.pem" -in "$TMP/cert.pem" -name "$NAME" \
    -keypbe PBE-SHA1-3DES -certpbe PBE-SHA1-3DES -macalg sha1 \
    -passout "pass:$PASS" -out "$TMP/identity.p12"

security import "$TMP/identity.p12" -k "$KEYCHAIN" -P "$PASS" -T /usr/bin/codesign

echo "Created identity \"$NAME\"."
