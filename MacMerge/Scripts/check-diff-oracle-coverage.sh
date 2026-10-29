#!/bin/bash

# Verifies MacMerge/DiffOracle/coverage.lock against the checked-out WinMerge fixtures
# and MacMerge alignment sources. Pass --refresh to rewrite recorded digests for review.
# Set DIFF_ORACLE_REQUIRE_GOLDENS=1 to fail while any required fixture source lacks a golden.

set -euo pipefail

package_root=$(cd "$(dirname "$0")/.." && pwd)
repository_root=$(cd "$package_root/.." && pwd)
temporary_root=$(mktemp -d "${TMPDIR:-/tmp}/macmerge-diff-oracle.XXXXXX")
trap 'rm -rf "$temporary_root"' EXIT

xcrun swiftc -warnings-as-errors -O \
    -module-name DiffOracleCoverageGate \
    "$package_root/Sources/MacMergeCore/DiffOracleManifest.swift" \
    "$package_root/Sources/MacMergeCore/DiffOracleFixtureCoverage.swift" \
    "$package_root/Scripts/DiffOracleCoverageGate/main.swift" \
    -o "$temporary_root/diff-oracle-coverage-gate"

gate_arguments=(--repository-root "$repository_root")
if [[ "${DIFF_ORACLE_REQUIRE_GOLDENS:-0}" == 1 ]]; then
    gate_arguments+=(--require-goldens)
fi

"$temporary_root/diff-oracle-coverage-gate" "${gate_arguments[@]}" "$@"
