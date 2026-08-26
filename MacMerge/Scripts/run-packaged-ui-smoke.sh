#!/bin/bash

set -euo pipefail

runtime_directory="$HOME/Library/Caches/io.github.egigoka.MacMerge/PackagedUISmoke"
for cache_ancestor in \
    "$HOME" \
    "$HOME/Library" \
    "$HOME/Library/Caches" \
    "$HOME/Library/Caches/io.github.egigoka.MacMerge"; do
    if [[ -L "$cache_ancestor" ]]; then
        echo "Refusing symlinked packaged UI smoke cache ancestor: $cache_ancestor" >&2
        exit 1
    fi
done
if [[ -e "$runtime_directory" || -L "$runtime_directory" ]]; then
    if [[ -L "$runtime_directory" || ! -d "$runtime_directory" || ! -O "$runtime_directory" ]]; then
        echo "Refusing untrusted packaged UI smoke cache: $runtime_directory" >&2
        exit 1
    fi
fi
mkdir -p "$runtime_directory"
chmod 700 "$runtime_directory"
for state_path in \
    "$runtime_directory/lock" \
    "$runtime_directory/orphan" \
    "$runtime_directory/PackagedUISmoke" \
    "$runtime_directory/PackagedUISmoke.fingerprint" \
    "$runtime_directory/build"; do
    if [[ -L "$state_path" ]] || { [[ -e "$state_path" ]] && [[ ! -O "$state_path" ]]; }; then
        echo "Refusing untrusted packaged UI smoke state: $state_path" >&2
        exit 1
    fi
done
exec 9>>"$runtime_directory/lock"
if [[ ! -f /dev/fd/9 ]] || [[ ! -O /dev/fd/9 ]]; then
    echo "Refusing untrusted packaged UI smoke lock: $runtime_directory/lock" >&2
    exit 1
fi
chmod 600 /dev/fd/9
set +e
/usr/bin/lockf -s -t 0 9
lock_status=$?
set -e
if [[ "$lock_status" == 75 ]]; then
    echo "Another packaged UI smoke is already running." >&2
    exit 1
elif [[ "$lock_status" != 0 ]]; then
    echo "Could not acquire packaged UI smoke lock (lockf exited $lock_status)." >&2
    exit 1
fi

package_root=$(cd "$(dirname "$0")/.." && pwd)
bundle_identifier="io.github.egigoka.MacMerge.UISmoke.Automated"
completion_guard="$runtime_directory/orphan"
container_parent="$HOME/Library/Containers"
container="$HOME/Library/Containers/$bundle_identifier"
driver="$runtime_directory/PackagedUISmoke"
driver_fingerprint_file="$runtime_directory/PackagedUISmoke.fingerprint"

for container_path in \
    "$HOME/Library" \
    "$container_parent" \
    "$container" \
    "$container/Data" \
    "$container/Data/Library" \
    "$container/Data/Library/Application Support" \
    "$container/Data/Library/Application Support/MacMerge" \
    "$container/Data/Library/Application Support/MacMerge/ComparisonSession.json"; do
    if [[ -L "$container_path" ]]; then
        echo "Refusing symlinked packaged UI smoke container path: $container_path" >&2
        exit 1
    fi
done

if [[ -e "$completion_guard" ]]; then
    echo "Previous packaged UI smoke may have left an isolated app running. Inspect bundle $bundle_identifier, then remove $completion_guard." >&2
    exit 1
fi

temporary_root=""
app=""
staged_driver=""
driver_pid=""
driver_launch_pending=0
pending_signal=0
cancellation_watchdog_pid=""
watchdog_stop_file=""
pid_file=""
launch_intent=""
cancellation_file=""

