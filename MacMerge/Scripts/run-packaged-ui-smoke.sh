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
chmod 600 "$runtime_directory/lock"
if ! /usr/bin/lockf -s -t 0 9; then
    echo "Another packaged UI smoke is already running." >&2
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

temporary_root=$(mktemp -d "${TMPDIR:-/tmp}/macmerge-packaged-ui.XXXXXX")
app="$temporary_root/MacMerge.app"
staged_driver="$runtime_directory/PackagedUISmoke.staged.$$"
driver_pid=""
driver_launch_pending=0
pending_signal=0
cancellation_watchdog_pid=""
pid_file="$temporary_root/launched-pids"
launch_intent="$temporary_root/launch-intent"
cancellation_file="$temporary_root/cancel"

# shellcheck disable=SC2329
cleanup() {
    local cleanup_status=0
    set +e
    trap - EXIT
    trap '' INT TERM HUP
    if [[ -n "$driver_pid" ]]; then
        echo "Waiting for isolated packaged UI smoke cleanup after interruption." >&2
        wait "$driver_pid" 2>/dev/null || true
    fi
    if [[ -f "$launch_intent" || -s "$pid_file" ]]; then
        echo "Packaged UI smoke may have been interrupted with an isolated app launch in flight; preserving $temporary_root." >&2
        return
    fi
    rm -f "$completion_guard"
    if [[ "$bundle_identifier" == "io.github.egigoka.MacMerge.UISmoke.Automated" ]] \
        && { [[ -e "$container/Data" ]] || [[ -L "$container/Data" ]]; }; then
        echo "Packaged UI smoke driver did not remove isolated data at $container/Data." >&2
        cleanup_status=1
    fi
    rm -f "$staged_driver"
    rm -rf "$temporary_root"
    if [[ "$cleanup_status" != 0 ]]; then
        exit "$cleanup_status"
    fi
}

# shellcheck disable=SC2329
handle_signal() {
    local status=$1
    if [[ "$driver_launch_pending" == 1 || -n "$driver_pid" ]]; then
        if [[ "$pending_signal" == 0 ]]; then
            pending_signal=$status
        fi
        if [[ -n "$driver_pid" ]]; then
            : > "$cancellation_file"
            if [[ -z "$cancellation_watchdog_pid" ]]; then
                (
                    sleep 30
                    kill -TERM "$driver_pid" 2>/dev/null || true
                ) &
                cancellation_watchdog_pid=$!
            fi
        fi
        return
    fi
    exit "$status"
}
trap cleanup EXIT
trap 'handle_signal 130' INT
trap 'handle_signal 143' TERM
trap 'handle_signal 129' HUP

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
    : > "$cancellation_file"
    (
        sleep 30
        kill -TERM "$driver_pid" 2>/dev/null || true
    ) &
    cancellation_watchdog_pid=$!
fi
driver_status=0
while true; do
    set +e
    wait "$driver_pid"
    driver_status=$?
    set -e
    if kill -0 "$driver_pid" 2>/dev/null; then
        continue
    fi
    break
done
driver_pid=""
if [[ -n "$cancellation_watchdog_pid" ]]; then
    kill "$cancellation_watchdog_pid" 2>/dev/null || true
    wait "$cancellation_watchdog_pid" 2>/dev/null || true
fi
if [[ "$pending_signal" != 0 ]]; then
    exit "$pending_signal"
fi
exit "$driver_status"
