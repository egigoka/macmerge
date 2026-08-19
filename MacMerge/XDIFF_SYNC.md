# XDiff Synchronization

## Source of truth

MacMerge follows the xdiff copy bundled by WinMerge, not `git/git` directly. Keep the
WinMerge snapshot and MacMerge-only fixes as separate reviewable layers:

| Field | Pinned value |
| --- | --- |
| Upstream repository | `https://github.com/WinMerge/winmerge.git` |
| Upstream branch | `master` |
| Upstream path | `Externals/xdiff` |
| Pinned xdiff snapshot | `7a3e1ec3efcc0ebad2034f72d8f87a6c74d62301` (2026-02-03) |
| Pinned snapshot tree | `bf7ade8ccf4199ab85649c5aac4474b14e44f55f` |
| Initial WinMerge import | `868be2fe127bb2a21073def6bf73f24d0ad5aff3` (2019-04-14) |
| Original Git xdiff commit | `611e42a5980a3a9f8bb3b1b49c1abde63c7a191e` (2018-11-02) |
| MacMerge patch base | `7a3e1ec3efcc0ebad2034f72d8f87a6c74d62301` |
| Current patched tree | `a2f958abe94a14a95200c911be748cd3f9b7e9f0` |
| Historical synchronization identity | No standalone sync commit; `7a3e1ec3efcc0ebad2034f72d8f87a6c74d62301` identifies the pristine tree |
| Historical patch introduction | `40d8b10d0928bc415e6c3febd2dab2f6daff1a5c` (2026-08-06; also introduces the complete native port, so it is not a standalone patch commit) |

The complete vendor snapshot is `Externals/xdiff`, including `COPYING` and
per-file notices. Preserve them; files do not all carry the same notice.

`Externals/versions.txt`, added by the initial WinMerge import, pins LibXDiff to
short object name `611e42a` on 2018-11-02. It resolves to the full Git commit
above. Imported file names and blobs match `611e42a:xdiff` except for one
portability delta in `xinclude.h`: WinMerge changed `#include <unistd.h>` to
`/*#include <unistd.h>*/`. WinMerge commit
`32d2f48cbfff1b85a483ad4ddcde6c43ec8fcf8c` later replaced that comment with an
`#ifndef _WIN32` include and added the `xdl_diff_modified` declaration. Both are
WinMerge lineage, not MacMerge patches.

This validator proves the original pin, recursive file inventory, equal
non-`xinclude.h` blobs, and exact one-line import delta:

```bash
set -euo pipefail
GIT_URL=https://github.com/git/git.git
GIT_COMMIT=611e42a5980a3a9f8bb3b1b49c1abde63c7a191e
WINMERGE_IMPORT=868be2fe127bb2a21073def6bf73f24d0ad5aff3
tmp=$(mktemp -d -t macmerge-git-xdiff.XXXXXX)
trap 'rm -rf "$tmp"' EXIT
git clone --quiet --filter=blob:none --no-checkout "$GIT_URL" "$tmp/git"
test "$(git show "$WINMERGE_IMPORT:Externals/versions.txt" |
  perl -ne 'if (/LibXDiff:\s+([0-9a-f]+)\s+on Nov 2, 2018/) { print "$1\n"; exit }')" = \
  "${GIT_COMMIT:0:7}"
test "$(git ls-tree -r --name-only "$WINMERGE_IMPORT:Externals/xdiff")" = \
  "$(git -C "$tmp/git" ls-tree -r --name-only "$GIT_COMMIT:xdiff")"
for file in $(git ls-tree -r --name-only "$WINMERGE_IMPORT:Externals/xdiff"); do
  test "$file" = xinclude.h && continue
  test "$(git rev-parse "$WINMERGE_IMPORT:Externals/xdiff/$file")" = \
    "$(git -C "$tmp/git" rev-parse "$GIT_COMMIT:xdiff/$file")"
done
git -C "$tmp/git" show "$GIT_COMMIT:xdiff/xinclude.h" > "$tmp/git-xinclude.h"
git show "$WINMERGE_IMPORT:Externals/xdiff/xinclude.h" > "$tmp/winmerge-xinclude.h"
test "$(perl -ne '$n++ if /^#include <unistd\.h>$/; END { print "$n\n" }' \
  "$tmp/git-xinclude.h")" = 1
perl -pe 's{^#include <unistd\.h>$}{/*#include <unistd.h>*/}' \
  "$tmp/git-xinclude.h" > "$tmp/expected-xinclude.h"
cmp "$tmp/expected-xinclude.h" "$tmp/winmerge-xinclude.h"
rm -rf "$tmp"
trap - EXIT
```

