# ADR: Retain the Narrow XDiff ABI and Require Differential Proof

- Status: Accepted architecture; behavioral-equivalence claim pending
- Date: 2026-08-11
- Decision owner: MacMerge diff core
- Scope: current two-pane text comparison pipeline

## Decision

Retain `MacMerge/Sources/CXDiff/include/macmerge_xdiff.h` as the native boundary over
WinMerge's bundled `Externals/xdiff` sources. Do not directly port
`Src/xdiff_gnudiff_compat.cpp` or `CDiffWrapper` into the macOS target now.

Keep file loading, text decoding, comparison transforms, aligned-row construction,
merge behavior, and macOS presentation in Swift. Keep xdiff invocation, native result
allocation, hunk extraction, moved-line extraction, and C-level input validation behind
the `mmx_*` ABI.

This decides the implementation boundary, not behavioral parity. Current evidence proves
that MacMerge compiles and executes the intended vendored xdiff engine and has substantial
Mac-only regression coverage. It does not prove that MacMerge reproduces current Windows
`CDiffWrapper` output. MacMerge must not describe an option, moved-block result, or
intra-line result as WinMerge-equivalent until the acceptance gates below pass for that
surface.

If those gates expose behavior that cannot be reproduced without importing substantial
`CDiffWrapper` policy, this decision reopens. Direct porting or extraction of a shared,
platform-neutral wrapper core remains the fallback.

## Context

The roadmap asks whether to port the Windows compatibility/wrapper pipeline or retain the
narrow C ABI with proven behavioral equivalence. It already records that MacMerge uses the
vendored xdiff implementation but reimplements option mapping, post-filtering, row
alignment, encoding, and merge behavior (`todo.md:386-405`).

The alternatives are not merely two call signatures over the same operation:

- MacMerge's C boundary accepts borrowed byte buffers and flags, returns owned hunk and
  moved-line arrays, enforces 64 MiB and 1,048,576-line limits, and exposes matching free
  functions (`MacMerge/Sources/CXDiff/include/macmerge_xdiff.h:11-113`).
- `LineDiff.compareResult` validates and parses Swift strings, prepares filters and
  substitutions, calls `mmx_diff` or `mmx_diff_with_moves`, validates native ranges, and
  creates aligned rows (`MacMerge/Sources/MacMergeCore/LineDiff.swift:696-817,955-1037,1066-1156`).
- Windows `xdiff_gnudiff_compat.cpp` converts `DiffutilsOptions` to xdiff flags, converts
  xdiff's script to GNU diffutils `change` nodes, participates in diffutils file loading
  and binary classification, and optionally invokes Windows moved-block analysis
  (`Src/xdiff_gnudiff_compat.cpp:8-49,57-102,105-195`).
- `CDiffWrapper` also owns file paths, prediff plugins, binary/status handling, two- and
  three-way orchestration, post-filters, `DiffList` translation, moved maps, and patch
  output (`Src/DiffWrapper.h:127-157,167-246`; `Src/DiffWrapper.cpp:358-740,761-996,1283-1422,1457-1860`).

The shared selector name `default` does not identify a shared engine route. On Windows,
`DIFF_ALGORITHM_DEFAULT` calls GNU diffutils `diff_2_files`; only minimal, patience,
histogram, and none call `diff_2_files_xdiff` (`Src/DiffWrapper.cpp:1170-1190`). On Mac,
`.default` calls xdiff with no algorithm-selection bit, while the other four selectors set
their corresponding xdiff bits (`MacMerge/Sources/MacMergeCore/LineDiff.swift:1066-1125,4407-4435`).
Therefore Windows GNU-default versus Mac xdiff-default is a cross-engine product-parity
surface. It is not xdiff engine parity, a compatible implementation, or evidence that the
two defaults choose the same script.

A direct `CDiffWrapper` port would therefore import Windows orchestration and data types,
not only remove a thin adapter. MacMerge's current product architecture is native macOS
and Swift-first (`MacMerge/Package.swift:16-46`), while migration guidance still excludes
three-way, plugin, and patch workflows (`MacMerge/MIGRATION.md:48-75`).

## Evidence

### What is established

| Evidence | Established fact |
| --- | --- |
| `Externals/versions.txt:11,19` | WinMerge's dependency ledger declares LibXDiff as Git commit prefix `611e42a`, dated 2018-11-02. This is declared origin metadata, not proof that the current vendored tree is byte-identical to that Git tree. |
| `MacMerge/Package.swift:16-27` | SwiftPM builds `CXDiff` and links it into `MacMergeCore`. |
| The seven `MacMerge/Sources/CXDiff/vendor_x*.c` shims | MacMerge directly compiles selected translation units from `Externals/xdiff`. |
| `MacMerge/Tests/MacMergeCoreTests/XDiffSourceManifestTests.swift:5-81` | Test records exact upstream C-source/shim coverage and intentional `xmerge.c` exclusion. |
| `MacMerge/Tests/MacMergeCoreTests/XDiffRuntimeRouteTests.swift:5-27` | Fault injection proves production `LineDiff.compare` reaches linked `mmx_diff`. |
| `MacMerge/Sources/CXDiff/macmerge_xdiff.c:10-21` | Compile-time assertions bind public flag values to vendored xdiff values. |
| `MacMerge/Sources/CXDiff/macmerge_xdiff.c:610-714` | Bridge validates outputs, pointers, limits, algorithms, and flags; then calls `xdl_diff_modified`, copies hunks, and cleans native state. |
| `MacMerge/Tests/MacMergeCoreTests/CABIFuzzRegressionTests.swift:22-250` | Seeded tests cover both diff entry points, invalid flags/result shells, cleanup, reuse, and sampled allocation failures. |
| `MacMerge/Tests/MacMergeCoreTests/DiffInputBoundaryTests.swift:6-72` and `MacMerge/Tests/MacMergeCoreTests/InputBoundaryContractTests.swift:16-93` | Tests exercise declared byte/line boundaries and reusable output state. |
| `MacMerge/Tests/MacMergeCoreTests/AlgorithmFallbackContractTests.swift:57-249` | Mac tests exercise five algorithms, both native APIs, fallback-shaped corpora, status mapping, and allocation cleanup. |
| `Testing/GoogleTest/DiffWrapper/DiffWrapper_test.cpp:24-518` | Windows tests assert selected ranges and trivial flags for trailing-EOL, line-break, comment, line-filter, and substitution fixtures. |
| `MacMerge/XDIFF_SYNC.md:3-119,152-218` | Vendored origin/identity, compilation boundary, patch inventory, and mechanical identity/reverse-patch validator are recorded separately. |

