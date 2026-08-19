# MacMerge

Native macOS port of WinMerge, started as an isolated Swift package so existing Windows builds remain unchanged.

## First milestone

- Native SwiftUI comparison window
- Two-file UTF-8, UTF-16, and verified Japanese legacy text loading
- Aligned line additions, removals, and modifications
- Shared, UI-independent diff model with unit tests
- Native C boundary over WinMerge's bundled xdiff comparison engine
- WinMerge-compatible line filters and regular-expression substitutions
- Two file paths accepted as command-line arguments

## Merge workflow

- Apply individual changed rows in either direction
- Merge all changes in either direction after confirmation
- Preserve target line endings when replacing, inserting, or deleting lines
- Track edited files independently against their last saved content
- Save edited files in place
- Navigate differences and keep the selected row visible
- Use a WinMerge-style command toolbar for file actions, full difference navigation, directional copies, copy-and-advance, merge-all, and reload
- Undo and redo merge operations with bounded history
- Bound retained undo snapshots to 100 entries and 128 MiB
- Protect unsaved edits before replacing either file
- Prompt to save or discard remaining edits when quitting
- Preserve UTF-8/UTF-16 byte order marks and byte order when saving
- Preserve unchanged CP932/CP51932/CP50220/CP1250/CP1251/CP1252 bytes exactly and validate edited legacy text before saving
- Ask for an explicit encoding when byte sequences have multiple valid interpretations
- Reject ambiguous BOM-less UTF-16 instead of guessing byte order
- Reject unsupported UTF-32 instead of misreading it as UTF-16
- Reject saves when another application changed the file on disk
- Coordinate bounded file reads and preserve symlink targets during saves
- Retain an explicit recovery copy when a save cannot prove cleanup or rollback safety
- Keep file loading, comparison, merging, and saving off the main thread
- Accept initial and subsequent Finder Open With requests

See [todo.md](../todo.md) for the port roadmap and current work order.
See [MIGRATION.md](MIGRATION.md) before moving a workflow from WinMerge and for the current feature-parity matrix.
See [PRIVACY.md](PRIVACY.md) for local file, settings, bookmark, and crash-diagnostic handling.

## Run

```bash
cd MacMerge
swift test
swift run MacMerge [left-file] [right-file]
```

## Package

Create a release `.app` with an ad-hoc signature for local development:

```bash
cd MacMerge
Scripts/package-app.sh
open dist/MacMerge.app
```

Packaged applications enable App Sandbox with user-selected read/write access and persistent app-scoped security bookmarks. Set `SIGN_IDENTITY`, `MARKETING_VERSION`, and `BUILD_NUMBER` to create a Developer ID-signed release candidate. Use the release flow below for notarization.

Create a notarized release archive after storing Apple credentials in a `notarytool` Keychain profile:

```bash
cd MacMerge
xcrun notarytool store-credentials MacMergeNotary
SIGN_IDENTITY="Developer ID Application: Example (TEAMID)" \
NOTARYTOOL_PROFILE=MacMergeNotary \
MARKETING_VERSION=0.1.0 \
BUILD_NUMBER=1 \
Scripts/release-app.sh
```

The release script requires a real Developer ID Application identity, waits for notarization, staples and validates the ticket, runs Gatekeeper assessment, and writes a SHA-256 file beside the versioned ZIP. Supported-version runtime testing remains a separate release gate.

## Port direction

MacMerge now uses WinMerge's bundled xdiff engine through a narrow C ABI, including algorithm selection, comparison flags, hunk-level line filters, and WinMerge replacement syntax. Debug tests sweep every native allocation failure and CI reruns them under Address Sanitizer. Comparison inputs are bounded to 64 MiB and 1,048,576 lines per side. Diff rows render through a reusable native AppKit table with off-main metadata generation, lazy text layout, and synchronized horizontal scrolling; the aligned row model is still materialized. Row and merge-all operations preserve mixed target line endings and final-newline state. Verified CP932, CP51932, CP50220, CP1250, CP1251, and CP1252 paths preserve original bytes until edits and fail closed on unsupported or ambiguous mappings; broader Windows code-page parity remains unfinished. Raw non-UTF-8 substitution bytes also fail closed until comparison transforms move to a byte-oriented representation. Next work adds repeatable large-file performance benchmarks, expands fixture parity and legacy mapping coverage, then completes sandboxed release packaging.
