# Safe Extension Design

Status: proposed design for Milestone 6. This document defines an implementation
boundary, not a promise that extensions are currently available.

## Decision

MacMerge extensions will be declarative packages containing an interpreted
WebAssembly module. MacMerge will execute each operation in a fresh, sandboxed
runner process through a narrow, versioned data protocol. The app will broker
all input and output as bytes, text, or a validated virtual file tree.

MacMerge will not load third-party code into its process. It will not execute
native bundles, dynamic libraries, shell commands, scripts, Apple events, or
extension-supplied XPC services. It will not expose host file paths or file
descriptors to extension code. Windows plugins must be rewritten against the
new data contract; binary or source compatibility with WinMerge COM and WSH
plugins is explicitly not a goal.

This design favors a smaller useful extension surface over reproducing every
Windows integration. An extension can transform content MacMerge already has;
it cannot become a general automation host.

## Security invariants

These requirements are release blockers:

1. No extension-controlled instruction executes in the MacMerge app process.
2. Only MacMerge-signed native code executes in the runner. Third-party code is
   interpreted WebAssembly with JIT disabled.
3. Extension code has no ambient filesystem, network, process, clipboard,
   Keychain, camera, microphone, location, or Apple-event access.
4. The runner receives content and bounded metadata, never security-scoped
   bookmarks, paths, file descriptors, environment variables, or app objects.
5. MacMerge validates every output before it reaches comparison state, editor
   state, or coordinated file-save code.
6. Every invocation has hard input, output, Wasm memory/stack, controlled native
   allocation, instruction, wall-clock, and log limits. A separate process
   footprint watchdog provides best-effort containment for system/runtime
   allocations that cannot be rejected before allocation. Cancellation
   terminates the runner.
7. Installing, inspecting, enabling, disabling, or discovering a package does
   not execute its module.
8. Signature trust and user approval do not weaken the sandbox. A trusted
   extension receives only its approved capabilities.
9. Extension failure never silently changes comparison semantics or writes a
   partially transformed file.
10. A document that was unpacked reversibly is pinned to the exact extension
    package digest needed to pack it again.

## Windows integration inventory

The replacement is grounded in the current WinMerge implementation rather
than only its menu labels.

### Extension types and contracts

WinMerge declares seven executable transformation events:
`BUFFER_PREDIFF`, `FILE_PREDIFF`, `EDITOR_SCRIPT`, `BUFFER_PACK_UNPACK`,
`FILE_PACK_UNPACK`, `FILE_FOLDER_PACK_UNPACK`, and `URL_PACK_UNPACK`
(`Src/Plugins.cpp:44-60`). Alias events compose unpacker, prediffer, and editor
pipelines (`Src/Plugins.h:175-181`).

Plugins expose Automation properties such as `PluginEvent`, description, file
filters, automatic selection, arguments, variables, unpacked extension, and
extended properties. Event-specific methods include buffer/file prediff,
buffer/file/folder unpack and pack, and `IsFolder`; editor scripts expose
arbitrary function names (`Src/Plugins.cpp:461-679`,
`Src/WinMergePluginBase.h:46-160`). Buffer APIs exchange mutable BSTR or
SAFEARRAY values, while file APIs exchange source and destination paths plus
changed/subcode values (`Src/Plugins.cpp:1345-1600`). An editor function maps
one BSTR to another (`Src/Plugins.cpp:1604-1639`).

Pipelines can contain multiple named stages, pane target flags, quoted
arguments, `%1` through `%9` variables, and recursive aliases. Alias expansion
uses a depth guard that rejects when its zero-based `stack` exceeds twenty
(`Src/FileTransform.cpp:86-303`). Automatic plugin selection uses filename
filters and per-plugin enablement
(`Src/Plugins.cpp:1058-1069`).

### Discovery and execution

WinMerge scans installation, AppData, and Documents `MergePlugins` directories
for `.sct`, `.wsc`, `.ocx`, and `.dll` candidates
(`Src/Plugins.cpp:740-797`). Candidates are instantiated to discover metadata,
then cached as COM `IDispatch` objects per thread
(`Src/Plugins.cpp:902-1012`). Current discovery has no source-visible package
signature or quarantine gate before loading a candidate.

WinMerge separately loads `Plugins.xml` from the installation, AppData, and
Documents `MergePlugins` locations. These files can be added, updated, removed,
and reloaded as user-authored command/script plugin definitions
(`Src/InternalPlugins.cpp:746-755,868-920,1045-1063`). The repository's
`Plugins/Plugins.xml` includes URL handlers and prettifiers that invoke `curl`,
`cmd`, `jq`, `yq`, and other programs (`Plugins/Plugins.xml:3-118`).
Internal command execution starts an inherited-handle child process and waits
indefinitely (`Src/InternalPlugins.cpp:603-655`). Native/script invocation is
synchronous and catches faults but does not impose a timeout
(`Src/Plugins.cpp:1223-1323`). Calls are serialized with a global mutex in the
unpack, prediff, and editor paths (`Src/FileTransform.cpp:475-506,586-619,
797-829,909-925`).

Some scriptlets also receive a host Automation object during
`PluginOnEvent`. For example, `PrediffLineFilter.sct` reads and writes WinMerge
options (`Plugins/dlls/PrediffLineFilter.sct:45-93`), while
`editor addin.sct` creates shell and filesystem Automation objects and exposes
commands ranging from case conversion to external filters
(`Plugins/dlls/editor addin.sct:40-139`). This is an ambient authority model,
not a capability boundary.

### Product behavior to preserve

Unpackers run before loading and can reverse their transformation during save
(`Src/DiffTextBuffer.cpp:205-221,520-535`). Prediffers produce comparison-only
content before the diff engine runs (`Src/DiffFileData.cpp:128-151`,
`Src/DiffWrapper.cpp:777-798`). Editor scripts transform selected text
(`Src/MergeEditView.cpp:3518-3549`). The same editor-script pipeline can
transform text while a difference is copied between panes
(`Src/MergeDoc.cpp:3088-3110`, `Src/MergeDocDiffCopy.cpp:482-517`).

These categories are not all reversible. WinMerge's generated
editor-to-unpacker adapter performs `UnpackFile` but deliberately reports
`PackFile` as unhandled, and save can fall back to transformed content
(`Src/InternalPlugins.cpp:231-288`, `Src/MergeDoc.cpp:860-891`).
`FILE_FOLDER_PACK_UNPACK` also has two distinct paths: normal unpacker pipelines
call `UnpackFile`/`PackFile` (`Src/FileTransform.cpp:366-435,488-506,599-610`),
whereas the archive adapter calls `IsFolder`/`UnpackFolder` and its
`CompressArchive` is unsupported
(`Src/Merge7zFormatMergePluginImpl.cpp:46-127`). Full-line copy transforms source
replacement text, while inline copy first assembles a destination span that can
retain untouched destination text and then transforms that span
(`Src/MergeDocDiffCopy.cpp:495-517,797-840`).