Derive the latest WinMerge path commit instead of copying repository HEAD. Trust
an existing remote only after its fetch URL exactly matches the pinned HTTPS URL:

```bash
set -euo pipefail
UPSTREAM_URL=https://github.com/WinMerge/winmerge.git
remote_urls=$(git config --get-all remote.winmerge-upstream.url || true)
if test -n "$remote_urls"; then
  test "$remote_urls" = "$UPSTREAM_URL" || {
    printf 'unexpected winmerge-upstream URL: %s\n' "$remote_urls" >&2
    exit 1
  }
else
  git remote add winmerge-upstream "$UPSTREAM_URL"
fi
test "$(git remote get-url winmerge-upstream)" = "$UPSTREAM_URL"
git fetch --no-tags winmerge-upstream \
  refs/heads/master:refs/remotes/winmerge-upstream/master
git log -1 --format='%H %cI %s' winmerge-upstream/master -- Externals/xdiff
```

## Compilation boundary

`Externals/xdiff/xdiff.vcxitems` is the authoritative WinMerge translation-unit
inventory; WinMerge adapts it through `Src/xdiff_gnudiff_compat.cpp`. SwiftPM
discovers C files recursively under `MacMerge/Sources/CXDiff` through
`MacMerge/Package.swift`. These seven shims compile upstream translation units
directly:

| MacMerge shim | WinMerge source |
| --- | --- |
| `MacMerge/Sources/CXDiff/vendor_xdiffi.c` | `Externals/xdiff/xdiffi.c` |
| `MacMerge/Sources/CXDiff/vendor_xemit.c` | `Externals/xdiff/xemit.c` |
| `MacMerge/Sources/CXDiff/vendor_xhistogram.c` | `Externals/xdiff/xhistogram.c` |
| `MacMerge/Sources/CXDiff/vendor_xnone.c` | `Externals/xdiff/xnone.c` |
| `MacMerge/Sources/CXDiff/vendor_xpatience.c` | `Externals/xdiff/xpatience.c` |
| `MacMerge/Sources/CXDiff/vendor_xprepare.c` | `Externals/xdiff/xprepare.c` |
| `MacMerge/Sources/CXDiff/vendor_xutils.c` | `Externals/xdiff/xutils.c` |

`Externals/xdiff/xmerge.c` is intentionally unwrapped; the public API in
`MacMerge/Sources/CXDiff/include/macmerge_xdiff.h` exposes diff, not xmerge.
`MacMerge/Sources/CXDiff/macmerge_xdiff_allocator.h` redirects vendor allocation
through the bridge. `MacMerge/Sources/CXDiff/macmerge_xdiff.c` owns input limits,
failure cleanup, hunk collection, and ABI flag assertions. Changes in those files
are adapter changes, not vendor patches.

`MacMerge/Tests/MacMergeCoreTests/XDiffSourceManifestTests.swift` checks the current
shim mapping and SwiftPM discovery, but its duplicated top-level source list is not
authoritative. During every update, derive the Windows set from `ClCompile` entries,
scan the vendor tree recursively, and compare both with recursively discovered shim
includes. The current sole deliberate exclusion is `xmerge.c`. Any source addition,
removal, rename, nesting change, duplicate include, or exclusion change must update
the shims, this list, and the test; when changing the test, make it parse
`xdiff.vcxitems` rather than adding another source-list authority.

Run this inventory gate from repository root against the worktree under review:

