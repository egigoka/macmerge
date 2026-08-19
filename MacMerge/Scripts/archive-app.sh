#!/bin/bash

set -euo pipefail
PATH=/usr/bin:/bin:/usr/sbin:/sbin
export PATH

usage() {
    cat <<'EOF'
Usage: archive-app.sh [--check] [--help]

Create a Developer ID-signed MacMerge.xcarchive through Xcode.

Environment:
  OUTPUT_DIR         Archive parent directory (default: <package>/dist)
  ARCHIVE_PATH       Archive path (default: <output>/MacMerge.xcarchive)
  CONFIGURATION      Xcode configuration (default: Release)
  SCHEME             Shared/Xcode-generated scheme (default: MacMerge)
  SIGN_IDENTITY      Required Developer ID Application identity or SHA-1 hash
  DEVELOPMENT_TEAM   Optional signing team override
  ENTITLEMENTS       Sandbox entitlements plist
                     (default: <package>/Packaging/MacMerge.entitlements)

Options:
  --check            Validate tools, package, scheme, archive support,
                     entitlements, and signing input without archiving
  -h, --help         Show this help

This script never performs ad-hoc signing. It fails when Xcode cannot archive
the Swift package scheme as a macOS application. Add an Xcode app target/shared
scheme (or supported SwiftPM app-product metadata) before retrying; it does not
fall back to assembling an app bundle by hand.
EOF
}

die() {
    printf 'archive-app.sh: %s\n' "$*" >&2
    exit 2
}

require_command() {
    command -v "$1" >/dev/null 2>&1 || die "required tool not found: $1"
}

plist_extract() {
    local key_path=$1
    local type=$2
    local file=$3

    plutil -extract "$key_path" raw -expect "$type" -o - "$file" 2>/dev/null
}

validate_entitlements() {
    local file=$1
    local keys
    local entitlement

    plutil -lint "$file" >/dev/null || die "invalid entitlements plist: $file"
    keys=$(plutil -convert json -o - "$file" 2>/dev/null | \
        ruby -rjson -e '
            value = JSON.parse(STDIN.read)
            abort unless value.is_a?(Hash)
            puts value.keys.sort
        ' 2>/dev/null) || die "entitlements plist must contain a dictionary: $file"
    [[ "$keys" == $'com.apple.security.app-sandbox\ncom.apple.security.files.bookmarks.app-scope\ncom.apple.security.files.user-selected.read-write' ]] || \
        die "entitlements must contain exactly the approved sandbox keys: $file"

    for entitlement in \
        com.apple.security.app-sandbox \
        com.apple.security.files.bookmarks.app-scope \
        com.apple.security.files.user-selected.read-write; do
        [[ "$(plist_extract "${entitlement//./\\.}" bool "$file" || true)" == "true" ]] || \
            die "required Boolean entitlement is not enabled: $entitlement"
    done
}

json_array_count() {
    local file=$1

    plutil -convert json -o - "$file" 2>/dev/null | ruby -rjson -e '
        value = JSON.parse(STDIN.read)
        abort unless value.is_a?(Array)
        puts value.length
    ' 2>/dev/null
}

validate_developer_id_code() {
    local code=$1
    local architecture=$2
    local label=$3
    local signature
    local team
    local requirement

    requirement="anchor apple generic and certificate leaf[field.1.2.840.113635.100.6.1.13] exists and certificate leaf = H\"$identity_hash\""
    codesign --verify --strict --all-architectures "$code" >/dev/null 2>&1 || \
        die "$label has an invalid code signature: $code"
    codesign --verify --strict --architecture "$architecture" -R="$requirement" "$code" >/dev/null 2>&1 || \
        die "$label architecture '$architecture' is not signed by the selected Apple Developer ID Application certificate: $code"
    signature=$(codesign --display --architecture "$architecture" --verbose=4 "$code" 2>&1) || \
        die "could not read $label signature for architecture '$architecture': $code"
    [[ "$signature" == *"Runtime Version="* ]] || \
        die "$label architecture '$architecture' does not enable hardened runtime: $code"
    [[ "$signature" == *"Timestamp="* ]] || \
        die "$label architecture '$architecture' does not have a secure timestamp: $code"
    team=$(printf '%s\n' "$signature" | awk -F= '$1 == "TeamIdentifier" { print $2; exit }')
    [[ "$team" == "$identity_team" ]] || \
        die "$label architecture '$architecture' team '$team' does not match selected certificate team '$identity_team': $code"
}

canonical_path() {
    ruby -e 'print File.realpath(ARGV.fetch(0))' "$1" 2>/dev/null
}

validate_contained_path() {
    local root=$1
    local path=$2
    local label=$3
    local canonical

    canonical=$(canonical_path "$path") || die "$label is missing, broken, or inaccessible: $path"
    case "$canonical" in
        "$root"|"$root"/*) printf '%s\n' "$canonical" ;;
        *) die "$label escapes its containing bundle: $path" ;;
    esac
}

validate_bundle_executable_name() {
    local name=$1
    local bundle=$2

    [[ -n "$name" && "$name" != "." && "$name" != ".." && "$name" != */* ]] || \
        die "nested code bundle CFBundleExecutable is unsafe: $bundle"
}

validate_executable_mode() {
    local path=$1
    local label=$2

    ruby -e 'exit((File.stat(ARGV.fetch(0)).mode & 0111).zero? ? 1 : 0)' "$path" 2>/dev/null || \
        die "$label has no POSIX execute permission: $path"
}

[[ $# -le 1 ]] || die "too many arguments"
check=false
case ${1:-} in
    "") ;;
    --check) check=true ;;
    -h|--help)
        usage
        exit 0
        ;;
    *)
        usage >&2
        die "unknown argument: $1"
        ;;
