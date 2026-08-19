# MacMerge Port Roadmap

Status key: `[x]` complete, `[-]` in progress, `[ ]` planned, `[!]` blocked pending external help.

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
- [-] Run shared behavior tests against WinMerge comparison fixtures (no-EOL, algorithm alignment, line filters, substitutions, ignore-blank-line post-splitting, moved blocks, allocation recovery, and a warnings-as-errors baseline of 1,409 XCTest cases plus 22 Swift Testing cases complete; broader Windows fixture parity pending).
- [-] Add encoding detection and lossless round trips (UTF-8/UTF-16 and verified CP932/CP51932/CP50220/CP1250/CP1251/CP1252/CP1253/CP1254 paths complete; ambiguity selection complete; broader Windows mapping parity pending).
- [x] Preserve mixed line endings and final-newline state.
- [x] Add whitespace, case, blank-line, line-filter, and substitution options.
- [x] Apply filters and substitutions to complete native diff hunks without hiding adjacent real changes.
- [x] Bound coordinated file loads and preserve symlink targets and recoverable save backups.
- [x] Detect moved blocks and expose intra-line differences: opt-in WinMerge-compatible moved-line maps, row highlighting, Location Pane connectors, context navigation, intra-line highlighting, and selection are complete.
- [-] Handle large files without materializing every rendered row (reusable native table, off-main render metadata, derived IDs, 16-byte packed rows, source-range-backed lazy text, single-word difference locations, allocation-free editable sentinel, direct document-record comparison, and UInt32 ordered difference indices complete; shallow row storage is 15.3 MiB at 1M rows, packaged 1M sparse comparison uses 564 MiB total resident memory, and 250k all-different rows use 245 MiB; aligned row metadata remains materialized; current safety limits: 64 MiB and 1,048,576 lines per side).

Acceptance: supported text comparisons match WinMerge fixture results and save without encoding or newline loss.

## Milestone 4: Directory comparison

- [PARTIAL] Core recursive folder scanner has deterministic ordering, cancellation, hidden/symlink policies, descriptor-relative no-follow traversal, cycle/escape protection, structured errors, and focused tests; background UI integration remains.
- [PARTIAL] Core folder comparator covers presence, type, size, timestamps, optional required content digests, normalized-path collisions, cancellation, diagnostics, deterministic ordering, and focused tests; directory-window integration remains.
- [PARTIAL] Core directory result model supports stable IDs, validated side/status invariants, multi-key sorting, filtering, selection persistence, and descriptor-pinned file-pair access with focused tests; results UI remains.
- [ ] Open selected file pairs in text comparison windows.
- [PARTIAL] Folder file-operation planning and dry-run validation cover containment, traversal, aliases/symlinks/special files, collisions, Unicode/case equivalence, overlaps, and read dependencies. Mutating copy/move/delete/synchronize paths deliberately fail closed until descriptor-relative commit/rollback guarantees are complete.
- [PARTIAL] Reviewed and tested deterministic exact-digest renamed/moved file pairing core exists; folder-results integration remains.
- [PARTIAL] Deterministic bounded plain-text, fixed-schema CSV, and self-contained HTML report generation exists with escaping, formula neutralization, summaries, and focused tests; folder/file report UI, clipboard, linked reports, and open-after-generation remain.

Acceptance: user can compare and synchronize realistic directory trees without blocking main thread.

## Milestone 5: macOS application experience

- [-] Move from executable package to signed `.app` product (ad-hoc package complete; Xcode archive pending).
- [-] Add document windows, recent items, drag and drop, and Finder Open With support (initial and subsequent Open With complete).
- [-] Add WinMerge-style toolbar command parity; track every command in the audit below.
- [x] Create editable two-pane untitled text comparisons and save scratchpads with Save As.
- [-] Add native menus, keyboard shortcuts, toolbar customization, and settings (comparison Settings scene, option persistence, and primary command shortcuts added; complete menus/customization pending).
- [PARTIAL] Reviewed and tested bounded UI-independent syntax tokenization exists for plain text, Swift, C-like languages, JSON, and Markdown; editor rendering and configurable colors/fonts remain.
- [x] Reviewed and tested bounded, versioned comparison-session persistence restores file and scratchpad identity, encodings, independent read-only sides, selection, active side, Location Pane state, and window frames through app startup, close, and termination flows.
- [ ] Meet VoiceOver, keyboard navigation, contrast, and localization requirements.

Acceptance: app behaves like first-class document-based macOS software.

## Windows-to-Mac UI Parity Ledger

Baseline audited: 2026-08-06. This ledger covers every user-visible Windows UI family found in `Src/Merge.rc`, `Src/Merge2.rc`, `Src/resource.h`, and their owning frame, view, document, dialog, and property-page classes. Resource presence alone does not prove parity: runtime handlers and update handlers define behavior and enabled state.

Status vocabulary:

- `MATCH`: same user-visible behavior and state contract.
- `MAC_ADAPTATION`: same user outcome through documented native macOS behavior.
- `PARTIAL`: usable implementation exists, but behavior, state, accessibility, persistence, or tests are incomplete.
- `MISSING`: no usable implementation exists; permanently disabled placeholders count as missing.
- `N/A`: Windows-only mechanism has no macOS meaning; any portable user outcome needs a separate adaptation row.

A row is complete only after placement, action wiring, result, enablement, check/radio state, dynamic text, shortcut, help, accessibility, persistence, model tests, UI tests, AX tests, and installed-app smoke tests pass in every applicable state.

### Source hierarchy

- [x] Toolbar order and grouping: `Src/Merge2.rc` `IDR_MAINFRAME` lines 63-104.
- [x] Main and contextual menu hierarchy: `Src/Merge.rc` `IDR_MAINFRAME`, `IDR_DIRDOCTYPE`, `IDR_MERGEDOCTYPE`, and every `IDR_POPUP_*` resource.
- [x] Keyboard commands: `Src/Merge.rc` `IDR_MAINFRAME` and `IDR_MERGEDOCTYPE` accelerator tables.
- [x] Dialog and property-page inventory: every `IDD_*` resource in `Src/Merge.rc` and `Src/resource.h`.
- [x] Actual action and validation semantics: MFC message maps plus `ON_COMMAND` and `ON_UPDATE_COMMAND_UI` handlers.
- [x] Windows rendered and interaction evidence: `Testing/GoogleTest/GUITests` and manual documentation.
- [-] Mac implementation evidence: `MacMerge/Sources/MacMerge`, 1,409 passing XCTest cases plus 22 Swift Testing cases, packaged `.app` AX snapshots, packaged performance reports, a full-Xcode Instruments capture harness, and installed-app smoke tests.

### Required state matrix

- [ ] Comparison lifecycle: empty, one side loaded, loading, current, stale, refreshing, failed, and canceled.
- [ ] Result: identical, different without selection, first/middle/last selected, cursor on a difference, and selection offscreen.
- [ ] Documents: both files, mixed file/scratchpad, both scratchpads, each dirty combination, save failure, external change, and missing disk file.
- [-] Editability: independent left/right/both read-only and editable merge destinations are covered in model and packaged AX smoke; focused native text-editor routing remains incomplete.
- [ ] Pane shape: two-way, three-way, active left/middle/right, swapped, vertical, and horizontal.
- [ ] Folder selection: none, one, many, mixed file/folder, missing side, identical, different, filtered, and hidden.
- [-] Window state: comparison/Settings key-window routing and restored sessions pass packaged smoke; background, multiple windows, tabs, narrow toolbar, and full-screen remain incomplete.
- [-] Invocation: primary AX activation, menu items, standard Undo/Redo shortcuts, and disabled-state checks pass packaged smoke; secondary arrows, complete keyboard traversal, and VoiceOver actions remain incomplete.

### Application shell and opening

