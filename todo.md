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
- [-] Run shared behavior tests against WinMerge comparison fixtures (no-EOL, algorithm alignment, line filters, substitutions, ignore-blank-line post-splitting, allocation recovery, and a 199-test Swift package baseline complete; broader Windows fixture parity pending).
- [-] Add encoding detection and lossless round trips (UTF-8/UTF-16 and verified CP932/CP51932/CP50220/CP1250/CP1251/CP1252 paths complete; ambiguity selection complete; broader Windows mapping parity pending).
- [x] Preserve mixed line endings and final-newline state.
- [x] Add whitespace, case, blank-line, line-filter, and substitution options.
- [x] Apply filters and substitutions to complete native diff hunks without hiding adjacent real changes.
- [x] Bound coordinated file loads and preserve symlink targets and recoverable save backups.
- [-] Detect moved blocks and expose intra-line differences (intra-line highlighting and selection complete; moved-block detection pending).
- [-] Handle large files without materializing every rendered row (reusable native table, off-main render metadata, derived row IDs, packed row metadata, single-word difference-location hashing, allocation-free editable sentinel, direct document-record comparison, and UInt32 ordered difference-row indices complete; shallow row storage is 38.1 MiB at 1M rows, packaged 1M sparse comparison uses 564 MiB total resident memory, and 250k all-different rows use 246 MiB; row text remains materialized; current safety limits: 64 MiB and 1,048,576 lines per side).

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
- [-] Add native menus, keyboard shortcuts, toolbar customization, and settings (comparison Settings scene, option persistence, and primary command shortcuts added; complete menus/customization pending).
- [ ] Add syntax highlighting and configurable colors and fonts.
- [ ] Restore window layouts and comparison sessions.
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
- [-] Mac implementation evidence: `MacMerge/Sources/MacMerge`, 199 passing package tests, packaged `.app` AX snapshots, packaged performance reports, a full-Xcode Instruments capture harness, and installed-app smoke tests.

### Required state matrix

- [ ] Comparison lifecycle: empty, one side loaded, loading, current, stale, refreshing, failed, and canceled.
- [ ] Result: identical, different without selection, first/middle/last selected, cursor on a difference, and selection offscreen.
- [ ] Documents: both files, mixed file/scratchpad, both scratchpads, each dirty combination, save failure, external change, and missing disk file.
- [ ] Editability: left/right/both read-only, editable destination, and text editor owning focus.
- [ ] Pane shape: two-way, three-way, active left/middle/right, swapped, vertical, and horizontal.
- [ ] Folder selection: none, one, many, mixed file/folder, missing side, identical, different, filtered, and hidden.
- [ ] Window state: key/background, multiple windows, tabs, narrow toolbar, restored session, and full-screen.
- [ ] Invocation: primary click, secondary arrow, menu item, shortcut, keyboard traversal, VoiceOver action, and disabled activation.

### Application shell and opening

- [PARTIAL] `IDR_MAINFRAME`: main application window, native menu bar, command strip, one comparison window, and status strip exist; multiple document windows/tabs, restorable sessions, output pane, and complete status state are missing.
- [MISSING] `IDD_OPEN`: unified Select Files or Folders view with two/three paths, read-only flags, swaps, browse/history, filter, recurse, unpacker/prediffer, comparison options, project save, and Compare split button.
- [PARTIAL] `IDR_POPUP_NEW`: two-pane Text exists; Table, Binary, Image, Webpage, Folder, every three-pane mode, and split-button secondary actions are missing.
- [PARTIAL] `IDR_POPUP_OPEN` and `IDR_POPUP_BROWSE`: native pair picker and per-side replacement exist; recent pairs, path history, project/conflict/clipboard variants, and split-button behavior are missing.
- [MAC_ADAPTATION] Windows common file/folder pickers: use `NSOpenPanel`, `NSSavePanel`, and Finder document events while preserving pair selection, cancellation, validation, and security-scoped access.
- [PARTIAL] Drag/drop and shell opening: Finder Open With works initially and while running; direct pane drop, pair drop, replacement drop, and Finder Services are missing.

### Compare workspaces