esac

package_root=$(cd "$(dirname "$0")/.." && pwd)
output_dir=${OUTPUT_DIR:-"$package_root/dist"}
archive_path=${ARCHIVE_PATH:-"$output_dir/MacMerge.xcarchive"}
configuration=${CONFIGURATION:-Release}
scheme=${SCHEME:-MacMerge}
sign_identity=${SIGN_IDENTITY:-}
development_team=${DEVELOPMENT_TEAM:-}
entitlements=${ENTITLEMENTS:-"$package_root/Packaging/MacMerge.entitlements"}
destination=${DESTINATION:-generic/platform=macOS}
package_manifest="$package_root/Package.swift"

[[ "$output_dir" == /* ]] || output_dir="$PWD/$output_dir"
[[ "$archive_path" == /* ]] || archive_path="$PWD/$archive_path"
[[ "$entitlements" == /* ]] || entitlements="$PWD/$entitlements"

[[ "$OSTYPE" == darwin* ]] || die "Xcode archives require macOS"
[[ -n "$output_dir" ]] || die "OUTPUT_DIR must not be empty"
[[ -n "$archive_path" ]] || die "ARCHIVE_PATH must not be empty"
[[ "$archive_path" == *.xcarchive ]] || die "ARCHIVE_PATH must end in .xcarchive"
[[ -n "$configuration" ]] || die "CONFIGURATION must not be empty"
[[ -n "$scheme" ]] || die "SCHEME must not be empty"
[[ -f "$package_manifest" ]] || die "Swift package manifest not found: $package_manifest"
[[ -f "$entitlements" ]] || die "entitlements file not found: $entitlements"
[[ -n "$sign_identity" ]] || die "SIGN_IDENTITY must name a Developer ID Application certificate"
[[ "$sign_identity" != "-" ]] || die "ad-hoc signing is forbidden; provide a Developer ID Application identity"
[[ -z "$development_team" || "$development_team" =~ ^[[:alnum:]]{10}$ ]] || \
    die "DEVELOPMENT_TEAM must be a 10-character team identifier"
cd "$package_root"

require_command xcodebuild
require_command xcrun
require_command security
require_command codesign
require_command plutil
require_command mktemp
require_command ruby
require_command shasum
require_command openssl
require_command find
require_command file

validate_entitlements "$entitlements"

package_description=$(mktemp "${TMPDIR:-/tmp}/macmerge-package.XXXXXX")
scheme_list=$(mktemp "${TMPDIR:-/tmp}/macmerge-schemes.XXXXXX")
build_settings=$(mktemp "${TMPDIR:-/tmp}/macmerge-build-settings.XXXXXX")
archive_applications=$(mktemp "${TMPDIR:-/tmp}/macmerge-applications.XXXXXX")
signed_entitlements=$(mktemp "${TMPDIR:-/tmp}/macmerge-entitlements.XXXXXX")
certificate=$(mktemp "${TMPDIR:-/tmp}/macmerge-certificate.XXXXXX")
identity_probe=$(mktemp "${TMPDIR:-/tmp}/macmerge-identity-probe.XXXXXX")
archive_files=$(mktemp "${TMPDIR:-/tmp}/macmerge-archive-files.XXXXXX")
archive_links=$(mktemp "${TMPDIR:-/tmp}/macmerge-archive-links.XXXXXX")
archive_bundles=$(mktemp "${TMPDIR:-/tmp}/macmerge-archive-bundles.XXXXXX")
archive_lock=
cleanup() {
    rm -f "$package_description" "$scheme_list" "$build_settings" "$archive_applications" \
        "$signed_entitlements" "$certificate" "$identity_probe" "$archive_files" \
        "$archive_links" "$archive_bundles"
    if [[ -n "$archive_lock" && -f "$archive_lock/owner" && \
        "$(cat "$archive_lock/owner" 2>/dev/null || true)" == "$$" ]]; then
        rm -f "$archive_lock/owner"
        rmdir "$archive_lock" 2>/dev/null || true
    fi
}
trap cleanup EXIT

xcrun swift package --package-path "$package_root" describe --type json >"$package_description" || \
    die "Swift package description failed"
package_name=$(plist_extract name string "$package_description" || true)
[[ "$package_name" == "MacMerge" ]] || die "expected Swift package named MacMerge, found: ${package_name:-unknown}"
product_count=$(plist_extract products array "$package_description" || true)
[[ "$product_count" =~ ^[1-9][0-9]*$ ]] || die "Package.swift exposes no products"
product_found=false
for ((index = 0; index < product_count; index++)); do
    product_name=$(plist_extract "products.$index.name" string "$package_description" || true)
    product_type=$(plutil -extract "products.$index.type" json -o - "$package_description" 2>/dev/null || true)
    if [[ "$product_name" == "MacMerge" && "$product_type" == *'"executable"'* ]]; then
        product_found=true
        break
    fi
done
[[ "$product_found" == true ]] || die "Package.swift must expose the MacMerge executable product"

xcode_container=()
scheme_root=
shopt -s nullglob
workspaces=("$package_root"/*.xcworkspace)
projects=("$package_root"/*.xcodeproj)
shopt -u nullglob
if (( ${#workspaces[@]} == 1 )); then
    xcode_container=(-workspace "${workspaces[0]}")
    scheme_root=workspace
elif (( ${#workspaces[@]} > 1 )); then
    die "multiple Xcode workspaces found; archive container is ambiguous"
elif (( ${#projects[@]} == 1 )); then
    xcode_container=(-project "${projects[0]}")
    scheme_root=project
elif (( ${#projects[@]} > 1 )); then
    die "multiple Xcode projects found; archive container is ambiguous"
fi

if ! xcodebuild ${xcode_container[@]+"${xcode_container[@]}"} -list -json >"$scheme_list"; then
    die "Xcode could not load the package, project, or workspace"
fi
if [[ -z "$scheme_root" ]]; then
    if plist_extract package.schemes array "$scheme_list" >/dev/null 2>&1; then
        scheme_root=package
    elif plist_extract workspace.schemes array "$scheme_list" >/dev/null 2>&1; then
        scheme_root=workspace
    elif plist_extract project.schemes array "$scheme_list" >/dev/null 2>&1; then
        scheme_root=project
    else
        die "Xcode did not report package schemes"
    fi
fi
scheme_count=$(plist_extract "$scheme_root.schemes" array "$scheme_list" || true)
[[ "$scheme_count" =~ ^[0-9]+$ ]] || die "Xcode did not report $scheme_root schemes"
scheme_found=false
for ((index = 0; index < scheme_count; index++)); do
    candidate=$(plist_extract "$scheme_root.schemes.$index" string "$scheme_list" || true)
    if [[ "$candidate" == "$scheme" ]]; then
        scheme_found=true
        break
    fi
done
[[ "$scheme_found" == true ]] || die "Xcode scheme not found: $scheme"

if ! xcodebuild \
    ${xcode_container[@]+"${xcode_container[@]}"} \
    -scheme "$scheme" \
    -configuration "$configuration" \
    -destination "$destination" \
    -showBuildSettings \
    -json \
    CODE_SIGNING_ALLOWED=NO \
    archive >"$build_settings"; then
    die "Xcode could not resolve Archive-action build settings for scheme '$scheme'"
fi
preflight_settings_count=$(json_array_count "$build_settings" || true)
if [[ ! "$preflight_settings_count" =~ ^[1-9][0-9]*$ ]]; then
    die "Xcode scheme '$scheme' has no archivable macOS build target. Add an Xcode application target with a shared archive-enabled scheme, or SwiftPM app-product metadata supported by installed Xcode."
fi
preflight_app_found=false
for ((index = 0; index < preflight_settings_count; index++)); do
    candidate_product=$(plist_extract "$index.buildSettings.PRODUCT_NAME" string "$build_settings" || true)
    candidate_type=$(plist_extract "$index.buildSettings.PRODUCT_TYPE" string "$build_settings" || true)
    if [[ "$candidate_product" == "MacMerge" && "$candidate_type" == "com.apple.product-type.application" ]]; then
        preflight_app_found=true
        break
    fi
done
[[ "$preflight_app_found" == true ]] || die \
    "Xcode scheme '$scheme' does not archive MacMerge as an application. SwiftPM executable-only archives are unsupported; add an Xcode application target/shared scheme."

identity_output=$(security find-identity -v -p codesigning 2>&1) || \
    die "could not query code-signing identities"
normalized_identity=${sign_identity^^}
identity_matches=$(printf '%s\n' "$identity_output" | awk -v identity="$sign_identity" -v normalized="$normalized_identity" '
    $2 ~ /^[[:xdigit:]]{40}$/ && index($0, "\"Developer ID Application:") {
        hash = toupper($2)
        start = index($0, "\"")
        name = substr($0, start + 1)
        sub(/\"[^\"]*$/, "", name)
        if ((normalized ~ /^[[:xdigit:]]{40}$/ && hash == normalized) || name == identity) {
            print hash
        }
    }
' | sort -u)
identity_match_count=$(printf '%s\n' "$identity_matches" | awk 'NF { count++ } END { print count + 0 }')
if (( identity_match_count == 0 )); then
    die "valid Developer ID Application identity not found: $sign_identity"
elif (( identity_match_count > 1 )); then
    die "Developer ID Application identity is ambiguous; set SIGN_IDENTITY to an exact SHA-1 hash"
fi
identity_hash=$identity_matches
[[ "$identity_hash" =~ ^[[:xdigit:]]{40}$ ]] || die "could not resolve signing identity hash"
identity_name=$(printf '%s\n' "$identity_output" | awk -v hash="$identity_hash" '
    toupper($2) == hash {
        line = $0
        sub(/^[^"]*"/, "", line)
        sub(/"[^"]*$/, "", line)
        print line
        exit
    }
')
[[ "$identity_name" == "Developer ID Application:"* ]] || die "could not resolve signing identity name"

security find-certificate -a -c "Developer ID Application:" -p | ruby -rbase64 -rdigest/sha1 -e '
    wanted = ARGV.fetch(0)
    certificates = STDIN.read.scan(/-----BEGIN CERTIFICATE-----.*?-----END CERTIFICATE-----/m)
    matches = certificates.select do |certificate|
        der = Base64.decode64(certificate.lines.reject { |line| line.start_with?("-----") }.join)
        Digest::SHA1.hexdigest(der).upcase == wanted
    end.uniq
    abort unless matches.length == 1
    print matches.first
' "$identity_hash" >"$certificate" 2>/dev/null || die "could not load selected signing certificate"
certificate_text=$(security verify-cert -q -L -p codeSign -c "$certificate" >/dev/null 2>&1 && \
    openssl x509 -in "$certificate" -noout -text -subject 2>/dev/null || true)
[[ -n "$certificate_text" ]] || die "selected signing certificate is not trusted for Apple code signing"
printf '%s\n' "$certificate_text" | grep -Eq '1\.2\.840\.113635\.100\.6\.1\.13([^0-9]|$)' || \
    die "selected certificate lacks Developer ID Application certificate OID"
identity_team=$(printf '%s\n' "$certificate_text" | awk '
    /^subject=/ {
        if (match($0, /OU[[:space:]]*=[[:space:]]*[[:alnum:]]{10}/) ||
            match($0, /\/OU=[[:alnum:]]{10}/)) {
            team = substr($0, RSTART, RLENGTH)
            sub(/^\//, "", team)
            sub(/^OU[[:space:]]*=[[:space:]]*/, "", team)
            print team
            exit
        }
    }
