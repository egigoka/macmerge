# MacMerge Privacy

MacMerge compares files locally on the Mac. It does not include advertising, analytics, telemetry upload, user accounts, or network services.

## Files and settings

MacMerge reads and writes only files selected by the user, files opened through Finder, and explicit command-line paths allowed by macOS. Sandboxed packages use app-scoped security bookmarks so a previously approved file can be reloaded or saved later. Bookmark data remains in the app container and is not transmitted.

Comparison settings, toolbar and pane preferences, and security bookmarks are stored locally in macOS preferences. Compared file contents, paths, differences, and edits are not sent anywhere by MacMerge.

## Crash diagnostics

MacMerge subscribes to Apple's MetricKit diagnostic delivery. Apple-generated crash, hang, CPU-exception, disk-write-exception, and app-launch diagnostic payloads are saved only on the local Mac. MacMerge does not add compared file contents or file paths to those payloads and does not upload them.

At most 20 diagnostic JSON files are retained; older files are deleted automatically. Removing MacMerge's container deletes its preferences, bookmarks, and diagnostics. Users may inspect or delete diagnostics at any time in:

```text
~/Library/Containers/io.github.egigoka.MacMerge/Data/Library/Application Support/MacMerge/Diagnostics
```

Ad-hoc builds with a custom bundle identifier use that identifier's container instead.
Unsandboxed `swift run MacMerge` builds use `~/Library/Application Support/MacMerge/Diagnostics`.

## Data collection

MacMerge does not track users and does not collect data as defined for App Store privacy disclosure because no data leaves the device. Apple may separately collect system diagnostics according to macOS settings and Apple's privacy policy; MacMerge does not control that operating-system service.
