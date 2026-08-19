# Webpage and Table Comparison Parity Evaluation

Status: engineering recommendation for `todo.md` Milestone 6 evaluation, 2026-08-11. This document evaluates behavior and implementation choices; it does not implement either feature or change roadmap state.

## Executive decision

| Scope | Decision | Reason |
| --- | --- | --- |
| Two-pane table comparison for CSV, TSV, and custom single-character DSV | **GO, phased** | WinMerge table mode is a record-oriented presentation and editing layer over its text comparison, not a spreadsheet engine. MacMerge can reuse coordinated I/O, command/history shells, xdiff through a new record adapter, and virtualized AppKit concepts; physical-line editing/merge cannot be reused. A byte-provenance parser and table-specific render/edit/merge model are required. |
| Full WinMerge table parity | **NO-GO as one milestone item** | WinMerge also supports three panes, configurable file-pattern routing, table reports, column filters, and mature column interactions. MacMerge has no three-pane model or integrated table-report workflow. Claim two-pane parity only after the acceptance gates below; keep remaining gaps explicit. |
| Port or reuse `WinWebDiffLib.dll` | **NO-GO** | It is a downloaded Windows binary with a Win32/COM-style ABI and WebView2 dependency, not portable source integrated into this tree. |
| Full dynamic webpage comparison parity | **NO-GO now** | It would add outbound networking, active untrusted content, browser profiles, nondeterministic rendering, JavaScript instrumentation, and large capture workloads to an app whose current privacy contract says it has no network services. Native WebKit cannot exactly reproduce Chromium/WebView2 output, and public WebKit APIs do not provide an exact WinWebDiff resource-tree inventory. |
| Native webpage research prototype | **CONDITIONAL GO after prerequisites** | An offline-local-fixture `WKWebView` spike may validate bounded HTML/text extraction and scroll synchronization independently. Viewport snapshot handoff requires accepted image-workspace integration; observed-resource/folder integration is optional spike work, and reports are explicitly deferred. Do not ship remote URL loading until a product decision accepts the network/privacy change and a threat model is approved. |

Priority recommendation: implement table comparison first. Defer remote webpage comparison until network/privacy approval, then reevaluate it as an explicitly experimental, privacy-scoped product rather than ordinary text-parity work. Image, folder, and report workspaces are prerequisites only for their corresponding snapshot, observed-resource, and report increments.

## Parity definition

This evaluation uses behavioral parity, not source or rendering-engine identity:

- Inputs are recognized or explicitly selected in the same useful cases.
- Parsing preserves record, field, encoding, line-ending, and quoting semantics needed for safe editing and saving.
- Comparison, navigation, editing, merging, undo/redo, and any included reporting produce equivalent user-visible outcomes within declared pane and feature scope.
- Unsupported WinMerge behavior is named rather than silently approximated.
- Security, privacy, resource, cancellation, and performance limits are part of the contract.

Pixel-identical webpage output across WebView2/Chromium and WebKit is not a viable parity criterion. Remote pages vary with browser engine, user agent, time, cookies, locale, network responses, font rasterization, viewport, animation, and service-worker state.

No `CODEOWNERS` file exists in this repository. "Owner" below therefore means source/runtime responsibility, not a maintainer assignment.

## WinMerge behavior inventory

### Table comparison

WinMerge table mode is delimiter-aware text comparison:

- It offers two- and three-pane Table entry points and routes `ID_MERGE_COMPARE_TABLE` through `CMainFrame` into the normal `CMergeDoc`/`CMergeEditFrame` stack, setting table editing properties before load. [W-TABLE-ROUTING]
- It automatically recognizes configured CSV, TSV, and custom DSV filename patterns. Defaults are `*.csv` with comma and `*.tsv` with tab; custom DSV defaults to semicolon but has no default filename pattern. Quote and "allow newlines in quotes" are exposed as global table options, but current custom-DSV auto/fallback initializers omit the fourth `TableProps` field and therefore disable quoted-newline joining; CSV, TSV, and the explicit dialog carry the setting. Treat this as observed WinMerge behavior/bug, not desired MacMerge parity. [W-TABLE-OPTIONS]
- Recompare As Table is conditional: when already in table mode it opens `COpenTableDlg`; from text mode, files matching configured CSV/TSV/DSV patterns reload directly with those settings, while an unmatched file reaches the dialog during reload. Recompare As Text returns to normal text display. The command line accepts `/t table` and table delimiter, quote, and quoted-newline options. [W-TABLE-MANUAL] [W-TABLE-DIALOG] [W-TABLE-OPTIONS] [W-TABLE-TESTS]
- The buffer uses a permissive quote-parity scanner: every enclosure character toggles quoted state wherever it occurs, delimiters count only outside that state, and quoted-newline mode joins physical lines until parity closes or EOF is reached. It does not enforce RFC field-boundary rules or reject an unmatched enclosure. `GetCellText` returns the serialized field slice, including enclosure characters and doubled enclosure characters; WinMerge does not display a dequoted CSV value. The implementation does not build typed spreadsheet values. [W-TABLE-BUFFER]
- All panes share column widths. The view exposes headers, optional first-record header labels, wrapping, drag resize, auto-fit, and vertical column selection. [W-TABLE-MANUAL] [W-TABLE-MODEL] [W-TABLE-VIEW]
- Difference navigation, editing, undo/redo, and directional merge remain normal text-window operations. Table mode forces intraline computation per logical record, but row alignment remains text/xdiff alignment; there is no key-column join, row sorting, formula evaluation, or typed numeric/date equivalence in the table owner. [W-TABLE-MANUAL] [W-TABLE-LINEDIFF]
- Table comparison emits a table-specific HTML report from `CMergeDoc`. Column context commands can add column-aware display filters. [W-TABLE-REPORT] [W-TABLE-VIEW]

This distinction is important: parity requires lossless logical-record handling and a column UI, not a spreadsheet data model.

### Table owners and resources

| Responsibility | WinMerge owner | Evidence |
| --- | --- | --- |
| Mode creation and routing | `CMainFrame`, `CMergeDoc` | `Src/MainFrm.cpp`, `Src/MergeDoc.cpp` [W-TABLE-ROUTING] |
| Pattern and delimiter settings | `PropCompareTable`, options registry | `Src/PropCompareTable.cpp`, `Src/OptionsDef.h`, `Src/OptionsInit.cpp` [W-TABLE-OPTIONS] |
| Explicit format dialog | `COpenTableDlg` | `Src/OpenTableDlg.cpp`, `Src/Merge.rc` [W-TABLE-DIALOG] |
| Record/column interpretation | `CCrystalTextBuffer` in Crystal Edit | `Externals/crystaledit/editlib/ccrystaltextbuffer.cpp` [W-TABLE-BUFFER] |
| Rendering and column interaction | `CMergeEditView` plus Crystal Edit view | `Src/MergeEditView.cpp`, `Externals/crystaledit/editlib/ccrystaltextview.cpp` [W-TABLE-VIEW] |
| Diff, merge, save, undo | Existing text owners `CMergeDoc`, `CDiffTextBuffer`, edit views | Table manual and `Src/MergeDocLineDiffs.cpp` [W-TABLE-LINEDIFF] |
| Windows resources | `IDD_OPEN_TABLE`, `IDD_PROPPAGE_COMPARE_TABLE`, File/New and Compare-As menu resources | `Src/Merge.rc` [W-RESOURCES] |
| Existing verification | Command-line/window-type and table property tests | `Src/Test.cpp`, `Testing/GoogleTest/CmdLine/MergeCmdLine_test.cpp` [W-TABLE-TESTS] |