```bash
set -euo pipefail
vcx_sources=$(mktemp -t macmerge-xdiff-vcx.XXXXXX)
tree_sources=$(mktemp -t macmerge-xdiff-tree.XXXXXX)
wrapped_sources=$(mktemp -t macmerge-xdiff-wrapped.XXXXXX)
mac_sources=$(mktemp -t macmerge-xdiff-mac.XXXXXX)
trap 'rm -f "$vcx_sources" "$tree_sources" "$wrapped_sources" "$mac_sources"' EXIT
xmllint --xpath '//*[local-name()="ClCompile"]/@Include' \
  Externals/xdiff/xdiff.vcxitems |
  perl -ne 'while (/Include="\$\(MSBuildThisFileDirectory\)([^\"]+\.c)"/g) {
    $p=$1; $p =~ s!\\!/!g; print "$p\n"
  }' | LC_ALL=C sort > "$vcx_sources"
test -s "$vcx_sources"
/usr/bin/find Externals/xdiff -type f -name '*.c' -print |
  perl -pe 's!^Externals/xdiff/!!' | LC_ALL=C sort > "$tree_sources"
cmp "$vcx_sources" "$tree_sources"
/usr/bin/find MacMerge/Sources/CXDiff -type f -name '*.c' \
  -exec perl -ne 'if (m{^\s*#\s*include\s+"(?:\.\./)+Externals/xdiff/(.+\.c)"\s*$}) {
    print "$1\n"
  }' {} + | LC_ALL=C sort > "$wrapped_sources"
{
  printf '%s\n' xmerge.c
  /bin/cat "$wrapped_sources"
} | LC_ALL=C sort > "$mac_sources"
cmp "$vcx_sources" "$mac_sources"
rm -f "$vcx_sources" "$tree_sources" "$wrapped_sources" "$mac_sources"
trap - EXIT
```

## Local patch inventory

This inventory is exactly the vendor delta from the pinned patch base. Keep each
future delta here and in a MacMerge patch commit; never hide one in an upstream
snapshot commit.

| Vendor file | MacMerge-only change | Status |
| --- | --- | --- |
| `Externals/xdiff/xdiff.h` | Guard `xdl_malloc`, `xdl_realloc`, and `xdl_free` so the bridge can inject its allocator. | Retain until WinMerge supplies an equivalent override mechanism. |
| `Externals/xdiff/xhistogram.c` | Check allocation-size arithmetic and invalid counts; release prepared environment after histogram errors. | Retain for overflow and allocation-failure safety. |
| `Externals/xdiff/xpatience.c` | Propagate longest-sequence allocation failure and release prepared environment after patience errors. | Retain for deterministic failure cleanup. |
| `Externals/xdiff/xprepare.c` | Stop suffix trimming when the common prefix consumed the shorter input. | Retain for identical-input bounds safety. |
| `Externals/xdiff/xutils.c` | Avoid an end-pointer EOL read; classify CR-, LF-, and CRLF-only lines as blank without treating terminators as content; keep one-byte unterminated content nonblank when no whitespace-ignore flag is set. | Retain for bounds and blank-line parity. |

The pinned `xutils.c` blob is `5b4a13023622696784b59e89d7119256455c1a77`;
the patched blob is `3735708107f8e6787143673cb6addffd6ea3588b`.
Audit the human-readable inventory mechanically:

```bash
git diff --stat 7a3e1ec3efcc0ebad2034f72d8f87a6c74d62301 HEAD -- Externals/xdiff
git diff 7a3e1ec3efcc0ebad2034f72d8f87a6c74d62301 HEAD -- Externals/xdiff
```

Expected changed files are exactly the five rows above. Wrapper and bridge files
must not appear in this vendor-delta command.

This machine-failing validator proves complete recursive vendor identity, exact
changed-file set, and reversibility of the recorded patch. Git tree IDs cover every
tracked path, mode, and blob, including project manifests, headers, license text,
and notices. During an update, run it with candidate values from the completed sync
and patch commits before recording those same values in the metadata commit:

