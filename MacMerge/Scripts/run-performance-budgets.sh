#!/bin/bash

set -euo pipefail

package_root=$(cd "$(dirname "$0")/.." && pwd)
fixture_dir=${FIXTURE_DIR:-"${TMPDIR:-/tmp}/macmerge-performance-$$"}
report=${REPORT_PATH:-"$package_root/dist/performance-report.json"}
app="$package_root/dist/MacMerge.app"
line_count=${LINE_COUNT:-1000000}
load_budget_ms=${LOAD_BUDGET_MS:-5000}
comparison_budget_ms=${COMPARISON_BUDGET_MS:-5000}
first_render_budget_ms=${FIRST_RENDER_BUDGET_MS:-1500}
scroll_budget_ms=${SCROLL_BUDGET_MS:-1500}
resident_budget_mib=${RESIDENT_BUDGET_MIB:-900}
pid=""

cleanup() {
    if [[ -n "$pid" ]] && kill -0 "$pid" 2>/dev/null; then
        kill "$pid" 2>/dev/null || true
        wait "$pid" 2>/dev/null || true
    fi
    rm -rf "$fixture_dir"
}
trap cleanup EXIT

if [[ ${SKIP_PACKAGE:-0} != 1 ]]; then
    "$package_root/Scripts/package-app.sh" >/dev/null
fi

mkdir -p "$fixture_dir" "$(dirname "$report")"
rm -f "$report"
swift run \
    --package-path "$package_root" \
    --configuration release \
    MacMergeBenchmark \
    --lines "$line_count" \
    --fixture-directory "$fixture_dir" >/dev/null

left="$fixture_dir/macmerge-$line_count-left.txt"
right="$fixture_dir/macmerge-$line_count-right.txt"
MACMERGE_PERFORMANCE_REPORT="$report" \
MACMERGE_PERFORMANCE_AUTOSCROLL=1 \
"$app/Contents/MacOS/MacMerge" "$left" "$right" >/dev/null 2>&1 &
pid=$!

for _ in {1..600}; do
    if [[ -s "$report" ]] && [[ $(plutil -extract complete raw "$report" 2>/dev/null || true) == 1 ]]; then
        break
    fi
    if ! kill -0 "$pid" 2>/dev/null; then
        echo "MacMerge exited before writing performance report." >&2
        exit 1
    fi
    sleep 0.1
done

if [[ ! -s "$report" ]] || [[ $(plutil -extract complete raw "$report" 2>/dev/null || true) != 1 ]]; then
    echo "Timed out waiting for packaged-app performance report." >&2
    exit 1
fi

check_budget() {
    local metric=$1
    local budget=$2
    local value
    value=$(plutil -extract "$metric" raw "$report")
    if (( value > budget )); then
        echo "$metric exceeded budget: ${value} > ${budget}" >&2
        exit 1
    fi
}

check_budget load_ms "$load_budget_ms"
check_budget comparison_ms "$comparison_budget_ms"
check_budget first_render_ms "$first_render_budget_ms"
check_budget scroll_ms "$scroll_budget_ms"
check_budget resident_mib "$resident_budget_mib"

plutil -p "$report"