### Webpage comparison

WinMerge webpage mode is an embedded browser comparator and exporter:

- The manual labels it experimental, potentially unstable, and very slow. It opens two or three URLs from the open dialog or `/t webpage`. Current documented limitations include FRAMESET, incomplete IFRAME comparison/event synchronization, and poor performance for very different pages. [W-WEB-MANUAL]
- `CWebPageDiffFrame` owns the WinMerge frame, but dynamically loads `WinWebDiff\WinWebDiffLib.dll` and delegates browser/comparison behavior through `IWebDiffWindow`. The dependency manifest pins WinWebDiff 1.0.20.0 and WebView2 SDK/package 1.0.1518.46, plus WIL, RapidJSON, and LibXDiff; `1.0.1518.46` is not proof of the installed Evergreen WebView2 runtime or Chromium engine version. WinMerge checks for a runtime at execution, while build setup downloads architecture-specific WinWebDiff release artifacts rather than building that implementation in this source tree. [W-WEB-FRAME] [W-WEB-ABI] [W-WEB-DEPS]
- The frame prompts to install the WebView2 runtime when unavailable, creates browser panes and a WinWebDiff tool/location window, and supports two or three inputs. Include/exclude regexes are tested against each raw input path or URL before ordinary type dispatch; one matching pane routes the whole comparison to webpage mode. Inputs then traverse the browser-mode unpacker pipeline before `IWebDiffWindow::Open`. Plugin-backed inputs are WinMerge behavior but are outside proposed MacMerge webpage scope. [W-WEB-ROUTING]
- Browser controls include horizontal/vertical pane layout, zoom, fit-to-window, fixed viewport sizes, custom user agent, difference and word-difference overlays, dark appearance, refresh, back/forward behavior, and first/previous/next/last difference navigation. Three-pane mode also exposes conflict navigation. [W-WEB-ABI] [W-WEB-FRAME]
- Event synchronization can independently mirror scroll, click, input, and back/forward events. Security-relevant WinMerge defaults are persistent AppData profiles, a separate user-data folder per pane, synchronization enabled, and flags `0xff`, which enables every currently defined event type. Browser data controls clear disk cache, cookies, history, or all profile data. [W-WEB-MANUAL] [W-WEB-ABI] [W-WEB-DEFAULTS]
- Derived comparisons request viewport screenshot, full-page screenshot, HTML, extracted text, or `RESOURCETREE` output into temporary artifacts, then hand those artifacts to image, text, or folder comparison owners. HTML uses the `PrettifyHTML` unpacker. Current callbacks ignore `WebDiffCallbackResult.errorCode` and open downstream comparisons after failed or partial `SaveFiles`; MacMerge must not copy that failure path. Because the DLL implementation is absent, the checked-in ABI proves that `RESOURCETREE` exists but not which requests, redirects, caches, service workers, bodies, or metadata it records. Treat it as black-box behavior pending version-pinned WinWebDiff fixture captures or upstream implementation evidence. [W-WEB-DERIVED] [W-WEB-ABI]
- Webpage reports ask WinWebDiff for per-pane difference PDFs and embed them in HTML. `CWebPageDiffFrame` writes pane report titles/descriptions into `<th>` content without HTML escaping, so an attacker-controlled URL or description can inject active markup into an opened report. Source/tab-change logging also writes the full current URL, including possible userinfo, query secrets, and fragments. These are WinMerge vulnerabilities to avoid, not parity requirements. The frame reports `IsModified() == false`; its ABI exposes browser edit commands but no cross-pane copy/merge operation or durable save-back contract. Webpage parity therefore does not imply webpage merging. [W-WEB-FRAME] [W-WEB-REPORT] [W-WEB-ABI]

### Webpage owners and resources

| Responsibility | WinMerge owner | Evidence |
| --- | --- | --- |
| Mode routing and host integration | `CMainFrame`, `CWebPageDiffFrame` | `Src/MainFrm.cpp`, `Src/WebPageDiffFrm.{h,cpp}` [W-WEB-FRAME] |
| Browser, DOM comparison, synchronization, captures | External `WinWebDiffLib.dll` through `IWebDiffWindow` | `Src/WinWebDiffLib.h` [W-WEB-ABI] |
| Browser runtime | Microsoft WebView2 Evergreen runtime | Runtime-presence check; checked-in `1.0.1518.46` identifies the SDK/package dependency, not guaranteed installed runtime/engine [W-WEB-DEPS] |
| Derived screenshot comparison | Image comparison owner | `CWebPageDiffFrame::OnWebCompareScreenshots` [W-WEB-DERIVED] |
| Derived HTML/text comparison | Text comparison owner and optional `PrettifyHTML` unpacker | `CWebPageDiffFrame::OnWebCompareHTMLs/Texts` [W-WEB-DERIVED] |
| Derived resource comparison | Folder comparison owner | Black-box `RESOURCETREE` export in `CWebPageDiffFrame::OnWebCompareResourceTrees` [W-WEB-DERIVED] |
| Settings | `PropCompareWebPage`, WinMerge options, WinWebDiff profile store | `Src/PropCompareWebPage.cpp`, `Src/OptionsDef.h` [W-WEB-OPTIONS] |
| Windows resources | Webpage menus, sync menus, property page, string and bitmap resources | `Src/Merge.rc` [W-RESOURCES] |

## Current MacMerge state and gaps

### Reusable foundations

- MacMerge targets macOS 14 and has no remote Swift package or binary dependencies. Package products are the app, benchmark executable, and `MacMergeCore`; targets also include the local `CXDiff` C bridge plus core and app tests. [M-PACKAGE]
- `TextFileDocumentIO` already provides bounded 64 MiB reads, encoding preservation, security-scoped access, `NSFileCoordinator`, symlink-aware identity checks, external-change rejection, atomic replacement, and recovery-copy behavior. [M-IO]
- `LineDiff` already aligns source-backed logical lines through xdiff with a 64 MiB and 1,048,576-line limit. The app computes comparison/render metadata in an actor and publishes rows through generation-guarded operations. [M-DIFF] [M-MODEL]
- Current `NSTableView` rendering reuses row views, owns one vertical scroll model, and applies one shared horizontal offset across both text panes. Navigation/history command shells and coordinated I/O are candidates for reuse, but current `DiffRow`, `ComparisonModel.editLine`, `LineTextEditing`, and `LineMerge` are keyed to physical line numbers. Stable logical-record IDs alone cannot make editing or merging mode-independent; table mode needs record/cell coordinates plus rendering, editing, and merge adapters. [M-RENDER] [M-LINE-MERGE]
- `MacMergeCore` contains bounded image loading/pixel comparison and image presentation state, tested folder scanning/comparison/result prototypes, and a tested bounded plain-text/CSV/HTML report generator. These remain unaccepted end-to-end image/folder/report workflows: `MacMergeApp.swift` has no workspace integration or derived-artifact handoff, and mutating folder operations deliberately fail closed pending commit/rollback guarantees. Require accepted integration for each derived webpage feature that uses one. [M-DERIVED-CORES] [M-REPORT] [M-PROTOTYPE-STATUS]
- Existing release gates exercise up to one million text rows with 5-second load, 5-second comparison, 1.5-second first render, 1.5-second bottom scroll, and 900 MiB resident-memory budgets. [M-PERFORMANCE]