# shellcheck disable=SC2329
cleanup() {
    local original_status=$?
    local cleanup_status=0
    local watchdog_pid=""
    set +e
    trap - EXIT
    trap '' INT TERM HUP
    if [[ -n "$driver_pid" ]]; then
        echo "Waiting for isolated packaged UI smoke cleanup after interruption." >&2
        wait "$driver_pid" 2>/dev/null || true
    fi
    if [[ "$cancellation_watchdog_pid" =~ ^[0-9]+$ ]]; then
        watchdog_pid="$cancellation_watchdog_pid"
        cancellation_watchdog_pid=""
        if [[ -n "$watchdog_stop_file" ]]; then
            : > "$watchdog_stop_file"
        fi
        wait "$watchdog_pid" 2>/dev/null || true
    fi
    cancellation_watchdog_pid=""
    if { [[ -n "$launch_intent" && -f "$launch_intent" ]] \
        || [[ -n "$pid_file" && -s "$pid_file" ]]; }; then
        echo "Packaged UI smoke may have been interrupted with an isolated app launch in flight; preserving $temporary_root." >&2
        cleanup_status=1
        if [[ "$original_status" != 0 ]]; then
            exit "$original_status"
        fi
        exit "$cleanup_status"
    fi
    rm -f "$completion_guard" || cleanup_status=1
    if [[ "$bundle_identifier" == "io.github.egigoka.MacMerge.UISmoke.Automated" ]] \
        && { [[ -e "$container/Data" ]] || [[ -L "$container/Data" ]]; }; then
        echo "Packaged UI smoke driver did not remove isolated data at $container/Data." >&2
        cleanup_status=1
    fi
    if [[ -n "$staged_driver" ]]; then
        rm -f "$staged_driver" || cleanup_status=1
    fi
    if [[ -n "$temporary_root" ]]; then
        rm -rf "$temporary_root" || cleanup_status=1
    fi
    if [[ "$original_status" != 0 ]]; then
        exit "$original_status"
    fi
    exit "$cleanup_status"
}

# shellcheck disable=SC2329
start_cancellation_watchdog() {
    local watched_pid="$driver_pid"
    local watched_parent=""
    local watched_start=""
    local driver_is_job=0
    local job_pid=""
    [[ -n "$watched_pid" ]] || return
    : > "$cancellation_file"
    if [[ -n "$cancellation_watchdog_pid" ]]; then
        return
    fi
    cancellation_watchdog_pid="starting"
    watched_start=$(ps -o lstart= -p "$watched_pid" 2>/dev/null || true)
    watched_parent=$(ps -o ppid= -p "$watched_pid" 2>/dev/null | tr -d '[:space:]' || true)
    while IFS= read -r job_pid; do
        if [[ "$job_pid" == "$watched_pid" ]]; then
            driver_is_job=1
            break
        fi
    done < <(jobs -pr)
    if [[ -z "$watched_start" || "$watched_parent" != "$$" || "$driver_is_job" != 1 ]]; then
        cancellation_watchdog_pid=""
        return
    fi
    (
        for ((seconds = 0; seconds < 30; seconds++)); do
            [[ ! -e "$watchdog_stop_file" ]] || exit 0
            sleep 1
        done
        current_parent=$(ps -o ppid= -p "$watched_pid" 2>/dev/null | tr -d '[:space:]' || true)
        if [[ "$current_parent" == "$$" ]] \
            && [[ "$(ps -o lstart= -p "$watched_pid" 2>/dev/null || true)" == "$watched_start" ]] \
            && kill -TERM "$watched_pid" 2>/dev/null; then
            for ((seconds = 0; seconds < 5; seconds++)); do
                [[ ! -e "$watchdog_stop_file" ]] || exit 0
                sleep 1
            done
            current_parent=$(ps -o ppid= -p "$watched_pid" 2>/dev/null | tr -d '[:space:]' || true)
            if [[ "$current_parent" == "$$" ]] \
                && [[ "$(ps -o lstart= -p "$watched_pid" 2>/dev/null || true)" == "$watched_start" ]]; then
                kill -KILL "$watched_pid" 2>/dev/null || true
            fi
        fi
    ) &
    cancellation_watchdog_pid=$!
}