- [PARTIAL] `IDR_MERGEDOCTYPE` text compare: two editable panes, alignment, line numbers, synchronized scrolling, row and intra-line highlighting, merge, save, and encoding safety exist; three-way text, moved blocks, word-diff model, syntax, margins, and complete view commands are missing.
- [MISSING] Table Compare and `IDD_OPEN_TABLE`: spreadsheet rendering, table header/filter menu, delimiters, quote/newline settings, and table-specific options.
- [MISSING] Hex/Binary Compare: native hex panes, byte editing, binary find/replace/go-to, character sets, per-pane status, and binary settings.
- [MISSING] Image Compare: multipage panes, location/tool pane, differences, block size, threshold, insertion detection, transforms, zoom, overlay, wipe, animation, OCR, and image status.
- [MISSING] Webpage Compare: browser panes, location/tool pane, screenshot/HTML/text/resource modes, viewport presets, synchronized events, browsing-data controls, and dependency handling.
- [MISSING] Folder Compare: recursive scan, table/tree results, state icons, columns, filters, sorting, method selection, file actions, progress/pause/cancel, and file-pair opening.

### Main menus and command surfaces

- [PARTIAL] File menu: New Text, pair Open, Save/Save Left/Save Right, Save Left/Right As, Merge Mode, Reload, and guarded Quit exist; all remaining `IDR_MERGEDOCTYPE` File commands are mapped in the command audits below.
- [PARTIAL] Edit menu: native field editing, model undo/redo, Select Line Difference, and Options exist; focus-routed history, previous line-difference selection, search, markers, numbered copy, bookmarks, and go-to are missing.
- [MISSING] View menu: font, zoom, syntax, diff context, whitespace/EOL/line differences/numbers/margins/wrap, pane swap/split/lock, toolbar choices, and dockable pane visibility.
- [PARTIAL] Merge menu: two-way cursor-relative navigation and copying exist; conflicts, three-way commands, Auto Merge, selected-line operations, and synchronization points are incomplete.
- [MISSING] Tools menu: Filters, Generate Patch, Generate Report, and Generate Archive.
- [MISSING] Plugins menu: settings, prediffers, unpackers, editor/copy scripts, transforms, and reload.
- [PARTIAL] Window menu: native close/minimize/zoom and two-pane Change Pane exist; multiple comparison windows/tabs, split, and document arrangement are missing.
- [MISSING] Help menu: Help Book, release notes, translations, configuration report, GPL, contributors, and complete About content.
- [PARTIAL] `IDR_MAINFRAME` toolbar: implemented commands use compact icons; exact command contract remains governed by the Toolbar Command Audit.
- [MISSING] Toolbar visibility, None/Small/Medium/Big/Huge sizes, native overflow, customization, reset, and persistence.
- [PARTIAL] Text editor context menu matches WinMerge's two-pane order and routes merge, selected-diff clipboard, line-difference, undo/redo, editing, and native file opening; selected-line merge, filters, scripts, go-to, shell, and other workspace context menus remain missing.
- [PARTIAL] Accelerators: native document shortcuts and some Option/Command merge shortcuts exist; full accelerator parity and focus-safety tests are missing.

### Bars, panes, and status surfaces

- [MISSING] MDI/document tab bar and tab context menu; replace with native windows/tabs while preserving dirty state, close-other/left/right, width, and restoration outcomes.
- [PARTIAL] `IDD_EDITOR_HEADERBAR`: side caption, filename, dirty state, open, and save exist; editable path, history, read-only, clipboard, plugin state, and header context menu are missing.
- [MISSING] Location Pane: whole-file map, moved blocks, click navigation, and context menu.
- [MISSING] Diff/Detail Pane: selected word/character difference detail and merge controls driven by the same intra-line model.
- [MISSING] Output Pane: message log plus Copy, Select All, Clear All, visibility, and persistence.
- [MISSING] `IDD_DISPLAY_FILTER_BAR`: expression, history/presets, apply/close, text/folder variants, and restoration.
- [PARTIAL] `IDD_ENCODINGERROR`: explicit encoding selection and safe failures exist as dialogs; recovery bar, unpacker, and hex alternatives are missing.
- [PARTIAL] Global status: processing/result, Merge Mode, difference count, and filenames exist; plugin state, current difference, and command prompts are missing.
- [MISSING] Per-pane text/table status: line, column, character, selection, encoding, BOM, EOL, and read-only state with click actions.
- [MISSING] Folder, hex, image, and web mode-specific status surfaces.