### Table gaps

- Table is a disabled menu placeholder. `ComparisonProject.Mode` already serializes `.table` and `.webpage`, but `ComparisonModel` and app routing have no integrated runtime mode discriminator. There is no CSV/TSV pattern routing, Recompare As Table action, delimiter/quote settings, or table-specific command-line contract. [M-PROJECT-MODE] [M-UI]
- Current `LineDiff` splits `String` input on physical CR/LF. A quoted field containing a newline would become multiple diff rows, unlike WinMerge's logical-record behavior. [M-DIFF]
- No lossless record/cell model tracks raw source ranges, delimiter positions, quote escaping, embedded line endings, uneven field counts, or per-record terminators.
- Current AppKit table contains one `NSTableColumn`; each custom cell paints two line panes. It has no field columns, header rows, corresponding-width synchronization, column selection, wrapping by cell, or auto-fit. [M-RENDER]
- Current snapshots and merge primitives are whole-text and physical-line based. `LineMerge.apply/applyAll` reparses CR/LF records and therefore can split or merge fragments of a quoted multiline table record. Table editing and directional merge must operate on logical-record raw ranges and cannot call the physical-line primitives. [M-LINE-MERGE]
- MacMerge supports two inputs only. WinMerge table mode also supports three panes. [M-MODEL] [W-TABLE-ROUTING]
- The generic report generator has no table adapter or app export UI, and there is no column-aware display-filter UI. [M-REPORT] [M-MIGRATION]

### Webpage gaps

- Webpage is also a disabled placeholder. File pickers accept local text/source/data files, open requests are truncated to two URLs, and the document model requires local `TextFileDocument` values. [M-UI] [M-MODEL]
- MacMerge imports neither WebKit nor a browser abstraction. It has no address/navigation UI, load lifecycle, browser profile store, event bridge, HTML/text/resource extraction, capture path, webpage diff model, or browser-process failure handling. [M-PACKAGE]
- The sandbox entitlements allow user-selected files and app-scoped bookmarks but not outgoing network connections. Apple requires `com.apple.security.network.client` for a sandboxed app to initiate them. [M-ENTITLEMENTS] [A-NETWORK]
- The published privacy contract says MacMerge has no network services and compared content and paths are not sent anywhere. Remote webpage loading necessarily sends destination/request metadata and can send cookies, form data, redirects, and page-driven subrequests depending on state and page behavior. This needs an explicit privacy-policy and product-contract revision, not only an entitlement edit. [M-PRIVACY]
- Image, folder, and generic report core prototypes exist, but the app has no corresponding workspaces, commands, export UI, or temporary-artifact handoff. They are tested partial cores, not accepted end-to-end workflows; mutating folder operations remain fail-closed. WinMerge's screenshot, resource-tree, and PDF-report paths therefore remain unavailable end to end. [M-DERIVED-CORES] [M-REPORT] [M-MIGRATION] [M-PROTOTYPE-STATUS]
- WebKit and WebView2 have different engines and privacy behavior. WebKit blocks third-party cookies by default and applies Intelligent Tracking Prevention; authenticated or tracker-heavy pages may therefore differ from WinMerge even with the same URL. [WEBKIT-PRIVACY]

## Native macOS implementation options

### Table options

#### Option T1: Lossless Swift record parser plus existing xdiff and AppKit

**Recommended, with an explicit compatibility contract.** Add a `MacMergeCore` table document layer that indexes both original-byte and decoded-text ranges for logical records and serialized field slices while preserving every raw record and terminator. Initial display and editor text must match WinMerge by exposing the raw serialized field slice, including enclosure characters; edits are interpreted as replacement serialized slices, not dequoted logical values. A later dequoted-value presentation/editor would be a declared divergence with separate serialization rules. RFC 4180 supplies strict interoperable fixtures, but it is not WinMerge's grammar: compatibility mode must reproduce WinMerge's quote-parity scanner, including quote toggles outside field boundaries and its acceptance of unmatched quotes through EOF. A separate strict mode may reject malformed RFC input only if labeled and excluded from parity claims. [W-TABLE-BUFFER] [RFC-4180]

Original-byte provenance is mandatory. Decoded `String` ranges do not identify safe splice boundaries in UTF-16, multibyte, noncanonical, or stateful legacy encodings, and current dirty saves re-encode the whole document. Each editable record must retain an original byte span plus codec state needed to prove record-local replacement. If state-safe byte splicing and re-decoding cannot be proven for an encoding, table editing is read-only for that encoding; unedited save still reuses the original persisted bytes. [M-IO] [M-CODEC]

Feed xdiff logical records, never original physical lines. Keep a map from xdiff record numbers to raw record ranges. Current `mmx_diff` and vendored xdiff accept newline-delimited byte buffers, so neither safe option is a trivial wrapper:

- Preferred for full 64 MiB source support: add a record-span adapter at the xdiff record-classification boundary. This is an xdiff-internal fork/adapter, not only a narrow public ABI change; isolate it, document synchronization with WinMerge's vendored xdiff, and test every algorithm/flag combination.
- Alternative: use a reversible newline-free comparison encoding only after proofs show collision freedom, transformed-size bounds, and equivalence under every supported xdiff option. Visible length prefixes or escapes can change whitespace/number equivalence and can expand a 64 MiB source past `MMX_MAX_INPUT_SIZE`; lower the source cap to the proven worst-case bound if this option is selected.

Render with view-based `NSTableView`: native tables support multiple columns, horizontal/vertical scrolling, resizable columns, and reusable offscreen cell views. A single table can retain vertical synchronization; corresponding left/right field widths can be coupled by the coordinator. [A-TABLE]

Benefits: no new dependency, compatible with existing I/O and comparison ownership, deterministic, sandbox-neutral, and testable without UI or network. Main cost: exact round-trip editing and two-dimensional virtualization need careful design.

#### Option T2: Apple's TabularData `DataFrame`

**Reject as authoritative model.** TabularData can create a data frame from CSV and exposes delimiter, quoting, escaping, and header options. Its purpose is importing and organizing typed data; it infers value types and represents cells semantically. MacMerge needs exact lexical preservation, custom quote behavior, malformed-input policy, legacy encoding ownership, per-record line endings, and byte-stable untouched saves. It may be useful in a throwaway read-only prototype, but not as save/merge truth. [A-TABULARDATA]

#### Option T3: Third-party CSV parser/grid

**Defer.** A mature streaming parser could reduce grammar work, but it adds license, supply-chain, release, and ABI/API maintenance while still requiring a raw-range preservation layer. A third-party grid would also fight the existing selection, merge, accessibility, and shared-scroll owners. Reconsider only if T1 parser fuzzing finds an unbounded standards burden and a candidate proves lossless source-range support.

#### Option T4: Treat delimiters as visual tab stops only

**Reject.** It cannot preserve quoted delimiters or embedded newlines and would create incorrect row alignment and merges.

### Webpage options