- [PARTIAL] `IDR_MAINFRAME`: main application window, native menu bar, command strip, one comparison window, status strip, and packaged session restoration exist; multiple document windows/tabs, output pane, and complete status state are missing.
- [MISSING] `IDD_OPEN`: unified Select Files or Folders view with two/three paths, read-only flags, swaps, browse/history, filter, recurse, unpacker/prediffer, comparison options, project save, and Compare split button.
- [PARTIAL] `IDR_POPUP_NEW`: two-pane Text exists; Table, Binary, Image, Webpage, Folder, every three-pane mode, and split-button secondary actions are missing.
- [PARTIAL] `IDR_POPUP_OPEN` and `IDR_POPUP_BROWSE`: native pair picker and per-side replacement exist; recent pairs, path history, project/conflict/clipboard variants, and split-button behavior are missing.
- [MAC_ADAPTATION] Windows common file/folder pickers: use `NSOpenPanel`, `NSSavePanel`, and Finder document events while preserving pair selection, cancellation, validation, and security-scoped access.
- [PARTIAL] Drag/drop and shell opening: Finder Open With works initially and while running; direct pane drop, pair drop, replacement drop, and Finder Services are missing.

### Compare workspaces

- [PARTIAL] `IDR_MERGEDOCTYPE` text compare: two editable panes, alignment, line numbers, synchronized scrolling, moved-block detection/highlighting/navigation, row and intra-line highlighting, merge, save, and encoding safety exist; three-way text, word-diff model, syntax, margins, and complete view commands are missing.
- [MISSING] Table Compare and `IDD_OPEN_TABLE`: spreadsheet rendering, table header/filter menu, delimiters, quote/newline settings, and table-specific options.
- [MISSING] Hex/Binary Compare: native hex panes, byte editing, binary find/replace/go-to, character sets, per-pane status, and binary settings.
- [MISSING] Image Compare: multipage panes, location/tool pane, differences, block size, threshold, insertion detection, transforms, zoom, overlay, wipe, animation, OCR, and image status.
- [MISSING] Webpage Compare: browser panes, location/tool pane, screenshot/HTML/text/resource modes, viewport presets, synchronized events, browsing-data controls, and dependency handling.
- [MISSING] Folder Compare: recursive scan, table/tree results, state icons, columns, filters, sorting, method selection, file actions, progress/pause/cancel, and file-pair opening.

### Main menus and command surfaces

- [PARTIAL] File menu: New Text, pair Open, Save/Save Left/Save Right, Save Left/Right As, Merge Mode, Reload, and guarded Quit exist; all remaining `IDR_MERGEDOCTYPE` File commands are mapped in the command audits below.
- [PARTIAL] Edit menu: native field editing, focus-routed model undo/redo, Select/Previous Line Difference, row context numbered copy, and Options exist; search, markers, multi-row/global numbered copy, bookmarks, and go-to remain missing.
- [MISSING] View menu: font, zoom, syntax, diff context, whitespace/EOL/line differences/numbers/margins/wrap, pane swap/split/lock, toolbar choices, and dockable pane visibility.
- [PARTIAL] Merge menu: two-way cursor-relative navigation and copying exist; conflicts, three-way commands, Auto Merge, selected-line operations, and synchronization points are incomplete.
- [MISSING] Tools menu: Filters, Generate Patch, Generate Report, and Generate Archive.
- [MISSING] Plugins menu: settings, prediffers, unpackers, editor/copy scripts, transforms, and reload.
- [PARTIAL] Window menu: native close/minimize/zoom and two-pane Change Pane exist; multiple comparison windows/tabs, split, and document arrangement are missing.
- [PARTIAL] Help menu: Copy Configuration Report produces bounded redacted runtime/build/options text; Help Book, release notes, translations, GPL, contributors, and complete About content remain missing.
- [PARTIAL] `IDR_MAINFRAME` toolbar: implemented commands use compact icons; exact command contract remains governed by the Toolbar Command Audit.
- [MISSING] Toolbar visibility, None/Small/Medium/Big/Huge sizes, native overflow, customization, reset, and persistence.
- [PARTIAL] Text editor context menu matches WinMerge's two-pane order and routes merge, selected-diff clipboard, numbered row copy, line-difference, undo/redo, editing, and native file opening; selected-line merge, multi-row numbered copy, filters, scripts, go-to, shell, and other workspace context menus remain missing.
- [PARTIAL] Accelerators: native document shortcuts and some Option/Command merge shortcuts exist; packaged smoke verifies Settings/comparison key-window Undo/Redo isolation, while full accelerator parity and focused-editor safety remain incomplete.

### Bars, panes, and status surfaces

- [MISSING] MDI/document tab bar and tab context menu; replace with native windows/tabs while preserving dirty state, close-other/left/right, width, and restoration outcomes.
- [PARTIAL] `IDD_EDITOR_HEADERBAR`: side caption, filename, dirty state, open, save, and independent accessible read-only toggles exist; editable path, history, clipboard, plugin state, and header context menu are missing.
- [PARTIAL] Location Pane: native two-pane scaled bars render packed significant-difference runs with editor colors and non-color shapes, selected marker, live viewport shading, click/drag centered navigation, wheel forwarding, moved-block connectors, moved-line context navigation, adjustable width, persisted visibility/width/click behavior, disabled-safe adjustable AX sliders and width handle, and WinMerge-style general context commands; compact/worst-case model tests, strict debug/release builds, packaged screenshot/AX checks, dark/increased-contrast screenshots, authorized runtime interaction checks, automated visibility/slider/exact-width-adjustment/persistence smoke, gated sparse and 250k/125k-run dense packaged budgets, and dense benchmark evidence pass. Context commands have semantic AX tests but no reliable packaged synthetic context-menu activation. Three-pane bars remain pending.
- [PARTIAL] Reviewed and tested bounded UI-independent Difference Detail model derives paired text fragments and grapheme-safe UTF-16 highlight ranges; pane UI, shared-core parity review, and merge controls remain.
- [MISSING] Output Pane: message log plus Copy, Select All, Clear All, visibility, and persistence.
- [MISSING] `IDD_DISPLAY_FILTER_BAR`: expression, history/presets, apply/close, text/folder variants, and restoration.
- [PARTIAL] `IDD_ENCODINGERROR`: explicit encoding selection and safe failures exist as dialogs; recovery bar, unpacker, and hex alternatives are missing.
- [PARTIAL] Global status: processing/result, Merge Mode, difference count, and filenames exist; plugin state, current difference, and command prompts are missing.
- [MISSING] Per-pane text/table status: line, column, character, selection, encoding, BOM, EOL, and read-only state with click actions.
- [MISSING] Folder, hex, image, and web mode-specific status surfaces.

### Dialog inventory

- [PARTIAL] `IDD_ABOUTBOX`: native About shell exists; WinMerge version detail, contributors, license, links, and credits are missing.
- [PARTIAL] `IDD_SAVECLOSING`: native save/discard/cancel adaptation exists, and packaged dirty-close Cancel smoke preserves exact comparison/Settings windows, content, dirty state, and undo history; independent per-side choices and broader UI tests remain missing.
- [PARTIAL] `IDD_LOAD_SAVE_CODEPAGE` and `IDD_ENCODINGERROR`: ambiguity selection exists; pane scope, load/save code pages, BOM controls, and recovery actions are incomplete.
- [MISSING] `IDD_EDIT_FIND`, `IDD_EDIT_REPLACE`, `IDD_EDIT_MARKER`, and `IDD_WMGOTO`.
- [PARTIAL] Tested core text search covers bounded literal/regex search, forward/backward wrapping, Unicode whole-word and grapheme-safe UTF-16 ranges, replace current/all, zero-length progress, and markers; find/replace/marker dialogs and editor wiring remain.
- [PARTIAL] Reviewed and tested row-level two-way comparison statistics core distinguishes unavailable move analysis from zero moves; statistics dialogs and three-way statistics remain. `IDD_DIRCOLS`, `IDD_DIRADDITIONALPROPS`, `IDD_DIRCOMP_PROGRESS`, `IDD_CONFIRM_COPY`, and `IDD_SELECT_FILES_OR_FOLDERS` remain missing.
- [MISSING] `IDD_GENERATE_PATCH`, `IDD_DIRCMP_REPORT`, `IDD_FILECMP_REPORT`, and `IDD_ARCHIVE`.
- [PARTIAL] `IDD_FILTERS_LINEFILTERS` and `IDD_FILTERS_SUBSTITUTIONFILTERS`: Settings supports enable state, ordered regex rules, case sensitivity, replacements, remove/clear, validation, persistence, and recomparison; file/condition/result/match-inside/shared/private/test-filter dialogs remain missing.
- [MISSING] `IDD_PLUGINS_SELECTPLUGIN`, `IDD_PLUGINS_LIST`, and `IDD_PLUGINS_EDITPLUGIN`.
- [MISSING] `IDD_DIALOG_WINDOWSMANAGER`, `IDD_INPUTBOX`, reusable translated message-box behavior, and dark font/color chooser adaptations.