### What is not established

- No checked-in Windows oracle currently executes the current `CDiffWrapper` and compares
  its normalized output with MacMerge output. The roadmap still lists that work as open
  (`todo.md:399-405`).
- Shared xdiff source does not prove wrapper equivalence. Windows routes non-default
  algorithms through `diff_2_files_xdiff`, but routes the default selector through GNU
  diffutils `diff_2_files`; the latter is not `diff_2_buffers_xdiff` with zero flags
  (`Src/DiffWrapper.cpp:1170-1190`). MacMerge routes all five `DiffAlgorithm` values,
  including `.default`, through `mmx_diff`
  (`MacMerge/Sources/MacMergeCore/LineDiff.swift:1066-1125,4407-4435`).
- `Externals/versions.txt` does not pin a full WinMerge wrapper checkout and does not prove
  exact tree identity between Git `611e42a` and any later WinMerge `Externals/xdiff`
  snapshot. No oracle may substitute that dependency-ledger entry for a full wrapper commit
  or for the separately measured tree and content hashes below.
- The current worktree has an uncommitted ASCII case-folding change in
  `Externals/xdiff/xutils.c` beyond the accepted xutils EOL/blank-line patch
  (`MacMerge/XDIFF_SYNC.md:152-176`). Until that delta is committed and inventoried or
  removed, source-synchronization and oracle-provenance gates fail; the accepted clean
  commit hash below does not describe the worktree.
- `AllAlgorithmWinMergeParityTests` contains expected rows derived from bundled-xdiff
  captures and source references, but does not run a Windows binary or verify a pinned
  `CDiffWrapper` artifact (`MacMerge/Tests/MacMergeCoreTests/AllAlgorithmWinMergeParityTests.swift:12-17,29-87`).
- Windows `DiffWrapper_test.cpp` does not directly test `diff_2_buffers_xdiff`, moved
  ranges, binary behavior, plugins, patches, or three-way output, and its comment/filter/
  substitution loops omit the `NONE` algorithm (`Testing/GoogleTest/DiffWrapper/DiffWrapper_test.cpp:313-518`).
- Mac moved-line tests establish current Mac behavior against documented fixtures, not a
  live `CDiffWrapper` oracle (`MacMerge/Tests/MacMergeCoreTests/MovedEditedParityTests.swift:5-128`).
- Mac intra-line ranges are computed separately with Swift `CollectionDifference`, not by
  the C ABI or `CDiffWrapper` (`MacMerge/Sources/MacMerge/MacMergeApp.swift:1304-1372`).
- ABI return-code meanings are implemented and tested but are not documented in the
  public header (`MacMerge/Sources/CXDiff/include/macmerge_xdiff.h:56-77`;
  `MacMerge/Sources/CXDiff/macmerge_xdiff.c:624-714`).

## Why This Boundary

Retaining the narrow ABI has the smallest platform coupling consistent with the current
product. It preserves one pinned vendored xdiff lineage while allowing macOS-native
file access, encoding safety, cancellation boundaries, AppKit/SwiftUI presentation, and
Swift value models. The bridge has explicit limits, ownership, cleanup, and fault-injection
coverage that the Windows `change *` compatibility function does not expose as a stable
cross-platform contract.

Directly porting the existing Windows files would not automatically prove parity. It could
move mismatches into platform-dependent file, encoding, parser, plugin, or `DiffList`
layers while retaining separate Mac row and intra-line logic. Differential output remains
required under either architecture.

The cost is intentional duplication of compatibility policy. MacMerge must treat that
duplication as a test obligation, not infer equivalence from common vendor source.

### Security, memory, and maintenance tradeoffs