#### Option W1: System `WKWebView`

**Only viable native browser option; conditional.** WebKit can load remote requests and constrained local file URLs, execute extraction JavaScript, take viewport snapshots, create PDFs, and create web archives. `WKWebsiteDataStore.nonPersistent()` keeps website state in memory rather than writing it to disk. [A-WEBKIT]

A prototype should use one separately created nonpersistent store per pane, deny popups and file panels through `WKUIDelegate`, deny media capture through its dedicated permission callback, and leave geolocation and notifications unavailable through configuration plus fail-closed fixtures because public macOS WebKit does not expose equivalent per-request delegate decisions. Downloads and external schemes are canceled. Never assume separate stores or `WKProcessPool` objects provide process, network, or privacy isolation; current `WKProcessPool` has no isolating effect, and store separation requires cross-pane and teardown tests. JavaScript extraction should run in an isolated content world, although DOM mutations remain visible across worlds. [A-WEBKIT] [WEBKIT-APPBOUND]

Offline local and remote modes must be separate. The spike accepts only explicitly selected local files loaded with minimum read access while the shipped signature has no `network.client` entitlement; any custom-scheme handler is local and rejects network references. A later remote mode accepts only `https` top-level URLs and must not load selected local files, because readable local content in a network-enabled view can be exfiltrated by scripts or subrequests.

Parity limitations remain:

- HTML and text require script evaluation after a defined load/settle barrier; arbitrary SPAs can mutate forever.
- Visible screenshots are directly supported. Stable full-page screenshots require bounded tiling or another validated capture path and can consume hundreds of MiB.
- Bounded browser-observed Resource Timing and validated `createWebArchiveData` parsing may provide partial evidence, but neither is an exact inventory of redirects, service-worker/cache decisions, cross-origin internals, or dynamically consumed responses. A separate `URLSession` crawl is excluded: it refetches under different cookie/cache/auth/user-agent state and can duplicate server effects. Label output "observed resources," attach explicit incomplete-inventory metadata, and do not claim WinMerge resource-tree parity without version-pinned black-box fixtures or upstream source.
- Scroll synchronization is feasible using normalized document position. Mirroring click, input, or back/forward actions requires injected event identity and recursion guards; it can duplicate purchases, form submissions, navigation, or other server-side effects. Do not include these events in an initial prototype.
- Snapshot differences require integrating the existing image core into an accepted app workspace. Any observed-resource comparison requires an accepted folder workspace, incomplete-inventory metadata, and protected handoff. These are cross-workspace blockers for those derived features, not requirements for basic HTML/text spike work. [M-DERIVED-CORES] [M-PROTOTYPE-STATUS]

#### Option W2: `URLSession` fetch plus text/source comparison

**CONDITIONAL GO only as a separate static-source convenience, not webpage parity.** It avoids active rendering but still requires the remote-network ADR, `network.client` entitlement, privacy revision, broad public/private/loopback egress decision, `https`-only redirect/scheme policy, time and response-byte caps, and an ephemeral `URLSessionConfiguration` with no shared cookie, cache, or credential stores. It cannot execute JavaScript, reproduce layout, capture pixels, or represent post-load DOM. Existing HTML text comparison already covers local saved sources; remote fetching alone does not justify a Webpage parity claim.

#### Option W3: External Safari windows

**Reject for parity.** Safari's scripting dictionary exposes loaded-page HTML source, page text, and JavaScript automation, so limited extraction is technically supported. It still gives MacMerge no integrated two-pane layout, lifecycle ownership, reliable event synchronization, capture contract, or difference navigation. A sandboxed implementation also needs `com.apple.security.automation.apple-events`, `NSAppleEventsUsageDescription`, TCC consent, and Safari's JavaScript-from-Apple-Events setting. Use external Safari only for user-directed viewing, not a comparison backend. [A-SAFARI]

#### Option W4: Bundle Chromium, CEF, Playwright, or a ported WinWebDiff

**Reject.** It introduces a large rapidly patched runtime, code-signing/notarization complexity, binary size, extra helper processes, supply-chain exposure, and a second browser security-update obligation. The checked-in ABI itself depends on Windows types and COM conventions. WebView2 rendering identity still would not be guaranteed across versions. [W-WEB-ABI] [W-WEB-DEPS]

## Risks and required controls

### Table security and correctness

| Risk | Consequence | Required control |
| --- | --- | --- |
| Ambiguous delimiter/quote controls | Misparse or impossible serialization | Delimiter is exactly one Unicode scalar, non-NUL, non-CR/LF, representable in target encoding; quote is either disabled with an empty value or one distinct scalar under the same restrictions. Reject equal delimiter/quote and unrepresentable settings before parse/edit. |
| Malformed quoting, giant fields, excessive columns/cells | Parser denial of service or incorrect record boundaries | Streaming/state-machine parser; checked arithmetic; retain 64 MiB file cap; initial hard caps of 1,048,576 records, 16,384 fields per record, and 10,000,000 total cells; distinguish WinMerge-compatible permissive mode from strict fail-closed mode and return mode plus source line/column in errors. |
| Canonicalizing untouched records | Silent byte, quote, whitespace, delimiter, EOL, or legacy-encoding changes | Preserve original byte and decoded ranges; serialize only changed records through proven codec-local splices; unedited save uses original bytes; unsupported/stateful edits are read-only; byte-for-byte round-trip tests. |
| Embedded newlines treated as xdiff lines | Misalignment and destructive row merges | Record-level comparison adapter; no physical-line fallback when quoted-newline mode is enabled. |
| Uneven schemas | Shifted columns or out-of-range edits | Preserve each record's actual field count; render missing cells explicitly; never pad serialized output unless user edits that cell. |
| Edits introduce delimiter, quote, or newline | Ambiguous cells or changed record boundaries | Compatibility editor accepts a replacement serialized field slice exactly as displayed. Preserve untouched slices; splice edited slice, then reparse the full record and require unchanged field count/boundaries plus exact edited raw slice. Fail closed when a raw edit creates a delimiter boundary, unmatched quote state, or disallowed quoted newline, or when target encoding cannot represent it. A future logical-value editor may use deterministic minimal quoting only under a separately tested contract. |
| Spreadsheet formulas in cells | Dangerous behavior after copy/export into spreadsheet software | Treat all values as inert text; never evaluate formulas; warn before every spreadsheet-targeted clipboard/export path containing formula-leading values, including one cell, or offer an explicit spreadsheet-safe export that leaves source bytes unchanged. |
| Cell-object explosion | High resident memory and slow first render | Source-range indexes, lazy string decoding/layout, reusable visible cells, horizontal virtualization when columns are wide. |
| Save races and symlink replacement | Data loss | Reuse `TextFileDocumentIO`; table mode must not bypass coordination, identity, recovery-copy, or encoding checks. |
| Existing physical-line edit/merge reuse | Multiline-record fragments copied, deleted, or assigned wrong terminators | Reuse command/history UI only; table-specific record/cell edit and merge primitives operate raw record spans. WinMerge-compatible replacement copies source serialized record content and source terminator; insertion does likewise while surrounding target byte order stays target-owned. Any target-terminator preservation mode is an explicit divergence with separate fixtures. |

### Webpage security and privacy

