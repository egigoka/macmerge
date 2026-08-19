#!/bin/bash

set -euo pipefail

package_root=$(cd "$(dirname "$0")/.." && pwd)
cd "$package_root"

# Existing sources in this list predate swift-format. Remove entries as they are migrated.
legacy_exclusions=(
    Benchmarks/MacMergeBenchmark/main.swift
    Scripts/generate-icon.swift
    Sources/MacMerge/MacMergeApp.swift
    Sources/MacMergeCore/ArchiveSupport.swift
    Sources/MacMergeCore/BinaryFileDocument.swift
    Sources/MacMergeCore/ComparisonHistory.swift
    Sources/MacMergeCore/ComparisonProject.swift
    Sources/MacMergeCore/DirectoryResults.swift
    Sources/MacMergeCore/FolderFileOperations.swift
    Sources/MacMergeCore/FolderScanner.swift
    Sources/MacMergeCore/LineDiff.swift
    Sources/MacMergeCore/TextFileCodec.swift
    Sources/MacMergeCore/TextFileDocument.swift
    Tests/MacMergeAppTests/ComparisonGenerationStateTests.swift
    Tests/MacMergeAppTests/ComparisonModelTests.swift
    Tests/MacMergeAppTests/IntralineUnicodeTests.swift
    Tests/MacMergeAppTests/StaleComparisonPublicationTests.swift
    Tests/MacMergeCoreTests/AdversarialDiffShapeTests.swift
    Tests/MacMergeCoreTests/AlgorithmFallbackContractTests.swift
    Tests/MacMergeCoreTests/ComparisonIsolationTests.swift
    Tests/MacMergeCoreTests/DetachedComparisonMetadataTests.swift
    Tests/MacMergeCoreTests/DirectionalSymmetryTests.swift
    Tests/MacMergeCoreTests/EncodingRecoveryTests.swift
    Tests/MacMergeCoreTests/FolderComparatorTests.swift
    Tests/MacMergeCoreTests/FolderScannerTests.swift
    Tests/MacMergeCoreTests/IndentHeuristicParityTests.swift
    Tests/MacMergeCoreTests/LineDiffTests.swift
    Tests/MacMergeCoreTests/MergeInvariantTests.swift
    Tests/MacMergeCoreTests/MovedEditedParityTests.swift
    Tests/MacMergeCoreTests/RandomizedDiffPropertyTests.swift
    Tests/MacMergeCoreTests/RegexSafetyTests.swift
    Tests/MacMergeCoreTests/TextFileCodecTests.swift
    Tests/MacMergeCoreTests/TextFileDocumentTests.swift
    Tests/MacMergeCoreTests/TextRecoveryVerificationTests.swift
    Tests/MacMergeCoreTests/UndoRedoRecompareInvariantTests.swift
    Tests/MacMergeCoreTests/Windows1253RecoveryTests.swift
    Tests/MacMergeCoreTests/XDiffSourceManifestTests.swift
)

formatted_files=()
while IFS= read -r file; do
    for excluded_file in "${legacy_exclusions[@]}"; do
        if [[ $file == "$excluded_file" ]]; then
            continue 2
        fi
    done
    formatted_files+=("$file")
done < <(git ls-files --cached -- '*.swift')

if [[ ${#formatted_files[@]} -eq 0 ]]; then
    echo "No Swift files selected for formatting; check legacy exclusions" >&2
    exit 1
fi

xcrun swift-format lint --strict --configuration .swift-format "${formatted_files[@]}"