WinMerge exposes global enablement, manual/automatic unpacker and prediffer
modes, per-plugin enablement, filters, arguments, reload, and pipeline selection
(`Src/OptionsDef.h:325-331`, `Src/OptionsInit.cpp:239-244`,
`Src/PluginsListDlg.cpp:71-172`). MacMerge should preserve these user goals,
not their executable format or ambient access.

## Goals

- Support deterministic content unpacking, repacking, prediffing, selected-text
  editing, copy-time text transformation, and eventually archive virtual trees.
- Keep extension compromise outside the app process and outside user files.
- Work with MacMerge's App Sandbox and security-scoped bookmark model without
  passing those authorities to extensions.
- Make applied transformations visible, reproducible, cancellable, and pinned
  to an extension version.
- Permit independently authored extensions after package signing, explicit
  install, capability review, and approval.
- Keep the protocol small enough to fuzz and provide a conformance kit.
- Preserve original bytes and MacMerge's coordinated, conflict-detecting save
  path. Extensions return proposed bytes; they never save files themselves.

## Non-goals

- Running existing `.sct`, `.wsc`, `.ocx`, `.dll`, VBScript, JScript,
  PowerShell, AppleScript, JavaScriptCore, Python, or shell integrations.
- Exposing a general command runner or allowing an extension to invoke a tool
  already installed on the Mac.
- WinMerge COM ABI, registry, option-object, command-line pipeline, or settings
  compatibility.
- Extension-provided views, menus, dialogs, Swift/Objective-C classes, XPC
  interfaces, syntax highlighters, diff engines, or arbitrary UI.
- Network fetchers, URL scheme handlers, Office automation, AI services,
  clipboard automation, or source-control clients.
- Treating signatures, notarization, or publisher reputation as a substitute
  for process and capability isolation.

## Threat model

### Assets

- Original and edited document bytes, including unsaved work.
- Files and directories authorized through security-scoped bookmarks.
- Other files in the app container, preferences, crash diagnostics, and recent
  file metadata.
- User privacy, system integrity, app availability, and trustworthy comparison
  results.
- Signing keys, publisher approvals, installed package state, and pipeline
  configuration.

### Adversaries and entry points

- A deliberately malicious extension package.
- A benign extension with exploitable parser or transformation bugs.
- A package modified after signing or after installation.
- A malicious document crafted to trigger an automatic extension, exploit its
  parser, consume resources, or produce deceptive output.
- A compromised publisher key or trusted package update.
- A crafted package archive containing traversal paths, links, duplicate
  entries, decompression bombs, malformed manifests, or malformed WebAssembly.
- Confused-deputy attempts that ask MacMerge to read, overwrite, or disclose a
  path not selected by the user.
- Output bombs, archive path traversal, invalid Unicode, spoofed media types,
  stale results, crashes, hangs, and cancellation races.

### Assumptions and residual risk

MacMerge's own native code, bundled interpreter, runner protocol, App Sandbox,
and macOS process isolation are trusted. A vulnerability in those components
can cross the boundary. Content is intentionally disclosed to an enabled
extension action, so a transform can return altered or misleading content.
With no network, process, clipboard, or arbitrary filesystem access, direct
exfiltration channels are sharply limited but not mathematically eliminated
(for example, output shown to a user can encode input). UI therefore identifies
which action produced transformed content.

A publisher signature proves package continuity, not safety. A compromised
publisher can ship malicious WebAssembly, but the same capability and process
limits still apply. Denial of service is bounded rather than impossible.

## Architecture

```text
user-selected file
      |
      v
MacMerge app (security scope, coordinated I/O, policy, validation)
      |  typed request containing bounded content; no path or descriptor
      v
MacMergeExtensionRunner.xpc (fresh process, App Sandbox, no extra entitlements)
      |
      v
non-JIT WebAssembly interpreter -> bounded output stream
      |
      v
MacMerge validation -> compare/editor/atomic save
```

### App components

- `ExtensionInstaller` treats a package as untrusted data, validates its
  container, manifest, hashes, and signature, then atomically copies it into
  the app container.
- `ExtensionRegistry` discovers installed manifests without loading modules.
  It resolves duplicate IDs, trust, approvals, compatibility, enablement, and
  package digests into immutable action descriptors.
- `ExtensionPolicy` intersects manifest requests with MacMerge-supported
  capabilities, user grants, action context, and hard resource ceilings.
- `ExtensionCoordinator` snapshots the selected package digest, streams a
  request to the runner, observes cancellation, validates the response, and
  publishes only a still-current result.
- Existing document code retains security-scoped access, external-change
  checks, recovery copies, and coordinated save responsibility.

### Runner

`MacMergeExtensionRunner.xpc` is built, signed, and versioned with MacMerge. A
release runner's entitlement dictionary is exactly
`{"com.apple.security.app-sandbox": true}`. In particular it has no
`com.apple.security.inherit`, network, user-selected-file, bookmark, app-group,
automation, temporary-exception, JIT, debugger, or Keychain entitlement. Its
`XPCService` configuration has `JoinExistingSession` absent or `false`; no
extension-enabled release may add another entitlement or join the app's
security session. Debug runners with broader signing or entitlements cannot run
third-party packages.

The interface name and message allowlist are not peer authentication. Before
resuming/activating either `NSXPCConnection`, each side installs an exact
build-generated code-signing requirement with the public connection API. The
app requires the expected runner identifier, MacMerge Team ID, signing anchor,
and build-specific CDHash; the runner symmetrically requires those exact facts
for its containing MacMerge app build. macOS evaluates each requirement against
the peer identity carried by the connection's audit token; application code
does not claim direct access to the token. The CDHash binds the runtime peer to
the release artifact whose hardened-runtime state, nested-code seal, and exact
entitlement allowlist passed build verification. Both sides reject a mismatched,
ad-hoc, or re-signed peer on its first post-activation message, before that
message reaches exported application code. After activation, the only permitted
first message is a content-free handshake that binds a random request nonce and
expected app launch instance. No manifest/module/document frame is created or
sent until that handshake returns successfully; timeout, nonce mismatch, stale
connection, or forwarded/replayed handshake closes the connection. The app then
sends manifest facts and module bytes from the already validated package; the
runner does not open the package or document.

The runner validates the module again, rejects undeclared imports, configures
an interpreter with fixed linear-memory and stack limits, installs an
instruction-fuel counter, and invokes one action. It never enables JIT or the
hardened-runtime exceptions needed for writable executable memory. It exposes
only the generated MacMerge stream ABI, not WASI.

