#!/bin/bash

set -euo pipefail

package_root=$(cd "$(dirname "$0")/.." && pwd)
fixture_dir=${FIXTURE_DIR:-"${TMPDIR:-/tmp}/macmerge-performance-$$"}
report=${REPORT_PATH:-"$package_root/dist/performance-report.json"}
app="$package_root/dist/MacMerge.app"
runtime_report=""
report_hash="$report.sha256"
line_count=${LINE_COUNT:-1000000}
density=${FIXTURE_DENSITY:-sparse}
content=${FIXTURE_CONTENT:-ascii}
line_bytes=${FIXTURE_LINE_BYTES:-}
reported_line_bytes=${line_bytes:-0}
load_budget_ms=${LOAD_BUDGET_MS:-5000}
comparison_budget_ms=${COMPARISON_BUDGET_MS:-5000}
first_render_budget_ms=${FIRST_RENDER_BUDGET_MS:-1500}
scroll_budget_ms=${SCROLL_BUDGET_MS:-1500}
location_pane_budget_ms=${LOCATION_PANE_BUDGET_MS:-1500}
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
    rm -f "$runtime_report"
    rm -rf "$fixture_dir"
}
trap cleanup EXIT

if [[ ${SKIP_PACKAGE:-0} != 1 ]]; then
    "$package_root/Scripts/package-app.sh" >/dev/null
fi
bundle_identifier=$(plutil -extract CFBundleIdentifier raw "$app/Contents/Info.plist")
runtime_report="$HOME/Library/Containers/$bundle_identifier/Data/tmp/macmerge-performance-$$.json"

mkdir -p "$fixture_dir" "$(dirname "$report")"
rm -f "$report" "$report_hash" "$runtime_report"
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
    --env "MACMERGE_PERFORMANCE_REPORT=$runtime_report" \
    --env "MACMERGE_PERFORMANCE_AUTOSCROLL=1" \
    --env "MACMERGE_PERFORMANCE_LOCATION_PANE=1" \
    --env "MACMERGE_PERFORMANCE_LINE_COUNT=$line_count" \
    --env "MACMERGE_PERFORMANCE_DENSITY=$density" \
    --env "MACMERGE_PERFORMANCE_CONTENT=$content" \
    --env "MACMERGE_PERFORMANCE_LINE_BYTES=$reported_line_bytes" \
    --env "MACMERGE_PERFORMANCE_LOAD_BUDGET_MS=$load_budget_ms" \
    --env "MACMERGE_PERFORMANCE_COMPARISON_BUDGET_MS=$comparison_budget_ms" \
    --env "MACMERGE_PERFORMANCE_FIRST_RENDER_BUDGET_MS=$first_render_budget_ms" \
    --env "MACMERGE_PERFORMANCE_SCROLL_BUDGET_MS=$scroll_budget_ms" \
    --env "MACMERGE_PERFORMANCE_LOCATION_PANE_BUDGET_MS=$location_pane_budget_ms" \
    --env "MACMERGE_PERFORMANCE_RESIDENT_BUDGET_MIB=$resident_budget_mib" \
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
    if [[ -s "$runtime_report" ]] && [[ $(plutil -extract complete raw "$runtime_report" 2>/dev/null || true) == 1 ]]; then
        break
    fi
    if ! kill -0 "$pid" 2>/dev/null; then
        echo "MacMerge exited before writing performance report." >&2
        exit 1
    fi
    sleep 0.1
done

if [[ ! -s "$runtime_report" ]] || [[ $(plutil -extract complete raw "$runtime_report" 2>/dev/null || true) != 1 ]]; then
    echo "Timed out waiting for packaged-app performance report." >&2
    exit 1
fi
cp "$runtime_report" "$report"

assert_metric() {
    local metric=$1
    local expected=$2
    local value
    value=$(plutil -extract "$metric" raw "$report")
    if [[ "$value" != "$expected" ]]; then
        echo "$metric did not match workload: ${value} != ${expected}" >&2
        exit 1
    fi
}

assert_metric fixture_line_count "$line_count"
assert_metric fixture_density "$density"
assert_metric fixture_content "$content"
assert_metric fixture_line_bytes "$reported_line_bytes"
assert_metric load_budget_ms "$load_budget_ms"
assert_metric comparison_budget_ms "$comparison_budget_ms"
assert_metric first_render_budget_ms "$first_render_budget_ms"
assert_metric scroll_budget_ms "$scroll_budget_ms"
assert_metric location_pane_budget_ms "$location_pane_budget_ms"
assert_metric resident_budget_mib "$resident_budget_mib"
assert_metric location_pane_requested 1
assert_metric location_pane_rendered 1
assert_metric location_map_rows "$line_count"
assert_metric resident_sampled 1

location_map_blocks=$(plutil -extract location_map_blocks raw "$report")
if (( location_map_blocks <= 0 )); then
    echo "Location Pane rendered no difference blocks." >&2
    exit 1
fi
if [[ "$density" == location-dense ]] && (( location_map_blocks != line_count / 2 )); then
    echo "Location Pane map did not retain worst-case runs: ${location_map_blocks} != $((line_count / 2))" >&2
    exit 1
fi

resident_bytes=$(plutil -extract resident_bytes raw "$report")
if (( resident_bytes <= 0 )); then
    echo "Resident-memory sampling returned no data." >&2
    exit 1
fi

machine_model=$(plutil -extract machine_model raw "$report")
os_version=$(plutil -extract os_version raw "$report")
if [[ -z "$machine_model" || "$machine_model" == unknown || -z "$os_version" ]]; then
    echo "Performance report omitted machine or operating-system provenance." >&2
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
check_budget location_pane_render_ms "$location_pane_budget_ms"

resident_budget_bytes=$((resident_budget_mib * 1048576))
if (( resident_bytes > resident_budget_bytes )); then
    echo "resident_bytes exceeded budget: ${resident_bytes} > ${resident_budget_bytes}" >&2
    exit 1
fi

shasum -a 256 "$report" | cut -d ' ' -f 1 > "$report_hash"

plutil -p "$report"
