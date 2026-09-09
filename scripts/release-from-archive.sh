#!/bin/zsh

set -euo pipefail

usage() {
    cat <<'EOF'
Export, notarize, staple, package, and publish the latest Pocket Stack archive.

Usage:
  scripts/release-from-archive.sh

Options:
  --archive PATH           Use a specific .xcarchive instead of the latest
                           Pocket Stack archive in Xcode's Archives folder.
  --notary-profile NAME    notarytool Keychain profile. Defaults to
                           PocketStack-Notary.
  --tag TAG                GitHub Release tag. Defaults to v<marketing-version>.
  --archives-dir PATH      Sparkle archive history directory. Defaults to
                           ./build/sparkle-releases.
  --export-root PATH       Export directory root. Defaults to ./build/export.
  --generate-appcast PATH  Explicit path to Sparkle's generate_appcast tool.
  --keychain-account NAME  Sparkle EdDSA Keychain account. Defaults to ed25519.
  --help                   Show this help.

Release notes are always read from .github/RELEASE_NOTES.md. GitHub Actions
creates the matching draft Release after a successful build. This script adds
the signed update archive, publishes the Sparkle files to R2, and publishes the
GitHub Release.

No Apple or Sparkle private key is accepted as a command-line argument.
Apple notarization credentials and the Sparkle EdDSA key are read from Keychain.
EOF
}

fail() {
    echo "Error: $1" >&2
    exit 1
}

archive_path=""
notary_profile="PocketStack-Notary"
release_tag=""
archives_dir="./build/sparkle-releases"
export_root="./build/export"
generate_appcast_path=""
keychain_account="ed25519"
script_dir="${0:A:h}"
repo_root="${script_dir:h}"
release_notes_path="${repo_root}/.github/RELEASE_NOTES.md"
r2_bucket="pocketstack-downloads"