MacMerge ships a fixed set of runner XPC service slots with distinct service
identities. A slot accepts exactly one authenticated connection and one request,
rejects a second request, and terminates itself after the reply handshake. The
runner sends one terminal reply, then waits for a `reply-received`
acknowledgement carrying the request ID and terminal digest. The coordinator
sends that acknowledgement only after receiving the complete terminal frame;
only then may the runner call native process exit. A native watchdog exits the
runner if the acknowledgement or any earlier transition misses its deadline,
so asynchronous reply submission is never treated as proof of delivery.

The coordinator never reuses the slot until it observes the deliberate-exit XPC
interruption, then invalidates that connection and creates a new one; launchd
starts a new process for the next request. Admission and single-request gates
are enforced in both coordinator and runner state machines so concurrent XPC
connections cannot share a process. XPC interruption, runner crash, memory
termination, malformed reply, missing acknowledgement, or early exit is an
ordinary failed invocation to the app. No runner-local module memory survives
between operations; only explicitly approved host-held preferences and pinned
document round-trip state persist.

This XPC boundary is preferred over an extension-provided executable. It gives
MacMerge one auditable native runner implementation and prevents package
signatures from authorizing native code. If process-per-request termination,
exclusive slot admission, and relaunch can not be proven with public APIs and
stress tests, third-party rollout is blocked; reusing a long-lived process after
untrusted execution is not an acceptable shortcut.

### WebAssembly profile

Version 1 accepts a documented subset of WebAssembly core instructions through
one pinned interpreter version. Threads, shared memory, SIMD, reference types,
exceptions, tail calls, dynamic linking, component downloads, and JIT are
rejected unless later reviewed and versioned. Modules cannot import WASI,
clocks, randomness, sockets, filesystem calls, process calls, environment
variables, or host logging APIs that accept arbitrary binary data.

Allowed imports are generated from the protocol specification and limited to:

- reading request metadata and typed parameters;
- pulling bounded chunks from declared input streams;
- pushing bounded chunks to one declared output stream;
- emitting virtual-tree entries for archive actions;
- reading declared namespaced preference values; and
- cooperative cancellation checks.

An unknown import, export, feature, capability, or ABI version rejects the
module before invocation.

## Package format and discovery

An extension is a ZIP container named `Name.macmergeext`. Installation never
executes it. Version 1 permits these entries only:

```text
manifest.json
module.wasm
signature.json
LICENSE.txt       optional
README.md         optional, plain text/Markdown shown as untrusted text
```

Package validation rejects absolute paths, `..`, empty components, NULs,
backslashes as separators, Unicode-normalization collisions, case-folding
collisions, duplicate entries, sparse files, devices, FIFOs, sockets, hard
links, symbolic links, nested archives, encrypted entries, unknown top-level
entries, and data beyond package limits. Validation streams compressed data and
enforces both compressed and expanded limits before extraction.

`manifest.json` is UTF-8 JSON with duplicate keys rejected, a maximum depth,
maximum string sizes, and a strict schema. Required fields include:

```json
{
  "schemaVersion": 1,
  "id": "org.example.normalize-json",
  "version": "1.2.0",
  "minimumMacMergeVersion": "0.1.0",
  "publisherKeyID": "sha256:...",
  "module": "module.wasm",
  "actions": [
    {
      "id": "normalize",
      "kind": "prediff",
      "operations": ["prediff"],
      "name": "Normalize JSON",
      "automaticEligible": true,
      "inputs": {
        "prediff": {
          "streams": [{"role": "source", "contentTypes": ["public.json"]}],
          "paneMode": "one"
        }
      },
      "outputs": {
        "prediff": {"contentTypes": ["public.json"], "presentation": "text"}
      },
      "capabilities": ["content.bytes", "output.bytes"],
      "parameters": []
    }
  ]
}
```

IDs use reverse-DNS ASCII syntax. Action IDs are stable within a package ID.
Names and descriptions are display text, never localization keys or format
strings. Content matching uses declared Uniform Type Identifiers and lowercase
extensions. Version 1 does not accept extension-supplied regular expressions.
Magic-byte rules, if added, will be fixed offset/mask comparisons evaluated by
MacMerge, not executable matchers.

Action kinds and operations are closed enums. Reversible unpackers must declare
both `unpack` and `pack` and `roundTrip: "lossless"`. An unpack-only action may
declare only `unpack`, but is comparison-only: its output can enter neither
editable nor normal save state. The UI may offer explicit export of transformed
content to a new user-selected file with a format warning. Archive actions must
declare both archive operations and the same round-trip claim when they
participate in save. Comparison-only archive unpack may declare only
`archive-unpack` because its tree can never enter editable/save state.
Installation statically validates the required exports. Per-operation input
contracts sign the exact stream count, roles, content types, and single-pane or
multi-pane mode. Per-operation output contracts sign content types, extension
hints, and presentation (`text`, `binary`, `image`, or `tree`). They constrain
terminal responses and replace WinMerge's unpacked-extension and
preferred-window metadata. Input or output outside those declarations is a
protocol violation.

Declarations do not prove that bytes have the claimed type. Before dispatching
an output to a text, image, archive, or other format parser, MacMerge runs its
own bounded structural validator for that declared type. UTF-8 text must decode
strictly; virtual trees use the validation below; image/archive formats require
host-owned validators that establish the minimum safe structure needed by the
consumer. A type with no such validator remains opaque `binary` regardless of
the extension's media type, UTI, extension hint, or presentation claim.

Manifest display text rejects control characters, line/paragraph separators,
unpaired scalars, and bidi controls. UI places extension text in bidi-isolated,
non-formatting labels and renders trust/capability labels from fixed MacMerge
strings, never package text.

MacMerge discovers only:

- packages bundled in its signed application resources; and
- packages atomically installed below its container's Application Support
  directory through **Install Extension...**.

It does not scan Downloads, Documents, sibling app directories, `PATH`, or
other conventional plugin folders. Opening a `.macmergeext` routes through the
same installer and review UI. Installed package directories are immutable to
MacMerge during use: the registry records every file hash, opens by package
digest, and revalidates before dispatch. A changed package is quarantined, not
silently re-trusted.

Only one installed version is active for new documents. Open documents retain
their pinned version and digest while it remains installed. Upgrade and removal
are atomic registry changes; running jobs retain their snapshot.

### Manifest inspection limits

- Package: 16 MiB compressed, 32 MiB expanded.
- Manifest: 256 KiB, depth 16, 256 actions, 128 parameters per action.
- Module: 16 MiB.
- Display strings: 4 KiB each; IDs and version fields: 256 bytes each.

Limits are hard app constants. A manifest cannot request larger package limits.

## Signing and trust

The package signature is Ed25519 over a domain-separated canonical package
digest. The digest covers canonical manifest bytes and the sorted path, length,
and SHA-256 hash of every permitted payload entry. `signature.json` contains
the algorithm, publisher key ID, digest, and signature; it is not included in
its own digest. Canonicalization and test vectors are part of the SDK.

Trust tiers are:

