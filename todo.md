# MacMerge Port Roadmap

Status key: `[x]` complete, `[-]` in progress, `[ ]` planned.

## Milestone 1: Native comparison shell

- [x] Create isolated Swift package without changing WinMerge Windows builds.
- [x] Load two Unicode text files from Finder or command-line paths.
- [x] Align unchanged, modified, inserted, and removed lines.
- [x] Render one synchronized, accessible SwiftUI comparison surface.
- [x] Cover line alignment and newline handling with unit tests.

## Milestone 2: File merge workflow

- [x] Copy one changed row from left to right or right to left.
- [x] Preserve target line-ending style while applying row merges.
- [x] Track unsaved changes independently for each side.
- [x] Save either edited file in place and report write failures.
- [x] Add bounded undo and redo for merge operations.
- [x] Bound retained undo snapshots by count and memory (100 snapshots, 128 MiB).
- [x] Navigate to previous and next differences.
- [x] Merge all changes in either direction with confirmation.
- [x] Warn before replacing a file that has unsaved changes.
- [x] Warn before quitting with unsaved changes and offer to save both sides.

Acceptance: user can open two files, apply individual changes in either direction, save result, and reopen it with zero unexpected differences.

## Milestone 3: WinMerge-compatible text core

- [x] Define stable C boundary for reusable comparison code.
- [x] Reuse WinMerge's bundled xdiff engine instead of growing starter Swift line engine.
- [-] Run shared behavior tests against WinMerge comparison fixtures (no-EOL, algorithm alignment, line filters, and substitutions complete).
- [-] Add encoding detection and lossless round trips (UTF-8/UTF-16 complete; verified CP932/CP51932/CP50220 paths and ambiguity selection complete; full Windows mapping parity pending).
- [x] Preserve mixed line endings and final-newline state.
- [x] Add whitespace, case, blank-line, line-filter, and substitution options.
- [x] Apply filters and substitutions to complete native diff hunks without hiding adjacent real changes.
- [x] Bound coordinated file loads and preserve symlink targets and recoverable save backups.
- [ ] Detect moved blocks and expose intra-line differences.
- [-] Handle large files without materializing every rendered row (reusable native table and off-main render metadata complete; row model remains materialized; current safety limits: 64 MiB and 1,048,576 lines per side).

Acceptance: supported text comparisons match WinMerge fixture results and save without encoding or newline loss.

## Milestone 4: Directory comparison

- [ ] Scan two folders recursively with cancellable background work.
- [ ] Compare file presence, size, timestamps, and content.
- [ ] Present sortable and filterable directory results.
- [ ] Open selected file pairs in text comparison windows.
- [ ] Copy, move, delete, and synchronize selected files safely.
- [ ] Detect renamed and moved files.
- [ ] Generate comparison reports.

Acceptance: user can compare and synchronize realistic directory trees without blocking main thread.

## Milestone 5: macOS application experience

- [-] Move from executable package to signed `.app` product (ad-hoc package complete; Xcode archive pending).
- [-] Add document windows, recent items, drag and drop, and Finder Open With support (initial and subsequent Open With complete).
- [-] Add WinMerge-style toolbar command parity; track every command in the audit below.
- [x] Create editable two-pane untitled text comparisons and save scratchpads with Save As.
- [ ] Add native menus, keyboard shortcuts, toolbar customization, and settings.
- [ ] Add syntax highlighting and configurable colors and fonts.
- [ ] Restore window layouts and comparison sessions.
- [ ] Meet VoiceOver, keyboard navigation, contrast, and localization requirements.

Acceptance: app behaves like first-class document-based macOS software.

## Toolbar Command Audit

Source of truth: `Src/Merge2.rc` `IDR_MAINFRAME`, in exact command order. A command is complete only when its primary action, secondary actions, enabled state, shortcut, accessibility metadata, model test, UI test, and installed-app smoke test match WinMerge or have a documented macOS-specific exception.

### File commands

