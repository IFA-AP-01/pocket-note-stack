#!/bin/bash

# Preflight checks for release configuration
set -e

echo "Running preflight checks..."

# Check for required secrets
if [ -z "$SPARKLE_ED_PRIVATE_KEY" ]; then
    echo "Error: SPARKLE_ED_PRIVATE_KEY is not set"
    exit 1
fi

if [ -z "$APPLE_DEVELOPER_ID_CERTIFICATE" ]; then
    echo "Error: APPLE_DEVELOPER_ID_CERTIFICATE is not set"
    exit 1
fi

if [ -z "$APPLE_DEVELOPER_ID_CERTIFICATE_PASSWORD" ]; then
    echo "Error: APPLE_DEVELOPER_ID_CERTIFICATE_PASSWORD is not set"
    exit 1
fi

if [ -z "$APPLE_NOTARIZATION_KEY" ]; then
    echo "Error: APPLE_NOTARIZATION_KEY is not set"
    exit 1
fi

if [ -z "$APPLE_NOTARIZATION_ISSUER_ID" ]; then
    echo "Error: APPLE_NOTARIZATION_ISSUER_ID is not set"
    exit 1
fi

if [ -z "$APPLE_NOTARIZATION_KEY_ID" ]; then
    echo "Error: APPLE_NOTARIZATION_KEY_ID is not set"
    exit 1
fi

# Check for required Info.plist keys
INFOPLIST_PATH="Pocket Stack/Info.plist"
if [ ! -f "$INFOPLIST_PATH" ]; then
    echo "Error: Info.plist not found at $INFOPLIST_PATH"
    exit 1
fi

# Check for required entitlements
ENTITLEMENTS_PATH="Pocket Stack/Pocket Stack.entitlements"
if [ ! -f "$ENTITLEMENTS_PATH" ]; then
    echo "Error: Entitlements not found at $ENTITLEMENTS_PATH"
    exit 1
fi

# Check for Sparkle mach-lookup exceptions
if ! grep -q "com.ifateam.Pocket-Stack-spks" "$ENTITLEMENTS_PATH"; then
    echo "Error: Sparkle mach-lookup exception not found in entitlements"
    exit 1
fi

if ! grep -q "com.ifateam.Pocket-Stack-spki" "$ENTITLEMENTS_PATH"; then
    echo "Error: Sparkle mach-lookup exception not found in entitlements"
    exit 1
fi

echo "Preflight checks passed!"