- **Bundled:** package digest ships inside the Developer ID-signed and
  notarized MacMerge app. Bundled does not bypass runtime isolation.
- **Trusted publisher:** publisher public key is shipped in MacMerge's signed
  trust store or explicitly imported by the user after fingerprint review.
  Installation still requires an action and capability review.
- **Local development:** unsigned packages require a separately enabled
  developer mode and explicit approval of each exact package digest. They are
  marked prominently, cannot run automatically, and lose approval after any
  byte changes. Release builds may omit developer mode.
- **Untrusted/revoked/invalid:** package can be inspected or removed but cannot
  be enabled or invoked.

MacMerge has no runner network capability and does not require online trust
checks. Publisher additions and revocations arrive in signed MacMerge updates;
advanced users can import or revoke a local key. A future gallery may download
packages in the app process only after a separate network/privacy design. It
must not change runner capabilities.

Approval binds publisher key, package ID, major version, action ID and kind,
declared operations and round-trip claim, exact capability set, each operation's
stream count, stream roles, pane mode and input match rules, each operation's
output declarations, and automatic eligibility. A new signing key, major
version, new action, capability increase, input arity or pane-role change,
multi-input enablement, broadened match rule, changed output declaration, newly
automatic-eligible action, or new round-trip claim requires review. Patch/minor
updates signed by the same key can retain approval only when none of those facts
broaden. The UI still shows the new version and changelog.

Trust state stores the highest approved version and any revoked package
digests. Installing or activating a lower version requires explicit rollback
review even when its publisher and capabilities match. A revoked digest can not
regain approval through reinstall, cache restore, or version rollback.

Gatekeeper and notarization cover MacMerge and its native runner, not the
safety of WebAssembly data packages. Documentation and UI must not call a
publisher-signed package "safe" or "notarized."

## Capabilities and permissions

Capabilities describe data exchanged with one action. They do not unlock
system APIs. Version 1 supports:

| Capability | Data made available | Typical actions |
| --- | --- | --- |
| `content.bytes` | One or more bounded byte input streams | unpack, pack, byte prediff |
| `content.text` | UTF-8 text plus selection/line metadata | text prediff, editor, copy |
| `content.tree` | Validated virtual entries and byte streams | archive pack |
| `output.bytes` | One bounded byte output stream | unpack, pack, prediff |
| `output.text` | One valid UTF-8 text output stream | text prediff, editor, copy |
| `output.tree` | Validated virtual entries and streams | archive unpack |
| `document.names` | Basenames and extensions only, never parent paths | format-sensitive transforms |
| `context.invocation-time` | One immutable host-formatted instant, locale, and time zone | manual time-insertion editor actions |
| `preferences.read` | Values declared by a typed preference schema | configurable transforms |
| `preferences.write` | Previewed proposed writes to its action namespace | explicit manual actions only |

Action kind constrains valid combinations. For example, `editor` requires
`content.text` and `output.text`; `archive-unpack` requires `content.bytes` and
`output.tree`. MacMerge rejects a redundant or nonsensical capability set.

Extension preferences are booleans, bounded numbers, enums, or bounded strings
declared in the manifest. MacMerge renders settings and stores values under the
publisher key, package ID, and action ID; one action cannot read another
action's namespace. Each action has a hard aggregate quota of 128 keys and
64 KiB encoded values, and each package has a 512 KiB aggregate quota across
actions and installed versions. Schema updates delete undeclared stale values
before quota accounting. A package signed by a different key starts with an
empty namespace unless the user explicitly previews and approves a typed
preference migration.

The runner receives its action snapshot with a revision and can return at most
64 schema-valid proposed mutations totaling 64 KiB in a `success` response.
Every mutation is shown in a host-rendered preview before commit; this remains
required even if a prior invocation proposed the same value. MacMerge queues
mutations for all stages and commits them only if the full manual pipeline
succeeds, its result is still current, the user accepts the preview, preference
revisions still match, and action/package quotas remain satisfied. Failure,
cancellation, stale output, preview rejection, or conflict commits none. There
is no extension-provided settings dialog or direct defaults access.

The following capabilities do not exist: arbitrary file read/write, directory
enumeration, full paths, bookmarks, file descriptors, network, DNS, local
sockets, process execution, environment, clipboard, pasteboard, accessibility,
Apple events, Keychain, notifications, camera, microphone, location, dynamic
code, native libraries, or extension UI. Adding one requires a new threat-model
review and protocol version, not a hidden manifest string.

Non-bundled actions start disabled. Installation presents publisher, signature
state, actions, automatic eligibility, content types, requested capabilities,
and worst-case resource limits. Users approve capabilities per package action.
Removing a grant disables pipelines that require it.

Automatic matching is separately granted per action and defaults off. Only
signed, non-development packages can be automatic. The host evaluates content
matching before sending bytes and records the chosen action in document state.

## Data contracts

The outer XPC interface uses a fixed `NSSecureCoding` class allowlist containing
small metadata objects and `Data` chunks. `NSXPCConnection` decodes an allowed
object before receiver code can inspect its fields and exposes no public encoded
wire length, so receiver checks are not claimed as predecode memory controls.
Only the mutually authenticated native app and runner may send transport
objects. Each sender enforces, before encoding, at most 1 MiB of
schema-computable logical fields per object, 256 KiB per nonempty data chunk,
sixteen unacknowledged frames, and 2 MiB of logical in-flight data in each
direction. Foundation archive/wire overhead is not available before encoding
and is covered only by the footprint watchdog. Receiver checks after allowlisted
decode are defense in depth and reject any logical-limit mismatch, but their
allocation is part of the best-effort process-footprint guard rather than the
hard native quota.

Extension code cannot construct transport objects: its output import accepts at
most one valid chunk, and runner native code applies limits before creating XPC
data. Acknowledgement backpressure stops the sender at either in-flight limit.
No content frame is accepted before peer authentication completes. These
framing ceilings apply before action-specific stream limits. If unauthenticated
or extension-controlled peers ever become transport senders, version 1 must be
replaced by low-level bounded framing whose lengths are inspected before
Foundation unarchiving. The extension ABI is generated from one versioned
schema. Integer widths, UTF-8 handling, endianness, status values, and stream
closure rules are normative and covered by public test vectors.

Every request includes:

- protocol version and random request ID;
- package ID, version, package digest, action ID, and action kind;
- operation (`unpack`, `pack`, `prediff`, `edit`, `copy`, `archive-unpack`, or
  `archive-pack`);
- pane role, declared content type, byte length, text encoding context where
  applicable, and optional basename when approved;
- validated typed parameters and preference snapshot;
- when the separately approved `context.invocation-time` capability is present
  on a manual editor action, one host-produced immutable time context containing
  the UTC instant, BCP 47 locale, IANA time zone, preformatted date and time
  strings, and host formatting-specification version;