')
[[ "$identity_team" =~ ^[[:alnum:]]{10}$ ]] || die "could not resolve selected certificate team identifier"
[[ -z "$development_team" || "$development_team" == "$identity_team" ]] || \
    die "DEVELOPMENT_TEAM '$development_team' does not match selected certificate team '$identity_team'"
development_team=$identity_team
/bin/cp /usr/bin/true "$identity_probe" || die "could not create signing identity probe"
codesign --force --sign "$identity_hash" --options runtime --timestamp=none "$identity_probe" >/dev/null 2>&1 || \
    die "selected signing identity could not sign code"
codesign --verify --strict --all-architectures \
    -R="anchor apple generic and certificate leaf[field.1.2.840.113635.100.6.1.13] exists and certificate leaf = H\"$identity_hash\"" \
    "$identity_probe" >/dev/null 2>&1 || die "selected signing identity is not Apple Developer ID Application"

build_overrides=(
    CODE_SIGN_STYLE=Manual
    CODE_SIGN_IDENTITY="$identity_hash"
    CODE_SIGN_INJECT_BASE_ENTITLEMENTS=NO
    ENABLE_HARDENED_RUNTIME=YES
    DEVELOPMENT_TEAM="$development_team"
)
if ! xcodebuild \
    ${xcode_container[@]+"${xcode_container[@]}"} \
    -scheme "$scheme" \
    -configuration "$configuration" \
    -destination "$destination" \
    -showBuildSettings \
    -json \
    "${build_overrides[@]}" \
    archive >"$build_settings"; then
    die "Xcode could not resolve Archive-action build settings for scheme '$scheme'"