```bash
set -euo pipefail
PATCH_BASE=7a3e1ec3efcc0ebad2034f72d8f87a6c74d62301
SYNC_COMMIT=7a3e1ec3efcc0ebad2034f72d8f87a6c74d62301
PATCH_COMMIT=40d8b10d0928bc415e6c3febd2dab2f6daff1a5c
FINAL_COMMIT=HEAD
PINNED_TREE=bf7ade8ccf4199ab85649c5aac4474b14e44f55f
PATCHED_TREE=a2f958abe94a14a95200c911be748cd3f9b7e9f0
test "$(git rev-parse "$PATCH_BASE:Externals/xdiff")" = "$PINNED_TREE"
test "$(git rev-parse "$SYNC_COMMIT:Externals/xdiff")" = "$PINNED_TREE"
test "$(git rev-parse "$PATCH_COMMIT:Externals/xdiff")" = "$PATCHED_TREE"
test "$(git rev-parse "$PATCH_COMMIT^:Externals/xdiff")" = "$PINNED_TREE"
test "$(git rev-parse "$FINAL_COMMIT:Externals/xdiff")" = "$PATCHED_TREE"
expected_files=$(mktemp -t macmerge-xdiff-files.XXXXXX)
actual_files=$(mktemp -t macmerge-xdiff-actual.XXXXXX)
patch_file=$(mktemp -t macmerge-xdiff-final.XXXXXX.patch)
temp_index=$(mktemp -t macmerge-xdiff-index.XXXXXX)
rm "$temp_index"
trap 'rm -f "$expected_files" "$actual_files" "$patch_file" "$temp_index"' EXIT
printf '%s\n' \
  Externals/xdiff/xdiff.h \
  Externals/xdiff/xhistogram.c \
  Externals/xdiff/xpatience.c \
  Externals/xdiff/xprepare.c \
  Externals/xdiff/xutils.c > "$expected_files"
git diff --name-only "$PATCH_BASE" "$PATCH_COMMIT" -- Externals/xdiff |
  LC_ALL=C sort > "$actual_files"
cmp "$expected_files" "$actual_files"
git diff --binary "$PATCH_BASE" "$PATCH_COMMIT" -- Externals/xdiff > "$patch_file"
test -s "$patch_file"
GIT_INDEX_FILE="$temp_index" git read-tree "$PATCH_COMMIT"
GIT_INDEX_FILE="$temp_index" git apply --cached --check --reverse "$patch_file"
GIT_INDEX_FILE="$temp_index" git apply --cached --reverse "$patch_file"
test "$(GIT_INDEX_FILE="$temp_index" git write-tree --prefix=Externals/xdiff/)" = \
  "$PINNED_TREE"
rm -f "$expected_files" "$actual_files" "$patch_file" "$temp_index"
trap - EXIT
```

## Update procedure

Use one shell for variables and temporary patch paths below.

1. Start a dedicated branch. The entire Git index must be empty before update
   staging. Unrelated work may remain unstaged outside the update scope, but the
   complete update scope must be clean:

   ```bash
   set -euo pipefail
   git switch -c sync-winmerge-xdiff
   UPDATE_SCOPE=(
     Externals/xdiff
     MacMerge/Package.swift
     MacMerge/Sources/CXDiff
     MacMerge/Tests/MacMergeCoreTests/XDiffSourceManifestTests.swift
     MacMerge/Tests/MacMergeCoreTests/XDiffRuntimeRouteTests.swift
     MacMerge/XDIFF_SYNC.md
     .github/workflows/macmerge.yml
   )
   git diff --cached --quiet
   test -z "$(git diff --cached --name-only)"
   test -z "$(git status --porcelain=v1 -- "${UPDATE_SCOPE[@]}")"
   ```

2. Fetch WinMerge and derive the new path commit with the command under Source of
   truth. Set `OLD_BASE` from the pinned patch base and `NEW_BASE` from that result.
   Review upstream-only movement before touching the worktree:

   ```bash
   OLD_BASE=7a3e1ec3efcc0ebad2034f72d8f87a6c74d62301
   NEW_BASE=$(git log -1 --format=%H winmerge-upstream/master -- Externals/xdiff)
   test -n "$NEW_BASE"
   git diff --stat "$OLD_BASE" "$NEW_BASE" -- Externals/xdiff
   git diff "$OLD_BASE" "$NEW_BASE" -- Externals/xdiff
   ```

3. Export the current MacMerge patch layer and retain it until CI passes:

   ```bash
   patch_file=$(mktemp -t macmerge-xdiff.XXXXXX.patch)
   git diff --binary "$OLD_BASE" HEAD -- Externals/xdiff > "$patch_file"
   test -s "$patch_file"
   git apply --check --reverse "$patch_file"
   git apply --cached --check --reverse "$patch_file"
   ```