### Preferences and settings

- [PARTIAL] `IDD_PREFERENCES`: native categorized Settings drives recomparison and supports persisted JSON Import, Export, and Reset for every current text option; Help and broader WinMerge pages are missing.
- [MISSING] General, System, Message Boxes, Project, Archive, Backup, Codepage, and Shell/Jump List pages.
- [MISSING] Compare Text, Folder, Table, Binary, Image, and Webpage pages.
- [MISSING] Editor General, Compare/Merge, and Syntax pages.
- [MISSING] Color Schemes, Differences, Syntax, Text/Selection, Markers, Folder, and System color pages.

### Project, conflict, clipboard, shell, and recent flows

- [MISSING] Project open/save, project comparison options, recent projects, and restoration.
- [PARTIAL] Tested core versioned comparison-project persistence validates schema, sides, URLs, options, regexes, symlinks, concurrent reads, deterministic JSON, exclusive atomic creation, and durability. Existing-project replacement deliberately fails closed pending metadata-preserving race-safe replacement; UI, recents, and restoration remain.
- [MISSING] Conflict parser and Base/Theirs/Mine comparison with conflict navigation.
- [MISSING] Clipboard text/image comparison and clipboard history menus.
- [MAC_ADAPTATION] Explorer registered editor/Open With/parent/shell menus: use Finder Open With, Reveal in Finder, Share/Services, and native file actions.
- [MISSING] Native recent documents plus WinMerge-compatible recent pair/folder history.
- [MISSING] Windows Jump List outcome: expose recent comparisons and common tasks through native recents, Dock menu, and app shortcuts where appropriate.

### Reports, patch, archive, filters, plugins, and scripts

- [MISSING] File and folder comparison reports with formats, clipboard output, linked file reports, and open-after-generation.
- [MISSING] Patch Generator with file selection, style/context, append, clipboard, command line, and external editor.
- [PARTIAL] Tested bounded core report and unified-patch generators cover safe CSV/HTML/text output, unified hunk ranges, missing final newlines, reverse patches, and Git-compatible quoted paths; dialogs, clipboard/file workflows, append, and external-editor integration remain.
- [MISSING] Archive Generator with report/patch/project inclusion and file/clipboard output.
- [PARTIAL] Filter settings include line/substitution editors; file filters, condition builders, comparison-result filters, expression helpers, and dedicated test dialogs remain missing.
- [MISSING] Plugin manager/editor/selector, unpacker/prediffer selection, automatic/manual modes, editor/copy scripts, macros, settings, and reload.
- [UNKNOWN] Plugin architecture adaptation: define a sandboxed, permission-aware extension model or document intentional unsupported scope before implementation.

### Navigation, merge, and pane controls

- [PARTIAL] First/Current/Previous/Next/Last Difference, cursor-relative fallback, and visible-versus-offscreen selection origin match the production model/AppKit contract; process-level interaction remains pending.
- [PARTIAL] Reviewed and tested parsed-conflict navigation core supports First/Last/Current/Next/Previous without wrapping and rejects forged/stale target identity; app command wiring and three-way pair-specific or side-only navigation remain.
- [PARTIAL] Copy Left/Right, Copy-and-Advance, Copy All, current-line fallback, and side-aware row context numbered copy exist; reviewed and tested lifecycle/editability policy plus File-menu/header controls drive independent left/right read-only state and shared merge/save eligibility. Session payload persistence and app lifecycle restoration preserve both read-only sides, while multi-difference selection, selected-line/multi-row copy, and Auto Merge remain incomplete.
- [MISSING] First/Previous/Next/Last compared-file navigation from folder results.
- [PARTIAL] Change Pane cycles two-pane editor focus with `F6`/`Shift-F6` while preserving logical row; reviewed and tested synchronization-point storage and bidirectional interpolation core exists, while app wiring, persistence, bookmarks, go-to definition, moved-line navigation, pane swap/lock, and dynamic split controls remain missing.

### Accessibility, persistence, and test completion

- [PARTIAL] Existing file controls, toolbar controls, summary, rows, editors, and selected state expose basic AX metadata.
- [ ] Add unique role, label, value, hint, enabled/check/selection state, focus order, actions, and announcements to every control and dynamic result.
- [ ] Verify Full Keyboard Access, VoiceOver activation, increased contrast, differentiate-without-color, dark mode, and localization expansion.
- [PARTIAL] Current text comparison preferences persist, and bounded comparison sessions restore independent read-only sides, file/scratchpad identity, encodings, selection, active side, Location Pane state, and window frames; window tabs, remaining pane and toolbar state, recents, and complete sandbox access remain missing.
- [PARTIAL] Model/core tests cover current text operations; command-contract, menu, toolbar, dialog, AX, persistence, screenshot, and installed-app smoke suites are incomplete.
- [ ] Every completed ledger row must cite model/unit, UI interaction, semantic AX, persistence if stateful, and packaged-app smoke evidence.

### Intentional macOS adaptations

- [MAC_ADAPTATION] MFC dialogs become native panels, alerts, sheets, and Settings scenes without changing outcomes.
- [MAC_ADAPTATION] Bitmap toolbar art becomes SF Symbols or native assets while command identity, order, grouping, and help remain equivalent.
- [MAC_ADAPTATION] MDI tile/cascade becomes native document windows and tabs; preserve comparison switching, close variants, dirty state, and restoration.
- [MAC_ADAPTATION] Registry/profile state becomes typed `UserDefaults`, scene restoration, document state, and security-scoped bookmarks.
- [MAC_ADAPTATION] Recycle Bin operations become Move to Trash with equivalent confirmation and recovery expectations.
- [MAC_ADAPTATION] CHM help becomes a macOS Help Book with web fallback and contextual anchors.
- [N/A] COM automation has no default Mac replacement; add a separate automation requirement only if approved.

## Toolbar Command Audit

Source of truth: `Src/Merge2.rc` `IDR_MAINFRAME`, in exact command order. A command is complete only when its primary action, secondary actions, enabled state, shortcut, accessibility metadata, model test, UI test, and installed-app smoke test match WinMerge or have a documented macOS-specific exception.

### File commands

- [x] `ID_FILE_NEW`: primary action creates a two-pane untitled text comparison.
- [ ] `ID_FILE_NEW`: present a split-button/menu indicator instead of hiding secondary New actions.
- [-] `ID_FILE_NEW_TABLE`: bounded CSV/TSV/custom-delimiter parsing, row/cell alignment, cancellation, canonical-Unicode matching, and 27 focused tests exist; document routing and table UI remain.
- [ ] `ID_FILE_NEW_HEX`: create a two-pane binary/hex comparison.
- [ ] `ID_FILE_NEW_IMAGE`: create a two-pane image comparison.
- [ ] `ID_FILE_NEW_WEBPAGE`: create a two-pane webpage comparison.
- [ ] `ID_FILE_NEW_FOLDER`: create a two-pane folder comparison.
- [-] `ID_FILE_NEW3`: bounded cancellable three-way merge, conflict regions/resolution, mixed-EOL preservation, all-algorithm overlap coverage, and 28 focused tests exist; three-pane document/UI integration remains.
- [ ] `ID_FILE_NEW3_TABLE`: create a three-pane table comparison.
- [ ] `ID_FILE_NEW3_HEX`: create a three-pane binary/hex comparison.
- [ ] `ID_FILE_NEW3_IMAGE`: create a three-pane image comparison.
- [ ] `ID_FILE_NEW3_WEBPAGE`: create a three-pane webpage comparison.
- [ ] `ID_FILE_NEW3_FOLDER`: create a three-pane folder comparison.
- [-] `ID_FILE_OPEN`: pair-level primary picker and left/right replacement exist; add WinMerge's full Open view and recent-path behavior.
- [x] `ID_FILE_OPEN`: present a split-button/menu indicator for pair Open plus left/right replacement actions.
- [-] `ID_FILE_OPENCONFLICT`: bounded Git two-way/diff3 conflict parsing with marker-width, malformed-input, label, range, and line-ending coverage passes 22 focused tests; file-open routing and conflict UI remain.
- [-] `ID_FILE_OPENCLIPBOARD`: bounded text/binary snapshot, stable identity, validation, comparison-input, and MRU history core passes 15 focused tests; `NSPasteboard`, command, and UI integration remain.
- [ ] `ID_FILE_OPENPROJECT`: open a WinMerge project.
- [ ] `ID_FILE_SAVEPROJECT`: save a comparison project.
- [-] Recent files/folders: bounded canonical `Codable` pair MRU core, hostile-persistence validation, and 18 focused tests exist; native recent-item exposure and persistence wiring remain.
- [x] `ID_FILE_SAVE`: save all dirty loaded sides and request destinations for untitled sides.
- [x] `ID_FILE_SAVE`: present secondary Save Left/Right actions from the toolbar button.
- [x] `ID_FILE_SAVE_LEFT`: save only the left side.
- [x] `ID_FILE_SAVE_RIGHT`: save only the right side.
- [ ] `ID_FILE_SAVE_MIDDLE`: save the middle side when three-pane comparison exists.
- [x] `ID_FILE_SAVEAS_LEFT`: Save As supports untitled and document-backed left panes while preserving encoding, BOM, exact clean bytes, source contents, and merge history.
- [x] `ID_FILE_SAVEAS_RIGHT`: Save As supports untitled and document-backed right panes with opposite-pane collision rejection.
- [ ] `ID_FILE_SAVEAS_MIDDLE`: Save As for a middle side.
- [x] Reject save destinations that alias another pane, including Save All collisions.
- [x] Preserve merge history when Save As changes identity but not text.