fi
settings_count=$(json_array_count "$build_settings" || true)
if [[ ! "$settings_count" =~ ^[1-9][0-9]*$ ]]; then
    die "Xcode scheme '$scheme' has no archivable macOS build target. Add an Xcode application target with a shared archive-enabled scheme, or SwiftPM app-product metadata supported by installed Xcode."
fi
app_settings_index=
helper_target=false
for ((index = 0; index < settings_count; index++)); do
    candidate_product=$(plist_extract "$index.buildSettings.PRODUCT_NAME" string "$build_settings" || true)
    candidate_type=$(plist_extract "$index.buildSettings.PRODUCT_TYPE" string "$build_settings" || true)
    skip_install=$(plist_extract "$index.buildSettings.SKIP_INSTALL" string "$build_settings" || true)
    if [[ "$candidate_product" == "MacMerge" && "$candidate_type" == "com.apple.product-type.application" ]]; then
        [[ -z "$app_settings_index" ]] || die "Xcode scheme '$scheme' contains multiple MacMerge application targets"
        app_settings_index=$index
    elif [[ "$skip_install" == "NO" ]]; then
        helper_target=true
    fi
done
[[ -n "$app_settings_index" ]] || die \
    "Xcode scheme '$scheme' does not archive MacMerge as an application. SwiftPM executable-only archives are unsupported; add an Xcode application target/shared scheme."