| Dimension | Narrow ABI retained | Direct wrapper port or shared-core extraction |
| --- | --- | --- |
| Security | Smaller native API avoids importing Windows-owned path, temporary-file, plugin, parser, patch, and SEH surfaces. Mac file I/O still handles paths/staging, and `CXDiff` compiles PCRE2 for untrusted filter/substitution patterns (`MacMerge/Sources/CXDiff/vendor_pcre2.c:1-2`; `MacMerge/Sources/CXDiff/macmerge_regex.c:1-17`). Diff subjects/outputs and PCRE2 match/depth/heap work are bounded, but pattern length and rule count have no separate lower cap; vendored C executes in-process, remains memory-unsafe, and can terminate MacMerge. Xdiff and PCRE2 require source pinning, review, and sanitizer/analyzer evidence. | Reusing authoritative policy can remove divergent reimplementations, but importing Windows path handling, plugin hooks, codepage conversion, C++ object lifetimes, and error assumptions enlarges attack and audit surface. A port receives no safety credit until those dependencies are removed or threat-modeled and same native gates pass. |
| Memory | ABI borrows C input buffers, but Swift currently materializes UTF-8 arrays, xdiff allocates record/script state, the bridge copies hunks/moved mappings, and Swift materializes rows. The 64 MiB per-input limit is not an aggregate-memory bound; current packaged gate checks one resident-memory sample after bottom scroll, not peak RSS. | A shared core might eliminate one transform or range copy. A literal `CDiffWrapper` port can instead retain `file_data`, text buffers, `DiffList`, temporary files, and Mac row models simultaneously. Any claimed reduction requires a separately instrumented peak-RSS comparison on identical fixtures. |
| Maintenance | Seven source shims and five recorded vendor patches keep the engine update small, but option transforms, post-filtering, alignment, moved logic, and merge behavior can drift from Windows and require a differential oracle. | Shared policy can reduce semantic drift. Directly carrying Windows orchestration creates a larger upstream merge surface and platform-adaptation burden; compile success does not establish behavioral or ownership correctness. |
| Licensing and provenance | Native distribution boundary includes recorded xdiff plus bundled PCRE2 10.47 and Mac adapters, not xdiff alone (`Externals/poco/dependencies/pcre2/src/pcre2.h:44-47`). Every sync requires source, notice, and patch-inventory review. | Importing more WinMerge/diffutils/plugin code broadens files and third-party notices that packaging and legal review must track. |

## Parity Contract

Parity applies only to a declared behavior surface and identical logical inputs. Each
surface must state whether comparison starts from raw file bytes, decoded text, or
post-transform bytes. Results are equivalent only when normalized observable outputs are
equal; implementation similarity is irrelevant.

For current two-pane text claims, normalized output must include:

- Pinned WinMerge commit, Windows `Externals/xdiff` Git tree ID, clean MacMerge commit,
  Mac patched-xdiff content-manifest hash, relevant Mac source tree IDs, fixture ID, schema
  version, input hashes, declared encodings, and option values. Post-filter surfaces also
  record PCRE2 version/tree identity. Windows tree, Mac patched content, and Mac wrapper/
  Swift source remain separate provenance fields because MacMerge carries local vendor
  patches and independent compatibility policy (`MacMerge/XDIFF_SYNC.md:3-32,87-119,152-218`).
- Success/error classification, binary classification where tested, missing-final-EOL
  state, and deterministic engine status.
- Ordered left/right ranges with one documented coordinate convention and explicit
  significant/trivial classification.
- Ordered aligned rows with left/right source line numbers, real/ghost state, and row kind.
- Both directional moved-line mappings when moved detection is enabled.
- Directional intra-line spans in UTF-16 coordinates when intra-line parity is claimed.
- For moved and intra-line surfaces, execution state: `executed`, `not-requested`, or
  `suppressed`, with named byte/line/UTF-8/UTF-16/character limit and observed count. Empty
  output is data only when state is `executed`; suppression cannot pass parity.
- Output text bytes plus source/target input hashes for row-merge and merge-all parity
  claims, followed by normalized recomparison output.

Status normalization is stage-based; native numeric codes are retained as diagnostics but
are not compared across unlike APIs:

| Normalized class | Windows evidence | Mac evidence |
| --- | --- | --- |
| `text-success` | `RunFileDiff == true` and `DIFFSTATUS.bBinaries == false` | `LineDiff.compareResult` returns; retain `mmx` status `0` in diagnostics. |
| `binary-same` | `RunFileDiff == true`, `bBinaries == true`, and `Identical == IDENTLEVEL::ALL` | No current `mmx` equivalent; outside text parity unless a separate binary oracle surface is declared. |
| `binary-different` | `RunFileDiff == true`, `bBinaries == true`, and `Identical == IDENTLEVEL::NONE` | No current `mmx` equivalent; outside text parity unless a separate binary oracle surface is declared. |
| `comparison-error` | `RunFileDiff == false` | `LineDiff` throws; record Swift error case and native status when present. |
| `preflight-rejection` | Oracle rejects an input before `RunFileDiff` under a declared common limit | Mac rejects before native allocation; record `LineDiffError`. |

Missing-final-EOL values and successful text ranges are compared separately from status.
An error-code parity claim requires a future cross-platform error taxonomy; equality of a
Windows boolean and an `mmx` integer is not meaningful.

Current option crosswalk is explicit; similar names are not enough:

| Behavior | Windows setting | Mac setting | Current classification |
| --- | --- | --- | --- |
| Default selector | `nDiffAlgorithm == DIFF_ALGORITHM_DEFAULT` | `algorithm == .default` | Common product intent only. Windows executes GNU diffutils; Mac executes xdiff with no algorithm-selection bit. Separate cross-engine gate; never call this xdiff engine parity. |
| Non-default algorithm | minimal, patience, histogram, none | same four names | Common xdiff selectors; wrapper and post-processing equivalence pending. |
| Whitespace | `nIgnoreWhitespace` | `whitespace` | Common: three values; equivalence pending. |
| Case, numbers, blank lines | corresponding `DIFFOPTIONS` booleans | `ignoreCase`, `ignoreNumbers`, `ignoreBlankLines` | Common; equivalence pending. |
| EOL-style differences | `bIgnoreEol` | `ignoreLineEndings` | Common intent; equivalence pending. |
| Indent heuristic | `bIndentHeuristic` | `indentHeuristic` | Common only for four non-default xdiff selectors. Windows GNU-default does not map this setting in `DiffutilsOptions::SetToDiffUtils`, while Mac default passes `XDF_INDENT_HEURISTIC`; default+indent is a named incompatibility, not a common option (`Src/CompareOptions.cpp:132-179`; `Src/xdiff_gnudiff_compat.cpp:8-49`). |
| Comment filtering | `bFilterCommentsLines` plus syntax definition | `ignoreComments` plus `commentSyntax` | Common only for a manifest-pinned syntax intersection. |
| Line filters and substitutions | wrapper filter lists | enabled Mac rule lists | Common only for a manifest-pinned regex/replacement intersection. |
| Moved blocks | `SetDetectMovedBlocks` | `detectMovedBlocks` | Common output concept; implementation and limits differ. |
| Missing trailing EOL | `bIgnoreMissingTrailingEol` | none | Missing on Mac as a distinct option; excluded from common option parity. |
| Treat line breaks as spaces | `bIgnoreLineBreaks` | none | Missing on Mac; excluded from common option parity. |
| Blank ignored changes from display | `bCompletelyBlankOutIgnoredChanges` | none | Windows presentation behavior; excluded. |

Option-parity claims cover only rows classified Common. Missing/adapted rows remain named
gaps and block any aggregate "full comparison-options parity" claim.

Allowed claim scopes are deliberately narrow:

- `vendored-xdiff provenance` means source identity only.
- `xdiff range parity` may cover only the four non-default xdiff selectors unless a
  separately declared zero-flag raw-xdiff surface is compared against
  `diff_2_buffers_xdiff`; it never includes Windows GNU-default.
- `default product parity` means GNU-default versus Mac xdiff-default passed its separate
  end-to-end gate; it does not imply common-engine or implementation parity.
- `CDiffWrapper parity` requires the authoritative Windows wrapper route and only the
  normalized surfaces named in the passing manifest.
- `two-pane text parity` requires every surface designated required in that versioned
  manifest. No passing subset supports `full WinMerge parity`.

No broad allowlist is permitted. A deliberate macOS adaptation must be named, documented
outside the parity surface, and tested as an adaptation. Unexplained differences fail the
gate.

The following remain outside this ADR's current parity surface: three-way comparison,
folder classification, binary/hex presentation, plugin and prediffer hosting, patch
generation, report generation, and Windows-specific status/UI behavior. Merge behavior is
also outside a `CDiffWrapper`-only claim: Windows performs it downstream in
`CMergeDoc::LineListCopy` for a selected aligned line, with merge-all entering through
`CopyAllList` / `CopyMultipleList` (`Src/MergeDocDiffCopy.cpp:61-170,643-735`). `ListCopy`
copies a whole `DIFFRANGE`, and `InlineDiffListCopy` copies word spans
(`Src/MergeDocDiffCopy.cpp:529-640,737-853`). Merge becomes a parity surface only when the
oracle executes the corresponding authoritative Windows operation and compares resulting
bytes. These exclusions do not imply equivalence or permanent rejection.

## Parity Obligations

1. Build a Windows fixture oracle that invokes the current `CDiffWrapper` path. For aligned
   rows, pin similar-line alignment off and continue through `CMergeDoc::PrimeTextBuffers`,
   which creates synchronized ghost lines (`Src/MergeDoc.cpp:540-551,1583-1746`). A future
   claim with similar-line alignment enabled must also run `AdjustDiffBlocks` and declare a
   separate surface. For intra-line output, continue through
   `CMergeDoc::GetWordDiffArrayInDiffBlock` / `GetWordDiffArrayInRange`, which call
   `strdiff::ComputeWordDiffs` (`Src/MergeDocLineDiffs.cpp:315-378`). For merge output,
   execute `LineListCopy` for the selected aligned row and `CopyAllList` for merge all;
   declare whole-`DIFFRANGE` `ListCopy` and partial `InlineDiffListCopy` as separate surfaces.
   Mac counterparts are `LineMerge.apply` and `LineMerge.applyAll`
   (`MacMerge/Sources/MacMergeCore/LineDiff.swift:4510-4599`). `CDiffWrapper` alone proves
   none of these downstream surfaces. Merge payload compares canonical in-memory Unicode
   scalar sequences and line terminators first. A saved-byte claim is separate: run each
   side's authoritative non-temporary save path with encoding, BOM, EOL policy, and lossy
   handling pinned, then compare bytes.
2. Pin every oracle artifact to a full WinMerge commit, Windows xdiff Git tree ID, and Mac
   patched-xdiff content-manifest hash. Also record the `Externals/versions.txt` LibXDiff
   declaration from that checkout as full commit, date, and source URL. Generated data
   without these fields is diagnostic only, not a golden. The versions entry is metadata
   to reconcile, not a replacement for measured tree identity.
3. Exercise minimal, patience, histogram, and none as the xdiff-selector matrix. Exercise
   Windows GNU-default versus Mac xdiff-default as a separate cross-engine matrix with
   identical fixtures/options and zero output differences. Never combine the default row
   into an `xdiff parity` pass count, and do not waive default mismatches because the user
   visible selector names agree.
4. Exercise each Common crosswalk option both off and on for every applicable algorithm.
   For GNU-default versus Mac default, hold indent heuristic off in the common matrix and
   run an additional on/off gap probe; the default surface cannot include indent-option
   parity unless Windows adopts equivalent behavior or Mac default deliberately neutralizes
   the flag under a separately reviewed product decision. Exercise the
   manifest-pinned line-filter, substitution, comment-syntax, and moved intersections for
   every algorithm with applicable fixtures. Exercise missing-final-EOL and line-break
   fixtures to prove their named gap; do not count them as common option parity.
