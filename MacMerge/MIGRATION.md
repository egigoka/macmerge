# Migrating from WinMerge to MacMerge

MacMerge is a pre-release native macOS port focused on two-pane text comparison. Keep WinMerge available for workflows marked partial or unavailable below, and work on copies of important files until MacMerge release packaging is complete.

## Requirements

- macOS 14 or later
- Two text files no larger than 64 MiB or 1,048,576 lines per side
- Explicit encoding selection when a file has multiple lossless interpretations

## Before migrating

1. Keep original files and WinMerge configuration backed up.
2. Do not expect WinMerge registry settings, projects, filters, plugins, or recent-item history to import automatically.
3. Verify files using unsupported encodings in WinMerge before editing them in MacMerge.
4. Retain WinMerge for folder, three-way, binary, image, table, webpage, archive, report, patch, and plugin workflows.

## Start a comparison

Open MacMerge and choose both files, use Finder Open With, or pass two paths to the executable:

```bash
MacMerge /path/to/left.txt /path/to/right.txt
```

MacMerge can replace either side after opening a pair. Unsaved changes are guarded before replacement, reload, or quit.

## Text and encoding behavior

MacMerge uses WinMerge's bundled xdiff engine through a native C boundary. Current text comparison supports aligned additions, removals, modifications, line and substitution filters, configurable algorithms, whitespace and case options, ignored blank lines, ignored line endings, and supported comment syntaxes.

UTF-8 with or without a BOM and BOM-marked UTF-16 LE/BE round-trip losslessly. Verified legacy paths cover CP932, CP51932, CP50220, CP1250, CP1251, and CP1252. Unchanged supported legacy files retain exact bytes; edited text must remain representable. Ambiguous or unsupported encodings fail closed rather than being rewritten under a guess.

Mixed line endings and final-newline state are preserved. A strict comparison can treat line-ending differences as significant; ignored-line-ending mode preserves unrelated target terminators during merges.

## Merge and recovery behavior

- Copy one difference or all differences in either direction.
- Copy-and-advance, difference navigation, selection, undo, and redo operate on comparison history.
- Save either side, save both dirty sides, or use Save As for files and scratchpads.
- Save rejects destinations that alias the opposite pane.
- Save rejects a file changed externally after loading.
- Symlink saves update the target without replacing the link.
- Failed saves retain a recovery copy when cleanup or rollback cannot be proven safe.

After a merge, save and reopen both files before retiring the source workflow. Recomparison should report no unexpected differences under the same options.

## Feature parity matrix

| WinMerge workflow | MacMerge status | Migration guidance |
| --- | --- | --- |
| Two-pane text comparison | Ready | Supported for current text and encoding limits. |
| Text difference navigation | Ready | First, current, previous, next, and last difference are available. |
| Row merge and Merge All | Ready | Both directions, copy-and-advance, bounded undo, and redo are available. |
| Text editing and scratchpads | Ready | Both panes are editable; untitled panes use Save As. |
| Encoding and newline preservation | Partial | UTF-8, UTF-16, and verified listed legacy code pages are supported; broader Windows mappings remain unavailable. |
| Comparison options and filters | Partial | Current text options, line filters, substitutions, persistence, and JSON settings transfer are available; full WinMerge option parity is pending. |
| Intra-line differences | Partial | Highlighting and current-line selection exist; full word-diff/detail-pane parity is pending. |
| Moved-block detection | Unavailable | Continue using WinMerge when moved-source and moved-destination ranges are required. |
| Location Pane | Partial | Two-pane difference map and navigation exist; moved connectors, persistence, and remaining interaction parity are pending. |
| Finder Open With | Adapted | Finder document events replace Windows shell registration. Direct pane drops and Services are pending. |
| Menus, toolbar, and shortcuts | Partial | Primary text commands exist; customization, overflow, and complete command parity are pending. |
| Settings | Partial | Native comparison settings persist and support JSON import/export/reset; broader pages are pending. |
| Multiple windows, tabs, and session restoration | Unavailable | Use one active comparison and reopen pairs manually. |
| Three-way and conflict comparison | Unavailable | Continue using WinMerge. |
| Folder comparison and synchronization | Unavailable | Continue using WinMerge. |
| Table comparison | Unavailable | Continue using WinMerge. |
| Binary/hex comparison | Unavailable | Continue using WinMerge. |
| Image comparison | Unavailable | Continue using WinMerge. |
| Webpage comparison | Unavailable | Continue using WinMerge. |
| Projects and recent pair history | Unavailable | Pass paths again or use Finder; WinMerge project files are not imported. |
| Reports, patches, and archives | Unavailable | Continue using WinMerge or another dedicated tool. |
| Plugins, prediffers, unpackers, and scripts | Unavailable | No compatible extension host exists yet. |
| Windows Explorer and Jump List integration | Adapted | Use Finder Open With and native macOS file workflows; complete recents and Services integration is pending. |
| Signed, notarized, sandboxed distribution | Unavailable | Current package script creates a local ad-hoc app; release engineering remains pending. |

See the [Windows-to-Mac UI Parity Ledger](../todo.md#windows-to-mac-ui-parity-ledger) for command-level status and completion evidence requirements.

## Rollback

MacMerge does not modify WinMerge installation or settings. To roll back, quit MacMerge, restore any files from backups or retained recovery copies, and resume the comparison in WinMerge. Keep generated MacMerge settings separate; no reverse settings conversion is required.
