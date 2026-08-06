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

if [[ -z "$build_number" ]]; then
    build_number=$(git -C "$package_root" rev-list --count HEAD 2>/dev/null || true)
    build_number=${build_number:-1}
fi

swift build \
    --package-path "$package_root" \
    --configuration "$configuration" \
    --product MacMerge
bin_dir=$(swift build \
    --package-path "$package_root" \
    --configuration "$configuration" \
    --show-bin-path)

rm -rf "$app_bundle"
mkdir -p "$executable_dir" "$resources_dir"
cp "$bin_dir/MacMerge" "$executable_dir/MacMerge"
cp "$package_root/Packaging/Info.plist" "$plist"
"$package_root/Scripts/generate-icon.sh" "$resources_dir"
chmod 755 "$executable_dir/MacMerge"

plist_buddy=/usr/libexec/PlistBuddy
"$plist_buddy" -c "Set :CFBundleIdentifier $bundle_identifier" "$plist"
"$plist_buddy" -c "Set :CFBundleShortVersionString $marketing_version" "$plist"
"$plist_buddy" -c "Set :CFBundleVersion $build_number" "$plist"
plutil -lint "$plist"

if [[ -n "$sign_identity" ]]; then
    if [[ "$sign_identity" == "-" ]]; then
        codesign --force --sign - "$app_bundle"
    else
        codesign --force --options runtime --timestamp --sign "$sign_identity" "$app_bundle"
    fi
    codesign --verify --deep --strict --verbose=2 "$app_bundle"
fi

echo "$app_bundle"
