#!/bin/zsh

set -euo pipefail

usage() {
    cat <<'EOF'
Create a signed Sparkle update archive and appcast from an exported macOS app.

Usage:
  scripts/make-sparkle-update.sh \
    --app "./build/export/Pocket Stack.app" \
    --archives-dir "./build/sparkle-releases" \
    --download-url-prefix "$POCKET_STACK_UPDATE_BASE_URL/releases/" \
    --release-notes "./.github/RELEASE_NOTES.md"

Options:
  --generate-appcast PATH  Path to Sparkle's generate_appcast tool. If omitted,
                           the script searches Xcode DerivedData.
  --keychain-account NAME  Sparkle EdDSA Keychain account. Defaults to ed25519.
  --skip-gatekeeper-check  Skip spctl assessment for a local test build.
  --help                   Show this help.

The private EdDSA key is read by generate_appcast from macOS Login Keychain.
This script never accepts the private key as a command-line argument.

Run this command from the repository root after exporting the notarized app to
build/export/Pocket Stack.app.
EOF
}

fail() {
    echo "Error: $1" >&2
    exit 1
}

app_path=""
archives_dir=""
download_url_prefix=""
release_notes_path=""
generate_appcast_path=""
keychain_account="ed25519"
skip_gatekeeper_check=false

while [[ $# -gt 0 ]]; do
    case "$1" in
        --app)
            [[ $# -ge 2 ]] || fail "--app requires a path"
            app_path="$2"
            shift 2
            ;;
        --archives-dir)
            [[ $# -ge 2 ]] || fail "--archives-dir requires a path"
            archives_dir="$2"
            shift 2
            ;;
        --download-url-prefix)
            [[ $# -ge 2 ]] || fail "--download-url-prefix requires a URL"
            download_url_prefix="$2"
            shift 2
            ;;
        --release-notes)
            [[ $# -ge 2 ]] || fail "--release-notes requires a path"
            release_notes_path="$2"
            shift 2
            ;;
        --generate-appcast)
            [[ $# -ge 2 ]] || fail "--generate-appcast requires a path"
            generate_appcast_path="$2"
            shift 2
            ;;
        --keychain-account)
            [[ $# -ge 2 ]] || fail "--keychain-account requires a name"
            keychain_account="$2"
            shift 2
            ;;
        --skip-gatekeeper-check)
            skip_gatekeeper_check=true
            shift
            ;;
        --help|-h)
            usage
            exit 0
            ;;
        *)
            fail "unknown option: $1"
            ;;
    esac
done

[[ -d "$app_path" && "$app_path" == *.app ]] || fail "--app must point to an exported .app bundle"
[[ -n "$archives_dir" ]] || fail "--archives-dir is required"
[[ -n "$download_url_prefix" ]] || fail "--download-url-prefix is required"
[[ -f "$release_notes_path" ]] || fail "--release-notes must point to an existing Markdown file"

if [[ "$download_url_prefix" != https://* ]]; then
    fail "--download-url-prefix must use HTTPS"
fi
if [[ "$download_url_prefix" != */ ]]; then
    download_url_prefix="${download_url_prefix}/"
fi

if [[ -z "$generate_appcast_path" ]]; then
    derived_data_root="${HOME}/Library/Developer/Xcode/DerivedData"
    if [[ -d "$derived_data_root" ]]; then
        generate_appcast_path=$(
            /usr/bin/find "$derived_data_root" \
                -type f \
                -path '*/SourcePackages/artifacts/sparkle/Sparkle/bin/generate_appcast' \
                -perm -111 \
                -print \
                -quit 2>/dev/null || true
        )
    fi
fi

[[ -x "$generate_appcast_path" ]] || fail "generate_appcast was not found; pass it with --generate-appcast"

info_plist_path="${app_path}/Contents/Info.plist"
[[ -f "$info_plist_path" ]] || fail "Info.plist was not found inside the app bundle"

short_version=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$info_plist_path")
build_version=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$info_plist_path")
feed_url=$(/usr/libexec/PlistBuddy -c 'Print :SUFeedURL' "$info_plist_path" 2>/dev/null || true)
public_ed_key=$(/usr/libexec/PlistBuddy -c 'Print :SUPublicEDKey' "$info_plist_path" 2>/dev/null || true)
[[ -n "$short_version" ]] || fail "CFBundleShortVersionString is empty"
[[ -n "$build_version" ]] || fail "CFBundleVersion is empty"
[[ "$feed_url" == https://* ]] || fail "SUFeedURL must be configured with a stable HTTPS appcast URL"
[[ -n "$public_ed_key" ]] || fail "SUPublicEDKey is missing"

echo "Verifying code signature for Pocket Stack ${short_version} (${build_version})..."
/usr/bin/codesign --verify --deep --strict --verbose=2 "$app_path"

if [[ "$skip_gatekeeper_check" == false ]]; then
    echo "Verifying Developer ID and notarization with Gatekeeper..."
    /usr/sbin/spctl --assess --type execute --verbose=4 "$app_path"
fi

/bin/mkdir -p "$archives_dir"
archive_name="Pocket-Stack-${short_version}.zip"
archive_path="${archives_dir}/${archive_name}"
release_notes_name="Pocket-Stack-${short_version}.md"
release_notes_destination="${archives_dir}/${release_notes_name}"

[[ ! -e "$archive_path" ]] || fail "archive already exists: ${archive_path}"

echo "Creating ${archive_name} with symlinks and resource forks preserved..."
/usr/bin/ditto -c -k --sequesterRsrc --keepParent "$app_path" "$archive_path"
/bin/cp "$release_notes_path" "$release_notes_destination"

echo "Signing the archive and generating appcast.xml using Login Keychain..."
"$generate_appcast_path" \
    --account "$keychain_account" \
    --download-url-prefix "$download_url_prefix" \
    --embed-release-notes \
    --maximum-deltas 0 \
    -o "${archives_dir}/appcast.xml" \
    "$archives_dir"

echo
echo "Sparkle update created:"
echo "  Archive: ${archive_path}"
echo "  Appcast: ${archives_dir}/appcast.xml"
echo
echo "Upload ${archive_name} to the configured download URL, then publish"
echo "appcast.xml at the stable HTTPS URL configured as SUFeedURL."