### Edit and line-detail commands

- [x] `ID_EDIT_UNDO`: undo latest merge mutation with bounded history.
- [x] `ID_EDIT_REDO`: redo latest reverted merge mutation.
- [x] `ID_SELECTLINEDIFF`: select the intra-line difference at the current line in the active pane; toolbar, Edit menu, and `F4` share model state.
- [-] `ID_SELECTPREVLINEDIFF`: Shift-F4, Edit menu, and editor context menu traverse previous intra-line ranges with model tests; UI interaction and WinMerge oracle parity remain.
- [-] Undo/Redo toolbar, Edit menu, and context menu route to focused native text history before comparison history with model tests; packaged smoke verifies comparison menu enablement/mutation, Settings/comparison key-window shortcut isolation, and dirty-close history preservation, while focused native-editor interaction remains.

### Difference navigation commands

- [x] `ID_NEXTDIFF`: select and reveal the next significant difference without wrapping.
- [x] `ID_PREVDIFF`: select and reveal the previous significant difference without wrapping.
- [ ] `ID_NEXTCONFLICT`: select and reveal the next three-way conflict.
- [ ] `ID_PREVCONFLICT`: select and reveal the previous three-way conflict.
- [x] `ID_FIRSTDIFF`: select and reveal the first significant difference.
- [x] `ID_CURDIFF`: reveal the selected/current difference; toolbar count surrogate removed.
- [x] `ID_LASTDIFF`: select and reveal the last significant difference.
- [x] Match WinMerge toolbar order exactly: Next, Previous, conflicts, First, Current, Last.
- [x] Match WinMerge navigation behavior when no difference is selected by using current row/cursor position.
- [x] Match WinMerge navigation behavior when selected difference is offscreen.
- [x] Disable each implemented navigation command from its own row-relative update rule.

### Merge commands

- [x] `ID_L2R`: copy selected/current difference from left to right without advancing.
- [x] `ID_R2L`: copy selected/current difference from right to left without advancing.
- [x] `ID_L2RNEXT`: copy selected/current difference left to right and advance; clear selection after final difference.
- [x] `ID_R2LNEXT`: copy selected/current difference right to left and advance; clear selection after final difference.
- [x] `ID_ALL_RIGHT`: copy all significant differences to the right after confirmation.
- [x] `ID_ALL_LEFT`: copy all significant differences to the left after confirmation.
- [x] Render `ID_ALL_RIGHT` and `ID_ALL_LEFT` as separate direct toolbar buttons.
- [ ] `ID_AUTO_MERGE`: implement WinMerge-compatible automatic merge and editable-state rules.
- [x] Support current-line merge when no explicit difference selection exists.
- [ ] Support merge commands over a selection containing multiple differences.
- [x] Implement independent read-only destination state and disable directional merge commands correctly.

### Comparison-set, options, and refresh commands

- [-] `ID_FIRSTFILE`: tested navigator selects the first openable pair in visible sorted/filtered directory-result order; command/UI wiring remains.
- [-] `ID_PREVFILE`: tested navigator selects the previous openable pair with boundary, wrap, and refreshed-selection handling; command/UI wiring remains.
- [-] `ID_NEXTFILE`: tested navigator selects the next openable pair with boundary, wrap, and refreshed-selection handling; command/UI wiring remains.
- [-] `ID_LASTFILE`: tested navigator selects the last openable pair in visible sorted/filtered directory-result order; command/UI wiring remains.
- [x] `ID_OPTIONS`: native categorized comparison settings open from toolbar/menu, drive real recomparison, persist all current options, edit line/substitution filters, and support JSON Import/Export plus Reset.
- [x] `ID_REFRESH`: recompare current in-memory buffers without disk I/O; disk Reload remains a separate guarded command.
- [x] Preserve left/right side identity when reloading a mixed scratchpad/file comparison.

### Toolbar interaction and presentation

- [x] Implement New/Open/Save split controls and direct merge commands with explicit secondary-action affordances.
- [x] Keep exact toolbar command grouping and separator order from `Merge2.rc`; unavailable context commands remain visible and accurately disabled.
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
- [-] Save, Save Left/Right, and Save Left/Right As exist; middle-pane variants await three-way comparison.
- [ ] Print, Page Setup, and Print Preview using native macOS printing.
- [-] Left/Right Read-Only state passes menu/header model and packaged AX persistence smoke; middle-pane state awaits three-way comparison.
- [-] Convert Line Endings core handles whole-document or selected-line CRLF/LF/CR conversion while preserving unrelated terminators, final-newline state, encoding/BOM, and dirty-state semantics across 17 focused tests; menu/editor wiring remains.
- [x] Merge Mode persists, exposes checked `F9` state and status, and maps unmodified arrows to merge/navigation while modified arrows retain editor behavior.
- [-] Guarded Reload from Disk and ambiguity-driven encoding selection exist; explicit File Encoding menu selection and broader rescan behavior remain missing.
- [ ] Recompare As Text, Table, Binary, Image, Webpage, or Archive.
- [-] Recent pair-history core is bounded, canonical, persistent-data-safe, and tested; native recent-document menu integration remains.
- [x] Exit/Quit warns about unsaved work and save recovery notices.

### Edit menu

- [-] Undo and Redo route to focused native text history or comparison history with standard shortcuts; command state invalidates on key-window and active-text changes, and packaged smoke verifies Settings/comparison key-window isolation, menu enablement, comparison mutation, and dirty-close history preservation. Focused native-editor interaction remains.
- [ ] Cut, Copy, Paste, and Select All for scratchpads and selectable diff text.
- [-] Select Line Difference and Select Previous Line Difference exist; UI interaction and WinMerge oracle parity remain.
- [ ] Find, Replace, Marker, and Repeat Search.
- [PARTIAL] Reviewed and tested bounded Copy With Line Numbers formatter drives a side-aware row context command with `Command-Shift-C`, AX enablement, checked pasteboard writes, app tests, and packaged smoke; multi-row selection and global Edit-menu routing remain.
- [-] Toggle, Next, Previous, and Clear All Bookmarks have deterministic bounded core state, edit remapping, navigation, hostile `Codable` validation, and 15 focused tests; editor/menu integration remains.
- [-] Go to Line and lightweight Go to Definition have Unicode-safe line/UTF-16 mapping, bounded Swift/C/C++ lexical indexing, and 34 focused tests; editor/menu integration and semantic language-server behavior remain.
- [x] Options with native `Command-,` integration.

### View menu