[[ "$helper_target" == false ]] || die \
    "Archive scheme contains another installed target; configure target-specific entitlements before archiving"

skip_install=$(plist_extract "$app_settings_index.buildSettings.SKIP_INSTALL" string "$build_settings" || true)
[[ "$skip_install" == "NO" ]] || die "MacMerge application target must participate in Archive with SKIP_INSTALL=NO"
code_signing_allowed=$(plist_extract "$app_settings_index.buildSettings.CODE_SIGNING_ALLOWED" string "$build_settings" || true)
[[ "$code_signing_allowed" == "YES" ]] || die "MacMerge application target must enable signing for Archive"
resolved_identity=$(plist_extract "$app_settings_index.buildSettings.EXPANDED_CODE_SIGN_IDENTITY" string "$build_settings" || true)
[[ "${resolved_identity^^}" == "$identity_hash" ]] || die "Archive action did not resolve the selected signing identity"
resolved_team=$(plist_extract "$app_settings_index.buildSettings.DEVELOPMENT_TEAM" string "$build_settings" || true)
[[ "$resolved_team" == "$identity_team" ]] || die "Archive action did not resolve the selected signing team"
resolved_entitlements=$(plist_extract "$app_settings_index.buildSettings.CODE_SIGN_ENTITLEMENTS" string "$build_settings" || true)
[[ -n "$resolved_entitlements" ]] || die \
    "MacMerge application target must set CODE_SIGN_ENTITLEMENTS; global entitlement overrides are forbidden"