- [x] `ID_FILE_NEW`: primary action creates a two-pane untitled text comparison.
- [ ] `ID_FILE_NEW`: present a split-button/menu indicator instead of hiding secondary New actions.
- [ ] `ID_FILE_NEW_TABLE`: create a two-pane table comparison.
- [ ] `ID_FILE_NEW_HEX`: create a two-pane binary/hex comparison.
- [ ] `ID_FILE_NEW_IMAGE`: create a two-pane image comparison.
- [ ] `ID_FILE_NEW_WEBPAGE`: create a two-pane webpage comparison.
- [ ] `ID_FILE_NEW_FOLDER`: create a two-pane folder comparison.
- [ ] `ID_FILE_NEW3`: create a three-pane text comparison.
- [ ] `ID_FILE_NEW3_TABLE`: create a three-pane table comparison.
- [ ] `ID_FILE_NEW3_HEX`: create a three-pane binary/hex comparison.
- [ ] `ID_FILE_NEW3_IMAGE`: create a three-pane image comparison.
- [ ] `ID_FILE_NEW3_WEBPAGE`: create a three-pane webpage comparison.
- [ ] `ID_FILE_NEW3_FOLDER`: create a three-pane folder comparison.
- [-] `ID_FILE_OPEN`: replace the left or right file; add WinMerge's single Open dialog and recent-path behavior.
- [ ] `ID_FILE_OPEN`: present a split-button/menu indicator for secondary Open actions.
- [ ] `ID_FILE_OPENCONFLICT`: open and parse a conflict file.
- [ ] `ID_FILE_OPENCLIPBOARD`: compare clipboard contents.
- [ ] `ID_FILE_OPENPROJECT`: open a WinMerge project.
- [ ] `ID_FILE_SAVEPROJECT`: save a comparison project.
- [ ] Recent files/folders: expose native recent items and WinMerge-compatible pair history.
- [x] `ID_FILE_SAVE`: save all dirty loaded sides and request destinations for untitled sides.
- [ ] `ID_FILE_SAVE`: present secondary Save actions from the toolbar button.
- [x] `ID_FILE_SAVE_LEFT`: save only the left side.
- [x] `ID_FILE_SAVE_RIGHT`: save only the right side.
- [ ] `ID_FILE_SAVE_MIDDLE`: save the middle side when three-pane comparison exists.
- [-] `ID_FILE_SAVEAS_LEFT`: Save As works for an untitled left side; add document-backed Save As.
- [-] `ID_FILE_SAVEAS_RIGHT`: Save As works for an untitled right side; add document-backed Save As.
- [ ] `ID_FILE_SAVEAS_MIDDLE`: Save As for a middle side.
- [x] Reject save destinations that alias another pane, including Save All collisions.
- [x] Preserve merge history when Save As changes identity but not text.

### Edit and line-detail commands

- [x] `ID_EDIT_UNDO`: undo latest merge mutation with bounded history.
- [x] `ID_EDIT_REDO`: redo latest reverted merge mutation.
- [ ] `ID_SELECTLINEDIFF`: select the intra-line difference at the current line.
- [ ] `ID_SELECTPREVLINEDIFF`: select the previous intra-line difference.
- [ ] Verify Undo/Redo button and Edit menu state against focused text editing versus comparison merge history.

### Difference navigation commands

- [x] `ID_NEXTDIFF`: select and reveal the next significant difference without wrapping.
- [x] `ID_PREVDIFF`: select and reveal the previous significant difference without wrapping.
- [ ] `ID_NEXTCONFLICT`: select and reveal the next three-way conflict.
- [ ] `ID_PREVCONFLICT`: select and reveal the previous three-way conflict.
- [x] `ID_FIRSTDIFF`: select and reveal the first significant difference.
- [ ] `ID_CURDIFF`: reveal the current difference; replace the toolbar's count-only surrogate with the real command.
- [x] `ID_LASTDIFF`: select and reveal the last significant difference.
- [ ] Match WinMerge toolbar order exactly: Next, Previous, conflicts, First, Current, Last.
- [ ] Match WinMerge navigation behavior when no difference is selected by using current row/cursor position.
- [ ] Match WinMerge navigation behavior when selected difference is offscreen.
- [ ] Disable each navigation command from its own update rule, not one shared `hasDifferences` approximation.

