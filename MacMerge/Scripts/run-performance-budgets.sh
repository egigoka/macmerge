#!/bin/bash

set -euo pipefail

package_root=$(cd "$(dirname "$0")/.." && pwd)
fixture_dir=${FIXTURE_DIR:-"${TMPDIR:-/tmp}/macmerge-performance-$$"}
report=${REPORT_PATH:-"$package_root/dist/performance-report.json"}
app="$package_root/dist/MacMerge.app"
line_count=${LINE_COUNT:-1000000}
density=${FIXTURE_DENSITY:-sparse}
content=${FIXTURE_CONTENT:-ascii}
line_bytes=${FIXTURE_LINE_BYTES:-}
load_budget_ms=${LOAD_BUDGET_MS:-5000}
comparison_budget_ms=${COMPARISON_BUDGET_MS:-5000}
first_render_budget_ms=${FIRST_RENDER_BUDGET_MS:-1500}
scroll_budget_ms=${SCROLL_BUDGET_MS:-1500}
resident_budget_mib=${RESIDENT_BUDGET_MIB:-900}
pid=""
launcher_pid=""
existing_pids=""

cleanup() {
    if [[ -n "$pid" ]] && kill -0 "$pid" 2>/dev/null; then
        kill "$pid" 2>/dev/null || true
        wait "$pid" 2>/dev/null || true
    fi
    if [[ -n "$launcher_pid" ]] && kill -0 "$launcher_pid" 2>/dev/null; then
        kill "$launcher_pid" 2>/dev/null || true
        wait "$launcher_pid" 2>/dev/null || true
    fi
    rm -rf "$fixture_dir"
}
trap cleanup EXIT

if [[ ${SKIP_PACKAGE:-0} != 1 ]]; then
    "$package_root/Scripts/package-app.sh" >/dev/null
fi

mkdir -p "$fixture_dir" "$(dirname "$report")"
rm -f "$report"
benchmark_arguments=(
    --lines "$line_count"
    --density "$density"
    --content "$content"
    --fixture-directory "$fixture_dir"
)
if [[ -n "$line_bytes" ]]; then
    benchmark_arguments+=(--line-bytes "$line_bytes")
fi
swift run \
    --package-path "$package_root" \
    --configuration release \
    MacMergeBenchmark \
    "${benchmark_arguments[@]}" >/dev/null

left="$fixture_dir/macmerge-$line_count-left.txt"
right="$fixture_dir/macmerge-$line_count-right.txt"
existing_pids=$(pgrep -f "^$app/Contents/MacOS/MacMerge$" || true)
open -n -W -a "$app" \
    --env "MACMERGE_PERFORMANCE_REPORT=$report" \
    --env "MACMERGE_PERFORMANCE_AUTOSCROLL=1" \
    "$left" "$right" >/dev/null 2>&1 &
launcher_pid=$!
for _ in {1..100}; do
    pid=$(pgrep -f "^$app/Contents/MacOS/MacMerge$" | while read -r candidate; do
        if ! grep -qx "$candidate" <<<"$existing_pids"; then
            echo "$candidate"
            break
        fi
    done) || true
    if [[ -n "$pid" ]]; then break; fi
    sleep 0.1
done
if [[ -z "$pid" ]]; then
    echo "MacMerge did not launch." >&2
    exit 1
fi

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