- [ ] Font selection, default font, zoom in/out/normal.
- [ ] Syntax highlighting scheme selection.
- [-] Diff context All/0/1/3/5/7/9, toggle, and invert have bounded row/hunk/gap projection, selection mapping, invalid-line safety, and 19 focused tests; view/menu wiring and persistence remain.
- [ ] Lock Panes, View Whitespace, View EOL, View Line Differences, View Line Numbers, View Margins, Top Margins, and Wrap Lines.
- [ ] Swap panes and vertical/horizontal split behavior.
- [ ] Toolbar visibility, size, overflow, and customization.
- [ ] Status, detail, location, output, and display-filter panes.
- [x] Refresh with `F5` semantics.

### Merge menu

- [x] Next, Previous, First, Current, and Last Difference.
- [PARTIAL] Reviewed and tested parsed-conflict navigation core supports First/Last/Current/Next/Previous without wrapping; menu/model wiring remains.
- [ ] Three-way advanced difference navigation for each pane pair and one-sided difference type.
- [-] Directional copy and copy-and-advance exist; dedicated copy-from aliases and selected-lines copy remain missing.
- [x] Copy All Left and Copy All Right.
- [ ] Auto Merge.
- [PARTIAL] Reviewed and tested synchronization-point core supports add, remove, clear, validation, edit remapping, bounded decode, and bidirectional mapping; editor commands and persistence integration remain.
- [ ] Ensure menu and toolbar invoke one shared command implementation and one shared enabled-state implementation.

### Tools, Plugins, Window, and Help menus

- [ ] Filters, Generate Patch, Generate Report, and Generate Archive.
- [ ] Define macOS replacement or explicit unsupported status for unpackers, prediffers, editor scripts, copying scripts, and plugin reload.
- [-] Native Close plus two-pane Change Pane exist; Close All, Split, Tile, and multi-window navigation remain missing.
- [PARTIAL] Reviewed and tested bounded deterministic Configuration report core drives Help > Copy Configuration Report with runtime/build/options metadata, checked pasteboard writes, native errors, adjacent/overlap-safe private-path redaction, app tests, and packaged smoke. Help, Release Notes, Translations, license, and complete About MacMerge remain missing.
- [ ] Add menu validation tests for title, order, shortcut, checked state, enabled state, target action, and result.

## Keyboard Shortcut Audit

- [ ] Port command shortcuts from `Merge.rc` without overriding native text-editing keys while an editor owns focus.
- [ ] Test New `Command-N`, Open `Command-O`, Save `Command-S`, Quit `Command-Q`, and Close `Command-W`.
- [-] Packaged smoke verifies Undo `Command-Z` and Redo `Command-Shift-Z` do not consume comparison history while Settings is key and mutate history when comparison is key; focused native-editor routing remains.
- [ ] Test Next/Previous Difference with `F8`/`F7` and platform-safe equivalents for WinMerge Alt-arrow shortcuts.
- [ ] Test First/Current/Last Difference equivalents for Alt-Home/Enter/End.
- [ ] Test directional copy and copy-and-advance without stealing standard word/paragraph navigation from selectable text.
- [x] Select Line Difference `F4`, Refresh `F5`, guarded Reload `Command-F5`, Change Pane `F6`/`Shift-F6`, and Merge Mode `F9` exist.
- [ ] Test every shortcut in empty, disabled, loading, selected, dirty, and text-focused states.

## Diff Core Provenance and Parity Audit

Current status: MacMerge **does use WinMerge's bundled `Externals/xdiff` C implementation**. `MacMerge/Sources/CXDiff/vendor_*.c` compiles those upstream source files through `mmx_diff`, and `MacMergeCore/LineDiff.swift` translates native hunks into aligned rows. MacMerge does **not yet reuse the full Windows `CDiffWrapper` pipeline**; option mapping, post-filtering, row alignment, encoding, and merge behavior are partly reimplemented and require differential parity tests.

### Provenance and build integrity

- [x] Compile bundled `Externals/xdiff` sources through the `CXDiff` target.
- [x] Route production `LineDiff.compare` through `mmx_diff` with no Swift fallback.
- [x] Add a build test that records exact upstream xdiff source files and fails if a wrapper silently stops compiling one.
- [x] Add a link/runtime test proving production comparisons execute `mmx_diff` rather than a test-only implementation.
- [x] Track WinMerge xdiff patches separately and document synchronization with upstream WinMerge.
- [x] Retain the narrow ABI under measurable parity gates; `XDIFF_ARCHITECTURE_DECISION.md` records the direct-port migration trigger.

### Differential oracle tests

- [!] Build a Windows fixture oracle that runs current WinMerge `CDiffWrapper` and serializes ranges, trivial flags, moved ranges, and intra-line ranges; requires a real supported Windows build environment.
- [!] Run the same fixture corpus through MacMerge and byte-diff normalized JSON results in CI; requires the Windows oracle artifacts and hosted CI execution.
- [ ] Pin the WinMerge commit used to generate each golden result.
- [ ] Cover every fixture under `Testing/GoogleTest/DiffWrapper` and relevant `Testing/Data` directories.
- [ ] Fail CI when MacMerge changes alignment without an reviewed WinMerge-oracle update.

### Algorithm tests

- [x] Cover default, minimal, patience, histogram, and none xdiff algorithms.
- [!] Compare every algorithm against WinMerge on repeated-line and ambiguous-alignment corpora; requires the Windows oracle runner.
- [x] Cover algorithm fallback and allocation-failure paths with deterministic fault injection across all algorithms, including non-fallback and moved-block paths.
- [x] Run native allocation-failure sweeps under Address Sanitizer.
- [ ] Add Undefined Behavior Sanitizer and Thread Sanitizer jobs where supported.

### Fundamental diff-shape tests

- [x] Equal, replacement, insertion, and deletion cases.
- [x] Empty left, empty right, and both empty.
- [x] Missing final EOL and EOL-only differences.
- [x] LF, CRLF, CR, mixed EOL, and strict versus ignored EOL.
- [x] Multiple adjacent hunks and hunks separated by one unchanged line.
- [x] Long repeated runs, duplicate lines, reordered blocks, and adversarial hash collisions.
- [x] Files containing NUL bytes and binary-looking text according to WinMerge policy.
- [-] Maximum accepted byte/line boundaries and one-unit-over rejection: exact line limit and both one-over paths are covered; exact 64 MiB reaches native allocation under injected failure, while successful full-size execution remains intentionally skipped to keep unit tests bounded.

### Comparison-option tests

- [x] Ignore case.
- [x] Ignore numbers.
- [x] Ignore blank lines.
- [x] Ignore all whitespace and ignore whitespace changes.
- [x] Ignore line-ending style.
- [x] Indent heuristic parity against reconstructed upstream xdiff fixtures.
- [x] ASCII-only case folding is locale-independent in the native route; non-ASCII UTF-8/code-page bytes remain distinct, with isolated-locale regression coverage.
- [x] Combined-option coverage includes exhaustive blank-line/EOL/whitespace matrices, filter/substitution interactions, and a bounded pairwise option matrix; `.none` retains WinMerge's positional semantics and all option suites pass together.
- [x] Moved-block detection honors whole-document comment/substitution transforms, avoids unused move analysis in row-only merge paths, preserves WinMerge's exact moved-and-edited subranges, and omits move-only metadata rather than failing rows when transformed near-limit buffers exceed the native cap.

### Filter and substitution tests