### Merge commands

- [x] `ID_L2R`: copy selected/current difference from left to right without advancing.
- [x] `ID_R2L`: copy selected/current difference from right to left without advancing.
- [x] `ID_L2RNEXT`: copy selected/current difference left to right and advance; clear selection after final difference.
- [x] `ID_R2LNEXT`: copy selected/current difference right to left and advance; clear selection after final difference.
- [x] `ID_ALL_RIGHT`: copy all significant differences to the right after confirmation.
- [x] `ID_ALL_LEFT`: copy all significant differences to the left after confirmation.
- [ ] Render `ID_ALL_RIGHT` and `ID_ALL_LEFT` as separate direct toolbar buttons instead of one hidden menu.
- [ ] `ID_AUTO_MERGE`: implement WinMerge-compatible automatic merge and editable-state rules.
- [ ] Support current-line merge when no explicit difference selection exists.
- [ ] Support merge commands over a selection containing multiple differences.
- [ ] Implement read-only destination state and disable directional merge commands correctly.

### Comparison-set, options, and refresh commands

- [ ] `ID_FIRSTFILE`: open the first file pair from directory comparison results.
- [ ] `ID_PREVFILE`: open the previous file pair from directory comparison results.
- [ ] `ID_NEXTFILE`: open the next file pair from directory comparison results.
- [ ] `ID_LASTFILE`: open the last file pair from directory comparison results.
- [ ] `ID_OPTIONS`: open native comparison settings from toolbar and menu bar.
- [-] `ID_REFRESH`: recomparison/repaint exists through Reload; separate WinMerge Refresh (`F5`) from Reload/Rescan (`Ctrl+F5`) semantics.
- [x] Preserve left/right side identity when reloading a mixed scratchpad/file comparison.

### Toolbar interaction and presentation

- [ ] Replace Open and Merge All menus with WinMerge-style direct commands plus explicit secondary-action affordances.
- [ ] Keep exact toolbar command grouping and separator order from `Merge2.rc`.
- [ ] Add native toolbar overflow behavior at narrow window widths without dropping commands silently.
- [ ] Add toolbar customization while retaining a Reset to WinMerge Defaults action.
- [ ] Persist toolbar visibility, size, and customization.
- [ ] Verify every toolbar icon has WinMerge-equivalent tooltip text and shortcut display.
- [ ] Verify every toolbar control has unique VoiceOver label, value, hint, enabled state, and keyboard focus behavior.
- [ ] Verify every toolbar action while comparison is empty, loading, equal, different, selected, dirty, read-only, failed, untitled, and externally changed.
- [ ] Add screenshot/AX regression for exact command order and grouping in a fresh window.
- [ ] Add screenshot/AX regression for exact command order and grouping in a loaded comparison.
- [ ] Add interaction tests for primary click, menu-arrow click, menu item selection, keyboard activation, VoiceOver activation, and disabled activation.

## Menu Bar Command Audit

Source of truth: `Src/Merge.rc` `IDR_MERGEDOCTYPE`. Every item must be implemented, disabled with an accurate reason, or listed in the intentional incompatibility document.

### File menu

- [ ] New submenu: Text, Table, Binary, Image, Webpage, Folder.
- [ ] New (3 panes) submenu: Text, Table, Binary, Image, Webpage, Folder.
- [ ] Open, Open Conflict File, and Open Clipboard.
- [ ] Open Project and Save Project.
- [ ] Save; Save Left/Middle/Right; Save Left/Middle/Right As.
- [ ] Print, Page Setup, and Print Preview using native macOS printing.
- [ ] Left/Middle/Right Read-Only state.
- [ ] Convert Line Endings to CRLF, LF, or CR without changing unrelated terminators unexpectedly.
- [ ] Merge Mode state and `F9` behavior.
- [ ] Reload/Rescan and File Encoding selection.
- [ ] Recompare As Text, Table, Binary, Image, Webpage, or Archive.
- [ ] Recent Files or Folders using native recent-document integration.
- [x] Exit/Quit warns about unsaved work and save recovery notices.