| Risk | Consequence | Required control before remote URLs ship |
| --- | --- | --- |
| Broad outbound network entitlement | App and loaded pages can reach public, loopback, and private-network services | Explicit product approval; update privacy docs and release review; visible sanitized destination in every pane; no automatic URL-pattern routing by default. HTTPS-only top-level navigation does not isolate subresource egress, and public `WKWebView` APIs do not provide a complete subresource interceptor. Threat model must explicitly accept broad egress or remote mode remains NO-GO. |
| Active untrusted page code | Tracking, phishing UI, abusive resource use, permission prompts | System WebKit only; directly deny new windows, downloads, file panels, media capture, and external schemes through supported callbacks. Keep geolocation/notifications unavailable and fixture-test fail-closed behavior; expose stop/reload and process-termination errors. |
| Persistent or cross-pane state | Cross-comparison identity leakage and undeclared retained data | Separate nonpersistent store per pane by default; test cookies, local/session storage, IndexedDB, Cache Storage/service workers, and HTTP cache across panes and after teardown. State isolation is required; process/network isolation is not promised. Persistent profiles require a later explicit opt-in, clear controls, and privacy review. |
| Local file disclosure | A selected HTML file may request adjacent or remote resources | Offline-local mode only, with release signature lacking `network.client`; use `loadFileURL(_:allowingReadAccessTo:)` with minimum scope, deny network/custom external schemes, and do not grant home-directory access. Remote mode never accepts local-file input. [A-WEBKIT] |
| Instrumentation access to page content | Passwords, tokens, form contents, and private DOM can enter app memory/logs | Extract only on user action or comparison start; never log DOM, URL query strings, cookies, headers, or form values; keep script bridge one-way and typed; do not persist captures by default. |
| Synchronized click/input | Duplicate destructive or financial actions | Initial and default synchronization limited to scroll; require a separate threat review and prominent per-session opt-in before click/input sync can be considered. |
| Nondeterministic navigation and mutation | Stale or misleading differences | Generation IDs for every navigation/capture, cancellation, 30-second load timeout, user-visible "page still changing" state, explicit Recompare, no automatic claim of stable equality. |
| Sensitive URL/report persistence | Credentials or tokens leak through logs, reports, recents, or crash diagnostics | UI may show current destination, but persisted metadata defaults to origin only with userinfo, path, query, and fragment removed. Persist a path only under an explicit reviewed segment-redaction policy. Context-escape all report data, apply restrictive CSP, and open reports inertly. Redact or disable raw MetricKit persistence during remote comparisons; add URL/report/crash redaction tests. |
| Browser engine drift | Results vary by macOS update and differ from WinMerge | Record macOS/WebKit version, viewport, user agent, timestamp, comparison mode, and sanitized origin in reports; fixture-test every supported macOS release. |
| Unbounded renderer/network work | WebContent DOM/heap, CPU, sockets, streaming bytes, or post-load activity can exhaust resources before output checks | Treat 64 MiB HTML/text, 100,000 observed resources, 50-megapixel raster, 20 main-frame redirects, and two panes as output/coordination caps, not renderer quotas. Enforce chunked byte/node/time accounting inside extraction, cancel and tear down views on timeout/cap, and require threat-model acceptance that public `WKWebView` exposes no hard per-pane CPU/memory/network quota. |
| Authentication and TLS challenges | Credential leakage, client-certificate exposure, or trust bypass | Accept only system-valid server trust; no trust exceptions or client certificates. Reject/cancel other challenges by default. Any later login support uses memory-only per-pane credentials with no shared credential store and explicit cancellation/teardown tests. |
| Partial frame visibility | Cross-origin, sandboxed, or late-added frames are omitted and false equality is reported | Define release scope as main frame plus fully observed same-origin frames. Enumerate every discovered frame; if any cross-origin, sandboxed, inaccessible, or late-added frame cannot be extracted under the same generation, mark result incomplete and prohibit an equality claim. |

### Dependency and maintenance

- Table T1 adds no runtime dependency. New parser code becomes security-sensitive and must be fuzzed, but its input grammar and limits are narrow.
- System WebKit avoids shipping a browser binary and receives OS security updates, but behavior is tied to supported macOS versions. It is a platform dependency with compatibility risk, not "no dependency."
- App-Bound Domains are not a general solution for arbitrary comparison URLs. WebKit limits the configured domain list and restricts powerful APIs outside it; arbitrary webpage comparison needs a deliberate balance between extraction capability and privacy. [WEBKIT-APPBOUND]
- Any new third-party parser or browser must pass license review, vulnerability monitoring, reproducible build, update-policy, notarization, and architecture checks. No candidate currently clears enough burden to beat native options.

### Performance

Table parsing, record-map construction, xdiff input generation, and render metadata must remain off the main actor. Preserve lazy source-backed strings and view reuse. Existing one-million-row budgets are useful regression gates, but table workloads also need wide-record and embedded-newline fixtures.

Web performance cannot use text-only budgets. Two `WKWebView` panes can reuse or swap one or more WebContent processes and can involve Networking/GPU processes; WebKit does not promise one process per pane or pane-contained crashes. A prototype must measure navigation-to-stable, extraction, compare, first render, synchronized scroll, capture latency, aggregate app/WebContent/Networking/GPU process-coalition RSS and process count, and post-quiescence memory after each of ten close/reopen cycles. Any affected pane must fail cleanly after process termination without crashing or publishing stale/equal results; do not promise unaffected-pane containment.

## Phased recommendation

### Phase 0: Freeze contracts and fixtures

- Write two named table grammars and malformed-input policies: WinMerge-compatible quote parity for parity mode, and optional strict RFC-style parsing. Include disabled quoting, quote occurrences inside unquoted text, unmatched quotes, doubled quotes, quoted CR/LF, custom delimiter/quote validation, uneven fields, empty final fields, and final-newline behavior.
- Capture WinMerge two-pane fixtures and expected raw cell display, logical rows, columns, navigation order, row merges, edits, and saved bytes. Every oracle fixture records WinMerge commit/version, architecture, Windows/WebView-independent locale where relevant, complete table/diff options, input encoding and hashes, invocation or generation command, and expected-output capture command.
- Define two-pane table parity as first delivery; explicitly exclude three-pane, reports, and column display filters.
- Add no webpage code. Write a short product ADR deciding whether remote active content belongs in MacMerge and whether its privacy statement may change.

Exit: fixture corpus and contracts reviewed; no ambiguous save behavior.

### Phase 1: Read-only table core

- Implement bounded lossless parser with original-byte provenance and a record-level xdiff adapter in `MacMergeCore`; document whether xdiff source is forked for spans or source limits/options are constrained by a proven reversible encoding.
- Add explicit Table open/recompare with CSV, TSV, and custom settings; add filename-pattern routing only after explicit mode works.
- Render field columns with shared corresponding widths, headers, resize, auto-fit, horizontal/vertical scroll, selection, accessibility, and difference navigation.
- Keep text comparison path unchanged and selectable.

Exit: parser/property/fuzz tests and read-only UI acceptance pass.

### Phase 2: Table editing and merge

- Add cell editing with changed-record-only, codec-proven serialization; keep unsupported legacy/stateful configurations read-only.
- Reuse command/history UI, reload/save coordination, external-change detection, encoding selection, and recovery behavior. Implement table-specific logical-record row merge, Merge All, copy-and-advance, undo/redo, and source-record/target-terminator handling; never invoke physical-line `LineMerge` for table content.
- Add wrapping and column selection. Defer typed sorting/formulas because WinMerge table parity does not require them.