resolved_source_root=$(plist_extract "$app_settings_index.buildSettings.SRCROOT" string "$build_settings" || true)
[[ -n "$resolved_source_root" ]] || die "Xcode did not report the MacMerge application target source root"
[[ "$resolved_entitlements" == /* ]] || resolved_entitlements="$resolved_source_root/$resolved_entitlements"
[[ -f "$resolved_entitlements" ]] || die "resolved app-target entitlements file not found: $resolved_entitlements"
[[ "$(cd "$(dirname "$resolved_entitlements")" && pwd)/$(basename "$resolved_entitlements")" == \
    "$(cd "$(dirname "$entitlements")" && pwd)/$(basename "$entitlements")" ]] || \
    die "app target CODE_SIGN_ENTITLEMENTS does not resolve to requested ENTITLEMENTS file"
validate_entitlements "$resolved_entitlements"

if [[ "$check" == true ]]; then
    printf 'Archive validation passed: scheme=%s configuration=%s identity=%s team=%s\n' \
        "$scheme" "$configuration" "$identity_hash" "$identity_team"
    exit 0
fi

mkdir -p "$output_dir" "$(dirname "$archive_path")"
[[ ! -e "$archive_path" ]] || die "archive already exists; remove it or choose ARCHIVE_PATH: $archive_path"
archive_lock="$archive_path.lock"
if ! mkdir "$archive_lock" 2>/dev/null; then
    lock_owner=$(cat "$archive_lock/owner" 2>/dev/null || true)
    if [[ "$lock_owner" =~ ^[1-9][0-9]*$ ]] && kill -0 "$lock_owner" 2>/dev/null; then
        die "archive path is locked by process $lock_owner: $archive_path"
    fi
    stale_lock="$archive_lock.stale.$$"
    mv "$archive_lock" "$stale_lock" 2>/dev/null || die "could not reclaim stale archive lock: $archive_path"
    rm -rf "$stale_lock"
    mkdir "$archive_lock" 2>/dev/null || die "could not acquire archive path lock: $archive_path"
fi
printf '%s\n' "$$" >"$archive_lock/owner" || die "could not record archive lock owner"

archive_arguments=(
    ${xcode_container[@]+"${xcode_container[@]}"}
    -scheme "$scheme"
    -configuration "$configuration"
    -destination "$destination"
    -archivePath "$archive_path"
    "${build_overrides[@]}"
    archive
)
xcodebuild "${archive_arguments[@]}"

[[ -d "$archive_path" ]] || die "xcodebuild reported success but archive is missing: $archive_path"
[[ ! -L "$archive_path" ]] || die "archive path must not be a symbolic link"
archive_root_canonical=$(canonical_path "$archive_path") || die "could not resolve archive path"
archive_info="$archive_path/Info.plist"
[[ -f "$archive_info" ]] || die "archive Info.plist is missing"
[[ ! -L "$archive_info" ]] || die "archive Info.plist must not be a symbolic link"
validate_contained_path "$archive_root_canonical" "$archive_info" "archive Info.plist" >/dev/null
plutil -lint "$archive_info" >/dev/null || die "archive Info.plist is invalid"
application_path=$(plist_extract ApplicationProperties.ApplicationPath string "$archive_info" || true)
[[ "$application_path" == "Applications/MacMerge.app" ]] || \
    die "archive primary application path is invalid: ${application_path:-missing}"
archive_identifier=$(plist_extract ApplicationProperties.CFBundleIdentifier string "$archive_info" || true)
[[ -n "$archive_identifier" ]] || die "archive primary application identifier is missing"
archive_team=$(plist_extract ApplicationProperties.Team string "$archive_info" || true)
[[ "$archive_team" == "$identity_team" ]] || die "archive signing team does not match selected certificate team"
archive_identity=$(plist_extract ApplicationProperties.SigningIdentity string "$archive_info" || true)
[[ "$archive_identity" == "$identity_name" ]] || die "archive signing identity does not match selected certificate"

products_applications="$archive_path/Products/Applications"
[[ -d "$products_applications" ]] || die "archive Products/Applications directory is missing"
[[ ! -L "$products_applications" ]] || die "archive Products/Applications must not be a symbolic link"
products_applications_canonical=$(validate_contained_path \
    "$archive_root_canonical" "$products_applications" "archive Products/Applications")
shopt -s nullglob dotglob
archive_application_candidates=("$products_applications"/*.app)
shopt -u nullglob dotglob
for application in "${archive_application_candidates[@]}"; do
    printf '%s\n' "$application" >>"$archive_applications"
done
[[ "$(wc -l <"$archive_applications" | tr -d '[:space:]')" == "1" ]] || \
    die "archive must contain exactly one application"
app_bundle="$products_applications/MacMerge.app"
[[ -d "$app_bundle" ]] || die "archive does not contain Products/Applications/MacMerge.app"
[[ ! -L "$app_bundle" ]] || die "archive application must not be a symbolic link"
app_bundle_canonical=$(canonical_path "$app_bundle") || die "could not resolve archived application path"
validate_contained_path "$products_applications_canonical" "$app_bundle" "archived application" >/dev/null
app_info="$app_bundle/Contents/Info.plist"
[[ -f "$app_info" && ! -L "$app_info" ]] || die "archived application Info.plist is missing or symbolic"
validate_contained_path "$app_bundle_canonical" "$app_info" "archived application Info.plist" >/dev/null
app_identifier=$(plist_extract CFBundleIdentifier string "$app_info" || true)
[[ "$app_identifier" == "$archive_identifier" ]] || die "archive application identifier metadata does not match app bundle"

codesign --verify --deep --strict --all-architectures --verbose=2 "$app_bundle"
signed_code_found=false
find "$archive_path" -type l -print0 >"$archive_links" || die "could not enumerate archived symbolic links"
while IFS= read -r -d '' link; do
    case "$link" in
        "$app_bundle"/*)
            validate_contained_path "$app_bundle_canonical" "$link" \
                "archived application symbolic link" >/dev/null
            ;;
        *)
            validate_contained_path "$archive_root_canonical" "$link" \
                "archived symbolic link" >/dev/null
            ;;
    esac
    case "$link" in
        *.app|*.appex|*.framework|*.plugin|*.xpc|*.bundle)
            die "nested code bundle must not be a symbolic link: $link"
            ;;
    esac
done <"$archive_links"
find "$app_bundle" -type f -print0 >"$archive_files" || die "could not enumerate archived files"
while IFS= read -r -d '' code; do
    validate_contained_path "$app_bundle_canonical" "$code" "archived file" >/dev/null
    file_type=$(file -b "$code" 2>/dev/null) || die "could not inspect archived file type: $code"
    [[ "$file_type" == *"Mach-O"* ]] || continue
    [[ "$file_type" != *"archive"* ]] || continue
    if [[ "$file_type" == *"executable"* ]]; then
        validate_executable_mode "$code" "archived Mach-O executable"
    fi
    architectures=$(xcrun lipo -archs "$code" 2>/dev/null) || \
        die "could not inspect archived Mach-O architectures: $code"
    [[ -n "$architectures" ]] || die "archived Mach-O has no architectures: $code"
    signed_code_found=true
    for architecture in $architectures; do
        validate_developer_id_code "$code" "$architecture" "archived code"
    done
done <"$archive_files"
find "$app_bundle/Contents" -mindepth 1 -type d \( \
    -name '*.app' -o -name '*.appex' -o -name '*.framework' -o -name '*.plugin' \
    -o -name '*.xpc' -o -name '*.bundle' \) -print0 >"$archive_bundles" || \
    die "could not enumerate nested code bundles"
while IFS= read -r -d '' bundle; do
    bundle_canonical=$(validate_contained_path "$app_bundle_canonical" "$bundle" "nested code bundle")
    if [[ "$bundle" == *.framework ]]; then
        if [[ -f "$bundle/Resources/Info.plist" ]]; then
            bundle_info="$bundle/Resources/Info.plist"
        else
            bundle_info="$bundle/Info.plist"
        fi
        bundle_executable_path_prefix="$bundle"
    else
        bundle_info="$bundle/Contents/Info.plist"
        bundle_executable_path_prefix="$bundle/Contents/MacOS"
    fi
    [[ -f "$bundle_info" ]] || die "nested code bundle Info.plist is missing: $bundle"
    validate_contained_path "$bundle_canonical" "$bundle_info" "nested code bundle Info.plist" >/dev/null
    plutil -lint "$bundle_info" >/dev/null || die "nested code bundle Info.plist is invalid: $bundle"
    bundle_executable=$(plist_extract CFBundleExecutable string "$bundle_info" || true)
    if [[ -z "$bundle_executable" ]]; then
        [[ "$bundle" == *.bundle ]] || die "nested code bundle CFBundleExecutable is missing: $bundle"
        continue
    fi
    validate_bundle_executable_name "$bundle_executable" "$bundle"
    bundle_executable_path="$bundle_executable_path_prefix/$bundle_executable"
    [[ -f "$bundle_executable_path" ]] || die "nested code bundle executable is missing: $bundle"
    validate_contained_path "$bundle_canonical" "$bundle_executable_path" \
        "nested code bundle executable" >/dev/null
    validate_executable_mode "$bundle_executable_path" "nested code bundle executable"
    architectures=$(xcrun lipo -archs "$bundle_executable_path" 2>/dev/null) || \
        die "nested code bundle executable is not Mach-O: $bundle"
    [[ -n "$architectures" ]] || die "nested code bundle has no Mach-O architectures: $bundle"
    for architecture in $architectures; do
        validate_developer_id_code "$bundle" "$architecture" "archived code bundle"
    done
done <"$archive_bundles"
[[ "$signed_code_found" == true ]] || die "archive application contains no signed Mach-O code"
app_executable=$(plist_extract CFBundleExecutable string "$app_info" || true)
validate_bundle_executable_name "$app_executable" "$app_bundle"
app_executable_path="$app_bundle/Contents/MacOS/$app_executable"
[[ -f "$app_executable_path" ]] || die "archived app executable is missing"
validate_contained_path "$app_bundle_canonical" "$app_executable_path" \
    "archived app executable" >/dev/null
validate_executable_mode "$app_executable_path" "archived app executable"
app_architectures=$(xcrun lipo -archs "$app_executable_path" 2>/dev/null) || \
    die "could not inspect archived app executable architectures"
[[ -n "$app_architectures" ]] || die "archived app executable has no Mach-O architectures"
archive_architectures=$(plist_extract ApplicationProperties.Architectures array "$archive_info" || true)
[[ "$archive_architectures" =~ ^[1-9][0-9]*$ ]] || die "archive primary application architectures are missing"
archive_architecture_array=()
for ((index = 0; index < archive_architectures; index++)); do
    architecture=$(plist_extract "ApplicationProperties.Architectures.$index" string "$archive_info" || true)
    [[ -n "$architecture" ]] || die "archive contains an invalid application architecture"
    archive_architecture_array+=("$architecture")
done
read -r -a app_architecture_array <<<"$app_architectures"
[[ "$(printf '%s\n' "${archive_architecture_array[@]}" | sort -u | tr '\n' ' ')" == \
    "$(printf '%s\n' "${app_architecture_array[@]}" | sort -u | tr '\n' ' ')" ]] || \
    die "archive application architecture metadata does not match app executable"
for architecture in $app_architectures; do
    validate_developer_id_code "$app_bundle" "$architecture" "archived application"
    codesign --display --architecture "$architecture" --entitlements "$signed_entitlements" --xml "$app_bundle" 2>/dev/null || \
        die "could not read archived application entitlements for architecture '$architecture'"
    validate_entitlements "$signed_entitlements"
done

printf '%s\n' "$archive_path"