### Edit menu

- [ ] Wire Undo and Redo to the correct focused editor or comparison history.
- [ ] Cut, Copy, Paste, and Select All for scratchpads and selectable diff text.
- [ ] Select Line Difference and Select Previous Line Difference.
- [ ] Find, Replace, Marker, and Repeat Search.
- [ ] Copy With Line Numbers.
- [ ] Toggle, Next, Previous, and Clear All Bookmarks.
- [ ] Go to Line and Go to Definition.
- [ ] Options with native `Command-,` integration.

### View menu

- [ ] Font selection, default font, zoom in/out/normal.
- [ ] Syntax highlighting scheme selection.
- [ ] Diff context All/0/1/3/5/7/9, toggle, and invert.
- [ ] Lock Panes, View Whitespace, View EOL, View Line Differences, View Line Numbers, View Margins, Top Margins, and Wrap Lines.
- [ ] Swap panes and vertical/horizontal split behavior.
- [ ] Toolbar visibility, size, overflow, and customization.
- [ ] Status, detail, location, output, and display-filter panes.
- [ ] Refresh with `F5` semantics.

### Merge menu

- [ ] Next, Previous, First, Current, and Last Difference.
- [ ] Next and Previous Conflict.
- [ ] Three-way advanced difference navigation for each pane pair and one-sided difference type.
- [ ] Directional copy, copy-from, selected-lines copy, and copy-and-advance commands.
- [ ] Copy All Left and Copy All Right.
- [ ] Auto Merge.
- [ ] Add and clear synchronization points.
- [ ] Ensure menu and toolbar invoke one shared command implementation and one shared enabled-state implementation.

### Tools, Plugins, Window, and Help menus

- [ ] Filters, Generate Patch, Generate Report, and Generate Archive.
- [ ] Define macOS replacement or explicit unsupported status for unpackers, prediffers, editor scripts, copying scripts, and plugin reload.
- [ ] Close, Close All, Change Pane, Split, Tile, and window navigation using native macOS windows/tabs.
- [ ] Help, Release Notes, Translations, Configuration, license, and About MacMerge.
- [ ] Add menu validation tests for title, order, shortcut, checked state, enabled state, target action, and result.

## Keyboard Shortcut Audit

- [ ] Port command shortcuts from `Merge.rc` without overriding native text-editing keys while an editor owns focus.
- [ ] Test New `Command-N`, Open `Command-O`, Save `Command-S`, Quit `Command-Q`, and Close `Command-W`.
- [ ] Test Undo `Command-Z` and Redo `Command-Shift-Z` plus focused-editor routing.
- [ ] Test Next/Previous Difference with `F8`/`F7` and platform-safe equivalents for WinMerge Alt-arrow shortcuts.
- [ ] Test First/Current/Last Difference equivalents for Alt-Home/Enter/End.
- [ ] Test directional copy and copy-and-advance without stealing standard word/paragraph navigation from selectable text.
- [ ] Test Select Line Difference `F4`, Refresh `F5`, Rescan `Command-F5`, Change Pane `F6`, and Merge Mode `F9`.
- [ ] Test every shortcut in empty, disabled, loading, selected, dirty, and text-focused states.

## Diff Core Provenance and Parity Audit

Current status: MacMerge **does use WinMerge's bundled `Externals/xdiff` C implementation**. `MacMerge/Sources/CXDiff/vendor_*.c` compiles those upstream source files through `mmx_diff`, and `MacMergeCore/LineDiff.swift` translates native hunks into aligned rows. MacMerge does **not yet reuse the full Windows `CDiffWrapper` pipeline**; option mapping, post-filtering, row alignment, encoding, and merge behavior are partly reimplemented and require differential parity tests.

