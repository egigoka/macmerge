# Differential Oracle Coverage

`coverage.lock` is the reviewed inventory that ties MacMerge alignment to WinMerge
`CDiffWrapper` oracle results. `Scripts/check-diff-oracle-coverage.sh` verifies it in the CI
quality job as its own step, **Check diff oracle coverage**; `Scripts/test-ci-quality.sh` only
requires that step to exist and runs a negative self-test (an edited alignment fingerprint must
fail). The parser, discovery, and audit live in
`Sources/MacMergeCore/DiffOracleFixtureCoverage.swift`; the script compiles that file with
`Sources/MacMergeCore/DiffOracleManifest.swift` and `Scripts/DiffOracleCoverageGate/main.swift`,
so it does not need a package build.

The workflow's `push` and `pull_request` path filters include `Testing/GoogleTest/DiffWrapper/**`
and `Testing/Data/**`, so a fixture-only change still runs the gate. `Scripts/test-ci-quality.sh`
fails if those filters are removed.

## Records

| Record | Meaning |
| --- | --- |
| `fixture-winmerge-commit` | Full WinMerge commit the checked-in `Testing/` fixtures come from (the upstream base of this fork). Every golden must be generated from this commit. |
| `fixture-xdiff-tree` | Git tree ID of `Externals/xdiff` at `fixture-winmerge-commit`. Every golden's `xdiff-tree` must equal it. The gate resolves `fixture-winmerge-commit` and checks the tree with `git rev-parse <commit>:Externals/xdiff`. The CI quality job checks out full history (`fetch-depth: 0`) so this always runs there. In a full clone that cannot resolve the commit the gate fails; only a shallow clone or a non-git tree skips the check, and the gate then prints "not verified" instead of claiming a match. |
| `alignment-path` | Repository-relative file or directory whose bytes determine MacMerge alignment for a required fixture. |
| `alignment-fingerprint` | SHA-256 over every `alignment-path` content digest. |
| `diffwrapper-tree` | File count and digest of every file under `Testing/GoogleTest/DiffWrapper`, so shared helpers such as `WriteToTempFile`, includes before the first `TEST`, and non-`.cpp` files cannot change without review. |
| `diffwrapper` | One `TEST` in `Testing/GoogleTest/DiffWrapper/*.cpp`: `right-file-sites` and the SHA-256 of its source text (from its `TEST(` line to the next test). `right-file-sites` counts `right = WriteToTempFile(` source sites only. It is **not** the number of comparisons: every test loops over four or five diff algorithms, and `RunFileDiff_IgnoreMissingTrailingEol` also loops over EOL styles. All DiffWrapper tests are required oracle sources. IDs must be ASCII `Suite.Name`. |
| `testing-data` | One top-level `Testing/Data` entry, either `required` (with file count and tree digest) or `excluded` (with a kebab-case reason). Names must be single tokens without whitespace or `=`. |
| `golden` | One normalized WinMerge result under `MacMerge/DiffOracle/goldens/`, with `source`, every `DiffOracleGoldenProvenance` field, the `alignment` fingerprint it was reviewed against, `path`, and the file's `sha256`. |

### Golden provenance mapping

Golden records reuse the `DiffOracleManifest.swift` value types. Each provenance key maps to one
`DiffOracleGoldenProvenance` property:

| Lock key | `DiffOracleGoldenProvenance` property |
| --- | --- |
| `winmerge-commit` | `winMergeCommit` |
| `xdiff-tree` | `windowsXDiffTree` |
| `libxdiff-commit` / `libxdiff-tree` | `topLevelLibXDiffCommit` / `topLevelLibXDiffTree` |
| `nested-libxdiff-commit` / `nested-libxdiff-tree` | `nestedLibXDiffCommit` / `nestedLibXDiffTree` |
| `oracle-executable` | `oracleExecutableSHA256` |
| `generator-version` | `generatorVersion` |
| `generator-executable` / `generator-schema` / `generator-configuration` | `generatorExecutableSHA256` / `generatorSchemaSHA256` / `generatorConfigurationSHA256` |
| `architecture` / `build-configuration` | `architecture` / `buildConfiguration` |

The lock is the coarse inventory: one record per DiffWrapper test and per top-level `Testing/Data`
entry. The manifest's `DiffOracleCorpusManifestEntry` records are the finer level (one per
expanded DiffWrapper case, one per `Testing/Data` file) that a Windows oracle run emits for each
required lock source.

## How the alignment paths were chosen

Each path is code that can change how a required fixture aligns:

- `Externals/xdiff` and `MacMerge/Sources/CXDiff`: the vendored xdiff engine and its C bridge
  (`vendor_*.c`, `macmerge_xdiff.c`, `macmerge_regex.c`).
- `Externals/poco/dependencies/pcre2/src`: compiled in through `CXDiff/vendor_pcre2.c` and used by
  `macmerge_regex.c`; it drives the `LineFilters` and `SubstitutionFilters` DiffWrapper tests.
- `MacMergeCore/LineDiff.swift`: comparison options, transforms, and EOL line splitting
  (`TextDocument`) before the native diff.
- `MacMergeCore/TextFileCodec.swift` and `MacMergeCore/TextFileDocument.swift`: byte-to-text
  decoding and file loading used by the `Codepages`, `Unicode`, and `LastLineEOL` fixtures.

App-layer files (rendering, scrolling, menus) are not listed: they do not change alignment.
When alignment moves into a new file, add it here and to the lock.

## What fails CI

- A DiffWrapper test, any file under `Testing/GoogleTest/DiffWrapper`, or a `Testing/Data`
  entry is added, removed, or changed without a lock update.
- A `Testing/Data` entry has no `required`/`excluded` decision, or a DiffWrapper test or
  `Testing/Data` entry has a name the lock cannot represent (reported as such).
- `fixture-winmerge-commit` cannot be resolved in a non-shallow checkout, or `fixture-xdiff-tree`
  disagrees with git.
- MacMerge alignment sources change without updating `alignment-fingerprint`.
- A golden's WinMerge commit or xdiff tree differs from the fixture pins, its file is missing
  or changed, or its `alignment` fingerprint is stale. Refreshing the lock never rewrites golden
  records, so an alignment change with goldens present fails until the WinMerge oracle result
  is regenerated or re-reviewed and its `alignment` field is updated by hand.
- With `DIFF_ORACLE_REQUIRE_GOLDENS=1`, any required source without a valid golden. A golden
  with any finding of its own (missing, changed, stale, or pin mismatch) does not cover its source.

## Current status

No golden results exist yet: generating them requires the Windows `CDiffWrapper` oracle runner
(see `XDIFF_ARCHITECTURE_DECISION.md`). Until then the gate reports every required source as
pending and enforces only inventory and fingerprint review. **Alignment review is currently
fingerprint acknowledgement only**: running `--refresh` and committing the new
`alignment-fingerprint` satisfies the gate without any comparison against WinMerge output. The
gate does not prove WinMerge parity.

## Updating

Run `Scripts/check-diff-oracle-coverage.sh --refresh` to rewrite recorded digests, then review
the lock diff. New `Testing/Data` entries are not added automatically; classify them by hand.
`fixture-winmerge-commit`, `fixture-xdiff-tree`, `alignment-path`, and golden records are never
rewritten by `--refresh`.