5. Include empty, identical, add/delete/change, repeated-line, ambiguous-alignment,
   fallback-shaped, mixed-EOL, missing-final-EOL, long-line, moved-and-edited, Unicode,
   and every currently supported legacy-encoding fixture. Separate byte-loading parity
   from decoded-text comparison parity.
6. Import every fixture represented by `Testing/GoogleTest/DiffWrapper/DiffWrapper_test.cpp`.
   A versioned corpus manifest must enumerate every file under `Testing/Data`; each file is
   either included in a named behavior surface or excluded by stable fixture ID and reason.
   CI fails on an unclassified added, removed, or renamed file.
7. Keep C ownership, error, limit, malformed-output, and allocation-failure tests independent
   of behavioral oracle tests. Oracle equality does not replace memory-safety evidence.
8. Re-run the oracle and all native safety gates whenever WinMerge's xdiff snapshot,
   `xdiff_gnudiff_compat`, `CDiffWrapper`, MacMerge's C ABI, or Swift transform/row logic
   changes.
9. For byte-loading and encoding claims, disable Windows plugins and pin codepage-detection
   mode, `OPT_ALLOW_MIXED_EOL`, requested `CRLFSTYLE`, BOM presence/policy, and lossy-load or
   lossy-save retry/rejection outcome. Run raw fixture bytes through Windows `codepage_detect::Guess`,
   `CMergeDoc::LoadFile` / `CDiffTextBuffer::LoadFromFile`, and non-temporary
   `CDiffTextBuffer::SaveToFile` (`Src/MergeDoc.cpp:2104-2212`;
   `Src/DiffTextBuffer.cpp:205-378,389-525`). Compare that with Mac
   `TextFileCodec.decode` / `encode` and `TextFileDocumentIO.load` / `save`
   (`MacMerge/Sources/MacMergeCore/TextFileCodec.swift:90-293`;
    `MacMerge/Sources/MacMergeCore/TextFileDocument.swift:75-209`). Automatic detection and
    explicitly selected encoding are separate surfaces; unchanged-byte round trip is not
    claimed across different normalization or lossy-recovery policies.

Every matrix run must emit machine-readable `planned`, `executed`, `passed`, `failed`, and
`skipped` counts plus one record per case. A gate passes only when `executed == planned`,
`passed == planned`, and `failed == skipped == 0`. Unsupported or inapplicable cases belong
in a versioned exclusion manifest, emit `classification: unsupported` in a separate
diagnostic report, and do not enter `planned` or any parity pass count. A required surface
with an unsupported case remains blocked.

### Pinned xdiff source identities

At the accepted WinMerge xdiff snapshot, both top-level WinMerge and nested WinIMerge entries
in `Externals/versions.txt:11,19` declare `LibXDiff: 611e42a on Nov 2, 2018` and link to
Git's `xdiff` directory. Git resolves that abbreviation to
`611e42a5980a3a9f8bb3b1b49c1abde63c7a191e`; its `xdiff` tree is
`77abde3699bc6874e10f1c17f4b97c219492542f`. For the initial WinMerge import, repository
validation establishes matching file inventory/blobs except the documented `xinclude.h`
portability delta, not byte-identical tree equality (`MacMerge/XDIFF_SYNC.md:25-64`). Later
WinMerge changes and the Mac patch layer remain separate provenance.

MacMerge's WinMerge path pin `7a3e1ec3efcc0ebad2034f72d8f87a6c74d62301` has
`Externals/xdiff` Git tree ID `bf7ade8ccf4199ab85649c5aac4474b14e44f55f`. Accepted Mac
patch-introduction commit `40d8b10d0928bc415e6c3febd2dab2f6daff1a5c` has patched tree
`a2f958abe94a14a95200c911be748cd3f9b7e9f0` and content-manifest SHA-256
`9625ad79f0afe1b596abefd6f7b5180f3895baafd109e007ce7356a9612bbc6e`.
These identify WinMerge engine source and Mac patched content only. The path pin is not a
current `CDiffWrapper` oracle pin, and this ADR accepts no Windows wrapper golden yet.
Because `Externals/xdiff/xutils.c` is modified in the current worktree and the extra
case-folding delta is absent from the accepted patched commit and inventory
(`MacMerge/XDIFF_SYNC.md:152-176`), the worktree hash is not accepted provenance. No parity
artifact may cite a dirty Mac worktree; an intentional delta requires a new clean commit,
updated inventory/tree ID, and regenerated content hash.

The Mac manifest includes every Git-tracked path under `Externals/xdiff`, sorted by raw
relative path bytes under `LC_ALL=C`. Each manifest line is
`SHA256(file)`, two ASCII spaces, relative path, and LF. SHA-256 of those concatenated
lines is the recorded content-manifest hash. Regenerate from repository root with:

```bash
git ls-files -z -- Externals/xdiff \
  | LC_ALL=C sort -z \
  | xargs -0 shasum -a 256 \
  | shasum -a 256
```