4. Replace `Externals/xdiff` from `NEW_BASE`, stage the complete directory, review
   it, and commit only the pristine WinMerge synchronization. Do not squash this
   commit with MacMerge fixes:

   ```bash
   git restore --source="$NEW_BASE" --worktree -- Externals/xdiff
   git add -A Externals/xdiff
   git diff --cached --check
   test -n "$(git diff --cached --name-only)"
   test "$(git diff --cached --name-only)" = \
     "$(git diff --cached --name-only -- Externals/xdiff)"
   git diff --cached --stat
   git diff --cached
   git diff --cached --stat -- Externals/xdiff
   git diff --cached -- Externals/xdiff
   git diff --quiet -- Externals/xdiff
   git commit -m "Sync xdiff from WinMerge at ${NEW_BASE:0:12}"
   SYNC_COMMIT=$(git rev-parse HEAD)
   git diff --cached --quiet
   test -z "$(git diff --cached --name-only)"
   ```

5. Reapply the saved layer in a second commit. Resolve conflicts using the rules
   below, restage the complete vendor directory because `git apply --3way` stages
   successful paths, and validate the staged patch rather than only the worktree:

   ```bash
   git apply --3way "$patch_file"
   # Resolve conflicts without choosing ours/theirs for a complete vendor file.
   git add -A Externals/xdiff
   git diff --cached --check
   git diff --quiet -- Externals/xdiff
   test -n "$(git diff --cached --name-only)"
   test "$(git diff --cached --name-only)" = \
     "$(git diff --cached --name-only -- Externals/xdiff)"
   git diff --cached --stat
   git diff --cached
   git diff --cached "$NEW_BASE" --stat -- Externals/xdiff
   git diff --cached "$NEW_BASE" -- Externals/xdiff
   rebased_patch=$(mktemp -t macmerge-xdiff-rebased.XXXXXX.patch)
   git diff --cached --binary "$NEW_BASE" -- Externals/xdiff > "$rebased_patch"
   test -s "$rebased_patch"
   git apply --cached --check --reverse "$rebased_patch"
   git commit -m "Reapply MacMerge xdiff fixes"
   PATCH_COMMIT=$(git rev-parse HEAD)
   git diff --cached --quiet
   test -z "$(git diff --cached --name-only)"
   ```

6. Run the authoritative recursive inventory gate under Compilation boundary.
   For every source change, add or remove a direct shim, or record a deliberate
   exclusion. Update the manifest test so it consumes `xdiff.vcxitems`, update ABI
   constants and assertions only when upstream flags changed, and add focused
   regression tests for behavior changes. Stage compatibility files explicitly,
   inspect the full cached diff, and commit them separately if any changed:

   ```bash
   git add -A MacMerge/Package.swift MacMerge/Sources/CXDiff \
     MacMerge/Tests/MacMergeCoreTests/XDiffSourceManifestTests.swift \
     MacMerge/Tests/MacMergeCoreTests/XDiffRuntimeRouteTests.swift \
     .github/workflows/macmerge.yml
   if ! git diff --cached --quiet; then
     git diff --cached --check
     git diff --cached --stat
     git diff --cached
     git commit -m "Reconcile MacMerge xdiff adapters"
     COMPAT_COMMIT=$(git rev-parse HEAD)
   fi
   git diff --cached --quiet
   test -z "$(git diff --cached --name-only)"
   ```

7. Compute candidate pinned and patched tree IDs from `SYNC_COMMIT` and
   `PATCH_COMMIT`, pass them with those commit IDs to the exact identity validator,
   set `FINAL_COMMIT=HEAD` after compatibility/test commits, then run all remaining
   local validation below. Fixes discovered by validation belong in the patch or
   compatibility commit, followed by another complete validation run:

   ```bash
   PINNED_TREE=$(git rev-parse "$SYNC_COMMIT:Externals/xdiff")
   PATCHED_TREE=$(git rev-parse "$PATCH_COMMIT:Externals/xdiff")
   ```

