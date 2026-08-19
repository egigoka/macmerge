#!/bin/bash

set -euo pipefail

package_root=$(cd "$(dirname "$0")/.." && pwd)
cd "$package_root"

analyzer_flags=(
    --analyze
    -std=c11
    -Wall
    -Wextra
    -Wpedantic
    -Werror
    -Xanalyzer
    -analyzer-werror
    -I Sources/CXDiff/include
    -I ../Externals/xdiff
    -I ../Externals/poco/dependencies/pcre2/src
    -o /dev/null
)

if [[ $# -gt 0 ]]; then
    for source in "$@"; do
        xcrun clang "${analyzer_flags[@]}" "$source"
    done
    exit 0
fi

for source in Sources/CXDiff/macmerge_xdiff.c Sources/CXDiff/macmerge_regex.c; do
    xcrun clang "${analyzer_flags[@]}" "$source"
done
xcrun clang "${analyzer_flags[@]}" -DDEBUG Sources/CXDiff/macmerge_xdiff.c
