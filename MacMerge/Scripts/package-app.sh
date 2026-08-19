#!/bin/bash

set -euo pipefail

package_root=$(cd "$(dirname "$0")/.." && pwd)
configuration=${CONFIGURATION:-release}
output_dir=${OUTPUT_DIR:-"$package_root/dist"}
app_bundle="$output_dir/MacMerge.app"
contents="$app_bundle/Contents"
executable_dir="$contents/MacOS"
resources_dir="$contents/Resources"
plist="$contents/Info.plist"
bundle_identifier=${BUNDLE_IDENTIFIER:-io.github.egigoka.MacMerge}
marketing_version=${MARKETING_VERSION:-0.1.0}
build_number=${BUILD_NUMBER:-}
sign_identity=${SIGN_IDENTITY:--}
entitlements=${ENTITLEMENTS:-"$package_root/Packaging/MacMerge.entitlements"}
swift_scratch_args=()
if [[ -n "${SWIFT_SCRATCH_PATH:-}" ]]; then
    swift_scratch_args=(--scratch-path "$SWIFT_SCRATCH_PATH")
fi

if [[ -z "$build_number" ]]; then
    build_number=$(git -C "$package_root" rev-list --count HEAD 2>/dev/null || true)
    build_number=${build_number:-1}
fi

swift build \
    --package-path "$package_root" \
    --configuration "$configuration" \
    ${swift_scratch_args[@]+"${swift_scratch_args[@]}"} \
    --product MacMerge
bin_dir=$(swift build \
    --package-path "$package_root" \
    --configuration "$configuration" \
    ${swift_scratch_args[@]+"${swift_scratch_args[@]}"} \
    --show-bin-path)

rm -rf "$app_bundle"
mkdir -p "$executable_dir" "$resources_dir"
cp "$bin_dir/MacMerge" "$executable_dir/MacMerge"
cp "$package_root/Packaging/Info.plist" "$plist"
cp "$package_root/Packaging/PrivacyInfo.xcprivacy" "$resources_dir/PrivacyInfo.xcprivacy"
"$package_root/Scripts/generate-icon.sh" "$resources_dir"
chmod 755 "$executable_dir/MacMerge"

plist_buddy=/usr/libexec/PlistBuddy
"$plist_buddy" -c "Set :CFBundleIdentifier $bundle_identifier" "$plist"
"$plist_buddy" -c "Set :CFBundleShortVersionString $marketing_version" "$plist"
"$plist_buddy" -c "Set :CFBundleVersion $build_number" "$plist"
plutil -lint "$plist"
plutil -lint "$entitlements"
plutil -lint "$resources_dir/PrivacyInfo.xcprivacy"
privacy_manifest_json=$(plutil -convert json -o - "$resources_dir/PrivacyInfo.xcprivacy")
for required_privacy_value in \
    '"NSPrivacyTracking":false' \
    '"NSPrivacyCollectedDataTypes":[]'; do
    if [[ "$privacy_manifest_json" != *"$required_privacy_value"* ]]; then
        echo "Privacy manifest is missing required value: $required_privacy_value" >&2
        exit 1
    fi
done
verify_privacy_reason() {
    local expected_category=$1
    local expected_reason=$2
    local index category reason
    for index in 0 1; do
        category=$($plist_buddy -c "Print :NSPrivacyAccessedAPITypes:$index:NSPrivacyAccessedAPIType" \
            "$resources_dir/PrivacyInfo.xcprivacy" 2>/dev/null || true)
        reason=$($plist_buddy -c "Print :NSPrivacyAccessedAPITypes:$index:NSPrivacyAccessedAPITypeReasons:0" \
            "$resources_dir/PrivacyInfo.xcprivacy" 2>/dev/null || true)
        if [[ "$category" == "$expected_category" && "$reason" == "$expected_reason" ]]; then
            return
        fi
    done
    echo "Privacy manifest is missing $expected_reason for $expected_category" >&2
    exit 1
}
verify_privacy_reason NSPrivacyAccessedAPICategoryUserDefaults CA92.1
verify_privacy_reason NSPrivacyAccessedAPICategoryFileTimestamp 3B52.1

if [[ -n "$sign_identity" ]]; then
    if [[ "$sign_identity" == "-" ]]; then
        codesign --force --sign - --entitlements "$entitlements" "$app_bundle"
    else
        codesign --force --options runtime --timestamp --sign "$sign_identity" \
            --entitlements "$entitlements" "$app_bundle"
    fi
    codesign --verify --deep --strict --verbose=2 "$app_bundle"
    signed_entitlements=$(codesign --display --entitlements - --xml "$app_bundle" 2>/dev/null)
    signed_entitlements_json=$(plutil -convert json -o - - <<<"$signed_entitlements")
    for entitlement in \
        com.apple.security.app-sandbox \
        com.apple.security.files.bookmarks.app-scope \
        com.apple.security.files.user-selected.read-write; do
        if [[ "$signed_entitlements_json" != *"\"$entitlement\":true"* ]]; then
            echo "Signed application entitlement is not enabled: $entitlement" >&2
            exit 1
        fi
    done
fi

echo "$app_bundle"