Exit: byte preservation, merge invariants, undo/redo, and save race gates pass.

### Phase 3: Table hardening and release

- Add 100k-by-20-field and 1M-by-3-field packaged benchmarks, near-16,384-column and near-10,000,000-cell two-pane gates, wide fields, quoted multiline fields, dense differences, legacy encodings, and accessibility/UI tests. Lower declared caps before release if near-cap workloads cannot meet budgets.
- Document two-pane scope in migration matrix. Add report and column-filter parity only when corresponding MacMerge owners exist.
- Reevaluate three-pane table work with the general three-way milestone; do not build a table-only three-pane architecture.

Exit: all table acceptance criteria below pass. Current CI uses only `macos-15`; release requires retained packaged test/benchmark reports from explicit macOS 14 and current supported-version jobs, with runner image/Xcode/architecture recorded.

### Phase 4: Offline WebKit feasibility spike

- Use selected local `file` fixtures or a bounded local custom-scheme handler under the production no-network signature. A loopback server is allowed only in a separately signed test harness with test-only `network.client` and an explicit loopback-HTTP exception that never ships.
- Build two nonpersistent `WKWebView` panes with navigation lifecycle, stop/reload, fixed viewport, visible snapshot, chunked bounded HTML/text extraction, normalized scroll synchronization, cancellation, frame-completeness accounting, and process-termination handling.
- Compare extracted text/HTML through the existing text owner. Snapshot handoff is enabled only after accepted image-workspace integration. Observed-resource handoff is optional and requires an accepted folder workspace plus explicit incomplete-inventory metadata; reports are not a Phase 4 prerequisite.
- Measure WebKit variance across supported macOS versions and document resource-inventory limitations.

Exit: security review and measurements produce a second go/no decision. Delete the spike if it requires persistent profiles, broad script bridges, or bundled Chromium to meet baseline behavior.

### Phase 5: Remote experimental webpage mode, only after renewed GO

- Add network entitlement and revised privacy documentation in the same reviewed change; verify actual release-signature entitlements.
- Ship `https`-only remote loading behind explicit experimental opt-in with nonpersistent per-pane state, no local-file inputs, and scroll-only synchronization.
- Add HTML/text/screenshot comparison incrementally. Do not label best-effort observed resources as resource-tree parity.
- Treat persistent login profiles, click/input sync, three panes, full-page screenshots, reports, and observed-resource trees as separate security-reviewed increments.

Exit: webpage acceptance criteria pass and release notes retain experimental qualification. Otherwise remain NO-GO.

## Acceptance criteria

### Two-pane table release gate

- Automatic defaults open `*.csv` as comma and `*.tsv` as tab; explicit mode supports one user-selected delimiter, optional empty quote to disable enclosure handling, and quoted-newline toggle. Delimiter/quote are each zero-or-one Unicode scalar as applicable, distinct, non-NUL, non-CR/LF, and representable in target encoding; rejection tests cover every invalid combination. Recompare As Text is lossless.
- Parser fixtures cover both WinMerge-compatible quote parity and strict RFC mode: CRLF/LF/CR and mixed terminators, BOM, UTF-8/UTF-16, CP932, CP51932, CP50220, CP1250, CP1251, CP1252, CP1253, doubled quotes, serialized quote display, quotes outside field boundaries, unmatched quotes, disabled quoting, delimiters in quotes, embedded newlines, empty/blank records, empty final fields, missing final newline, uneven field counts, NUL rejection, maximum-length fields, and every cap boundary. Stateful/noncanonical edit cases prove safe byte splicing or remain read-only.
- For every accepted input, concatenating original byte record spans and terminators reproduces input bytes exactly; decoded spans also reproduce decoded text. Opening and saving an unedited supported file reproduces original bytes exactly.
- Logical record count and every raw field string, decoded/source range, and byte range match fixture expectations. Compatibility-mode cells display serialized enclosure characters. Quoted newlines produce one diff row. No fallback silently treats malformed quoted data as ordinary physical lines.
- Alignment and significant-difference order match WinMerge fixtures for two panes under equivalent text options. Navigation, row merge, Merge All, copy-and-advance, undo, redo, and reload work in both directions.
- Editing one cell replaces its raw serialized field slice exactly as displayed. Fixtures include edits to quoted and doubled-quote slices such as `"bar"` and `"a""b"`; reparsing must preserve field count/boundaries and recover the exact intended raw slice without accidental extra quoting. Edits that create a delimiter boundary, unmatched quote state, or disallowed quoted newline fail closed. Unrelated records, quote choices, delimiters, whitespace, line endings, final-newline state, BOM, and representable legacy bytes remain unchanged.
- Column headers, first-record-as-header option, resize, auto-fit, corresponding width synchronization, wrapping, horizontal/vertical scroll, column selection, keyboard editing, and VoiceOver cell row/column/value/status announcements pass UI tests. Header mode is non-consuming: record one still participates in comparison, editing, merge, navigation, and save and supplies labels only when hidden/scrolled as WinMerge does.
- Formula-leading values remain inert. Every spreadsheet-oriented export or clipboard test, including one-cell copy, requires a warning or explicit spreadsheet-safe export; source text is never mutated for formula mitigation.
- Existing text tests and packaged budgets do not regress. Table CI fixtures include 100,000 records by 20 fields and 1,000,000 records by 3 fields within the 64 MiB source cap, plus near-16,384-column and near-10,000,000-cell two-pane cases within whichever transformed-input cap the chosen xdiff adapter proves. Each must meet the existing 5,000 ms load, 5,000 ms comparison, 1,500 ms first render, 1,500 ms bottom scroll, and 900 MiB resident budget on the recorded CI class. If a near-cap shape cannot meet budgets, lower the product cap; threshold changes require a committed benchmark report and explicit review, not silent relaxation.
- Cancellation and generation tests prove stale parse/compare results cannot publish over newer inputs. Parser, record-map, serialization, and render-metadata stages check cancellation with a measured maximum latency. Native xdiff is synchronous and non-cancellable, so stale native work must run outside the serial comparison actor or use a replaceable worker whose result is abandoned; release gate records worst-case cancellation-to-new-publication latency. Parser fuzzing plus deterministic cap, overflow, and parser-state fault tests cover malformed quoting and serialization. Do not require ordinary Swift heap-allocation failure injection because allocation failure traps unless a dedicated injectable allocator is introduced.
- Pinned WinMerge oracle fixtures carry commit/version, architecture, option set, encoding, input/output hashes, and exact invocation/capture commands. CI runs fixture parity and packaged UI/performance gates on macOS 14 and current supported macOS jobs and retains reports containing runner image, Xcode, architecture, and fixture hashes.
- Migration and parity docs state: two panes supported; three panes, table reports, and WinMerge column display filters remain unsupported until separately delivered.

### Remote experimental webpage gate

These criteria are prerequisites, not current approval to implement:

- Product ADR explicitly approves remote active content, outbound network entitlement, privacy-policy changes, supported schemes, profile policy, and experimental support burden.
- Remote mode uses exactly two panes, separate nonpersistent stores, `https` only, 30-second navigation timeout, 20 main-frame redirects maximum, and no automatic URL-pattern routing. It rejects local-file inputs. Offline-local mode uses selected files/minimum read scope under a no-egress release signature and is never mixed into a network-enabled comparison. Subresource redirect/egress behavior is not represented by the main-frame cap and must be covered by the broad-egress threat decision.
- Cross-pane and post-teardown tests prove separation of cookies, local/session storage, IndexedDB, Cache Storage/service workers, and HTTP cache; no process or network isolation is claimed. Persistent state remains disabled.
- Popups, downloads, file panels, camera/microphone capture, and external schemes are denied through supported delegates. Geolocation and notifications remain unavailable and fixture-tested fail closed. Local file read access is restricted to the minimum selected file or resource directory.
- Offline-local security fixtures attempt top-level, frame, script, form, redirect, and subresource access to public, private, and loopback destinations. Every request fails under the actual no-`network.client` release signature; tests also verify custom-scheme handlers reject network references and actual signature entitlements.
- No compared DOM, text, screenshot, URL userinfo/query/fragment, cookie, header, form value, or resource body appears in app-authored logs, preferences, bookmarks, recents, reports, or post-quit storage. Raw MetricKit diagnostic persistence is redacted or disabled during remote comparisons, with fixtures proving sensitive URLs do not enter saved crash metadata.
- Fixture pages prove cancellation, stale-generation rejection, process crash recovery, CSP, redirects, endless mutation, animation, very tall pages, large DOM, and cap failures. Authentication tests accept only system-valid server trust, reject trust exceptions/client certificates and all unsupported challenges, and prove any later session credentials remain memory-only and pane-local.
- Frame fixtures cover main-frame, same-origin, cross-origin, sandboxed, and late-added frames. Equality is allowed only when main frame and every discovered same-origin frame are fully extracted under one generation; any inaccessible, sandboxed, cross-origin, or late-mutating frame marks result incomplete and blocks equality.
- HTML and extracted-text results are explicitly timestamped snapshots. UI shows loading, changing, compared, failed, and process-terminated states. Equality is never reported from one loaded pane and one stale pane.
- Viewport screenshot, HTML, and text derived comparisons work end to end. Handoff is in memory, or uses protected temporary artifacts excluded from recents/bookmarks with close-time deletion and launch-time orphan purge; partial/failed artifact sets never open downstream workspaces. Full-page capture, observed-resource trees, reports, click/input synchronization, persistent profiles, and three panes remain disabled until their own criteria pass.
- Scroll sync cannot recurse and remains within one viewport-height error after ten bidirectional fixture scrolls. Click and input are not synchronized in initial release.
- Captures above 50 megapixels, extraction above 64 MiB, or observed-resource lists above 100,000 entries fail with actionable errors. Chunked in-web-process extraction enforces byte/node/time caps before one-shot serialization can exceed them; timeout/cap cancels navigation and tears down affected views. Residual lack of hard WebContent CPU/memory/network quotas is explicitly accepted by threat review.
- After quiescence following each of ten close/reopen fixture comparisons, aggregate MacMerge/WebContent/Networking/GPU process-coalition RSS and process count are recorded. Gate fails on monotonic process-count growth or aggregate retained growth above both 10% of first closed baseline and a documented absolute noise floor; keep every iteration in the artifact.
- macOS 14 and current supported-version jobs record OS build, WebKit/runtime version, viewport, user agent, sanitized origin, extraction/capture timings, fixture hashes, process-coalition measurements, and expected engine-specific differences from WinMerge.
- Privacy documentation and entitlements land together, and release review verifies actual signature entitlements.

## Explicit conclusions

1. **GO: build native two-pane table comparison using an original-byte-provenance record model, an explicitly maintained record-level xdiff adapter, and view-based AppKit.** This is genuine WinMerge workflow parity only in documented compatibility mode and within declared pane/report limits.
2. **NO-GO: do not call plain delimiter coloring, physical-line CSV comparison, or a canonicalizing `DataFrame` round trip table parity.** Each can corrupt quoted-newline alignment or untouched bytes.
3. **NO-GO: do not port or bundle WinWebDiff/WebView2/Chromium.** Windows ABI, binary dependency, browser patching, signing, size, and supply-chain costs exceed value.
4. **NO-GO now: do not implement or advertise full remote webpage parity in Milestone 6.** Current MacMerge lacks network/privacy approval, integrated image/folder/report workspaces and handoff, three panes, and deterministic resource-tree capability.
5. **CONDITIONAL GO later: run a bounded offline-local-fixture `WKWebView` spike after a product threat-model ADR.** HTML/text and scroll work may proceed independently; image integration is required only for snapshot handoff, folder integration only for optional observed-resource handoff, and reports remain deferred. A successful spike permits a second decision and does not authorize remote shipping.
6. **NO-GO for an unqualified parity claim:** even a shipped WebKit mode must disclose engine-dependent rendering and best-effort resource observation. Acceptance should target equivalent workflows and transparent limitations, never pixel identity with WebView2.

## Evidence index

Repository references are relative to repository root. Line ranges describe the inspected 2026-08-11 worktree.

### WinMerge table evidence

- **[W-TABLE-ROUTING]** `Src/MainFrm.cpp:261-268,887-909,1012-1062,1121-1127`; `Src/MergeDoc.cpp:2227-2306,3141-3167`; `Src/Merge.rc:320-339`.
- **[W-TABLE-OPTIONS]** `Src/OptionsInit.cpp:73-86,166-174`; `Src/OptionsDef.h:293-300`; `Src/PropCompareTable.cpp:22-38`; `Src/MergeDoc.cpp:2227-2264`.
- **[W-TABLE-DIALOG]** `Src/OpenTableDlg.cpp:21-77`; `Src/Merge.rc:3171-3189,3310-3332`.
- **[W-TABLE-BUFFER]** `Externals/crystaledit/editlib/ccrystaltextbuffer.cpp:2029-2118`; `Src/DiffTextBuffer.cpp:458-507`.
- **[W-TABLE-MODEL]** `Src/MergeDoc.cpp:2291-2301,2647-2659,2898-2905`.
- **[W-TABLE-VIEW]** `Docs/Manual/English/Compare_table.xml:94-127`; `Src/MergeEditView.cpp:2894-2907,4311-4319,4427-4455`; `Externals/crystaledit/editlib/ccrystaltextview.cpp:2443-2447,7135-7228`; `Externals/crystaledit/editlib/ccrystaltextview2.cpp:533-594,708-728`.
- **[W-TABLE-LINEDIFF]** `Docs/Manual/English/Compare_table.xml:13-15`; `Src/MergeDoc.cpp:302-327,940-1036`; `Src/DiffWrapper.cpp:1154-1189`; `Src/MergeDocDiffCopy.cpp:66-159,495-640`; `Src/MergeDocLineDiffs.cpp:128-132,315-330`.
- **[W-TABLE-REPORT]** `Src/MergeDoc.cpp:3205-3239`.
- **[W-TABLE-TESTS]** `Src/Test.cpp:186-217,244-291`; `Testing/GoogleTest/CmdLine/MergeCmdLine_test.cpp:2182-2208,2229-2243`.
- **[W-TABLE-MANUAL]** `Docs/Manual/English/Compare_table.xml:13-15,28-90,94-127`.