### Dialog inventory

- [PARTIAL] `IDD_ABOUTBOX`: native About shell exists; WinMerge version detail, contributors, license, links, and credits are missing.
- [PARTIAL] `IDD_SAVECLOSING`: native save/discard/cancel adaptation exists; independent per-side choices and UI tests are missing.
- [PARTIAL] `IDD_LOAD_SAVE_CODEPAGE` and `IDD_ENCODINGERROR`: ambiguity selection exists; pane scope, load/save code pages, BOM controls, and recovery actions are incomplete.
- [MISSING] `IDD_EDIT_FIND`, `IDD_EDIT_REPLACE`, `IDD_EDIT_MARKER`, and `IDD_WMGOTO`.
- [MISSING] `IDD_DIRCOLS`, `IDD_DIRADDITIONALPROPS`, `IDD_DIRCOMP_PROGRESS`, `IDD_CONFIRM_COPY`, `IDD_SELECT_FILES_OR_FOLDERS`, `IDD_COMPARE_STATISTICS`, and `IDD_COMPARE_STATISTICS3`.
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
- [MISSING] Conflict parser and Base/Theirs/Mine comparison with conflict navigation.
- [MISSING] Clipboard text/image comparison and clipboard history menus.
- [MAC_ADAPTATION] Explorer registered editor/Open With/parent/shell menus: use Finder Open With, Reveal in Finder, Share/Services, and native file actions.
- [MISSING] Native recent documents plus WinMerge-compatible recent pair/folder history.
- [MISSING] Windows Jump List outcome: expose recent comparisons and common tasks through native recents, Dock menu, and app shortcuts where appropriate.

### Reports, patch, archive, filters, plugins, and scripts

- [MISSING] File and folder comparison reports with formats, clipboard output, linked file reports, and open-after-generation.
- [MISSING] Patch Generator with file selection, style/context, append, clipboard, command line, and external editor.
- [MISSING] Archive Generator with report/patch/project inclusion and file/clipboard output.
- [PARTIAL] Filter settings include line/substitution editors; file filters, condition builders, comparison-result filters, expression helpers, and dedicated test dialogs remain missing.
- [MISSING] Plugin manager/editor/selector, unpacker/prediffer selection, automatic/manual modes, editor/copy scripts, macros, settings, and reload.
- [UNKNOWN] Plugin architecture adaptation: define a sandboxed, permission-aware extension model or document intentional unsupported scope before implementation.

### Navigation, merge, and pane controls

- [PARTIAL] First/Current/Previous/Next/Last Difference and cursor-relative fallback exist; offscreen-selection behavior still needs parity verification.
- [MISSING] Next/Previous Conflict and all three-way pair-specific or side-only navigation.
- [PARTIAL] Copy Left/Right, Copy-and-Advance, Copy All, and current-line fallback exist; multi-difference selection, selected-line copy, read-only targets, and Auto Merge are incomplete.
- [MISSING] First/Previous/Next/Last compared-file navigation from folder results.
- [PARTIAL] Change Pane cycles two-pane editor focus with `F6`/`Shift-F6` while preserving logical row; synchronization points, bookmarks, go-to definition, moved-line navigation, pane swap/lock, and dynamic split controls remain missing.

### Accessibility, persistence, and test completion