- per-request stream, output, fuel, memory, and deadline limits; and
- for `pack`, the original packed bytes and opaque round-trip token returned by
  `unpack`; or
- for `archive-pack`, the original archive bytes, edited virtual tree, and
  opaque round-trip token returned by `archive-unpack`.

The runner has no clock import. Time-dependent actions consume only the supplied
time context, so retries/replays of the same request see identical values. It
never includes a source or destination path, URL, bookmark, descriptor,
security-scoped token, environment value, process ID, app object, or unrestricted
locale-dependent dictionary.

Each input stream is immutable. Runner imports pull chunks by stream ID; they
cannot seek outside declared bounds. Output is append-only through a bounded
sink. MacMerge computes a digest while streaming and publishes nothing until
the runner closes the stream and returns a terminal response.

A terminal response is exactly one of:

- `not-handled`: valid only before output starts;
- `unchanged`: no output and no state change;
- `success`: output descriptor, length, digest, media type, sanitized warnings,
  optional bounded round-trip token, and bounded preference mutations;
- `cancelled`; or
- `failure`: stable error code and bounded, untrusted diagnostic text.

Mixed states, missing closure, extra streams, unknown fields, digest mismatch,
trailing protocol messages, output after cancellation, or success after the
deadline are protocol violations. Diagnostics are escaped and labeled with the
extension name; they are never interpreted as Markdown, paths, or commands.
Warnings and diagnostics reject controls, line/paragraph separators, and bidi
controls, have per-item and aggregate limits, and render bidi-isolated as plain
text.

### Byte and text transforms

A reversible unpack receives original bytes and returns comparison/editor bytes
plus an opaque round-trip token of at most 64 KiB. MacMerge stores a sealed
round-trip record containing the exact pre-stage input bytes, publisher key,
package ID/version/digest, action ID, signed operation contracts, protocol and
ABI versions, pane role, input/output content types, basename and encoding
context, typed parameters, preference snapshot and revision, optional immutable
time context, output digest, and token. Pack reuses that record exactly; current
settings, names, matching results, preferences, and defaults cannot replace any
pinned value. Pack receives the pre-stage input bytes and edited unpacked bytes
as separate immutable streams plus the token, then returns complete candidate
destination bytes. This permits preservation of container data omitted from the
editable representation without giving the extension a path.

If any pinned package or protocol implementation is unavailable, approval is
revoked, or retaining the complete record would exceed document/pipeline
storage limits, reversible editing is disabled before unpack and the action may
run only as a comparison transform. MacMerge performs encoding checks,
external-change detection, coordinated atomic replacement, rollback, and
recovery-copy handling. The runner never sees or writes the destination. An
unpack-only action follows the same comparison-only rule but produces no token
or save state.

Prediff returns comparison-only bytes or UTF-8 text. It cannot change the
loaded document or save representation. Each pane is transformed independently
unless the action explicitly declares a multi-input prediff contract; such an
action still receives only the selected pane streams and cannot write either.

Editor and copy transforms receive valid UTF-8 text. Editor requests include
the selected range relative to the supplied text, not the full document unless
the user selected all. A copy request identifies source, destination, and active
pane roles plus the destination replacement range. For full-line copy its sole
content stream is the complete source replacement text including the chosen
EOL. For inline copy, MacMerge first assembles the candidate destination span by
substituting selected source fragments into untouched destination text, then
sends that complete candidate as the sole content stream. The transform result
replaces exactly the declared destination range. Pipeline pane targeting uses
the captured active-pane role, matching WinMerge behavior. No other source or
destination document text is disclosed. The app applies a successful result as
one undoable copy/edit after checking all captured document revisions and
ranges. A stale result is discarded.

Parameters are typed values, not a command-line string. No interpolation such
as WinMerge `%1`, `${SRC_FILE}`, `${DST_FILE}`, or `${*}` exists.

### Virtual trees

Archive unpack returns a virtual tree, not a real destination directory. Each
entry has a normalized relative path, kind (`directory` or `regular-file`),
mode-free metadata, optional declared size, and a content stream for files.
MacMerge rejects absolute paths, empty path components, `.` or `..`, separator
confusion, NULs, controls, line/paragraph separators, bidi controls,
Unicode/case collisions, duplicate entries, hard links, symbolic links,
devices, FIFOs, sockets, resource forks, extended attributes, ACLs, setuid bits,
undeclared trailing data, and hierarchy conflicts. Every non-root ancestor of an
entry must itself appear exactly once as a canonical `directory`; a regular file
can never be an ancestor of another entry. Path UI visibly escapes nonprinting
scalars and renders each component in a bidi-isolated label.

Reversible archive unpack also returns an opaque token under the same 64 KiB
limit as byte unpack and retains the same complete pinned round-trip record,
including the original archive stream and archive-unpack context. Archive pack
receives that original archive byte stream, token, pinned context, and edited
virtual model, then returns one complete archive byte stream. Comparison-only
archive actions receive no pack operation or save path. No archive action
receives on-disk paths. Archive extraction to disk, if later offered, is a
separate app operation requiring a user-selected destination and MacMerge
performs every write after tree validation.

Version 1 tree limits are 10,000 entries, path depth 32, path length 1,024 UTF-8
bytes, single expanded file 128 MiB, total expanded data 512 MiB, and expansion
ratio 100:1. Hitting any limit fails the whole operation. Larger archives can be
compared outside MacMerge until a reviewed streaming design raises these
ceilings.

## Pipelines and automatic selection

MacMerge owns pipeline composition. A stage is a structured reference to
publisher key, package ID, exact package digest for active documents, action ID,
pane targets, and typed parameter values. Pipeline resolution fails on any
signer/package ambiguity. Extensions cannot define aliases that expand to other
extensions and cannot select or invoke another package.

Pipelines contain at most eight stages and execute serially. Each stage gets the
validated output of the prior stage and its own fresh runner process. For every
reversible stage, MacMerge retains the complete round-trip record above,
including that stage's exact pre-stage byte stream, not merely document-level
original bytes. Reverse packing runs the exact stages in reverse order, feeding
each stage its own retained pre-stage stream, edited output of the next stage,
token, and pinned context. Retention is charged to aggregate document and
pipeline storage limits before editable unpack begins. Prediff and unpack-only
pipelines are one-way and never enter save state. Editor and copy pipelines are
manual configuration and apply atomically: MacMerge commits only the final
validated output.

Eight stages is a MacMerge compatibility limit, not a WinMerge limit. WinMerge
aliases can expand to more stages. Settings, migration reports, and pipeline
import/validation must disclose the cap, report expanded stage count and names,
and reject rather than truncate an oversized pipeline.

Automatic selection occurs in the app from approved content types/extensions,
enabled state, user ordering, and action kind. Ambiguity never picks whichever
package was discovered first. MacMerge either applies an explicit user priority
or asks once and records the choice. Automatic actions never run merely because
a package was installed.

