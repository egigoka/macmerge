# MacMerge Performance Benchmarks

Run deterministic sparse-edit comparisons in release mode:

```sh
swift run -c release MacMergeBenchmark
```

Default sizes are 10,000, 100,000, 250,000, and 1,000,000 lines per side. Output is CSV with elapsed comparison time, throughput, shallow `DiffRow` storage, and resident-memory growth. Every run also verifies row count, difference count, boundary line alignment, line-ending modes, filters, substitutions, and directional merge behavior.

Repeat runs or select sizes with:

```sh
swift run -c release MacMergeBenchmark --iterations 3 --lines 100000,1000000
```

Exercise all rows as differences with `--density dense`. Exercise the Location Pane's worst-case changed-run count with alternating changed and unchanged rows through `--density location-dense`. Packaged harnesses accept both modes through `FIXTURE_DENSITY`.

Exercise long lines by setting their minimum UTF-8 payload size:

```sh
swift run -c release MacMergeBenchmark --lines 10000 --line-bytes 4096
```

Exercise tab expansion and wide-Unicode display columns with `--content tabs` or `--content wide-unicode`. Packaged harnesses accept the same options through `FIXTURE_CONTENT` and `FIXTURE_LINE_BYTES`.

Generate the same file pairs for packaged-app scrolling and Instruments runs:

```sh
swift run -c release MacMergeBenchmark --lines 1000000 --fixture-directory /tmp/macmerge-benchmark
open -a ./dist/MacMerge.app --args /tmp/macmerge-benchmark/macmerge-1000000-left.txt /tmp/macmerge-benchmark/macmerge-1000000-right.txt
```

Use a release build, close unrelated memory-intensive applications, and record machine model, macOS version, Swift version, and iteration count with results. Resident-memory growth is process-wide and intended for regression comparison on the same runner, not as a cross-machine absolute value.

Run packaged-app load, first-visible-row, bottom-scroll, and resident-memory budgets with:

```sh
Scripts/run-performance-budgets.sh
```

Defaults exercise 1,000,000 rows per side and enforce 5,000 ms load, 5,000 ms comparison, 1,500 ms first render, 1,500 ms Location Pane render, 1,500 ms bottom scroll, and 900 MiB resident memory. Override any threshold with `LOAD_BUDGET_MS`, `COMPARISON_BUDGET_MS`, `FIRST_RENDER_BUDGET_MS`, `LOCATION_PANE_BUDGET_MS`, `SCROLL_BUDGET_MS`, or `RESIDENT_BUDGET_MIB`. The harness enables self-scroll only through `MACMERGE_PERFORMANCE_AUTOSCROLL`; normal launches are unchanged.

Every packaged budget run forces the Location Pane visible and rejects reports unless its current nonempty map rendered within budget, raw resident-memory sampling succeeded, fixture and budget inputs match, and machine/OS provenance is present. CI additionally gates a 250,000-line alternating changed/unchanged fixture with `FIXTURE_DENSITY=location-dense`, 125,000 Location Map runs, and a 450 MiB resident ceiling. Each retained budget JSON report has a matching `.sha256` sidecar.

Capture the same workflow with Instruments and `LoadPair`, `Comparison`, `FirstVisibleRow`, and `AutoScroll` signposts:

```sh
Scripts/run-performance-trace.sh
```

The trace harness requires a full Xcode installation with `xctrace`. It records for 20 seconds by default, exports the signpost table, and verifies completed `LoadPair`, `Comparison`, `FirstVisibleRow`, and `AutoScroll` intervals without applying non-instrumented performance budgets. Override `TRACE_PATH`, `TRACE_TEMPLATE`, `TRACE_TIME_LIMIT`, or `LINE_COUNT` as needed.