while [[ $# -gt 0 ]]; do
    case "$1" in
        --archive)
            [[ $# -ge 2 ]] || fail "--archive requires a path"
            archive_path="$2"
            shift 2
            ;;
        --notary-profile)
            [[ $# -ge 2 ]] || fail "--notary-profile requires a name"
            notary_profile="$2"
            shift 2
            ;;
        --tag)
            [[ $# -ge 2 ]] || fail "--tag requires a value"
            release_tag="$2"
            shift 2
            ;;
        --archives-dir)
            [[ $# -ge 2 ]] || fail "--archives-dir requires a path"
            archives_dir="$2"
            shift 2
            ;;
        --export-root)
            [[ $# -ge 2 ]] || fail "--export-root requires a path"
            export_root="$2"
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
        --help|-h)
            usage
            exit 0
            ;;
        *)
            fail "unknown option: $1"
            ;;
    esac
done

[[ -f "$release_notes_path" ]] || fail ".github/RELEASE_NOTES.md is missing"

wrangler_path=$(command -v wrangler 2>/dev/null || true)
[[ -x "$wrangler_path" ]] || fail "Wrangler was not found in PATH; install Wrangler 4 or newer"

gh_path=$(command -v gh 2>/dev/null || true)
[[ -x "$gh_path" ]] || fail "GitHub CLI was not found in PATH; install gh and authenticate it"

origin_url=$(/usr/bin/git -C "$repo_root" remote get-url origin 2>/dev/null || true)
[[ -n "$origin_url" ]] || fail "Git remote 'origin' is missing"

case "$origin_url" in
    https://github.com/*)
        github_repository="${origin_url#https://github.com/}"
        ;;
    git@github.com:*)
        github_repository="${origin_url#git@github.com:}"
        ;;
    ssh://git@github.com/*)
        github_repository="${origin_url#ssh://git@github.com/}"
        ;;
    *)
        fail "Git remote 'origin' must point to a GitHub repository"
        ;;
esac
github_repository="${github_repository%.git}"
[[ "$github_repository" == */* && "$github_repository" != */*/* ]] || fail "could not derive OWNER/REPOSITORY from Git remote 'origin'"

working_tree_status=$(/usr/bin/git -C "$repo_root" status --porcelain --untracked-files=normal)
[[ -z "$working_tree_status" ]] || fail "the Git working tree must be clean before publishing a release"

if [[ -z "$archive_path" ]]; then
    archive_candidates=("${HOME}"/Library/Developer/Xcode/Archives/*/"Pocket Stack"*.xcarchive(Nom))
    [[ ${#archive_candidates[@]} -gt 0 ]] || fail "no Pocket Stack archive was found in Xcode Archives"
    archive_path="${archive_candidates[1]}"
fi

[[ -d "$archive_path" && "$archive_path" == *.xcarchive ]] || fail "--archive must point to an .xcarchive"

archive_info_path="${archive_path}/Info.plist"
[[ -f "$archive_info_path" ]] || fail "archive Info.plist was not found"

application_path=$(/usr/libexec/PlistBuddy -c 'Print :ApplicationProperties:ApplicationPath' "$archive_info_path")
team_id=$(/usr/libexec/PlistBuddy -c 'Print :ApplicationProperties:Team' "$archive_info_path")
short_version=$(/usr/libexec/PlistBuddy -c 'Print :ApplicationProperties:CFBundleShortVersionString' "$archive_info_path")
build_version=$(/usr/libexec/PlistBuddy -c 'Print :ApplicationProperties:CFBundleVersion' "$archive_info_path")

[[ -n "$application_path" ]] || fail "the archive does not contain an application path"
[[ -n "$team_id" ]] || fail "the archive does not contain an Apple Developer Team ID"
[[ -n "$short_version" ]] || fail "the archive does not contain a marketing version"
[[ -n "$build_version" ]] || fail "the archive does not contain a build version"

release_notes_title=$(/usr/bin/sed -n '/[^[:space:]]/{p;q;}' "$release_notes_path")
[[ "$release_notes_title" == "# Pocket Stack ${short_version}" ]] \
    || fail ".github/RELEASE_NOTES.md must start with '# Pocket Stack ${short_version}'"

archived_app_path="${archive_path}/Products/${application_path}"
archived_info_path="${archived_app_path}/Contents/Info.plist"
[[ -f "$archived_info_path" ]] || fail "the archived app Info.plist was not found"

feed_url=$(/usr/libexec/PlistBuddy -c 'Print :SUFeedURL' "$archived_info_path" 2>/dev/null || true)
public_ed_key=$(/usr/libexec/PlistBuddy -c 'Print :SUPublicEDKey' "$archived_info_path" 2>/dev/null || true)
[[ "$feed_url" == https://* ]] || fail "the archived app has no HTTPS SUFeedURL; configure it and create a new archive"
[[ -n "$public_ed_key" ]] || fail "the archived app has no SUPublicEDKey"
public_base_url="${feed_url%/*}"

if [[ -z "$release_tag" ]]; then
    release_tag="v${short_version}"
fi

echo "Checking GitHub release prerequisites..."
"$gh_path" auth status --hostname github.com >/dev/null
head_revision=$(/usr/bin/git -C "$repo_root" rev-parse HEAD)
"$gh_path" api "repos/${github_repository}/commits/${head_revision}" >/dev/null
if ! release_is_draft=$("$gh_path" release view "$release_tag" \
    --repo "$github_repository" \
    --json isDraft \
    --jq .isDraft 2>/dev/null); then
    fail "GitHub Release ${release_tag} does not exist; push the version first and wait for Verify"
fi
if [[ "$release_is_draft" == "true" ]]; then
    echo "Found draft GitHub Release ${release_tag}."
else
    echo "Found published GitHub Release ${release_tag}."
fi

export_dir="${export_root}/${short_version}-${build_version}"
[[ ! -e "$export_dir" ]] || fail "export directory already exists: ${export_dir}"
/bin/mkdir -p "$export_root"

app_name=$(/usr/bin/basename "$application_path")
exported_app_path="${export_dir}/${app_name}"

accepted_submission_app=""
submission_logs=("${archive_path}"/Submissions/*/notarization-log.json(N.om))
for submission_log in "${submission_logs[@]}"; do
    submission_status=$(/usr/bin/plutil -extract status raw "$submission_log" 2>/dev/null || true)
    submission_app="${submission_log:h}/${app_name}"
    if [[ "$submission_status" == "Accepted" && -d "$submission_app" ]]; then
        accepted_submission_app="$submission_app"
        break
    fi
done

temporary_dir=$(/usr/bin/mktemp -d "/private/tmp/pocket-stack-notary.XXXXXX")
cleanup() {
    if [[ -n "${temporary_dir:-}" && "$temporary_dir" == /private/tmp/pocket-stack-notary.* && -d "$temporary_dir" ]]; then
        /bin/rm -rf -- "$temporary_dir"
    fi
}
trap cleanup EXIT

export_options_path="${temporary_dir}/ExportOptions.plist"
echo "Archive: ${archive_path}"
echo "Version: ${short_version} (${build_version})"
echo "Team: ${team_id}"

if [[ -n "$accepted_submission_app" ]]; then
    echo "Using the accepted, notarized app already stored in this Xcode archive..."
    /bin/mkdir -p "$export_dir"
    /usr/bin/ditto "$accepted_submission_app" "$exported_app_path"
else
    /usr/bin/plutil -create xml1 "$export_options_path"
    /usr/bin/plutil -insert method -string developer-id "$export_options_path"
    /usr/bin/plutil -insert destination -string export "$export_options_path"
    /usr/bin/plutil -insert signingStyle -string automatic "$export_options_path"
    /usr/bin/plutil -insert teamID -string "$team_id" "$export_options_path"

    echo "Exporting a Developer ID signed app..."
    /usr/bin/xcodebuild -exportArchive \
        -archivePath "$archive_path" \
        -exportPath "$export_dir" \
        -exportOptionsPlist "$export_options_path" \
        -allowProvisioningUpdates

    [[ -d "$exported_app_path" ]] || fail "exported app was not found at ${exported_app_path}"

    echo "Verifying the exported code signature..."
    /usr/bin/codesign --verify --deep --strict --verbose=2 "$exported_app_path"

    notarization_zip_path="${temporary_dir}/Pocket-Stack-notarization.zip"
    /usr/bin/ditto -c -k --sequesterRsrc --keepParent "$exported_app_path" "$notarization_zip_path"

    echo "Submitting the exported app to Apple's notary service..."
    notarization_result_path="${temporary_dir}/notarization-result.plist"
    /usr/bin/xcrun notarytool submit "$notarization_zip_path" \
        --keychain-profile "$notary_profile" \
        --wait \
        --timeout 1h \
        --output-format plist > "$notarization_result_path"

    notarization_status=$(/usr/bin/plutil -extract status raw "$notarization_result_path")
    if [[ "$notarization_status" != "Accepted" ]]; then
        /usr/bin/plutil -p "$notarization_result_path" >&2
        fail "Apple notarization status was ${notarization_status}"
    fi

    echo "Stapling and validating the notarization ticket..."
    /usr/bin/xcrun stapler staple "$exported_app_path"
fi

echo "Verifying the final app..."
/usr/bin/codesign --verify --deep --strict --verbose=2 "$exported_app_path"
/usr/bin/xcrun stapler validate "$exported_app_path"

download_url_prefix="${public_base_url}/releases/"
package_arguments=(
    --app "$exported_app_path"
    --archives-dir "$archives_dir"
    --download-url-prefix "$download_url_prefix"
    --release-notes "$release_notes_path"
    --keychain-account "$keychain_account"
)

if [[ -n "$generate_appcast_path" ]]; then
    package_arguments+=(--generate-appcast "$generate_appcast_path")
fi

"${script_dir}/make-sparkle-update.sh" "${package_arguments[@]}"

archive_name="Pocket-Stack-${short_version}.zip"
archive_output_path="${archives_dir}/${archive_name}"
appcast_output_path="${archives_dir}/appcast.xml"
archive_object_key="releases/${archive_name}"

[[ -f "$archive_output_path" ]] || fail "Sparkle archive was not created at ${archive_output_path}"
[[ -f "$appcast_output_path" ]] || fail "appcast.xml was not created at ${appcast_output_path}"

echo
echo "Uploading the signed archive to GitHub Release ${release_tag}..."
"$gh_path" release upload "$release_tag" "$archive_output_path" \
    --repo "$github_repository"

echo "Uploading the immutable update archive to Cloudflare R2..."
"$wrangler_path" r2 object put "${r2_bucket}/${archive_object_key}" \
    --file "$archive_output_path" \
    --content-type "application/zip" \
    --cache-control "public, max-age=31536000, immutable" \
    --remote

echo "Publishing appcast.xml to Cloudflare R2..."
"$wrangler_path" r2 object put "${r2_bucket}/appcast.xml" \
    --file "$appcast_output_path" \
    --content-type "application/rss+xml; charset=utf-8" \
    --cache-control "no-cache, no-store, must-revalidate" \
    --remote

echo "Updating and publishing GitHub Release ${release_tag}..."
"$gh_path" release edit "$release_tag" \
    --repo "$github_repository" \
    --title "Pocket Stack ${short_version}" \
    --notes-file "$release_notes_path" \
    --draft=false \
    --latest

echo
echo "Release ${release_tag} published to Cloudflare R2 and GitHub."
echo "Update: ${public_base_url}/${archive_object_key}"
echo "Appcast: ${public_base_url}/appcast.xml"