- [x] Line filters over full native hunks.
- [x] Multiline regex anchors for LF, CRLF, and CR.
- [x] WinMerge capture references and supported replacement escapes.
- [x] Reject substitutions that change line structure unexpectedly.
- [-] Ignore comment differences persists and handles C-family plus JavaScript/JSON/InstallShield, legacy hash-line, PowerShell, Python, SQL, HTML with embedded JavaScript/CSS, markup, MATLAB, Properties, TOML, YAML, Basic, CSS, INI, TeX, Ada/VHDL, DCL, REXX, AutoLISP/SIOD, Fortran, NSIS, Resources, Verilog, Batch, Inno Setup, Lua, Pascal, D, Go, Rust, ABAP, AutoIt, F#, ASP, PHP, and Smarty parser families, including WinMerge's whole-comment-line, UTF-16 tokenization, embedded-NUL, quote, interpolation, column, continuation, language-mode, nested-depth, raw-string, long-delimiter, and aliased-cookie quirks; C/C++ digit-separator/raw-string and C# verbatim-string corners plus Tree-sitter-backed TypeScript/TSX and F# signature files remain pending.
- [x] Unequal filtered runs adjacent to real edits.
- [x] Multiple overlapping line filters and substitutions with deterministic declared-order precedence.
- [x] Raw-byte substitution escapes `0x80...0xFF` run through WinMerge-compatible bundled PCRE2 8-bit substitutions, remain matchable by later ordered regex rules including byte classes/ranges, and reach native xdiff as exact bytes without Unicode placeholders.
- [-] Regex invalidity, cancellation, bounded PCRE2 catastrophic-backtracking for substitutions and line filters, exact subject/output bounds, public error propagation, recovery, and concurrent calls are covered; regex allocator injection remains pending.

### Moved-block and intra-line tests

- [x] Port moved-block detection and compare moved-source/moved-destination ranges with WinMerge.
- [x] Cover duplicate moved blocks, WinMerge-exact moved-and-edited subranges, swapped and ambiguous move orientation, option transforms, and moves adjacent to insert/delete hunks.
- [ ] Port intra-line/word difference ranges.
- [x] Cover Unicode grapheme clusters, combining marks, emoji, tabs, wide glyphs, and code-page text in intra-line ranges.
- [x] Verify model selection metadata and mounted production editor highlights use the same exact sorted, disjoint UTF-16 ranges and clear them on reuse.

### Encoding and byte-preservation tests

- [x] UTF-8 with/without BOM and UTF-16 LE/BE with BOM.
- [x] Fail closed for ambiguous BOM-less UTF-16 and unsupported UTF-32.
- [-] CP932, CP51932, and CP50220 representative streams; full Windows mapping tables pending.
- [ ] Run every WinMerge code-page fixture through load, compare, edit, save, reload, and byte comparison.
- [-] Noncanonical CP932/CP50220 aliases, unrepresentable edits, canonicalized CP50220 output, and explicit CP1250/CP1251/CP1252/CP1253/CP1254 selection are covered; app-level canonicalization warning interaction remains pending.
- [-] External edits, symlink retargeting, coordinated save races, descriptor-stable bounded reads, binary/text recovery retention, identity-checked quarantine cleanup, missing/symlinked recovery artifacts, and pathless uncertainty have deterministic coverage; same-instruction unlink race elimination and broader cleanup-failure injection remain pending.

### Merge correctness properties

- [x] Row merge both directions.
- [x] Merge All both directions.
- [x] Preserve target mixed EOLs and final-newline policy where required.
- [x] For every nontrivial row, applying left-to-right then recomparing must remove exactly the intended difference and preserve unrelated bytes.
- [x] Merge All then recompare must produce zero significant differences under the same options.
- [x] Undo then recompare reproduces exact pre-merge results and redo reproduces exact post-merge results for modified, added, removed, and Merge All paths; snapshot equality is UTF-8 byte exact for NFC/NFD changes.
- [x] Directional symmetry tests swap left/right inputs and invert added/removed plus copy direction.
- [x] Randomized/property tests generate valid line documents and verify alignment, monotonic line numbers, and merge invariants.
- [-] Deterministic C ABI safety/fuzz coverage includes malformed lengths and flags, pointer/count coherence, allocation faults, hunk/moved invariants, codec inputs, regexes, filters, and cancellation; sanitizer breadth and regex allocator injection remain pending.

### Performance and UI integration tests

- [x] Deterministic release benchmarks cover 10k, 100k, 250k, and 1M rows with CSV timing, throughput, shallow row storage, resident growth, fixture export, semantic/invariant checks, and CI artifacts; packaged-app CI enforces 1M-row load, comparison, first-render, bottom-scroll, and resident-memory budgets, captures an Instruments trace when full Xcode provides `xctrace`, and validates exported completed `LoadPair`, `Comparison`, `FirstVisibleRow`, and `AutoScroll` intervals; 4 KiB long-line, tab-heavy, and wide-Unicode fixtures also run in CI.
- [x] Dense difference sets, 4 KiB long lines, tab-heavy rows, and wide-Unicode rows have deterministic core fixtures, packaged-harness support, and CI coverage.
- [-] Public comparison rows, summary, and moved metadata cross a detached Swift 6 task as `Sendable`; private app render metadata and publication pipeline isolation remain unverified.
- [x] Stale live/open generations cannot publish over newer input; scheduling invalidates old results immediately, loading preserves current old input while commands are blocked, and generation tests use bounded deterministic coordination.
- [-] UI-test selection, First/Current/Last, Next/Previous, copy, copy-and-advance, Copy All, Undo, Redo, Refresh, and Save against core results (command-chain integration coverage passes; process-level XCUI coverage remains pending).
- [-] UI-test one shared horizontal scroll position across every visible row and both panes (AppKit integration harness covers visible-row reuse, both panes, resize clamping, and zero bound; process-level XCUI coverage remains pending).
- [-] UI-test VoiceOver row status, line numbers, selected state, copy direction, and toolbar/menu command results (semantic AppKit accessibility and command tests pass; process-level VoiceOver automation remains pending).

## Milestone 6: Extended WinMerge parity

- [-] Compare images with overlays, blinking, and difference navigation (bounded native loading, normalized pixel differences, regions/navigation, overlay/blink state, and focused tests added; document routing and comparison UI pending).
- [-] Compare binary files in hexadecimal view (bounded binary alignment, hex/ASCII presentation, safe editing/save core, and focused tests added; app routing and hex-view UI pending).
- [-] Compare and create supported archives (safe archive core and tests exist; user-visible comparison/create workflow and integrated verification pending).
- [x] Design safe replacement for Windows plugin and script integrations (`MacMerge/EXTENSION_DESIGN.md` defines sandboxed out-of-process capabilities, trust, limits, compatibility mapping, UX, testing, and rollout).
- [x] Evaluate web-page and table comparison parity (`MacMerge/WEB_TABLE_PARITY_EVALUATION.md` records source-backed scope, risks, go/no-go decisions, phases, and acceptance criteria).
- [x] Document intentionally unsupported Windows shell features (`MacMerge/WINDOWS_SHELL_SCOPE.md` records adaptations, unsupported boundaries, rationale, and revisit criteria).

## Milestone 7: Release engineering

- [!] Add CI for tests, release builds, formatting, and static analysis (quality job, ShellCheck, migrated Swift-format baseline, xdiff source/runtime coverage, Clang analyzer, package artifact wiring, integrated warnings-as-errors tests, and release build pass locally); completion requires hosted CI matrix execution.
- [x] Add performance and memory regression suites: deterministic xdiff allocation-failure sweep, CI Address Sanitizer, 10k-to-1M release comparison benchmarks, packaged 1M-row UI/memory budgets, conditional full-Xcode Instruments trace artifacts, and completed signpost-interval export validation exist.
- [x] Add crash reporting and privacy documentation.
- [x] Configure sandbox entitlements and persistent security-scoped bookmarks.
- [!] Sign, notarize, package, and exercise updates on supported macOS versions (fail-closed Developer ID/notarytool release automation complete); completion requires a Developer ID certificate, notarization profile, and supported-version Mac runners.
- [x] Publish migration notes and feature-parity matrix.

## Release Readiness

- [-] Current release scope is preview-quality two-pane text comparison and merge. Core compare, edit, merge, save, reload, independent read-only controls and session restoration, release build, ad-hoc packaging, strict signing validation, and packaged AX smoke pass.
- [ ] General production release is not ready, independent of signing/notarization. Close process-level XCUI/VoiceOver coverage, supported-version runtime coverage, accessibility/contrast/localization validation, and remaining advertised workflow gaps before claiming production readiness.
- [!] Public distribution remains externally blocked on Developer ID signing, notarization credentials, hosted CI, and supported-version Mac runners.

## Verification Snapshot: 2026-08-14

