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
if [[ -e "$runtime_directory/lock" && ! -f "$runtime_directory/lock" ]]; then
    echo "Refusing non-regular packaged UI smoke lock: $runtime_directory/lock" >&2
    exit 1
fi
for state_path in \
    "$runtime_directory/lock" \
    "$runtime_directory/active.lock" \
    "$runtime_directory/orphan" \
    "$runtime_directory/PackagedUISmoke" \
    "$runtime_directory/PackagedUISmoke.fingerprint" \
    "$runtime_directory/build"; do
    if [[ -L "$state_path" ]] || { [[ -e "$state_path" ]] && [[ ! -O "$state_path" ]]; }; then
        echo "Refusing untrusted packaged UI smoke state: $state_path" >&2
        exit 1
    fi
done

package_root=$(cd "$(dirname "$0")/.." && pwd)
bundle_identifier="io.github.egigoka.MacMerge.UISmoke.Automated"
completion_guard="$runtime_directory/orphan"
container_parent="$HOME/Library/Containers"
container="$HOME/Library/Containers/$bundle_identifier"
driver="$runtime_directory/PackagedUISmoke"
driver_fingerprint_file="$runtime_directory/PackagedUISmoke.fingerprint"
lock_directory="$runtime_directory/active.lock"

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
lock_acquired=0
lock_acquisition_pending=0
legacy_lock_open=0
shared_state_owned=0
completion_guard_created=0

# shellcheck disable=SC2329
cleanup() {
    trap '' INT TERM HUP
    local original_status=$1
    local cleanup_status=0
    local preserve_state=0
    local watchdog_pid=""
    set +e
    trap - EXIT
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
        preserve_state=1
    fi
    if [[ "$preserve_state" == 0 ]]; then
        if [[ "$shared_state_owned" == 1 && "$completion_guard_created" == 1 ]]; then
            rm -f "$completion_guard" || cleanup_status=1
            if [[ "$bundle_identifier" == "io.github.egigoka.MacMerge.UISmoke.Automated" ]] \
                && { [[ -e "$container/Data" ]] || [[ -L "$container/Data" ]]; }; then
                echo "Packaged UI smoke driver did not remove isolated data at $container/Data." >&2
                cleanup_status=1
            fi
            if [[ -n "$staged_driver" ]]; then
                rm -f "$staged_driver" || cleanup_status=1
            fi
        fi
        if [[ -n "$temporary_root" ]]; then
            rm -rf "$temporary_root" || cleanup_status=1
        fi
    fi
    if [[ "$lock_acquired" == 1 ]]; then
        rmdir "$lock_directory" 2>/dev/null || cleanup_status=1
    fi
    if [[ "$legacy_lock_open" == 1 ]]; then
        exec 9>&-
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
        exec 9>&-
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
    if [[ "$lock_acquisition_pending" == 1 || "$driver_launch_pending" == 1 || -n "$driver_pid" ]]; then
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
trap 'cleanup $?' EXIT
trap 'handle_signal 130' INT
trap 'handle_signal 143' TERM
trap 'handle_signal 129' HUP

lock_acquisition_pending=1
lock_status=0
set +e
(trap '' INT TERM HUP; mkdir "$lock_directory") 2>/dev/null
lock_status=$?
set -e
if [[ "$lock_status" == 0 ]]; then
    lock_acquired=1
fi
lock_acquisition_pending=0
if [[ "$pending_signal" != 0 ]]; then
    exit "$pending_signal"
fi
if [[ "$lock_status" != 0 ]]; then
    if [[ -L "$lock_directory" ]]; then
        echo "Refusing symlinked packaged UI smoke lock: $lock_directory" >&2
    elif [[ -d "$lock_directory" ]]; then
        echo "Another packaged UI smoke is already running. If no run is active, inspect and remove stale lock directory $lock_directory." >&2
    else
        echo "Could not acquire packaged UI smoke lock at $lock_directory." >&2
    fi
    exit 1
fi

exec 9>>"$runtime_directory/lock"
legacy_lock_open=1
if [[ ! -f /dev/fd/9 ]] || [[ ! -O /dev/fd/9 ]]; then
    echo "Refusing untrusted packaged UI smoke lock: $runtime_directory/lock" >&2
    exit 1
fi
chmod 600 /dev/fd/9
set +e
/usr/bin/lockf -s -t 0 9
legacy_lock_status=$?
set -e
if [[ "$legacy_lock_status" == 75 ]]; then
    echo "Another packaged UI smoke is already running." >&2
    exit 1
elif [[ "$legacy_lock_status" != 0 ]]; then
    echo "Could not acquire packaged UI smoke legacy lock (lockf exited $legacy_lock_status)." >&2
    exit 1
fi
shared_state_owned=1

if [[ -e "$completion_guard" ]]; then
    echo "Previous packaged UI smoke may have left an isolated app running. Inspect bundle $bundle_identifier, then remove $completion_guard." >&2
    exit 1
fi

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
    "$package_root/Scripts/package-app.sh" 9>&- >/dev/null

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
        -o "$staged_driver" \
        9>&-
    codesign --force --sign - --identifier io.github.egigoka.MacMerge.PackagedUISmoke "$staged_driver"
    chmod 700 "$staged_driver"
    mv -f "$staged_driver" "$driver"
    printf '%s\n' "$driver_fingerprint" > "$driver_fingerprint_file"
fi
chmod 700 "$driver"

driver_launch_pending=1
: > "$completion_guard"
completion_guard_created=1
"$driver" "$app" "$pid_file" "$launch_intent" "$completion_guard" "$cancellation_file" "$bundle_identifier" 9>&- &
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
