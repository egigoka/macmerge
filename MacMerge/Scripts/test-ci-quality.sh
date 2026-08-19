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

package_job = jobs.fetch("test-and-package")
needs = Array(package_job.fetch("needs"))
abort "test-and-package must need quality" unless needs.include?("quality")
package_runs = package_job.fetch("steps").map { |step| step["run"] if step.is_a?(Hash) }.compact
abort "test-and-package must package the app" unless package_runs.include?("Scripts/package-app.sh")
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

echo "CI quality self-test passed"
