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
content=${FIXTURE_CONTENT:-ascii}
line_bytes=${FIXTURE_LINE_BYTES:-}
app="$package_root/dist/MacMerge.app"
app_executable="$app/Contents/MacOS/MacMerge"
trace_pid=""
app_pid=""
existing_pid=""
toc=""
signposts=""
cleanup_apps=0
owned_app_pids=()
watchdog_pid=""

if [[ ! "$line_count" =~ ^[1-9][0-9]*$ ]]; then
    echo "LINE_COUNT must be a positive decimal integer." >&2
    exit 1
fi
if (( ${#line_count} > 7 )) || (( ${#line_count} == 7 && 10#$line_count > 1048576 )); then
    echo "LINE_COUNT exceeds MacMerge's 1,048,576-line limit." >&2
    exit 1
fi
line_count=$((10#$line_count))

app_pids() {
    local candidate command
    while IFS= read -r candidate; do
        [[ -n "$candidate" ]] || continue
        command=$(ps -p "$candidate" -o command= 2>/dev/null || true)
        if [[ "$command" == "$app_executable" || "$command" == "$app_executable "* ]]; then
            echo "$candidate"
        fi
    done < <(pgrep -x MacMerge || true)
}

cleanup() {
    if [[ -n "$watchdog_pid" ]] && kill -0 "$watchdog_pid" 2>/dev/null; then
        kill "$watchdog_pid" 2>/dev/null || true
        wait "$watchdog_pid" 2>/dev/null || true
    fi
    if [[ $cleanup_apps == 1 ]]; then
        for candidate in "${owned_app_pids[@]-}"; do kill "$candidate" 2>/dev/null || true; done
        for _ in {1..50}; do
            local alive=0
            for candidate in "${owned_app_pids[@]-}"; do
                if kill -0 "$candidate" 2>/dev/null; then alive=1; break; fi
            done
            if [[ $alive == 0 ]]; then break; fi
            sleep 0.1
        done
        for candidate in "${owned_app_pids[@]-}"; do kill -KILL "$candidate" 2>/dev/null || true; done
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
existing_pid=$(app_pids)
if [[ -n "$existing_pid" ]]; then
    echo "Close the packaged MacMerge app before recording a trace." >&2
    exit 1
fi
cleanup_apps=1
xcrun xctrace record \
    --template "$template" \
    --time-limit "$time_limit" \
    --output "$trace" \
    --env "MACMERGE_PERFORMANCE_REPORT=$report" \
    --env "MACMERGE_PERFORMANCE_AUTOSCROLL=1" \
    --launch -- \
    "$app" &
trace_pid=$!

for _ in {1..100}; do
    app_pid=$(app_pids | tail -n 1) || true
    if [[ -n "$app_pid" ]]; then break; fi
    sleep 0.1
done
if [[ -z "$app_pid" ]]; then
    kill "$trace_pid" 2>/dev/null || true
    echo "MacMerge did not launch under Instruments." >&2
    exit 1
fi
owned_app_pids=("$app_pid")
open -a "$app" "$left" "$right"
(
    sleep 60
    if kill -0 "$trace_pid" 2>/dev/null; then
        kill -INT "$trace_pid" 2>/dev/null || true
        sleep 5
        kill -KILL "$trace_pid" 2>/dev/null || true
    fi
) &
watchdog_pid=$!
trace_status=0
wait "$trace_pid" || trace_status=$?
trace_pid=""
kill "$watchdog_pid" 2>/dev/null || true
wait "$watchdog_pid" 2>/dev/null || true

if [[ ! -d "$trace" ]]; then
    echo "Instruments did not create trace bundle (status $trace_status): $trace" >&2
    exit 1
fi
toc=$(xcrun xctrace export --input "$trace" --toc)
time_limit_reached=$(xmllint --xpath \
    'boolean(/trace-toc/run/info/summary/end-reason[text()="Time limit reached"])' \
    - <<<"$toc" 2>/dev/null || true)
if (( trace_status != 0 )) && [[ "$time_limit_reached" != true ]]; then
    echo "Instruments recording failed with status $trace_status." >&2
    exit 1
fi
has_target=$(xmllint --xpath \
    'boolean(/trace-toc/run/info/target/process[@type="launched" and @name="MacMerge"])' \
    - <<<"$toc" 2>/dev/null || true)
has_time_profile=$(xmllint --xpath \
    'boolean(/trace-toc/run/data/table[@schema="time-profile"])' \
    - <<<"$toc" 2>/dev/null || true)
has_signposts=$(xmllint --xpath \
    'boolean(/trace-toc/run/data/table[@schema="os-signpost"])' \
    - <<<"$toc" 2>/dev/null || true)
if [[ "$has_target" != true || "$has_time_profile" != true || "$has_signposts" != true ]]; then
    echo "Instruments trace does not contain MacMerge Time Profiler and signpost data." >&2
    exit 1
fi
signposts=$(xcrun xctrace export \
    --input "$trace" \
    --xpath '/trace-toc/run[@number="1"]/data/table[@schema="os-signpost"]')
subsystem_id=$(xmllint --xpath \
    'string((//subsystem[@fmt="io.github.egigoka.MacMerge"])[1]/@id)' \
    - <<<"$signposts" 2>/dev/null || true)
if [[ -z "$subsystem_id" ]]; then
    echo "Instruments signpost export does not contain MacMerge events." >&2
    exit 1
fi
end_event_id=$(xmllint --xpath \
    'string((//event-type[@fmt="End"])[1]/@id)' \
    - <<<"$signposts" 2>/dev/null || true)
begin_event_id=$(xmllint --xpath \
    'string((//event-type[@fmt="Begin"])[1]/@id)' \
    - <<<"$signposts" 2>/dev/null || true)
for interval in LoadPair Comparison FirstVisibleRow AutoScroll; do
    name_id=$(xmllint --xpath \
        "string((//signpost-name[@fmt='$interval'])[1]/@id)" \
        - <<<"$signposts" 2>/dev/null || true)
    begin="(//row[(event-type/@fmt='Begin' or event-type/@ref='$begin_event_id') and (signpost-name/@fmt='$interval' or signpost-name/@ref='$name_id') and (subsystem/@fmt='io.github.egigoka.MacMerge' or subsystem/@ref='$subsystem_id')])[1]"
    identifier_id=$(xmllint --xpath \
        "string(($begin/os-signpost-identifier/@id | $begin/os-signpost-identifier/@ref)[1])" \
        - <<<"$signposts" 2>/dev/null || true)
    has_end=$(xmllint --xpath \
        "boolean(//row[(event-type/@fmt='End' or event-type/@ref='$end_event_id') and (signpost-name/@fmt='$interval' or signpost-name/@ref='$name_id') and (os-signpost-identifier/@id='$identifier_id' or os-signpost-identifier/@ref='$identifier_id') and (subsystem/@fmt='io.github.egigoka.MacMerge' or subsystem/@ref='$subsystem_id')])" \
        - <<<"$signposts" 2>/dev/null || true)
    if [[ -z "$name_id" || -z "$identifier_id" || "$has_end" != true ]]; then
        echo "Instruments trace is missing a completed $interval interval." >&2
        exit 1
    fi
done
if [[ ! -s "$report" ]] || [[ $(plutil -extract complete raw "$report" 2>/dev/null || true) != 1 ]]; then
    echo "Traced app did not complete packaged performance workflow." >&2
    exit 1
fi
for metric in load_ms comparison_ms first_render_ms scroll_ms resident_mib; do
    value=$(plutil -extract "$metric" raw "$report" 2>/dev/null || true)
    if [[ ! "$value" =~ ^[0-9]+$ ]] || [[ "$metric" == resident_mib && "$value" == 0 ]]; then
        echo "Traced performance report is missing $metric." >&2
        exit 1
    fi
done
if [[ $(plutil -extract rows raw "$report" 2>/dev/null || true) != $((line_count + 1)) ]]; then
    echo "Traced performance report has unexpected row count." >&2
    exit 1
fi

echo "$trace"
plutil -p "$report"