- [x] `Scripts/test-ci-quality.sh`, `Scripts/check-extension-design.sh`, `shellcheck Scripts/*.sh`, and `git diff --check` pass.
- [x] The former AppKit test-window/swizzle teardown crash reproducer passes 2/2 serially, and `ShortcutStateMatrixTests` passes 11/11. The full test run progressed past the former `SIGSEGV`; crash evidence remains at `~/Library/Logs/DiagnosticReports/xctest-2026-08-12-164013.ips`.
- [x] Cycle 2 completed all 60 implementation/review/fix/test lanes. The ten new regression suites pass 44/44 together under `-warnings-as-errors`.
- [x] `ArchiveScriptContractTests` passes 8/8 after five security-review loops. Archive validation now fails closed for unsafe bundle metadata/executable paths, escaping links, hidden extra apps, unsigned or untimestamped Mach-O code, mismatched certificate/team/hash, invalid architectures, and concurrent archive-path use; `bash -n`, ShellCheck, and the ad-hoc-signing rejection path pass.
- [x] Normal text saves atomically quarantine verified displaced data and delete it through a stable filesystem-object reference, so a path swap cannot delete an unrelated replacement. Ordinary saves leave no recovery warning or artifact; changed, swapped, opaque, or uncertain artifacts remain preserved with their actual path. Recovery, code-page, filesystem-race, command-chain, and comparison-model regressions pass. Same-inode mutation between final verification and deletion remains outside the shipped hostile-filesystem guarantee and stays tracked below.
- [x] Three-way touching changes deduplicate a genuinely shared boundary insertion without collapsing an independent equal-text insertion and one-for-one replacement; mirrored and metadata cases pass 31/31. The shell-scope documentation status contract also passes.
- [x] `swift test -Xswiftc -warnings-as-errors` passes 1,161 XCTest cases with 4 skipped and 0 failures, plus 22 Swift Testing cases with 0 failures. `swift build -c release -Xswiftc -warnings-as-errors` also passes. Skips cover unavailable filesystem canonical-name/malformed-UTF-8 fixtures and two key-window interactions unavailable in the headless test host.
- [x] `Scripts/package-app.sh` produces a valid ad-hoc `dist/MacMerge.app`; strict code-sign verification, Info.plist/privacy-manifest lint, and the exact sandbox/bookmark/user-selected-file entitlements pass.
- [!] External release verification requires a Developer ID identity, notarization profile, macOS 14 runtime coverage, real GitHub Actions, packaged AX/XCUI execution, and forced MetricKit delivery.
- [x] Latest six-phase cycle completed 10 core implementation, 10 review, 10 bug-fix, 10 test-writing, 10 test-review, and 10 test-fix lanes, then repeated affected conflict/three-way/table/text-navigation/diff-context review and fix loops. The ten focused suites pass 211 tests under warnings-as-errors: conflict parsing 22, three-way merge 31, table comparison 27, clipboard comparison 15, recent pairs 18, line endings 17, bookmarks 15, text navigation 34, diff context 19, and directory pair navigation 13.
- [x] Stable `MacMergeCore` warnings-as-errors builds and `git diff --check` pass after the repeated fix loops. Final focused audits found no remaining clipboard, recent-pair, line-ending, bookmark, or directory-navigation findings; reported conflict-parser memory retention, three-way shared-boundary/EOF merge behavior, table canonical fingerprint/work accounting, text-navigation lexer/indexing defects, and invalid diff-context spans were fixed and retested.
- [x] Archive harness `/usr/bin/file` lookup is stabilized. Full warnings-as-errors tests, release build, formatting, CI-quality self-test, extension-design contract, ShellCheck, `git diff --check`, and local ad-hoc package verification pass.
- [x] Latest ten-lane core cycle completed review, bug-fix, focused test-writing, regression review/fix, and integrated verification for rename detection, syntax highlighting, session restoration, comparison statistics, synchronization points, numbered copy, conflict navigation, merge command policy, Difference Detail, and configuration reporting. Focused tranche gate passes 116 tests; policy/app integration gate passes 40 tests with 2 headless key-window skips.
- [x] Residual app lifecycle fixes now target the registered comparison scene, ignore stale reader teardown, honor forwarded close vetoes before save/discard side effects, defer discard until confirmed close, and prevent Settings/noncomparison key windows from mutating hidden comparison history. History availability ignores redundant tails without mutating during command polling; CR/LF/CRLF continuation counting excludes unsupported Unicode separators.
- [x] Explicit scanner residual review and repeated adversarial repair completed with a final independent clean audit. Scanner now has typed containment reasons, checked depth/entry/examined-entry/issue/path/byte/pending-name/open-descriptor limits, pre-syscall descriptor reservation, deterministic bounded retention, complete subtree issue/accounting/journal rollback, final origin/target/ancestry revalidation, descriptor ownership balance, cancellation propagation, and 69 focused tests with 2 filesystem-dependent skips.
- [x] Explicit text/binary recovery residual review and four adversarial repair loops completed with a final independent clean audit. Save paths pin staged/target/recovery identities, revalidate Save As bindings and retained identity/data, classify every observed post-commit failure as verified recovery or pathless uncertainty, and use identity-bound cleanup with the exact `FSDeleteObject` `OSErr` ABI. No unverified artifact path is advertised; recovery/document/code-page/app focused suites pass.
- [x] `Scripts/test-ci-quality.sh`, `Scripts/check-extension-design.sh`, ShellCheck, `git diff --check`, release warnings-as-errors build, and ad-hoc package validation pass. `dist/MacMerge.app` passes strict code-sign verification with exactly sandbox, app-scoped bookmark, and user-selected read/write entitlements. Gatekeeper rejects the ad-hoc signature as expected.
- [x] Configuration-report and numbered-copy app integration passes 73 focused tests, then the full warnings-as-errors gate: 1,270 XCTest cases with 4 skipped and 0 failures plus 22 Swift Testing cases. Release build, CI-quality, extension-design, ShellCheck, `git diff --check`, ad-hoc packaging, strict signing, plist/privacy lint, and exact three-entitlement checks pass. Packaged AX smoke copied `1: # MacMerge` from a row and a sandboxed version/build/options configuration report from Help.
- [x] Independent left/right read-only commands now share File-menu and side-header state, immediately update editor AX/editability and directional merge/save eligibility, preserve state across reload and Save As, and reject dirty read-only Save, Save All, Save-and-Reload, and replacement-save paths without partial writes. Focused warnings-as-errors command/AX coverage passes 22 tests; the full gate passes 1,310 XCTest cases with 4 skips plus 22 Swift Testing cases, release warnings-as-errors build and independent review. Packaged process-level AX smoke passes for header activation and File > Read-Only routing, including immediate summary and editor-label updates; automated XCUI remains pending.

## Verification Update: 2026-08-16

- [x] The second adversarial review/test cycle completed all ten core tranches: rename detection, syntax highlighting, session restoration, comparison statistics, synchronization points, numbered copy, conflict navigation, merge command policy, Difference Detail, and configuration reporting. Repeated independent residual audits found no remaining scoped correctness issues.
- [x] Final numbered-copy grapheme-boundary repair passes 31 focused tests. Final Difference Detail repair passes 22 focused tests, strengthened Configuration Report coverage passes 41 focused tests, and final syntax-highlighting coverage passes 89 focused tests.
- [x] Final rename-detection digest/cancellation, syntax lexer/recovery, session DEL escaping/exact-wire-shape, and conflict topology/lifecycle-precedence findings were repaired and regression-tested.
- [x] Full serial `swift test -Xswiftc -warnings-as-errors` passes 1,407 XCTest cases with 4 skipped and 0 failures plus 22 Swift Testing cases. `swift build -c release -Xswiftc -warnings-as-errors`, `Scripts/check-format.sh`, `Scripts/test-ci-quality.sh`, `Scripts/check-extension-design.sh`, ShellCheck, and `git diff --check` pass.
- [x] Comparison-session schema 1 now persists independent left/right read-only state without changing default editable wire bytes. Existing payloads default both sides to editable; explicit booleans round-trip independently; explicit null and wrong-type values fail closed. Focused warnings-as-errors coverage passes 31 tests plus independent review/fix loops.
- [x] Bounded comparison-session storage is wired into app startup, termination, and close flows with atomic persistence, explicit-open precedence, file/scratchpad identity and encoding, selection, active side, independent read-only state, location-pane state, and window frame restoration. Structurally malformed and obsolete sessions are quarantined and cleared; unloadable, oversized, probe-limited, and unsupported future sessions are preserved and fail closed.
- [x] Repeated adversarial syntax and session audits closed JSON wire limits, Swift/C/C++ numeric and regex recovery, phase-two splice handling, Markdown metadata accounting, work/cancellation bounds, and hot-loop allocation findings. Focused warnings-as-errors gate passes 181 tests; final independent closure review reports no issues.
- [x] Current `dist/MacMerge.app` was rebuilt from the reviewed source using an isolated SwiftPM build path. Info.plist, privacy manifest, exact three sandbox entitlements, arm64 executable, ad-hoc signing, and independent strict code-sign verification pass.