### Provenance and build integrity

- [x] Compile bundled `Externals/xdiff` sources through the `CXDiff` target.
- [x] Route production `LineDiff.compare` through `mmx_diff` with no Swift fallback.
- [ ] Add a build test that records exact upstream xdiff source files and fails if a wrapper silently stops compiling one.
- [ ] Add a link/runtime test proving production comparisons execute `mmx_diff` rather than a test-only implementation.
- [ ] Track WinMerge xdiff patches separately and document synchronization with upstream WinMerge.
- [ ] Decide whether to port `Src/xdiff_gnudiff_compat.cpp`/`CDiffWrapper` directly or retain the narrow ABI with proven behavioral equivalence.

### Differential oracle tests

- [ ] Build a Windows fixture oracle that runs current WinMerge `CDiffWrapper` and serializes ranges, trivial flags, moved ranges, and intra-line ranges.
- [ ] Run the same fixture corpus through MacMerge and byte-diff normalized JSON results in CI.
- [ ] Pin the WinMerge commit used to generate each golden result.
- [ ] Cover every fixture under `Testing/GoogleTest/DiffWrapper` and relevant `Testing/Data` directories.
- [ ] Fail CI when MacMerge changes alignment without an reviewed WinMerge-oracle update.

### Algorithm tests

- [x] Cover default, minimal, patience, histogram, and none xdiff algorithms.
- [ ] Compare every algorithm against WinMerge on repeated-line and ambiguous-alignment corpora.
- [ ] Cover algorithm fallback and allocation-failure paths with deterministic fault injection.
- [x] Run native allocation-failure sweeps under Address Sanitizer.
- [ ] Add Undefined Behavior Sanitizer and Thread Sanitizer jobs where supported.

### Fundamental diff-shape tests

- [x] Equal, replacement, insertion, and deletion cases.
- [x] Empty left, empty right, and both empty.
- [x] Missing final EOL and EOL-only differences.
- [x] LF, CRLF, CR, mixed EOL, and strict versus ignored EOL.
- [ ] Multiple adjacent hunks and hunks separated by one unchanged line.
- [ ] Long repeated runs, duplicate lines, reordered blocks, and adversarial hash collisions.
- [ ] Files containing NUL bytes and binary-looking text according to WinMerge policy.
- [ ] Maximum accepted byte/line boundaries and one-unit-over rejection.

### Comparison-option tests

- [x] Ignore case.
- [x] Ignore numbers.
- [x] Ignore blank lines.
- [x] Ignore all whitespace and ignore whitespace changes.
- [x] Ignore line-ending style.
- [ ] Indent heuristic parity against WinMerge fixtures.
- [ ] Unicode case-folding and locale behavior versus WinMerge byte/code-page behavior.
- [ ] Combined-option matrix using pairwise coverage plus high-risk exhaustive combinations.

### Filter and substitution tests

- [x] Line filters over full native hunks.
- [x] Multiline regex anchors for LF, CRLF, and CR.
- [x] WinMerge capture references and supported replacement escapes.
- [x] Reject substitutions that change line structure unexpectedly.
- [ ] Comment-filter parity for every supported syntax parser.
- [ ] Unequal filtered runs adjacent to real edits.
- [ ] Multiple overlapping line filters and substitutions with deterministic precedence.
- [ ] Raw-byte substitution escapes `0x80...0xFF` using a byte-oriented transform instead of fail-closed String handling.
- [ ] Regex invalidity, catastrophic-backtracking limits, cancellation, and memory bounds.

### Moved-block and intra-line tests