The executable synchronization validator must compare both recorded values and fail if
`git status --porcelain=v1 -- Externals/xdiff` is nonempty. Any intentional vendor change
updates `MacMerge/XDIFF_SYNC.md`, this identity block, and oracle provenance together.
It must parse the top-level LibXDiff declaration at `Externals/versions.txt:19` as the
WinMerge xdiff origin field and resolve its abbreviation to exactly one full Git commit and
Git `xdiff` tree ID. The nested WinIMerge declaration at line 11 is a separately named
dependency field; it currently agrees but is not required to follow the top-level entry.
Failure to resolve either declared abbreviation is a provenance failure for surfaces that
consume that dependency, not permission to infer an origin.
Each future Windows oracle artifact separately records its full checkout commit. Before
building the oracle, CI must assert `git rev-parse HEAD` equals that value and
`git rev-parse HEAD:Externals/xdiff` equals the artifact's Windows xdiff tree ID. Detached
HEAD is allowed; any object-ID mismatch or locally modified wrapper input fails provenance.

## Acceptance Gates

The narrow-ABI approach may be labeled behaviorally equivalent for a declared surface only
when every common gate and every gate mapped to that surface pass. Each oracle artifact
contains a schema-versioned surface manifest; aggregate "two-pane text parity" is forbidden
until every surface marked required by that manifest passes.

| Surface | Required surface-specific gates |
| --- | --- |
| Non-default xdiff engine ranges and comparison options | Corpus coverage, non-default xdiff option coverage, output equality |
| Default product behavior | Corpus coverage, separate GNU-default-versus-Mac-default option coverage, output equality |
| Aligned rows | Engine-range gates plus authoritative-row equality |
| Moved lines | Engine-range gates plus moved equality |
| Intra-line spans | Aligned-row gates plus intra-line equality |
| Raw-byte loading and decoded text | Encoding-stage equality plus engine/row gates for the decoded result |
| Row merge and merge all | Aligned-row gates plus authoritative-merge equality |

Oracle provenance, oracle execution, ABI contract, safety, performance, and source
synchronization are common gates for every surface.

| Gate | Measurable pass condition |
| --- | --- |
| Oracle provenance | Every golden contains full WinMerge wrapper checkout commit, checkout `Externals/xdiff` tree ID, separately named top-level and nested `Externals/versions.txt` LibXDiff declarations resolved to full Git commits and Git `xdiff` tree IDs, clean MacMerge commit, Mac patched-xdiff content hash, relevant Mac source tree IDs, schema version, and input hashes. Post-filter goldens also pin PCRE2 version/tree. CI proves object IDs and clean scoped worktrees, rejecting missing fields, unresolved abbreviations, uninventoried vendor deltas, or mixed provenance. |
| Oracle execution | Windows CI builds authoritative wrapper and regenerates normalized output; Mac CI runs same corpus through production Mac stages. Artifact envelope records provenance, executable SHA-256, architecture, build configuration, and option-manifest hash. Separate canonical payload contains only schema-defined comparable fields, excludes platform metadata and unlike native diagnostics, uses fixed key ordering/encoding, and is byte-compared Windows-to-golden and Windows-to-Mac. `RunFileDiff` return and `DIFFSTATUS` are asserted. Report satisfies `executed == planned`, `passed == planned`, and `failed == skipped == 0`. |
| Corpus coverage | Manifest expands every inline block and loop iteration in all six `DiffWrapper_test.cpp` tests. Case ID is SHA-256 of test name, loop parameters/options, and raw left/right input bytes; CI compares exact generated ID set and count with oracle enumeration, not test-name count alone. It includes at least one fixture for every category in obligation 5 and every Mac-supported encoding. Every file under `Testing/Data` is included or excluded by stable ID/reason; CI rejects unclassified changes. Excluded data does not count toward a passing surface. |
| Non-default xdiff option coverage | Matrix contains exactly 4 algorithms x 3 whitespace modes x 32 combinations of ignore-case, ignore-numbers, ignore-blank-lines, ignore-EOL, and indent-heuristic flags = 384 base configurations per required fixture. Separate post-filter and moved manifests run each applicable fixture under all 4 selectors. Every boolean option has at least one paired sensitivity fixture whose normalized output changes when only that option toggles. Report satisfies complete-execution counts above. |
| Default product option coverage | Common matrix contains exactly 1 Windows GNU-default-versus-Mac-xdiff-default route x 3 whitespace modes x 16 combinations of ignore-case, ignore-numbers, ignore-blank-lines, and ignore-EOL, with indent heuristic fixed off = 48 base configurations per required fixture, plus every applicable post-filter and moved fixture. Each of the 4 common booleans has a paired sensitivity fixture. Separate indent on/off gap cases must execute and remain classified unsupported; they block any default-indent or full-options claim. A pass supports only the declared default-without-indent product surface, never xdiff engine parity. |
| Output equality | Zero differences in normalized status class, binary classification when in-surface, missing-final-EOL state, ordered ranges, and trivial flags. Default-algorithm differences are failures. |
| Authoritative-row equality | Zero differences in ordered left/right real-or-ghost source line IDs and row kinds after Windows `PrimeTextBuffers` versus Mac `LineDiff` alignment. |
| Moved equality | Zero differences in both ordered directional moved-line mappings when moved detection is enabled, and both sides report execution rather than suppression. Fixtures stay within Mac transformed-move limits of 8 MiB and 65,536 lines per file when transforms are active (`MacMerge/Sources/MacMergeCore/LineDiff.swift:683-684,718-745`). |
| Intra-line equality | Before intra-line parity is claimed, zero differences in directional UTF-16 spans against a pinned WinMerge oracle corpus, and both sides report execution rather than suppression. Oracle pins `OPT_BREAK_TYPE`, `OPT_BREAK_ON_WORDS`, `OPT_BREAK_SEPARATORS`, byte-coloring mode, and table-editing mode because they configure `ComputeWordDiffs` and its break-character table (`Src/MergeDocLineDiffs.cpp:315-378`; `Src/MergeDoc.cpp:2810-2821`; `Src/Merge.cpp:451-452`; `Src/stringdiffs.cpp:44-59,789-804`). Mac fixtures stay within 16,384 UTF-8 bytes, 8,192 UTF-16 units, and 2,048 characters per line (`MacMerge/Sources/MacMerge/MacMergeApp.swift:1316-1324,1392-1398`). Existing Mac-only Unicode tests remain required but are not oracle proof. |
| Encoding-stage equality | Zero differences in selected encoding, decoded scalar sequence, loss/failure classification, and unchanged-byte round trip for every encoding fixture in the declared surface. |
| Authoritative-merge equality | Zero differences in canonical in-memory Unicode scalar sequences and line terminators for row merge and merge all in both directions, followed by zero normalized recomparison differences. Saved-byte equality is a separate encoding-stage gate using authoritative save paths and pinned encoding/BOM/EOL/loss policy. |
| ABI contract | Public status meanings, zero-initialization, ownership, limits, and free semantics are documented and tested; no ABI type exposes Windows `file_data`, `change`, path, plugin, or `DiffList` state. |
| Safety | Windows wrapper tests, `swift test -Xswiftc -warnings-as-errors`, Address Sanitizer tests, release build, boundary tests, and C analyzer over every C translation unit SwiftPM compiles in `CXDiff`, including seven xdiff shims, `vendor_pcre2.c`, `macmerge_xdiff.c`, and `macmerge_regex.c`, pass with production includes/defines. Candidate migrations additionally enumerate and analyze/sanitize every linked native translation unit and test every ownership edge/failure exit they add. For fallback, non-fallback, and moved corpora under all 5 Mac selectors, both native entry points sweep exactly `0..<successfulAllocationAttemptCount`; caps fail. Every injected failure returns nonzero, leaves outputs zeroed/reusable, and leaves zero tracked allocations. This proves tested handling, not absence of native vulnerabilities. |
| Performance and memory | Packaged gates require load <= 5,000 ms, comparison <= 5,000 ms, first render <= 1,500 ms, Location Pane render <= 1,500 ms, bottom scroll <= 1,500 ms, and post-scroll resident bytes <= the configured MiB ceiling. Reports record raw bytes plus successful sampling status, line count, density, content, line bytes, all six budgets, machine/OS, and a retained SHA-256 sidecar. The baseline fixture remains 1,000,000-line sparse ASCII at <= 900 MiB; CI also gates 250,000 alternating changed/unchanged lines (`location-dense`) with exactly 125,000 Location Map runs at <= 450 MiB. Threshold/fixture changes require ADR amendment and before/after report. This is neither peak RSS nor a claim for all inputs below 64 MiB. |
| Source synchronization | `XDiffSourceManifestTests` and `XDiffRuntimeRouteTests` pass, and an executable validator reproduces the file set, ordering, SHA-256 manifest, clean vendor status, pinned Windows tree ID, shim mapping, and local patch inventory defined above and in `MacMerge/XDIFF_SYNC.md`. Current source/runtime tests alone do not validate those hashes. |