### WinMerge webpage evidence

- **[W-WEB-MANUAL]** `Docs/Manual/English/Compare_webpages.xml:12-19,22-80,98-189,193-344,348-375`.
- **[W-WEB-FRAME]** `Src/WebPageDiffFrm.h:28-77,99-130,169-200`; `Src/WebPageDiffFrm.cpp:318-351,354-367,400-538,624-665,909-927,1061-1334`.
- **[W-WEB-ROUTING]** `Src/MainFrm.cpp:850-909`; `Src/WebPageDiffFrm.cpp:370-395,909-927`.
- **[W-WEB-ABI]** `Src/WinWebDiffLib.h:7-203`.
- **[W-WEB-OPTIONS]** `Src/OptionsDef.h:276-288`; `Src/PropCompareWebPage.cpp:21-46`.
- **[W-WEB-DEFAULTS]** `Src/OptionsInit.cpp:194-205`; `Src/WebPageDiffFrm.cpp:454-458,624-665`; `Src/WinWebDiffLib.h:32-65,191-196`.
- **[W-WEB-DERIVED]** `Src/WebPageDiffFrm.cpp:1396-1500`.
- **[W-WEB-REPORT]** `Src/WebPageDiffFrm.h:61-75`; `Src/WebPageDiffFrm.cpp:1570-1627`.
- **[W-WEB-DEPS]** `DownloadDeps.cmd:27-29`; `Externals/versions.txt:12-15`; `Docs/Users/Contributors.txt:342-346`; `Docs/Users/ChangeLog.md:2328-2340`.
- **[W-RESOURCES]** `Src/Merge.rc:279-318,1278-1301,3171-3189,3310-3332,3363-3375,5482,5661,5670,5689-5690`; `Src/Merge2.rc:52-53,196,201`; `Src/Merge.vcxproj:1054,1127,1435,1532,1592,1781`.

### MacMerge evidence

- **[M-PACKAGE]** `MacMerge/Package.swift:1-47`.
- **[M-IO]** `MacMerge/Sources/MacMergeCore/TextFileDocument.swift:75-340,343-450,458-466`.
- **[M-CODEC]** `MacMerge/Sources/MacMergeCore/TextFileCodec.swift:3-39,67-86,150-191,194-290,293-334,478-590`.
- **[M-DIFF]** `MacMerge/Sources/MacMergeCore/LineDiff.swift:266-294,308-389,679-821`.
- **[M-MODEL]** `MacMerge/Sources/MacMerge/MacMergeApp.swift:1212-1259,1390-1454,1480-1518,1633-1755,1758-1829`.
- **[M-RENDER]** `MacMerge/Sources/MacMerge/MacMergeApp.swift:4103-4269,4276-4418,4629-4736`.
- **[M-LINE-MERGE]** `MacMerge/Sources/MacMergeCore/LineDiff.swift:4387-4439,4452-4647`; `MacMerge/Sources/MacMerge/MacMergeApp.swift:1576-1619`.
- **[M-PROJECT-MODE]** `MacMerge/Sources/MacMergeCore/ComparisonProject.swift:58-70`; no `.table` or `.webpage` runtime routing exists in `ComparisonModel` in the inspected worktree.
- **[M-UI]** `MacMerge/Sources/MacMerge/MacMergeApp.swift:153-161,2778-2912,3267-3283`.
- **[M-DERIVED-CORES]** `MacMerge/Sources/MacMergeCore/ImageComparison.swift:5-59,87-203,359-537`; `MacMerge/Sources/MacMergeCore/ImageComparisonPresentation.swift:3-147`; `MacMerge/Sources/MacMergeCore/FolderScanner.swift:118-154`; `MacMerge/Sources/MacMergeCore/FolderComparator.swift:52-85,105-173,165-250`.
- **[M-REPORT]** `MacMerge/Sources/MacMergeCore/ComparisonReport.swift:3-23,72-157,196-294`; no `ComparisonReport`, `ImageComparison`, `ImageDifferenceEngine`, `FolderScanner`, or `FolderComparator` use exists in `MacMerge/Sources/MacMerge/MacMergeApp.swift` in the inspected worktree.
- **[M-PROTOTYPE-STATUS]** `todo.md:43-54,181-186`.
- **[M-ENTITLEMENTS]** `MacMerge/Packaging/MacMerge.entitlements:1-12`.
- **[M-PRIVACY]** `MacMerge/PRIVACY.md:1-13,24-26`.
- **[M-MIGRATION]** `MacMerge/MIGRATION.md:3-16,48-75`.
- **[M-PERFORMANCE]** `MacMerge/Scripts/run-performance-budgets.sh:10-18,100-115`; `MacMerge/Benchmarks/README.md:1-42`; `.github/workflows/macmerge.yml:24-26,53-55,70-113,131-150`.

### Platform and format evidence

- **[A-TABLE]** Apple, *Table View Programming Guide for Mac*, table rows/columns, scrolling, column behavior, and reusable view cells: <https://developer.apple.com/library/archive/documentation/Cocoa/Conceptual/TableView/Introduction/Introduction.html> and <https://developer.apple.com/library/archive/documentation/Cocoa/Conceptual/TableView/PopulatingView-TablesProgrammatically/PopulatingView-TablesProgrammatically.html>.
- **[A-TABULARDATA]** Apple, `DataFrame.init(csvData:...)` and `CSVReadingOptions`: <https://developer.apple.com/documentation/tabulardata/dataframe/init(csvdata:columns:rows:types:options:)> and <https://developer.apple.com/documentation/tabulardata/csvreadingoptions>.
- **[A-WEBKIT]** Apple, `WKWebView` and `WKWebsiteDataStore.nonPersistent()`: <https://developer.apple.com/documentation/webkit/wkwebview> and <https://developer.apple.com/documentation/webkit/wkwebsitedatastore/nonpersistent()>; API contracts were cross-checked in installed macOS SDK headers `WebKit.framework/Headers/WKWebView.h:119-148,247-349,419-448`, `WKWebsiteDataStore.h:38-85`, `WKWebViewConfiguration.h:105-161`, `WKUIDelegate.h:85-97,157-165,285-295`, and `WKNavigationDelegate.h:40-107,150-190`.
- **[A-NETWORK]** Apple, App Sandbox outgoing-network entitlement: <https://developer.apple.com/documentation/bundleresources/entitlements/com.apple.security.network.client>.
- **[A-SAFARI]** Installed Safari scripting dictionary, `/Applications/Safari.app/Contents/Resources/Safari.sdef:19-31,41-63`, exposes document/tab `source`, `text`, URL, and `do JavaScript`.
- **[WEBKIT-APPBOUND]** WebKit, *App-Bound Domains*, restricted APIs, arbitrary navigation tradeoffs, and privacy rationale: <https://webkit.org/blog/10882/app-bound-domains/>.
- **[WEBKIT-PRIVACY]** WebKit, *Tracking Prevention in WebKit*, default cookie policy, ephemeral sessions, storage partitioning, and ITP: <https://webkit.org/tracking-prevention/>.
- **[RFC-4180]** RFC 4180, record/field quoting, embedded CRLF, doubled quotes, interoperability, and security considerations: <https://www.rfc-editor.org/rfc/rfc4180>.