- [PARTIAL] Existing file controls, toolbar controls, summary, rows, editors, and selected state expose basic AX metadata.
- [ ] Add unique role, label, value, hint, enabled/check/selection state, focus order, actions, and announcements to every control and dynamic result.
- [ ] Verify Full Keyboard Access, VoiceOver activation, increased contrast, differentiate-without-color, dark mode, and localization expansion.
- [PARTIAL] Current text comparison preferences persist; window frames/tabs, panes, toolbar, recents, bookmarks, comparison sessions, and sandbox access remain missing.
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
- [-] `ID_FILE_OPEN`: pair-level primary picker and left/right replacement exist; add WinMerge's full Open view and recent-path behavior.
- [x] `ID_FILE_OPEN`: present a split-button/menu indicator for pair Open plus left/right replacement actions.
- [ ] `ID_FILE_OPENCONFLICT`: open and parse a conflict file.
- [ ] `ID_FILE_OPENCLIPBOARD`: compare clipboard contents.
- [ ] `ID_FILE_OPENPROJECT`: open a WinMerge project.
- [ ] `ID_FILE_SAVEPROJECT`: save a comparison project.
- [ ] Recent files/folders: expose native recent items and WinMerge-compatible pair history.
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
- [ ] `ID_SELECTPREVLINEDIFF`: select the previous intra-line difference.
- [ ] Verify Undo/Redo button and Edit menu state against focused text editing versus comparison merge history.

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
- [ ] Match WinMerge navigation behavior when selected difference is offscreen.
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
- [ ] Implement read-only destination state and disable directional merge commands correctly.

### Comparison-set, options, and refresh commands

- [ ] `ID_FIRSTFILE`: open the first file pair from directory comparison results.
- [ ] `ID_PREVFILE`: open the previous file pair from directory comparison results.
- [ ] `ID_NEXTFILE`: open the next file pair from directory comparison results.
- [ ] `ID_LASTFILE`: open the last file pair from directory comparison results.
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
- [ ] Left/Middle/Right Read-Only state.
- [ ] Convert Line Endings to CRLF, LF, or CR without changing unrelated terminators unexpectedly.
- [x] Merge Mode persists, exposes checked `F9` state and status, and maps unmodified arrows to merge/navigation while modified arrows retain editor behavior.
- [-] Guarded Reload from Disk and ambiguity-driven encoding selection exist; explicit File Encoding menu selection and broader rescan behavior remain missing.
- [ ] Recompare As Text, Table, Binary, Image, Webpage, or Archive.
- [ ] Recent Files or Folders using native recent-document integration.
- [x] Exit/Quit warns about unsaved work and save recovery notices.

### Edit menu

- [ ] Wire Undo and Redo to the correct focused editor or comparison history.
- [ ] Cut, Copy, Paste, and Select All for scratchpads and selectable diff text.
- [-] Select Line Difference exists; Select Previous Line Difference remains missing.
- [ ] Find, Replace, Marker, and Repeat Search.
- [ ] Copy With Line Numbers.
- [ ] Toggle, Next, Previous, and Clear All Bookmarks.
- [ ] Go to Line and Go to Definition.
- [x] Options with native `Command-,` integration.

### View menu

- [ ] Font selection, default font, zoom in/out/normal.
- [ ] Syntax highlighting scheme selection.
- [ ] Diff context All/0/1/3/5/7/9, toggle, and invert.
- [ ] Lock Panes, View Whitespace, View EOL, View Line Differences, View Line Numbers, View Margins, Top Margins, and Wrap Lines.
- [ ] Swap panes and vertical/horizontal split behavior.
- [ ] Toolbar visibility, size, overflow, and customization.
- [ ] Status, detail, location, output, and display-filter panes.
- [x] Refresh with `F5` semantics.

### Merge menu

- [x] Next, Previous, First, Current, and Last Difference.
- [ ] Next and Previous Conflict.
- [ ] Three-way advanced difference navigation for each pane pair and one-sided difference type.
- [-] Directional copy and copy-and-advance exist; dedicated copy-from aliases and selected-lines copy remain missing.
- [x] Copy All Left and Copy All Right.
- [ ] Auto Merge.
- [ ] Add and clear synchronization points.
- [ ] Ensure menu and toolbar invoke one shared command implementation and one shared enabled-state implementation.

### Tools, Plugins, Window, and Help menus

- [ ] Filters, Generate Patch, Generate Report, and Generate Archive.
- [ ] Define macOS replacement or explicit unsupported status for unpackers, prediffers, editor scripts, copying scripts, and plugin reload.
- [-] Native Close plus two-pane Change Pane exist; Close All, Split, Tile, and multi-window navigation remain missing.
- [ ] Help, Release Notes, Translations, Configuration, license, and About MacMerge.
- [ ] Add menu validation tests for title, order, shortcut, checked state, enabled state, target action, and result.

## Keyboard Shortcut Audit

