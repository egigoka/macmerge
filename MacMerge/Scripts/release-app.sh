#!/bin/bash

set -euo pipefail

package_root=$(cd "$(dirname "$0")/.." && pwd)
output_dir=${OUTPUT_DIR:-"$package_root/dist"}
sign_identity=${SIGN_IDENTITY:-}
notarytool_profile=${NOTARYTOOL_PROFILE:-}
marketing_version=${MARKETING_VERSION:-0.1.0}
archive="$output_dir/MacMerge-$marketing_version.zip"
app_bundle="$output_dir/MacMerge.app"

if [[ -z "$sign_identity" || "$sign_identity" == "-" ]]; then
    echo "SIGN_IDENTITY must name a Developer ID Application certificate" >&2
    exit 2
fi
if [[ -z "$notarytool_profile" ]]; then
    echo "NOTARYTOOL_PROFILE must name a notarytool Keychain profile" >&2
    exit 2
fi
if ! security find-identity -v -p codesigning | grep -Fq "\"$sign_identity\""; then
    echo "Code-signing identity not found: $sign_identity" >&2
    exit 2
fi

SIGN_IDENTITY="$sign_identity" \
MARKETING_VERSION="$marketing_version" \
OUTPUT_DIR="$output_dir" \
    "$package_root/Scripts/package-app.sh"

codesign --verify --deep --strict --verbose=2 "$app_bundle"
codesign --display --verbose=4 "$app_bundle" 2>&1 | grep -q "Runtime Version"

rm -f "$archive"
ditto -c -k --sequesterRsrc --keepParent "$app_bundle" "$archive"
xcrun notarytool submit "$archive" --keychain-profile "$notarytool_profile" --wait
xcrun stapler staple "$app_bundle"
xcrun stapler validate "$app_bundle"
spctl --assess --type execute --verbose=2 "$app_bundle"

# Recreate the distributable so its app contains the stapled ticket.
rm -f "$archive"
ditto -c -k --sequesterRsrc --keepParent "$app_bundle" "$archive"
shasum -a 256 "$archive" > "$archive.sha256"

echo "$archive"