## Lifecycle and resource limits

Packages have no initialize, terminate, install hook, background task, timer,
daemon, persistent process, or host callback. Lifecycle is:

1. Inspect and install package as data.
2. Discover and validate manifest without module execution.
3. User enables an action and, separately, automatic use if eligible.
4. Coordinator snapshots package digest, policy, input revision, and limits.
5. Fresh runner revalidates and invokes one operation.
6. App validates terminal response and publishes it only if still current.
7. Runner exits and all module memory is discarded.

Default hard limits are:

| Resource | Editor/copy | Prediff | Unpack/pack | Archive operations |
| --- | ---: | ---: | ---: | ---: |
| Wall time | 2 s | 5 s | 15 s | 30 s |
| Input | 16 MiB | 64 MiB | unpack: one 128 MiB source; pack: one 128 MiB original plus one 128 MiB edited stream (256 MiB aggregate) | archive-unpack: one 128 MiB archive; archive-pack: one 128 MiB original archive plus one 512 MiB tree (640 MiB aggregate) |
| Output | 16 MiB | 64 MiB | unpack: 128 MiB; pack: 128 MiB | archive-unpack: 512 MiB tree; archive-pack: 128 MiB archive |
| Wasm linear memory | 64 MiB | 128 MiB | 128 MiB | 256 MiB |
| Wasm stack | 1 MiB | 1 MiB | 1 MiB | 1 MiB |
| Controlled native allocation | 64 MiB | 128 MiB | 128 MiB | 256 MiB |
| Diagnostic output | 64 KiB | 64 KiB | 64 KiB | 64 KiB |

All allocations controlled by the runner, including module decoding,
interpreter metadata, Wasm memory, stream buffers, tree entries, and output
bookkeeping, use checked quota allocators charged to the table's native or Wasm
limit. Overflow or quota exhaustion fails before those allocations. Foundation,
XPC, loader, and other system/runtime allocations cannot all be intercepted or
charged before allocation; they are bounded indirectly by authenticated sender
framing and the footprint watchdog and are not part of the hard memory claim.

A native watchdog separately samples physical footprint and terminates a slot
after it observes footprint above a release-calibrated baseline plus the
action's combined Wasm, stack, native, and transport quotas with a fixed 32 MiB
margin. Sampling can overshoot between observations; this is a kill-after-
overrun containment guard, not a hard whole-process ceiling. CI measures the
baseline, sampling interval, and worst observed overshoot for every supported
macOS/CPU pair and proves each malicious allocation fixture is terminated. The
guard does not use a virtual address-space limit, which is not meaningful for
modern macOS process mappings. Extensions remain disabled on a supported
environment where quota allocation or the footprint watchdog cannot be
verified.

Fuel values are calibrated per interpreter release and included in conformance
tests; wall time is not the only CPU bound. A module cannot request more fuel or
memory. MacMerge may lower limits based on remaining document or pipeline
budgets. Total intermediate pipeline bytes are capped at twice the final action
output limit, excluding separately charged pinned pre-stage streams. Across the
app, at most two runner slots and 768 MiB of combined declared runner request
quotas are active; each document gets at most one invocation. App-held extension
data uses at most 256 MiB of RAM. Larger permitted round-trip state and archive
trees use app-owned mode-0600 temporary files in a dedicated container spool
with a 1 GiB per-action quota, 2 GiB per-document quota, and 4 GiB app-wide
quota. Before work starts MacMerge reserves quota and checks available capacity;
it streams through files opened without link traversal, never maps the whole
spool into memory, and deletes partial/intermediate files on failure,
cancellation, process exit, document close, and next-launch orphan cleanup.
Archive operations fail before invocation when both RAM and spool quotas cannot
cover declared worst-case input, output, and intermediate bytes. Jobs queue
before any input copy when a budget is unavailable. Automatic work has lower
scheduler priority than direct user actions.

Cancellation stops input delivery immediately and starts a short grace period
for cooperative cancellation. The runner watchdog then terminates the process.
Late replies are ignored by request ID and document revision. A timeout is not
retryable automatically.

Three crashes, timeouts, memory exits, or protocol violations from one package
digest in a session quarantine that digest for the session. Persistent
quarantine requires user review on next launch; it is never cleared merely by
rediscovery. Content-level `failure` responses do not count as crashes unless
they violate protocol.

## Compatibility mapping

| WinMerge integration | MacMerge replacement | Compatibility notes |
| --- | --- | --- |
| `BUFFER_PACK_UNPACK` | Reversible byte `unpack`/`pack`, or comparison-only unpack-only action | Bytes and bounded round-trip context replace mutable SAFEARRAY and subcode. One-way WinMerge adapters map only to comparison/export, never normal save. |
| `FILE_PACK_UNPACK` | Same byte actions | Extension receives content, not source/destination paths. WinMerge implementations whose `PackFile` returns not handled map to unpack-only. |
| `FILE_FOLDER_PACK_UNPACK` in normal unpacker pipelines | Same byte actions using `UnpackFile`/`PackFile` semantics | WinMerge's normal pipeline treats this event as a file transform; no real folder is exposed. |
| `FILE_FOLDER_PACK_UNPACK` through archive adapter | Comparison-only `archive-unpack` virtual-tree action | WinMerge calls `IsFolder`/`UnpackFolder`; its adapter never calls `PackFolder`, and `CompressArchive` fails. MacMerge `archive-pack` is new behavior requiring an explicit lossless pair, not compatibility mapping. |
| `URL_PACK_UNPACK` | No version 1 replacement | HTTP, registry, clipboard, and custom URL handlers remain unsupported. User must materialize content outside MacMerge. |
| `BUFFER_PREDIFF` | Text or byte `prediff` action | Output is comparison-only and cannot mutate the document. |
| `FILE_PREDIFF` | Streaming byte `prediff` action | No temp path or direct filesystem access. |
| `EDITOR_SCRIPT` | Named manual `editor` actions | Functions become manifest actions with typed parameters. Clock-dependent scripts require separately approved deterministic host time context; other ambient APIs remain unavailable. |
| Editor script used while copying | Explicit `copy` action/pipeline | Full-line copy transforms complete source replacement text. Inline copy transforms the assembled destination span, including untouched destination text, with explicit source/destination/active-pane roles. Result is one undoable copy. Disabled by default. |
| `ALIAS_*` and textual pipelines | Host-owned structured pipelines | No recursive extension aliases, shell quoting, or `%1`/`${*}` expansion. MacMerge rejects expanded pipelines above eight stages and migration reports list the rejected stages. |
| `PluginFileFilters`/`PluginIsAutomatic` | Host-evaluated UTI/extension matching plus separate user grant | No extension regex in version 1; automatic disabled by default. |
| `PluginArguments` | Manifest-declared typed parameters | No command-line construction or interpolation. |
| `PluginVariables` and host object | Bounded request context and namespaced preferences | No path, registry/options object, arbitrary callback, or mutable app state. |
| `ShowSettingsDialog` | MacMerge-rendered preference schema | No extension UI. |
| `PluginOnEvent` | None | No initialization/termination callbacks or persistent state. |
| Generated editor/unpacker adapters | Package declares multiple explicit actions | No runtime code generation or action discovery by execution. |
| `.sct`/`.wsc` scriptlets and COM DLLs | Rewrite as `.macmergeext` WebAssembly | Existing binaries and scripts do not load. |
| Installation/AppData/Documents `Plugins.xml` integrations | Non-executable migration report, built-in feature, or WebAssembly rewrite | MacMerge may parse bounded XML as data only to list event, name, filters, arguments, pipeline, commands/scripts, and unsupported dependencies. It never imports executable logic or scans these files for runtime discovery. Shell commands and external executables do not run. |

