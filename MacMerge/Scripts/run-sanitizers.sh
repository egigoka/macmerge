#!/bin/bash
#
# Runs the MacMerge test suite under Undefined Behavior Sanitizer and Thread
# Sanitizer. Address Sanitizer already runs as its own CI step.
#
# Usage: Scripts/run-sanitizers.sh [undefined|thread]...
#   With no arguments, runs undefined and then thread.
#
# Environment:
#   SANITIZER_SCRATCH_ROOT  Directory holding one scratch build per sanitizer.
#                           Defaults to <package>/.build/sanitizers.
#   SANITIZER_TEST_FILTER   Optional `swift test --filter` expression. Unset runs
#                           every test target.
#   SANITIZER_TEST_SKIP     Optional `swift test --skip` expression applied after
#                           the filter.
#
# Supported combinations on Apple platforms with SwiftPM:
#   - undefined: instruments the CXDiff C target (xdiff, PCRE2, the bridge).
#     Swift code has no UBSan checks of its own; Swift traps on overflow and
#     out-of-bounds access already. Runs with halt_on_error=1 because UBSan
#     otherwise only logs findings and the run still passes.
#   - thread: instruments Swift and C code together.
#   - thread cannot be combined with address in one build; clang and swiftc
#     reject the pair. undefined could be combined with address, but it runs
#     alone here so each finding names a single sanitizer.
#   - thread keeps the runtime's default strip_env=1, so DYLD_INSERT_LIBRARIES
#     does not leak into git, archive tools or other children the tests spawn.
#     Tests that re-launch the xctest bundle in a child process therefore abort
#     in that child with "Interceptors are not working"; CI skips them through
#     SANITIZER_TEST_SKIP. They still run in the plain and address jobs.
#   - SwiftPM --sanitize accepts only address, thread, undefined, scudo and
#     fuzzer; it offers no memory or leak sanitizer on any platform. scudo is
#     Linux-only, and fuzzer is out of scope for this test runner. All three are
#     rejected with a usage message.
#   - Caller UBSAN_OPTIONS/TSAN_OPTIONS are appended to the script defaults, so
#     they can change any key except halt_on_error, which is always re-applied
#     last as halt_on_error=1 (later keys win).

set -euo pipefail

package_root=$(cd "$(dirname "$0")/.." && pwd)
scratch_root=${SANITIZER_SCRATCH_ROOT:-"$package_root/.build/sanitizers"}
test_filter=${SANITIZER_TEST_FILTER:-}
test_skip=${SANITIZER_TEST_SKIP:-}

usage() {
    echo "usage: $0 [undefined|thread]..." >&2
    exit 64
}

sanitizers=("$@")
if [[ ${#sanitizers[@]} -eq 0 ]]; then
    sanitizers=(undefined thread)
fi

for sanitizer in "${sanitizers[@]}"; do
    case "$sanitizer" in
        undefined | thread) ;;
        address)
            echo "address sanitizer runs as its own CI step: swift test --sanitize address" >&2
            exit 64
            ;;
        *) usage ;;
    esac
done

run_sanitizer() {
    local sanitizer=$1
    local scratch_path="$scratch_root/$sanitizer"
    local arguments=(
        --package-path "$package_root"
        --scratch-path "$scratch_path"
        --sanitize "$sanitizer"
        -Xswiftc -warnings-as-errors
    )
    if [[ -n "$test_filter" ]]; then
        arguments+=(--filter "$test_filter")
    fi
    if [[ -n "$test_skip" ]]; then
        arguments+=(--skip "$test_skip")
    fi

    echo "Running tests with $sanitizer sanitizer (scratch: $scratch_path)"
    case "$sanitizer" in
        undefined)
            UBSAN_OPTIONS="print_stacktrace=1:report_error_type=1${UBSAN_OPTIONS:+:$UBSAN_OPTIONS}:halt_on_error=1" \
                swift test "${arguments[@]}"
            ;;
        thread)
            TSAN_OPTIONS="second_deadlock_stack=1${TSAN_OPTIONS:+:$TSAN_OPTIONS}:halt_on_error=1" \
                swift test "${arguments[@]}"
            ;;
    esac
}

for sanitizer in "${sanitizers[@]}"; do
    run_sanitizer "$sanitizer"
done

echo "Sanitizer runs passed: ${sanitizers[*]}"