## Verification Update: 2026-08-17

- [x] Comparison-session storage now pins descriptor-relative directory operations, serializes processes with a revalidated lock file, revalidates reads, atomically quarantines corrupt entries, compare-and-clears superseded writes, fully syncs staged files and directories, and prohibits multiple packaged app instances.
- [x] Session schema probing validates complete JSON with strict UTF-8 and number grammar before applying schema-1 limits. Structurally corrupt and obsolete sessions are cleared; future, oversized, probe-limited, and runtime-unloadable recovery state is preserved.
- [x] Startup explicit opens, deferred close/quit callbacks, restore cancellation, option changes, stale persistence, and last-window termination are lifecycle-generation guarded. Restored comment syntax derives from restored file URLs, and independent read-only/encoding/layout state remains covered.
- [x] Exact-current warnings-as-errors gate passes 1,407 XCTest cases with 4 skipped and 0 failures plus 22 Swift Testing cases. Release warnings-as-errors build, Swift 6 packaged-smoke helper typecheck, formatting, CI-quality self-test, extension-design contract, ShellCheck, `git diff --check`, plist/privacy lint, arm64 validation, strict ad-hoc signing, and exact three-entitlement checks pass.
- [x] Isolated manual CuaDriver lifecycle smoke opens two files, persists exact contents plus independent read-only state on Quit after SwiftUI window unregistration, restores both files and read-only AX editor labels on relaunch, and gives explicit-open arguments precedence over persisted recovery. Caching the latest registered/closed comparison-window frame fixed the observed teardown-time `window state is unavailable` persistence failure; focused regression coverage passes after window unregistration and close.
- [x] Packaged sandbox restoration now opens the deepest existing Application Support ancestor directly, revalidates its descriptor identity, and retains descriptor-relative no-follow creation below it; root-by-root traversal had failed with `EPERM` inside the sandbox. An Accessibility-authorized isolated process/AX smoke passes scratchpad restoration, independent read-only activation, persisted JSON, termination, and relaunch.
- [x] Accessibility-authorized packaged process smoke creates real comparison undo history, proves `Cmd-Z`/`Cmd-Shift-Z` cannot consume it while Settings owns the key window, checks Undo/Redo menu enablement and mutations after comparison focus returns, and verifies dirty-close Cancel preserves the exact comparison and Settings windows, dirty content, and undo history. Swift 6 warnings-as-errors typechecking, ShellCheck, static review, and full runtime execution pass.
- [x] Session cleanup binds stale-write removal to exact file identity plus encoded bytes, preserves unresolved quarantine data, rejects unsafe or oversized store locations, and orders forwarded close veto, approved retry, discard, lifecycle generation, and queued termination callbacks without destructive side effects. Focused warnings-as-errors coverage passes 23 tests and final independent closure review reports no issues.

## Current Work Order

1. Resolve the latest partial ten-tranche rereview: directly verify `JSONEncoder` DEL (`U+007F`) output and fix or reject the reported session preflight overcount, rerun the cancelled rename/syntax review, then rerun unified focused, full serial, release, format, and diff gates. Synchronization/numbered-copy, conflict/policy, and Difference Detail/configuration-report rereviews returned clean.
2. Finish Location Pane parity: two-pane map, significant-difference blocks, selected marker, viewport shading, click/drag and AX slider navigation, wheel forwarding, moved connectors/navigation, adjustable accessibility/width, general context commands, persisted resized width, model tests, dark/increased-contrast screenshots, authorized automated packaged AX/runtime checks, and gated sparse/dense packaged performance are complete; add three-pane bars after three-way comparison UI exists.
3. Expand xdiff fixture parity through remaining comment syntaxes and Windows differential-oracle coverage; exact moved-and-edited subranges, MATLAB, Properties, TOML, raw-byte substitutions, blank-line combinations, adjacent hunks, and overlapping-rule precedence are complete.
4. Expand legacy code-page coverage beyond verified CP932/CP51932/CP50220/CP1250/CP1251/CP1252/CP1253/CP1254 mappings; keep unsupported mappings fail-closed.
5. [!] Obtain a Developer ID Application identity and notarization profile, then run the hardened Xcode archive/notarization flow and macOS 14+ runtime matrix.
6. Integrate tested directory scanner/comparator/results/report cores into UI; keep mutating file operations disabled until descriptor-relative commit, rollback, and recovery guarantees pass another security review.
7. Keep hostile-filesystem guarantees bounded to observed validation points: macOS exposes no atomic whole-tree namespace snapshot or atomic same-inode verify-and-delete operation. Preserve/flag uncertain artifacts and reject detected scanner instability rather than claiming stronger guarantees.

## Verification Update: 2026-08-18

- [x] Accessibility-authorized packaged smoke passes Location Pane visibility, left/right slider navigation, exact +8/-8 width adjustment through the AX adjustable handle, persisted resized width, Settings/comparison key-window Undo/Redo isolation, comparison history mutation, dirty-close Cancel preservation, independent read-only state, and relaunch restoration.
- [x] Retained dark and increased-contrast Location Pane screenshots include semantic AX sidecars, hashes, and capture provenance under `MacMerge/Tests/VisualEvidence`; system appearance was restored afterward.
- [x] Packaged context-menu activation is not claimed: synthetic mouse and detached `AXShowMenu` delivery were unreliable. Location Pane general context commands remain covered by semantic `AccessibilityCommandTests`.
- [x] Exact-current warnings-as-errors gate passes 1,409 XCTest cases with 4 skipped and 0 failures plus 22 Swift Testing cases. Release warnings-as-errors build, packaged-smoke Swift 6 typecheck, formatting, ShellCheck, Bash syntax, JSON validation, and `git diff --check` pass.
- [x] Packaged performance reports now prove exact fixture/budget inputs, forced Location Pane visibility, both nonzero current-map Canvas draws, exact map row/run counts, actual bottom-row visibility, nonzero raw resident-byte sampling, and machine/OS provenance before completion; each retained budget report has a SHA-256 sidecar.
- [x] The 250,000-line alternating changed/unchanged packaged gate passes with exactly 125,000 Location Map runs: 318 ms load, 364 ms comparison, 117 ms first row, 80 ms Location Pane render, 155 ms verified bottom scroll, and 371,146,752 resident bytes (353 MiB) against a 450 MiB ceiling on `VirtualMac2,1`, macOS 26.5.1 build 25F80.
- [x] CP1254 Turkish decoding, exact Unicode Consortium byte mapping, undefined-byte rejection, fresh encoding, automatic ambiguity ordering, unrepresentable-edit failure, document save/reload, session persistence, and decoded-byte comparison behavior pass focused warnings-as-errors coverage. Full warnings-as-errors tests and release build, formatting, CI-quality, extension-design, and `git diff --check` pass.
- [PAUSED] Later ten-tranche residual work modified the current worktree after the verified gates above. Rename/syntax focused repairs pass 86 tests, session-state repairs pass 26, and conflict/policy repairs pass 35; final numbered-copy passes 31, Difference Detail 22, and Configuration Report 41. A strict debug build and `git diff --check` passed after these edits. Final rereviews were clean for synchronization/numbered-copy, conflict/policy, and Difference Detail/configuration-report; rename/syntax rereview was cancelled, and session rereview reported a disputed DEL escaped-size overcount that requires direct encoder verification. No new full-suite, release, packaging, or exact-current count is claimed.
- [PAUSED] Dense Location Pane packaged-gate implementation and its 1,409-XCTest/22-Swift-Testing verification are recorded above. The final smoke-runner lock portability edit now uses an atomic private lock directory and still needs post-edit static and packaged-runtime verification next session.
