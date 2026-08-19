#!/bin/bash
# shellcheck disable=SC2016

set -euo pipefail

package_root=$(cd "$(dirname "$0")/.." && pwd)
design="$package_root/EXTENSION_DESIGN.md"

[[ -f "$design" ]] || {
    printf 'Extension design contract missing: %s\n' "$design" >&2
    exit 1
}

document=$(LC_ALL=C tr '\n' ' ' <"$design" | LC_ALL=C tr -s '[:space:]' ' ')

require_contract() {
    local contract=$1
    shift

    local fragment
    for fragment in "$@"; do
        if [[ $document != *"$fragment"* ]]; then
            printf 'EXTENSION_DESIGN.md %s contract missing: %s\n' "$contract" "$fragment" >&2
            exit 1
        fi
    done
}

require_contract out-of-process \
    'execute each operation in a fresh, sandboxed runner process' \
    'will not load third-party code into its process' \
    'A slot accepts exactly one authenticated connection and one request' \
    'coordinator never reuses the slot until it observes the deliberate-exit XPC interruption'

require_contract audit-identity \
    'Before resuming/activating either `NSXPCConnection`, each side installs an exact build-generated code-signing requirement' \
    'expected runner identifier, MacMerge Team ID, signing anchor, and build-specific CDHash' \
    'runner symmetrically requires those exact facts for its containing MacMerge app build' \
    "peer identity carried by the connection's audit token; application code does not claim direct access to the token" \
    'reject a mismatched, ad-hoc, or re-signed peer on its first post-activation message' \
    'No manifest/module/document frame is created or sent until that handshake returns successfully'

require_contract exact-entitlements \
    'release runner'\''s entitlement dictionary is exactly `{"com.apple.security.app-sandbox": true}`' \
    'no `com.apple.security.inherit`, network, user-selected-file, bookmark, app-group, automation, temporary-exception, JIT, debugger, or Keychain entitlement' \
    '`JoinExistingSession` absent or `false`' \
    'Debug runners with broader signing or entitlements cannot run third-party packages' \
    'Assert each release runner entitlement dictionary equals exactly `{"com.apple.security.app-sandbox": true}`'

require_contract no-ambient-authority \
    'Extension code has no ambient filesystem, network, process, clipboard, Keychain, camera, microphone, location, or Apple-event access' \
    'never security-scoped bookmarks, paths, file descriptors, environment variables, or app objects' \
    'Modules cannot import WASI, clocks, randomness, sockets, filesystem calls, process calls, environment variables' \
    'Verify it cannot open known files outside its own sandbox or connect to local/network sockets'

require_contract per-action-quotas \
    'Each action has a hard aggregate quota of 128 keys and 64 KiB encoded values' \
    'each package has a 512 KiB aggregate quota across actions and installed versions' \
    'at most 64 schema-valid proposed mutations totaling 64 KiB' \
    'action/package quotas remain satisfied' \
    'with a 1 GiB per-action quota, 2 GiB per-document quota, and 4 GiB app-wide quota' \
    'Before work starts MacMerge reserves quota and checks available capacity'

require_contract bounded-framing \
    'at most 1 MiB of schema-computable logical fields per object' \
    '256 KiB per nonempty data chunk' \
    'sixteen unacknowledged frames' \
    '2 MiB of logical in-flight data in each direction' \
    'Receiver checks after allowlisted decode are defense in depth' \
    'Acknowledgement backpressure stops the sender at either in-flight limit' \
    'No content frame is accepted before peer authentication completes' \
    'framing ceilings apply before action-specific stream limits'

require_contract complete-round-trip \
    'sealed round-trip record containing the exact pre-stage input bytes, publisher key, package ID/version/digest, action ID, signed operation contracts' \
    'protocol and ABI versions, pane role, input/output content types, basename and encoding context, typed parameters, preference snapshot and revision' \
    'optional immutable time context, output digest, and token' \
    'Pack reuses that record exactly; current settings, names, matching results, preferences, and defaults cannot replace any pinned value' \
    'pre-stage input bytes and edited unpacked bytes as separate immutable streams plus the token' \
    'including the original archive stream and archive-unpack context' \
    'Archive pack receives that original archive byte stream, token, pinned context, and edited virtual model' \
    "including that stage's exact pre-stage byte stream, not merely document-level original bytes" \
    'each stage its own retained pre-stage stream, edited output of the next stage, token, and pinned context' \
    'complete context pinning, each pre-stage original stream, reverse pack order'