# shellcheck disable=SC2329
handle_signal() {
    local status=$1
    if [[ "$pending_signal" != 0 ]]; then
        return
    fi
    if [[ "$driver_launch_pending" == 1 || -n "$driver_pid" ]]; then
        if [[ "$pending_signal" == 0 ]]; then
            pending_signal=$status
        fi
        if [[ -n "$driver_pid" ]]; then
            start_cancellation_watchdog
        fi
        return
    fi
    exit "$status"
}
trap cleanup EXIT
trap 'handle_signal 130' INT
trap 'handle_signal 143' TERM
trap 'handle_signal 129' HUP

temporary_root=$(mktemp -d "${TMPDIR:-/tmp}/macmerge-packaged-ui.XXXXXX")
app="$temporary_root/MacMerge.app"
staged_driver="$runtime_directory/PackagedUISmoke.staged.$$"
pid_file="$temporary_root/launched-pids"
launch_intent="$temporary_root/launch-intent"
cancellation_file="$temporary_root/cancel"
watchdog_stop_file="$temporary_root/watchdog-stop"

OUTPUT_DIR="$temporary_root" \
    BUNDLE_IDENTIFIER="$bundle_identifier" \
    SWIFT_SCRATCH_PATH="$runtime_directory/build" \
    "$package_root/Scripts/package-app.sh" >/dev/null

if [[ -L "$driver" ]]; then
    echo "Refusing symlinked packaged UI smoke driver: $driver" >&2
    exit 1
fi
driver_fingerprint=$(
    {
        shasum -a 256 "$package_root/Scripts/packaged-ui-smoke.swift"
        xcrun swiftc --version
        printf '%s\n' '-swift-version 6 -parse-as-library -warnings-as-errors AppKit ApplicationServices ad-hoc-sign-v1'
    } | shasum -a 256 | cut -d ' ' -f 1
)
cached_fingerprint=""
if [[ -f "$driver_fingerprint_file" ]]; then
    IFS= read -r cached_fingerprint < "$driver_fingerprint_file" || true
fi
if [[ ! -f "$driver" || ! -x "$driver" || "$cached_fingerprint" != "$driver_fingerprint" ]]; then
    xcrun swiftc \
        -swift-version 6 \
        -parse-as-library \
        -warnings-as-errors \
        "$package_root/Scripts/packaged-ui-smoke.swift" \
        -framework AppKit \
        -framework ApplicationServices \
        -o "$staged_driver"
    codesign --force --sign - --identifier io.github.egigoka.MacMerge.PackagedUISmoke "$staged_driver"
    chmod 700 "$staged_driver"
    mv -f "$staged_driver" "$driver"
    printf '%s\n' "$driver_fingerprint" > "$driver_fingerprint_file"
fi
chmod 700 "$driver"

driver_launch_pending=1
: > "$completion_guard"
"$driver" "$app" "$pid_file" "$launch_intent" "$completion_guard" "$cancellation_file" "$bundle_identifier" &
driver_pid=$!
driver_launch_pending=0
if [[ "$pending_signal" != 0 ]]; then
    start_cancellation_watchdog
fi
driver_status=0
while true; do
    set +e
    wait "$driver_pid"
    driver_status=$?
    set -e
    driver_running=0
    while IFS= read -r job_pid; do
        if [[ "$job_pid" == "$driver_pid" ]]; then
            driver_running=1
            break
        fi
    done < <(jobs -pr)
    if [[ "$driver_running" == 1 ]]; then
        continue
    fi
    break
done
driver_pid=""
if [[ "$cancellation_watchdog_pid" =~ ^[0-9]+$ ]]; then
    watchdog_pid="$cancellation_watchdog_pid"
    cancellation_watchdog_pid=""
    : > "$watchdog_stop_file"
    wait "$watchdog_pid" 2>/dev/null || true
fi
cancellation_watchdog_pid=""
if [[ "$pending_signal" != 0 ]]; then
    exit "$pending_signal"
fi
exit "$driver_status"