Representative migrations should start with pure functions from
`editor addin.sct` (upper/lower case, sorting, trimming) and simple prediffers
such as leading-line-number removal. Command-backed prettifiers can be ported
only when their transformation library can be compiled into the accepted Wasm
profile and its license permits distribution. `ExecFilterCommand`, `curl` URL
handling, registry/clipboard handlers, Office COM automation, and networked AI
scripts cannot be represented and stay unsupported.
Bundled `insert datetime.sct` can be rewritten only as a manual action using the
approved immutable host time context; scripts that read clocks repeatedly or
depend on unrestricted locale/host state remain unsupported.

## User experience

### Installation and management

Settings contains an **Extensions** pane with package name, publisher,
signature/trust state, version, enabled actions, capabilities, content matches,
automatic state, resource ceilings, failure/quarantine state, and package
digest. Users can install, inspect README/license text, enable or disable each
action, reorder automatic matches, revoke grants, remove versions, and reveal
diagnostics. "Reload plugins" is unnecessary; installation and registry updates
are atomic.

Install review states plainly that an extension receives contents passed to its
enabled actions. It distinguishes manual use from automatic use and highlights
reversible save participation. Unsigned developer packages use persistent
warning styling and cannot be mistaken for trusted-publisher packages.

### Use in a comparison

Each pane shows an extension indicator when unpacked or prediffed. The detail
popover lists ordered stages, versions, package digests, automatic/manual
selection, duration, and warnings. Users can compare original bytes, retry a
manual action, disable the automatic action for this comparison, or choose a
different approved pipeline. MacMerge never changes modes silently after a
failure.

Manual editor actions appear under **Transform Selection** and show typed
parameter controls. The result is previewed for destructive or large changes;
acceptance creates one undo entry. Copy transforms are selected explicitly per
comparison, appear beside copy controls, and show a confirmation the first time
they are enabled because copied text will differ from source text.

When a reversible unpacker is active, save UI identifies the pack action and
pinned version. Removing, revoking, quarantining, or upgrading that exact
package does not silently substitute another version. If it is unavailable,
normal save is disabled; users can reinstall the pinned package, discard edits,
or save the transformed content to a new user-selected file with a clear format
warning.

Extension diagnostics omit document content, parent paths, and
extension-controlled diagnostic text by default. Exported diagnostics contain
MacMerge version, protocol version, extension ID, package digest, action,
resource outcome, stable error code, and durations. Including basenames,
extension-controlled text, or content samples requires a separate
user-selected content-bearing diagnostic export with a preview.

## Failure handling

- Invalid package, manifest, signature, trust, approval, ABI, or import:
  quarantine before invocation and show the exact validation class.
- No automatic match or ambiguous match: use no extension and explain the
  choice; never pick by scan order.
- `not-handled`: continue only when pipeline policy explicitly permits an
  optional stage. A required stage fails the pipeline.
- Content failure: preserve original/document state and show a bounded error.
  Do not automatically retry with different parameters or package version.
- Crash, timeout, cancellation, memory exit, or protocol violation: terminate
  runner, discard all partial output, record failure, and apply quarantine
  policy.
- Invalid bytes, UTF-8, media type, tree, output size, or digest: treat as a
  protocol violation and publish nothing.
- Prediff/unpack failure: do not silently compare raw content under transformed
  settings. Offer an explicit **Compare Original Content** fallback.
- Editor/copy failure or stale result: make no edit and create no undo entry.
- Multi-stage failure: discard every intermediate result and leave prior state
  unchanged.
- Pack failure: leave destination untouched, retain edited transformed content,
  and offer a recovery/save-transformed-copy workflow.
- External destination change during pack: discard candidate output or retain
  it only as an explicit recovery copy; existing save conflict behavior wins.
- Missing pinned version: never substitute a compatible version for save.
- Extension update failure: keep the prior validated version active and report
  update failure; never leave a partially extracted package.

Failures must remain visible in document state until resolved or the user
explicitly switches to original content. Comparison caches include package and
action digests so stale transformed results cannot be reused after settings,
approval, package, parameter, or content changes.

## Testing and verification

### Package and trust tests

- Golden canonicalization/signature vectors for every supported SDK language.
- Wrong key, changed byte, missing/extra entry, duplicate JSON key, unknown
  field, downgrade, revoked key, changed capabilities, and stale approval.
- ZIP traversal, absolute path, both separator styles, symlink/hardlink/device,
  duplicate/case/Unicode collision, encrypted data, nesting, truncation, CRC
  mismatch, and compression bomb fixtures.
- Fuzz package parsing, JSON/schema parsing, semantic versions, IDs, UTIs,
  parameter schemas, signature records, and registry conflict resolution.
- Verify inspection, enablement, settings rendering, and discovery never invoke
  module exports.

### Runner and protocol tests

- ABI conformance kit with valid minimal modules and every malformed request,
  response, stream transition, status, UTF-8 sequence, digest, and unknown
  field/import/export case.
- Malicious modules that loop, recurse, grow memory, exhaust fuel, trap, panic,
  emit output forever, close streams twice, reply after cancellation, spoof a
  request ID, and try all WASI/system imports.
- Assert each release runner entitlement dictionary equals exactly
  `{"com.apple.security.app-sandbox": true}`, `JoinExistingSession` is absent or
  false, and no inherit, bookmark, temporary-exception, network,
  user-selected-file, app-group, automation, JIT, debugger, or Keychain
  entitlement appears. Verify it cannot open known files outside its own
  sandbox or connect to local/network sockets.
- Test mutual connection code-signing requirements (evaluated by macOS against
  peer audit-token identity) with wrong Team ID, identifier, signing anchor,
  entitlements, hardened-runtime state, and re-signed binaries. Test stale and
  forwarded connections, wrong app-launch identity, bad nonce, and handshake
  timeout; assert no content frame is sent or admitted before success.