- [ ] Port moved-block detection and compare moved-source/moved-destination ranges with WinMerge.
- [ ] Cover duplicate moved blocks, moved-and-edited blocks, and moves adjacent to insert/delete hunks.
- [ ] Port intra-line/word difference ranges.
- [ ] Cover Unicode grapheme clusters, combining marks, emoji, tabs, wide glyphs, and code-page text in intra-line ranges.
- [ ] Verify `Select Line Difference`, detail pane, and highlighted ranges use the same core result.

### Encoding and byte-preservation tests

- [x] UTF-8 with/without BOM and UTF-16 LE/BE with BOM.
- [x] Fail closed for ambiguous BOM-less UTF-16 and unsupported UTF-32.
- [-] CP932, CP51932, and CP50220 representative streams; full Windows mapping tables pending.
- [ ] Run every WinMerge code-page fixture through load, compare, edit, save, reload, and byte comparison.
- [ ] Test noncanonical byte aliases, unrepresentable edits, canonicalization warnings, and explicit encoding selection.
- [ ] Test external edits, symlink retargeting, coordinated save races, recovery-copy retention, and cleanup failures with deterministic filesystem injection.

### Merge correctness properties

- [x] Row merge both directions.
- [x] Merge All both directions.
- [x] Preserve target mixed EOLs and final-newline policy where required.
- [ ] For every nontrivial row, applying left-to-right then recomparing must remove exactly the intended difference and preserve unrelated bytes.
- [ ] Merge All then recompare must produce zero significant differences under the same options.
- [ ] Undo then recompare must reproduce the exact pre-merge result; redo must reproduce the exact post-merge result.
- [ ] Directional symmetry tests swap left/right inputs and invert added/removed plus copy direction.
- [ ] Randomized/property tests generate valid line documents and verify alignment, monotonic line numbers, and merge invariants.
- [ ] Fuzz C ABI lengths, flags, malformed encodings, regexes, filters, and cancellation.

### Performance and UI integration tests

- [ ] Benchmark 10k, 100k, 250k, and 1M rows with fixed CPU, memory, load, first-render, and scroll budgets.
- [ ] Benchmark extremely long lines, tabs, wide Unicode, and dense difference sets.
- [ ] Assert comparison and render metadata stay off the main actor.
- [ ] Assert stale canceled comparisons cannot publish over newer input.
- [ ] UI-test selection, First/Current/Last, Next/Previous, copy, copy-and-advance, Copy All, Undo, Redo, Refresh, and Save against core results.
- [ ] UI-test one shared horizontal scroll position across every visible row and both panes.
- [ ] UI-test VoiceOver row status, line numbers, selected state, copy direction, and toolbar/menu command results.

## Milestone 6: Extended WinMerge parity

- [ ] Compare images with overlays, blinking, and difference navigation.
- [ ] Compare binary files in hexadecimal view.
- [ ] Compare and create supported archives.
- [ ] Design safe replacement for Windows plugin and script integrations.
- [ ] Evaluate web-page and table comparison parity.
- [ ] Document intentionally unsupported Windows shell features.

## Milestone 7: Release engineering

- [-] Add CI for tests, release builds, formatting, and static analysis (tests, strict builds, xdiff path coverage, and package artifact complete).
- [-] Add performance and memory regression suites (deterministic xdiff allocation-failure sweep and CI Address Sanitizer run complete).
- [ ] Add crash reporting and privacy documentation.
- [ ] Configure sandbox entitlements and persistent security-scoped bookmarks.
- [ ] Sign, notarize, package, and exercise updates on supported macOS versions.
- [ ] Publish migration notes and feature-parity matrix.

## Current Work Order

1. Add repeatable million-row scrolling and memory performance benchmarks; reduce remaining materialized row storage.
2. Expand xdiff fixture parity through comments, blank-line combinations, raw-byte substitutions, and moved-block behavior.
3. Expand CP932/CP51932/CP50220 coverage against Windows fixtures; keep unsupported mappings fail-closed.
4. Convert packaging to an Xcode archive with sandbox entitlements and Developer ID signing.
5. Expand into directory comparison after text-core behavior is fixture-compatible.
