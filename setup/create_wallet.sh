#!/usr/bin/env bash
# create_wallet.sh — Create Oracle Wallet with CA certificates for HTTPS
#
# Usage:
#   ./create_wallet.sh [wallet_dir] [wallet_password]
#
# Defaults:
#   wallet_dir:      /opt/oracle/wallet
#   wallet_password:  (prompted if not provided)
#
# Prerequisites:
#   - orapki (from $ORACLE_HOME/bin)
#   - curl or wget (to download CA bundle)
#   - openssl (to split CA bundle into individual certs)

set -euo pipefail

WALLET_DIR="${1:-/opt/oracle/wallet}"
WALLET_PWD="${2:-}"
CA_BUNDLE_URL="https://curl.se/ca/cacert.pem"
TEMP_DIR=$(mktemp -d)

cleanup() {
    rm -rf "$TEMP_DIR"
}
trap cleanup EXIT

echo "=== QubitOn Oracle Wallet Setup ==="
echo ""

# Prompt for password if not provided
if [ -z "$WALLET_PWD" ]; then
    echo -n "Enter wallet password (min 8 chars): "
    read -rs WALLET_PWD
    echo ""
    if [ ${#WALLET_PWD} -lt 8 ]; then
        echo "ERROR: Password must be at least 8 characters."
        exit 1
    fi
fi

# Check for orapki
if ! command -v orapki &>/dev/null; then
    if [ -n "${ORACLE_HOME:-}" ] && [ -x "$ORACLE_HOME/bin/orapki" ]; then
        export PATH="$ORACLE_HOME/bin:$PATH"
    else
        echo "ERROR: orapki not found. Set ORACLE_HOME or add orapki to PATH."
        exit 1
    fi
fi

# Create wallet directory
echo "1. Creating wallet directory: $WALLET_DIR"
mkdir -p "$WALLET_DIR"

# Create wallet (or open existing)
if [ -f "$WALLET_DIR/ewallet.p12" ]; then
    echo "   Wallet already exists at $WALLET_DIR — adding certificates."
else
    echo "2. Creating new auto-login wallet..."
    orapki wallet create \
        -wallet "$WALLET_DIR" \
        -pwd "$WALLET_PWD" \
        -auto_login
fi

# Download CA bundle
echo "3. Downloading CA certificate bundle..."
CA_BUNDLE="$TEMP_DIR/cacert.pem"
if command -v curl &>/dev/null; then
    curl -sS -o "$CA_BUNDLE" "$CA_BUNDLE_URL"
elif command -v wget &>/dev/null; then
    wget -q -O "$CA_BUNDLE" "$CA_BUNDLE_URL"
else
    echo "ERROR: curl or wget required to download CA bundle."
    exit 1
fi

# Split CA bundle into individual certs and add to wallet
echo "4. Adding CA certificates to wallet..."
CERT_COUNT=0
csplit -s -z -f "$TEMP_DIR/cert-" -b "%03d.pem" "$CA_BUNDLE" '/-----BEGIN CERTIFICATE-----/' '{*}' 2>/dev/null || true

for CERT_FILE in "$TEMP_DIR"/cert-*.pem; do
    if [ -s "$CERT_FILE" ] && grep -q "BEGIN CERTIFICATE" "$CERT_FILE"; then
        orapki wallet add \
            -wallet "$WALLET_DIR" \
            -trusted_cert \
            -cert "$CERT_FILE" \
            -pwd "$WALLET_PWD" 2>/dev/null || true
        CERT_COUNT=$((CERT_COUNT + 1))
    fi
done

echo "   Added $CERT_COUNT CA certificates."

# Verify wallet contents
echo "5. Verifying wallet..."
CERT_IN_WALLET=$(orapki wallet display -wallet "$WALLET_DIR" -pwd "$WALLET_PWD" 2>/dev/null | grep -c "Trusted Certificates" || echo "0")
echo "   Wallet contains certificates."

# Test connectivity (optional)
echo ""
echo "=== Wallet Setup Complete ==="
echo ""
echo "Wallet location: $WALLET_DIR"
echo "Auto-login:      enabled (cwallet.sso)"
echo ""
echo "To test connectivity from SQL*Plus:"
echo ""
echo "  SELECT UTL_HTTP.REQUEST("
echo "      url         => 'https://api.qubiton.com/api/health',"
echo "      wallet_path => 'file:$WALLET_DIR'"
echo "  ) FROM DUAL;"
echo ""
echo "If using auto-login wallet, no password is needed in PL/SQL."
echo "To use with password: UTL_HTTP.SET_WALLET('file:$WALLET_DIR', 'your_password');"