require_contract ancestor-validation \
    'hierarchy conflicts. Every non-root ancestor of an entry must itself appear exactly once as a canonical `directory`' \
    'a regular file can never be an ancestor of another entry' \
    'file-as-ancestor conflicts'

require_contract one-way-unpackers \
    'An unpack-only action may declare only `unpack`, but is comparison-only' \
    'its output can enter neither editable nor normal save state' \
    'explicit export of transformed content to a new user-selected file with a format warning' \
    'same comparison-only rule but produces no token or save state' \
    'Prediff and unpack-only pipelines are one-way and never enter save state' \
    'One-way unpack fixtures remain comparison-only'

require_contract deterministic-host-timestamp \
    '`context.invocation-time` | One immutable host-formatted instant, locale, and time zone | manual time-insertion editor actions' \
    'one host-produced immutable time context containing the UTC instant, BCP 47 locale, IANA time zone, preformatted date and time strings, and host formatting-specification version' \
    'The runner has no clock import' \
    'retries/replays of the same request see identical values'

byte_input_pattern='unpack: one ([0-9]+) MiB source; pack: one ([0-9]+) MiB original plus one ([0-9]+) MiB edited stream \(([0-9]+) MiB aggregate\)'
archive_input_pattern='archive-unpack: one ([0-9]+) MiB archive; archive-pack: one ([0-9]+) MiB original archive plus one ([0-9]+) MiB tree \(([0-9]+) MiB aggregate\)'
output_pattern='unpack: ([0-9]+) MiB; pack: ([0-9]+) MiB.*archive-unpack: ([0-9]+) MiB tree; archive-pack: ([0-9]+) MiB archive'

[[ $document =~ $byte_input_pattern ]] || {
    printf 'EXTENSION_DESIGN.md size-consistency contract missing byte input limits\n' >&2
    exit 1
}
byte_unpack_input=${BASH_REMATCH[1]}
byte_pack_original=${BASH_REMATCH[2]}
byte_pack_edited=${BASH_REMATCH[3]}
byte_pack_aggregate=${BASH_REMATCH[4]}

[[ $document =~ $archive_input_pattern ]] || {
    printf 'EXTENSION_DESIGN.md size-consistency contract missing archive input limits\n' >&2
    exit 1
}
archive_unpack_input=${BASH_REMATCH[1]}
archive_pack_original=${BASH_REMATCH[2]}
archive_pack_tree=${BASH_REMATCH[3]}
archive_pack_aggregate=${BASH_REMATCH[4]}

[[ $document =~ $output_pattern ]] || {
    printf 'EXTENSION_DESIGN.md size-consistency contract missing output limits\n' >&2
    exit 1
}
byte_unpack_output=${BASH_REMATCH[1]}
byte_pack_output=${BASH_REMATCH[2]}
archive_unpack_output=${BASH_REMATCH[3]}
archive_pack_output=${BASH_REMATCH[4]}

if ((byte_unpack_input != 128 || byte_pack_original != 128 || byte_pack_edited != 128 || byte_pack_aggregate != 256 ||
    archive_unpack_input != 128 || archive_pack_original != 128 || archive_pack_tree != 512 || archive_pack_aggregate != 640 ||
    byte_unpack_output != 128 || byte_pack_output != 128 || archive_unpack_output != 512 || archive_pack_output != 128 ||
    byte_pack_original + byte_pack_edited != byte_pack_aggregate ||
    archive_pack_original + archive_pack_tree != archive_pack_aggregate ||
    byte_unpack_input != byte_pack_original || byte_unpack_output != byte_pack_edited || byte_pack_output != byte_unpack_input ||
    archive_unpack_input != archive_pack_original || archive_unpack_output != archive_pack_tree || archive_pack_output != archive_unpack_input)); then
    printf 'EXTENSION_DESIGN.md round-trip input/output limits are inconsistent\n' >&2
    exit 1
fi

printf 'EXTENSION_DESIGN.md security contracts verified\n'
