#!/bin/bash

set -euo pipefail

package_root=$(cd "$(dirname "$0")/.." && pwd)
output_dir=${1:-"$package_root/dist"}
work_dir=$(mktemp -d "${TMPDIR:-/tmp}/macmerge-icon.XXXXXX")
iconset="$work_dir/MacMerge.iconset"

cleanup() {
    rm -rf "$work_dir"
}
trap cleanup EXIT

mkdir -p "$output_dir"
swift "$package_root/Scripts/generate-icon.swift" "$iconset"
iconutil --convert icns --output "$output_dir/MacMerge.icns" "$iconset"

echo "$output_dir/MacMerge.icns"