- Delay/drop terminal acknowledgements and prove runner waits after reply,
  exits after valid acknowledgement, and watchdog-exits without one.
- Assert module code never appears on a MacMerge app-process stack and one
  invocation cannot observe another invocation's memory, token, or undeclared
  process state; preferences are visible only through its declared snapshot.
- Kill runner at each protocol transition and verify app liveness, complete
  partial-output disposal, and deterministic error classification.
- Race cancellation, document edits, package update/removal, approval changes,
  window closure, app termination, and late replies.
- Benchmark fuel and wall limits on every supported macOS/CPU combination;
  limits fail closed if calibration is unavailable.

### Transformation tests

- Golden byte/text fixtures for unchanged, changed, non-handled, invalid,
  maximum-size, mixed-EOL, BOM, legacy-encoding, NUL, combining-mark, and large
  expansion cases.
- Property tests: unpack then pack without edits reproduces original bytes for
  every extension's signed `roundTrip: "lossless"` claim; edited round trips
  preserve documented container invariants.
- Prediff never changes source bytes or save state. Editor and copy output is
  one undoable operation and stale output never publishes.
- Pipelines preserve stage order, pane targeting, parameter typing, digest
  pinning, complete context pinning, each pre-stage original stream, reverse pack
  order, aggregate budgets, eight-stage rejection, and all-or-nothing behavior.
- One-way unpack fixtures remain comparison-only and expose only explicit
  transformed-copy export. Full-line and inline copy fixtures verify exact
  source/destination/active-pane roles and assembled replacement text.
- Output tests spoof every declared media type and prove host validation occurs
  before specialized parsing; unverifiable types remain opaque binary.
- Archive fuzz/property tests reject traversal, collisions, links, metadata
  tricks, file-as-ancestor conflicts, count/depth/size/ratio overflow, and
  malformed streams before writes. Quota tests cover spool reservation,
  free-space failure, cancellation cleanup, and next-launch orphan cleanup.
- Generate Windows-side golden outputs for representative pure WinMerge
  prediff/editor/unpacker fixtures, then verify rewritten reference Wasm actions
  match where parity is claimed. Differences must be documented per action.

### Product and release tests

- UI tests for install review, trust states, grants, automatic opt-in,
  management, pipeline selection, active-transform indicators, preview, undo,
  quarantine, missing pinned package, and every failure fallback.
- Save integration tests combine reversible packing with security-scoped URLs,
  coordinated I/O, external edits, symlinks, atomic replacement, rollback,
  recovery-copy retention, and cleanup failure injection.
- Build checks fail if the app links or calls extension-provided native code,
  enables JIT, adds forbidden runner entitlements, exposes path/descriptor
  fields, or allows a non-generated XPC class.
- Codesign/notarization checks verify app and runner identities, designated
  requirements, entitlements, nested-code sealing, and package resources.
- Crash and privacy review verifies MacMerge's own exported diagnostics remain
  local and redact content/path data by default. macOS may separately retain or
  transmit system crash reports according to the user's Analytics &
  Improvements settings; privacy documentation states this residual, and the
  runner places no content in process names, signposts, native error strings, or
  unified logs.

Security tests run under Address Sanitizer where supported and protocol/package
parsers receive continuous fuzzing. Third-party enablement does not ship until
runner escape, timeout, output validation, cancellation, and save failure suites
are mandatory CI gates.

## Rollout

1. **Protocol foundation:** publish manifest, signature, ABI, canonicalization,
   status/error, and resource-limit specifications plus test vectors. Implement
   parser/registry and malicious-package tests with invocation disabled.
2. **Bundled manual transforms:** ship the sandboxed runner behind a feature
   flag with MacMerge-signed case/trim and simple prediff reference packages.
   Validate isolation, diagnostics, cancellation, and editor undo behavior.
3. **Bundled reversible transforms:** add unpack/pack pinning and save-path
   integration. Require byte-round-trip, external-change, rollback, and recovery
   tests before enabling writes.
4. **Signed third-party manual actions:** expose package install, publisher-key
   trust, capability approval, quarantine, SDK, and conformance tooling.
   Automatic execution remains disabled.
5. **Automatic prediff/unpack:** enable only after explicit per-action opt-in,
   deterministic conflict resolution, visible document indicators, and
   performance budgets are proven.
6. **Archive virtual trees:** ship only after archive comparison exists and all
   traversal, expansion, streaming, and pack-save gates pass.

Each phase has a kill switch that disables new invocation while preserving the
ability to inspect/remove packages and recover unpacked edits. Protocol major
versions coexist only when each has a maintained, separately tested runner
adapter. Unsupported versions stay installed but disabled. Rollback never
converts a package into native/script execution.

No compatibility importer should translate WinMerge command strings or script
files automatically. A migration tool may inspect metadata and produce a
non-executable report listing likely action kinds, filters, and unsupported
dependencies; a developer must write, review, sign, and test the Wasm action.

## Explicitly unsupported behavior

Unless a later design revises the threat model, MacMerge will not support:

- loading any extension code in the app process;
- native third-party executables, dylibs, bundles, frameworks, COM/ActiveX,
  Rosetta-hosted Windows binaries, or extension-owned XPC services;
- shell commands, command templates, pipes, subprocesses, external tool lookup,
  shebang scripts, or arbitrary language runtimes;
- WSH scriptlets, VBScript, JScript, PowerShell, JavaScriptCore, Python,
  AppleScript, Shortcuts, Automator, or Apple-event automation;
- direct extension access to paths, files, directories, security-scoped
  bookmarks, file descriptors, environment variables, app preferences,
  Keychain, clipboard, other applications, or accessibility APIs;
- network, URL fetching/handling, registry URLs, clipboard URLs, AI service
  calls, update checks, telemetry, or local sockets from the runner;
- extension UI, settings dialogs, arbitrary menus, toolbar items, web views, or
  rendered HTML/Markdown controlled by an extension;
- initialization/termination hooks, background execution, daemons, timers,
  persistent processes, cross-invocation memory, or hidden document observers;
- extension-defined recursive aliases, executable discovery metadata, or
  command-line parameter interpolation;
- silent automatic enablement, silent fallback after transformation failure,
  silent package-version substitution during save, or bypass of output limits;
- archive links, devices, special files, ownership/ACL/xattr restoration, or
  extraction by extension code; and
- binary compatibility with existing WinMerge plugins or automatic conversion
  of their executable logic.

Users who require external commands or automation can run those tools outside
MacMerge and compare their materialized outputs. MacMerge should document that
workflow rather than weakening the extension boundary.

## Implementation acceptance criteria

The design is implemented only when all security invariants have executable
tests, app and runner entitlements are release-verified, reference extensions
pass conformance and round-trip suites, failures preserve original data, UI
shows every active transform, and the compatibility/unsupported tables are
reflected in migration documentation. Until then, the existing disabled plugin
menu remains preferable to a partial native or script host.