8. Last, use one metadata-only commit to update the pinned snapshot, snapshot tree,
   patch base, patched tree, sync and patch commit identities, compatibility commit
   identities, inventory, and rollback ledger in this document. A patch commit
   cannot record its own hash without changing that hash. Stage and review only the
   document:

   ```bash
   git add MacMerge/XDIFF_SYNC.md
   git diff --cached --check
   test "$(git diff --cached --name-only)" = MacMerge/XDIFF_SYNC.md
   git diff --cached --stat
   git diff --cached
   git commit -m "Record xdiff synchronization metadata"
   METADATA_COMMIT=$(git rev-parse HEAD)
   git diff --cached --quiet
   test -z "$(git diff --cached --name-only)"
   ```

Keep `SYNC_COMMIT`, `PATCH_COMMIT`, every compatibility/test commit, and
`METADATA_COMMIT` in the update review record. Keep `patch_file` and
`rebased_patch` until both-platform CI passes.

## Conflict handling

- If WinMerge contains an equivalent fix, drop the local hunk and its inventory
  row; cite the WinMerge commit in the patch commit message.
- If behavior overlaps but is not equivalent, port the smallest remaining fix and
  add a focused regression test. Never choose ours/theirs for a whole vendor file.
- If source layout changes, keep shims limited to diagnostics plus allocator setup
  and one direct include. Do not copy vendor implementation into a shim.
- If public flags, callback contracts, ownership, or error returns change, update
  `MacMerge/Sources/CXDiff/include/macmerge_xdiff.h` and
  `MacMerge/Sources/CXDiff/macmerge_xdiff.c` together. Treat silent fallback or a
  leak as a failed synchronization.
- If license text or file notices change, carry upstream text unchanged and stop
  review until distribution obligations are understood.
- If intent cannot be proven from upstream history or tests, stop the update and
  open a focused follow-up; do not guess compatibility.

## Validation

Run from repository root unless a command changes directory:

```bash
set -euo pipefail
test -f Externals/xdiff/COPYING
test -z "$(git status --porcelain=v1 -- Externals/xdiff MacMerge/Package.swift \
  MacMerge/Sources/CXDiff \
  MacMerge/Tests/MacMergeCoreTests/XDiffSourceManifestTests.swift \
  MacMerge/Tests/MacMergeCoreTests/XDiffRuntimeRouteTests.swift \
  MacMerge/XDIFF_SYNC.md .github/workflows/macmerge.yml)"
git diff --cached --quiet
test -z "$(git diff --cached --name-only)"
git diff --check
git diff --cached --check
```

Run the recursive inventory gate and exact identity validator above. The identity
validator must use values recorded by the final metadata commit; visual diff or
file count is not a substitute.

```bash
set -euo pipefail
cd MacMerge
swift build --target CXDiff
swift test --filter XDiffSourceManifestTests
swift test --filter XDiffRuntimeRouteTests
swift test -Xswiftc -warnings-as-errors
swift test --sanitize address -Xswiftc -warnings-as-errors
swift build -c release -Xswiftc -warnings-as-errors

c_sources=()
while IFS= read -r source; do
  c_sources+=("$source")
done < <(swift package describe --type json |
  jq -r '.targets[] | select(.name == "CXDiff") |
    .path as $path | .sources[] | select(endswith(".c")) | $path + "/" + .' |
  LC_ALL=C sort)
test "${#c_sources[@]}" -gt 0
described_sources=$(mktemp -t macmerge-cxdiff-described.XXXXXX)
disk_sources=$(mktemp -t macmerge-cxdiff-disk.XXXXXX)
printf '%s\n' "${c_sources[@]}" > "$described_sources"
/usr/bin/find Sources/CXDiff -type f -name '*.c' -print |
  LC_ALL=C sort > "$disk_sources"
cmp "$described_sources" "$disk_sources"
analyzer_flags=(--analyze -std=c11 -Wall -Wextra -Wpedantic -Werror \
  -Xanalyzer -analyzer-werror -I Sources/CXDiff/include \
  -I ../Externals/xdiff -I ../Externals/poco/dependencies/pcre2/src -o /dev/null)
for definition in '' -DDEBUG; do
  for source in "${c_sources[@]}"; do
    extra_flags=()
    test -n "$definition" && extra_flags+=("$definition")
    case "$source" in
      Sources/CXDiff/vendor_pcre2.c|Sources/CXDiff/vendor_xprepare.c)
        # Included vendor code has known dead stores; every other checker stays fatal.
        extra_flags+=(-Xanalyzer -analyzer-disable-checker=deadcode.DeadStores)
        ;;
    esac
    xcrun clang "${analyzer_flags[@]}" "${extra_flags[@]}" "$source"
  done
done
rm -f "$described_sources" "$disk_sources"
```

