#!/bin/bash

set -euo pipefail

package_root=$(cd "$(dirname "$0")/.." && pwd)
repository_root=$(cd "$package_root/.." && pwd)
workflow="$repository_root/.github/workflows/macmerge.yml"
temporary_root=$(mktemp -d "${TMPDIR:-/tmp}/macmerge-ci-quality.XXXXXX")
trap 'rm -rf "$temporary_root"' EXIT

fail() {
    echo "CI quality self-test failed: $*" >&2
    exit 1
}

ruby -ryaml - "$workflow" "$repository_root" <<'RUBY'
workflow = YAML.load_file(ARGV.fetch(0))
repository_root = ARGV.fetch(1)
abort "workflow root must be a mapping" unless workflow.is_a?(Hash)

triggers = workflow["on"] || workflow[true]
abort "workflow triggers are missing" unless triggers.is_a?(Hash)

required_paths = [
  "MacMerge/**",
  "Externals/xdiff/**",
  "Externals/poco/dependencies/pcre2/**",
  "Testing/GoogleTest/DiffWrapper/**",
  "Testing/Data/**",
  ".github/workflows/macmerge.yml",
]
native_dependencies = Dir.glob(File.join(repository_root, "MacMerge/Sources/CXDiff/**/*.{c,h}"))
  .flat_map { |path| File.read(path).scan(%r{#\s*include\s+"(?:\.\./)+(Externals/[^"]+)"}).flatten }
  .uniq
abort "no external native dependencies discovered" if native_dependencies.empty?

["push", "pull_request"].each do |event|
  paths = triggers.dig(event, "paths")
  abort "#{event} paths are missing: #{required_paths.join(", ")}" unless paths.is_a?(Array)
  missing = required_paths - paths
  abort "#{event} paths are missing: #{missing.join(", ")}" unless missing.empty?
  uncovered = native_dependencies.reject do |dependency|
    paths.any? do |pattern|
      pattern.end_with?("/**") && dependency.start_with?(pattern.delete_suffix("/**") + "/")
    end
  end
  abort "#{event} paths do not cover native dependencies: #{uncovered.join(", ")}" unless uncovered.empty?
end

jobs = workflow.fetch("jobs")
quality = jobs.fetch("quality")
quality_runs = quality.fetch("steps").map { |step| step["run"] if step.is_a?(Hash) }.compact
abort "quality job must run Scripts/test-ci-quality.sh" unless quality_runs.include?("Scripts/test-ci-quality.sh")
abort "quality job must run Scripts/analyze-native.sh" unless quality_runs.include?("Scripts/analyze-native.sh")
abort "quality job must run Scripts/check-extension-design.sh" unless quality_runs.include?("Scripts/check-extension-design.sh")
abort "quality job must run ShellCheck" unless quality_runs.include?("shellcheck Scripts/*.sh")
oracle_step = quality.fetch("steps").find do |step|
  step.is_a?(Hash) && step["name"] == "Check diff oracle coverage" && step["run"] == "Scripts/check-diff-oracle-coverage.sh"
end
abort "quality job must run Scripts/check-diff-oracle-coverage.sh as 'Check diff oracle coverage'" unless oracle_step
quality_checkout = quality.fetch("steps").find { |step| step.is_a?(Hash) && step["uses"].to_s.start_with?("actions/checkout@") }
abort "quality checkout must use fetch-depth 0 so the diff oracle gate can resolve its pinned commit" \
  unless quality_checkout && quality_checkout.dig("with", "fetch-depth") == 0

package_job = jobs.fetch("test-and-package")
needs = Array(package_job.fetch("needs"))
abort "test-and-package must need quality" unless needs.include?("quality")
package_runs = package_job.fetch("steps").map { |step| step["run"] if step.is_a?(Hash) }.compact
abort "test-and-package must package the app" unless package_runs.include?("Scripts/package-app.sh")
["undefined", "thread"].each do |sanitizer|
  job_name = "sanitize-#{sanitizer}"
  sanitizer_job = jobs[job_name]
  abort "#{job_name} job is missing" unless sanitizer_job.is_a?(Hash)
  abort "#{job_name} must need quality" unless Array(sanitizer_job["needs"]).include?("quality")
  abort "#{job_name} must not need test-and-package" if Array(sanitizer_job["needs"]).include?("test-and-package")
  abort "#{job_name} must set timeout-minutes" unless sanitizer_job["timeout-minutes"].is_a?(Integer)
  sanitizer_step = sanitizer_job.fetch("steps").find do |step|
    step.is_a?(Hash) && step["run"] == "Scripts/run-sanitizers.sh #{sanitizer}"
  end
  abort "#{job_name} must run Scripts/run-sanitizers.sh #{sanitizer}" unless sanitizer_step
  filter = sanitizer_step.dig("env", "SANITIZER_TEST_FILTER")
  abort "#{job_name} must set a focused SANITIZER_TEST_FILTER" unless filter.is_a?(String) && !filter.strip.empty?
  abort "#{job_name} filter must match MacMergeCoreTests\\.(...)/" unless filter.is_a?(String) && filter.start_with?("MacMergeCoreTests\\.(") && filter.end_with?(")/")
  if sanitizer == "thread"
    skip = sanitizer_step.dig("env", "SANITIZER_TEST_SKIP")
    abort "#{job_name} must skip the xctest re-launch tests with an anchored SANITIZER_TEST_SKIP" \
      unless skip.is_a?(String) && skip.start_with?("FolderScannerTests/(") && skip.end_with?(")$") &&
        ["testFollowPolicyStopsDirectoryCycleAndReportsIssue", "testFollowPolicyBoundsSymbolicLinkResolutionCycle"].all? { |name| skip.include?(name) }
  end
  abort "test-and-package must not run Scripts/run-sanitizers.sh #{sanitizer}" if package_runs.include?("Scripts/run-sanitizers.sh #{sanitizer}")
end
dense_step = package_job.fetch("steps").find do |step|
  step.is_a?(Hash) && step["name"] == "Enforce dense Location Pane packaged budget" && step["run"] == "Scripts/run-performance-budgets.sh"
end
abort "dense Location Pane packaged budget is missing" unless dense_step
dense_environment = dense_step.fetch("env")
abort "dense gate must use 250000 lines" unless dense_environment["LINE_COUNT"] == 250000
abort "dense gate must use Location Pane worst-case fixtures" unless dense_environment["FIXTURE_DENSITY"] == "location-dense"
abort "dense gate must keep the 450 MiB ceiling" unless dense_environment["RESIDENT_BUDGET_MIB"] == 450
abort "dense gate must retain its report" unless dense_environment["REPORT_PATH"].end_with?("/performance-dense-report.json")
upload_step = package_job.fetch("steps").find do |step|
  step.is_a?(Hash) && step["uses"] == "actions/upload-artifact@v4"
end
abort "artifact upload is missing" unless upload_step
uploaded_paths = upload_step.dig("with", "path").lines.map(&:strip)
abort "dense report artifact is missing" unless uploaded_paths.include?("MacMerge/dist/performance-dense-report.json")
abort "dense report hash artifact is missing" unless uploaded_paths.include?("MacMerge/dist/performance-dense-report.json.sha256")
RUBY

"$package_root/Scripts/check-format.sh"

format_root="$temporary_root/format"
mkdir -p "$format_root/Scripts" "$format_root/Sources"
cp "$package_root/.swift-format" "$format_root/.swift-format"
cp "$package_root/Scripts/check-format.sh" "$format_root/Scripts/check-format.sh"
printf 'struct CIQualityUnformattedFixture{let value:Int}\n' > "$format_root/Sources/CIQualityUnformattedFixture.swift"
git -C "$format_root" init --quiet
git -C "$format_root" add .swift-format Scripts/check-format.sh Sources/CIQualityUnformattedFixture.swift
if "$format_root/Scripts/check-format.sh" >"$temporary_root/format.log" 2>&1; then
    fail "formatter accepted unformatted non-legacy Swift fixture"
fi
if ! grep -q '\[Spacing\]' "$temporary_root/format.log"; then
    fail "formatter fixture failed without expected spacing diagnostic"
fi

"$package_root/Scripts/analyze-native.sh"

analyzer_fixture="$temporary_root/analyzer-warning.c"
printf 'int main(void) { int *pointer = 0; return *pointer; }\n' > "$analyzer_fixture"
if "$package_root/Scripts/analyze-native.sh" "$analyzer_fixture" >"$temporary_root/analyzer.log" 2>&1; then
    fail "analyzer accepted warning fixture"
fi
if ! grep -q 'Dereference of null pointer' "$temporary_root/analyzer.log"; then
    fail "analyzer fixture failed without expected warning"
fi

# The real coverage gate runs as its own workflow step; only its negative self-test lives here.
oracle_lock="$temporary_root/coverage.lock"
zero_fingerprint=0000000000000000000000000000000000000000000000000000000000000000
sed -E "s/^alignment-fingerprint [0-9a-f]{64}\$/alignment-fingerprint $zero_fingerprint/" \
    "$package_root/DiffOracle/coverage.lock" > "$oracle_lock"
if cmp -s "$package_root/DiffOracle/coverage.lock" "$oracle_lock"; then
    fail "diff oracle self-test could not rewrite the alignment fingerprint"
fi
if "$package_root/Scripts/check-diff-oracle-coverage.sh" --lock "$oracle_lock" >"$temporary_root/oracle.log" 2>&1; then
    fail "diff oracle gate accepted an unreviewed alignment change"
fi
if ! grep -qF "MacMerge alignment sources changed (fingerprint $zero_fingerprint ->" "$temporary_root/oracle.log"; then
    fail "diff oracle gate failed without expected alignment diagnostic"
fi

for unsupported_case in "address:runs as its own CI step" "memory:usage:" "fuzzer:usage:"; do
    unsupported_sanitizer=${unsupported_case%%:*}
    expected_diagnostic=${unsupported_case#*:}
    sanitizer_status=0
    "$package_root/Scripts/run-sanitizers.sh" "$unsupported_sanitizer" >"$temporary_root/sanitizer.log" 2>&1 \
        || sanitizer_status=$?
    if [[ $sanitizer_status -ne 64 ]]; then
        fail "sanitizer runner exited $sanitizer_status, not 64, for unsupported sanitizer $unsupported_sanitizer"
    fi
    if ! grep -qF "$expected_diagnostic" "$temporary_root/sanitizer.log"; then
        fail "sanitizer runner rejected $unsupported_sanitizer without expected diagnostic: $expected_diagnostic"
    fi
done

echo "CI quality self-test passed"
