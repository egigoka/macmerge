#!/bin/bash

set -euo pipefail

package_root=$(cd "$(dirname "$0")/.." && pwd)
fixture_dir=${FIXTURE_DIR:-"${TMPDIR:-/tmp}/macmerge-trace-$$"}
owns_fixture_dir=0
if [[ -z ${FIXTURE_DIR:-} ]]; then
    owns_fixture_dir=1
fi
report=${REPORT_PATH:-"$package_root/dist/performance-trace-report.json"}
trace=${TRACE_PATH:-"$package_root/dist/MacMerge-performance.trace"}
template=${TRACE_TEMPLATE:-"Time Profiler"}
time_limit=${TRACE_TIME_LIMIT:-20s}
line_count=${LINE_COUNT:-1000000}
density=${FIXTURE_DENSITY:-sparse}
app="$package_root/dist/MacMerge.app"
trace_pid=""
app_pid=""

cleanup() {
    if [[ -n "$app_pid" ]] && kill -0 "$app_pid" 2>/dev/null; then
        kill "$app_pid" 2>/dev/null || true
        wait "$app_pid" 2>/dev/null || true
    fi
    if [[ -n "$trace_pid" ]] && kill -0 "$trace_pid" 2>/dev/null; then
        kill -INT "$trace_pid" 2>/dev/null || true
        wait "$trace_pid" 2>/dev/null || true
    fi
    if [[ $owns_fixture_dir == 1 ]]; then
        rm -rf "$fixture_dir"
    fi
}
trap cleanup EXIT

if ! xcrun --find xctrace >/dev/null 2>&1; then
    echo "Instruments xctrace is unavailable. Select a full Xcode installation with xcode-select." >&2
    exit 1
fi

if [[ ${SKIP_PACKAGE:-0} != 1 ]]; then
    "$package_root/Scripts/package-app.sh" >/dev/null
fi

mkdir -p "$fixture_dir" "$(dirname "$report")" "$(dirname "$trace")"
if [[ -e "$trace" ]]; then
    echo "Refusing to replace existing trace path: $trace" >&2
    exit 1
fi
rm -f "$report"
swift run \
    --package-path "$package_root" \
    --configuration release \
    MacMergeBenchmark \
    --lines "$line_count" \
    --density "$density" \
    --fixture-directory "$fixture_dir" >/dev/null

left="$fixture_dir/macmerge-$line_count-left.txt"
right="$fixture_dir/macmerge-$line_count-right.txt"
xcrun xctrace record \
    --template "$template" \
    --time-limit "$time_limit" \
    --output "$trace" \
    --launch -- \
    /usr/bin/env \
    MACMERGE_PERFORMANCE_REPORT="$report" \
    MACMERGE_PERFORMANCE_AUTOSCROLL=1 \
    "$app/Contents/MacOS/MacMerge" &
trace_pid=$!

for _ in {1..100}; do
    app_pid=$(pgrep -n -f "^$app/Contents/MacOS/MacMerge$") || true
    if [[ -n "$app_pid" ]]; then break; fi
    sleep 0.1
done
if [[ -z "$app_pid" ]]; then
    kill "$trace_pid" 2>/dev/null || true
    echo "MacMerge did not launch under Instruments." >&2
    exit 1
fi
open -a "$app" "$left" "$right"
wait "$trace_pid"

if [[ ! -d "$trace" ]]; then
    echo "Instruments did not create trace bundle: $trace" >&2
    exit 1
fi
if [[ ! -s "$report" ]] || [[ $(plutil -extract complete raw "$report" 2>/dev/null || true) != 1 ]]; then
    echo "Traced app did not complete packaged performance workflow." >&2
    exit 1
fi

echo "$trace"
plutil -p "$report"