This analyzes every C source SwiftPM reports for `CXDiff`, in release and `DEBUG`
modes. No translation unit may be omitted to avoid a finding. Two targeted
`deadcode.DeadStores` suppressions cover existing dead stores inside directly
included vendor code; do not broaden them or suppress other checkers.

On a Windows Developer Command Prompt, also verify the authoritative consumer:

```powershell
msbuild WinMerge.sln /m /p:Configuration=Release /p:Platform=x64
```

## Review checklist

- Upstream URL, path, snapshot commit, patch base, and patch commit are exact.
- Pristine synchronization and MacMerge patch layer are separate, unsquashed commits;
  a later metadata-only commit records their final hashes.
- Pinned and patched tree IDs pass the exact identity/reverse-patch validator.
- Final `git diff <patch-base> <patch-commit> -- Externals/xdiff` matches exactly
  the five-file inventory, or its explicitly updated replacement.
- Recursive vendor `.c` inventory equals authoritative `xdiff.vcxitems` `ClCompile`
  entries; each entry is directly wrapped or explicitly excluded.
- Shims contain no copied implementation or conditional source inclusion.
- Allocator overrides, failure cleanup, ABI flags, and public ownership rules were re-audited.
- `COPYING` and all changed source notices match WinMerge.
- Source-manifest, runtime-route, full, sanitizer, release, all-C-source analyzer,
  and Windows builds pass.
- Full cached diffs were reviewed, staged patch checks passed, and global index was
  empty before and after every update commit.

## Rollback

Keep the previous pin and saved patch until both platforms pass CI. Before merge,
discard the dedicated branch rather than rewriting shared history. After merge,
revert every commit from the synchronization in strict reverse dependency order.
This includes metadata, all compatibility, shim, ABI, workflow and test commits,
the MacMerge patch commit, and finally the pristine WinMerge synchronization:

```bash
set -euo pipefail
git diff --cached --quiet
test -z "$(git diff --cached --name-only)"
git revert "$METADATA_COMMIT"
git revert "$LAST_COMPATIBILITY_OR_TEST_COMMIT"
# Repeat compatibility/test reverts in reverse chronological order.
git revert "$PATCH_COMMIT"
git revert "$SYNC_COMMIT"
```

Set each variable from the update review record. Omit only a compatibility category
for which the update created no commit. Resolve conflicts without skipping a
dependent commit, rerun complete validation, and verify the restored tree ID equals
the previously recorded patched tree. Do not revert individual vendor files; that
breaks the recorded baseline and inventory.

Current baseline predates split-commit policy. Never revert
`40d8b10d0928bc415e6c3febd2dab2f6daff1a5c` to isolate xdiff fixes: that commit also
introduces the complete native port. Test pristine current WinMerge snapshot on a
disposable branch with a vendor-only test commit instead:

```bash
set -euo pipefail
git diff --cached --quiet
test -z "$(git diff --cached --name-only)"
git switch -c test-pristine-xdiff
git restore --source=7a3e1ec3efcc0ebad2034f72d8f87a6c74d62301 \
  --worktree -- Externals/xdiff
git add -A Externals/xdiff
git diff --cached --check
test "$(git diff --cached --name-only)" = \
  "$(git diff --cached --name-only -- Externals/xdiff)"
git diff --cached
git commit -m "Test pristine pinned xdiff snapshot"
```

Validate that disposable state on both platforms, then discard branch without
merging it. For every future synchronization following this document, reverting
only its standalone MacMerge patch commit is a valid diagnostic and leaves that
update's pristine WinMerge snapshot; revert all later dependent commits first.