Until all applicable gates pass, documentation must use scoped wording such as "uses
WinMerge's bundled xdiff" or "matches these fixtures," not "full `CDiffWrapper` parity."

## Alternatives Considered

### Port `xdiff_gnudiff_compat.cpp` only

Rejected. Its public-looking functions depend on GNU diffutils `change` and `file_data`,
diffutils file loading and binary detection, WinMerge option types, and moved-block analysis
(`Src/xdiff_gnudiff_compat.h:3-7`; `Src/xdiff_gnudiff_compat.cpp:57-195`). Porting it alone
would widen the Mac native boundary without importing the policy that consumes those
types. It would also retain separate Swift post-filter and row logic, so it would not
resolve pipeline parity.

### Port `CDiffWrapper` directly

Rejected for current scope. It would bring path and temporary-file management, prediff
plugins, codepage-aware filters, binary status, two-/three-way `DiffList` construction,
moved maps, patch output, exception/SEH handling, and Windows-oriented dependencies into
the Mac core. Most are outside current two-pane text scope. A future shared-core extraction
may be justified, but a direct source port is not presently a narrow or proven change.

### Extract a new shared platform-neutral wrapper core

Deferred. This could eventually centralize option mapping, post-filter semantics, and
normalized range production while injecting file loading, syntax parsing, and allocation.
It requires a passing differential oracle first; otherwise extraction can preserve or
introduce unknown behavior. Reconsider when migration triggers fire.

### Replace vendored xdiff with a Swift diff implementation

Rejected. It would discard current source provenance and algorithm behavior, enlarge the
parity problem, and invalidate native fallback, flag, and moved-analysis evidence without
solving `CDiffWrapper` equivalence.

## Risks and Mitigations