- [ ] Port command shortcuts from `Merge.rc` without overriding native text-editing keys while an editor owns focus.
- [ ] Test New `Command-N`, Open `Command-O`, Save `Command-S`, Quit `Command-Q`, and Close `Command-W`.
- [ ] Test Undo `Command-Z` and Redo `Command-Shift-Z` plus focused-editor routing.
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
- [x] Multiple adjacent hunks and hunks separated by one unchanged line.
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
- [-] Combined-option coverage includes exhaustive blank-line/EOL/whitespace matrices and filter/substitution interactions; broader pairwise option generation remains pending.

### Filter and substitution tests

- [x] Line filters over full native hunks.
- [x] Multiline regex anchors for LF, CRLF, and CR.
- [x] WinMerge capture references and supported replacement escapes.
- [x] Reject substitutions that change line structure unexpectedly.
- [-] Ignore comment differences persists and handles C-family plus JavaScript/JSON/InstallShield, legacy hash-line, Python, SQL, markup, MATLAB, Properties, TOML, YAML, Basic, CSS, INI, TeX, Ada/VHDL, DCL, REXX, AutoLISP/SIOD, Fortran, NSIS, Resources, Verilog, Batch, Inno Setup, Lua, Pascal, D, Go, Rust, ABAP, AutoIt, and F# parser families, including WinMerge's whole-comment-line, UTF-16 tokenization, embedded-NUL, quote, interpolation, column, continuation, language-mode, nested-depth, raw-string, long-delimiter, and aliased-cookie quirks; C/C++ digit-separator/raw-string and C# verbatim-string corners, HTML embedded languages, Tree-sitter-backed TypeScript/TSX and F# signature files, and remaining ASP/PHP/Smarty parser families are pending.
- [x] Unequal filtered runs adjacent to real edits.
- [x] Multiple overlapping line filters and substitutions with deterministic declared-order precedence.
- [x] Raw-byte substitution escapes `0x80...0xFF` run through WinMerge-compatible bundled PCRE2 8-bit substitutions, remain matchable by later ordered regex rules including byte classes/ranges, and reach native xdiff as exact bytes without Unicode placeholders.
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

- [x] Deterministic release benchmarks cover 10k, 100k, 250k, and 1M rows with CSV timing, throughput, shallow row storage, resident growth, fixture export, semantic/invariant checks, and CI artifacts; packaged-app CI enforces 1M-row load, comparison, first-render, bottom-scroll, and resident-memory budgets, captures an Instruments trace when full Xcode provides `xctrace`, and validates exported completed `LoadPair`, `Comparison`, `FirstVisibleRow`, and `AutoScroll` intervals; 4 KiB long-line, tab-heavy, and wide-Unicode fixtures also run in CI.
- [x] Dense difference sets, 4 KiB long lines, tab-heavy rows, and wide-Unicode rows have deterministic core fixtures, packaged-harness support, and CI coverage.
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
- [x] Add performance and memory regression suites: deterministic xdiff allocation-failure sweep, CI Address Sanitizer, 10k-to-1M release comparison benchmarks, packaged 1M-row UI/memory budgets, conditional full-Xcode Instruments trace artifacts, and completed signpost-interval export validation exist.
- [ ] Add crash reporting and privacy documentation.
- [ ] Configure sandbox entitlements and persistent security-scoped bookmarks.
- [ ] Sign, notarize, package, and exercise updates on supported macOS versions.
- [ ] Publish migration notes and feature-parity matrix.

## Current Work Order

1. Remove duplicate row-text ownership to reduce materialized 1M-row storage further; packed rows, single-word difference locations, UInt32 ordered indices, and dense/4 KiB/tab-heavy/wide-Unicode benchmarks are complete.
2. Expand xdiff fixture parity through remaining comment syntaxes and moved-block behavior (MATLAB, Properties, TOML, raw-byte substitutions, blank-line combinations, adjacent hunks, and overlapping-rule precedence complete).
3. Expand legacy code-page coverage beyond verified CP932/CP51932/CP50220/CP1250/CP1251/CP1252 mappings; keep unsupported mappings fail-closed.
4. Convert packaging to an Xcode archive with sandbox entitlements and Developer ID signing.
5. Expand into directory comparison after text-core behavior is fixture-compatible.