| Risk | Mitigation |
| --- | --- |
| Common xdiff source creates false confidence | Require executable Windows oracle output; distinguish engine provenance from wrapper parity. |
| Windows default uses GNU diffutils while Mac default uses xdiff without an algorithm-selection bit | Keep default outside xdiff-engine claims; run its own 48-common-configuration-per-fixture cross-engine matrix plus indent gap probes and reopen architecture or product semantics on any in-surface mismatch. |
| Swift and `CDiffWrapper` transforms drift | Full option/post-filter matrix and fixture-manifest coverage in CI. |
| Moved detection implementations diverge | Compare both directional mappings, ambiguous moves, edited moves, and swapped inputs under every algorithm. |
| Unicode or codepage handling diverges before xdiff | Separate raw-byte, decoded-text, and transformed-byte stages; run supported encoding fixtures through both pipelines. |
| ABI grows into an unstable mirror of Windows internals | Keep `mmx_*` value/buffer based; architecture review before exposing wrapper-owned types. |
| Vendored updates silently alter behavior | Follow `MacMerge/XDIFF_SYNC.md`; regenerate pinned oracle artifacts on every relevant sync. |
| In-process vendored C compromises memory safety | Preserve strict input/result validation, full allocation-failure sweeps, ASan/analyzer gates, patch inventory, and immediate security-trigger review; do not characterize sanitizer success as proof of safety. |
| Narrow bridge duplicates allocations or hurts large-file memory | Preserve current boundary limits and packaged post-scroll RSS gate; add identical-fixture peak-RSS instrumentation before claiming a shared/direct port is cheaper. |
| Direct port expands security or licensing scope | Inventory every imported path/plugin/parser/codepage dependency and notice; require threat model, packaging review, and same safety gates before adoption. |
| Oracle arrives late and reveals systemic differences | Treat failure as migration input, not as a reason to weaken expected output or add broad exceptions. |

## Migration Triggers

Any trigger requires a new ADR or explicit amendment before widening `mmx_*`. The first
trigger below is the direct-port decision rule, not merely a prompt for more investigation:

- After provenance, option serialization, input bytes, coordinate normalization, and oracle
  determinism are verified, at least one required surface still has one or more
  reproducible mismatches in two consecutive clean CI runs. Permit one bounded narrow fix:
  <= 200 changed nonblank, noncomment policy lines, no new native dependency, and no ABI
  type. If that candidate cannot reach zero, compare a direct policy-port prototype and a
  shared-core extraction prototype on the same corpus. Each prototype supplies the same
  policy-line manifest and a sorted linked-native-dependency/license manifest. Migration
  becomes required only when at least one prototype reaches zero without relaxing safety,
  memory, or performance gates; choose shared extraction when both pass unless direct port
  has fewer nonblank, noncomment policy lines and its dependency/license manifest is a
  subset of shared extraction's. If only one passes, choose it; if both pass and direct does
  not meet that tie-break, choose shared extraction. If neither passes,
  product owners must remove or redefine the required surface in an ADR amendment; broad
  exceptions are forbidden.
- Default product parity fails because GNU diffutils behavior cannot be reproduced through
  xdiff without an algorithm-selection bit plus platform-neutral post-processing. This is
  direct evidence for importing/extracting the GNU compatibility route or renaming/removing
  Mac `.default`; calling both settings `default` is not an acceptable workaround.
- Supporting three-way comparison, WinMerge-compatible patch generation, prediff plugins,
  or shared folder/file classification becomes committed product scope.
- A proposed ABI revision would expose `file_data`, `change`, `DiffList`, paths, codepages,
  parser objects, or plugin state rather than a platform-neutral value contract.
- Two consecutive pinned WinMerge wrapper updates require behavior-changing edits in both
  `MacMerge/Sources/CXDiff` and Swift transform/row code to preserve the same oracle output;
  behavior-changing means noncomment/non-whitespace lines changed in files from the
  checked-in policy manifest and at least one normalized oracle payload changes before the
  edit. Record diff-tool version, changed-line counts, before/after payload hashes, and
  affected surface IDs in both update reports.
- Measured maintenance or performance data from a prototype shared-core extraction shows
  at least 25% fewer nonblank, noncomment lines in a checked-in manifest of files that
  implement option mapping, transforms, hunk/range translation, alignment, and moved logic.
  The same report pins baseline/prototype commits and tool version. On one pinned machine/OS,
  after one warm-up and at least 10 alternating runs, prototype median comparison time must
  be <= 110% of baseline. Peak RSS uses Darwin `proc_pid_rusage` high-water bytes sampled
  after launch, load, comparison, first render, bottom scroll, and immediately before exit;
  prototype maximum across runs must be <= 110% of baseline. Commit all raw samples. Every
  applicable acceptance gate passes without relaxed limits or budgets. Current post-scroll
  resident sample alone cannot satisfy this trigger.
- Security, memory safety, licensing, or upstream synchronization requirements can no
  longer be satisfied by the shim-compilation model.

## Revisit Criteria

Revisit this decision:

- Before marking comparison options, moved blocks, or intra-line behavior fully
  WinMerge-compatible.
- On every pinned WinMerge xdiff synchronization that changes flags, callbacks, script
  shape, allocation behavior, or compiled translation units.
- When `xdiff_gnudiff_compat.cpp`, `CDiffWrapper`, MacMerge transform logic, or normalized
  oracle schema changes observable output.
- Before adding any migration-trigger feature.
- Immediately after an unexplained oracle mismatch persists after inputs, coordinate
  conventions, and provenance are verified.

## Consequences

- MacMerge keeps a small C surface and native Swift/macOS orchestration.
- Existing C ABI and Mac regression tests remain valuable but are explicitly insufficient
  as cross-platform parity proof.
- Windows oracle infrastructure becomes mandatory work, not optional confidence testing.
- Default algorithm, moved blocks, post-filtering, encodings, and intra-line ranges remain
  separately auditable parity surfaces.
- Direct `CDiffWrapper` porting is avoided now but remains a defined migration path if
  evidence shows the narrow boundary cannot reproduce required behavior.
