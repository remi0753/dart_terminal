# Terminal inspector and local diagnostics reference

Dart Terminal provides a local, read-only inspector for the currently focused
live pane and an explicitly requested JSON diagnostics export. It is intended
for investigating parser, renderer, configuration, hierarchy, and native
feature state without copying terminal contents.

## Open and export

- Choose **View > Open Terminal Inspector** or press Option-Command-I.
- Choose **File > Export Diagnostics…** or press Option-Command-E.
- Both commands are also searchable in the Command Palette and may be used as
  stable keybind actions: `view.open-terminal-inspector` and
  `file.export-diagnostics`.
- The actions are available only when a live pane is focused. Escape closes the
  inspector and returns keyboard focus to the current live terminal.

The application owns at most one inspector window. While it is open, parser
capture follows the focused pane. Moving focus clears the previous pane's
retained records before starting an empty capture for the new pane. Closing the
window, closing the pane, or terminating the application disables capture and
clears retained records.

## Local crash report and hang sample

Two additional File actions create sensitive raw artifacts only after explicit
local consent:

- **File > Export Latest Crash Report…** (`file.export-latest-crash-report`)
  opens a Save panel with a raw-data warning. Only after the user chooses
  **Save and Continue** does Dart Terminal scan the non-recursive standard
  Apple DiagnosticReports directory for an exact product `.ips` report and
  copy the latest match to the selected `.ips` file.
- **File > Capture Hang Sample…** (`file.capture-hang-sample`) shows the same
  class of warning before invoking `/usr/bin/sample` directly, without a
  shell, for the current Dart Terminal PID, one second, and one interval. The
  validated result is published only as the selected `.sample.txt` file.

Both actions are searchable in the Command Palette and may be assigned to a
keybind. Neither has a default keyboard shortcut. Cancelling the Save panel
causes no report-directory access, process sampling, or file write. The one
read-only **Local Incident Diagnostics** window reports only fixed status,
matching-report count, completed-save count, and failure count. Escape or
window close cancels an active operation and restores terminal focus.

## Privacy boundary

The inspector and exported version-1 report contain only reviewed enums,
booleans, bounded counters, generations, dimensions, scale, resource counts,
safe installed-font PostScript names, and redacted parser metadata. Printable characters are counted but not copied.
OSC, DCS, APC, and related string payloads contribute only their byte length.
Recognized CSI/DCS headers may contain canonical numeric parameters and control
bytes needed to identify a protocol action.

The renderer's `font_diagnostics` object reports configured/applied/unavailable
variation and override counts, override matches/fallbacks, normal CoreText
fallbacks, missing glyphs, and at most 256 aggregate resolution records. Each
record contains only a resolution class, reviewed flags, an installed face's
PostScript name, and a count. It never includes shaped terminal text or the
configured Unicode scalar/range that selected a face.

The report never contains:

- terminal text, scrollback, shell history, commands, argv, or environment;
- current directories, file paths, titles, stable pane/session/process IDs, or
  timestamps;
- clipboard contents, notification text, AppleScript input, hyperlink targets,
  image bytes, or opaque protocol payloads;
- native/Dart exception messages, stack traces, or raw errors.

The chosen destination path exists only between the save panel and the atomic
writer. It is not retained in the report, UI status, logs, or machine-readable
acceptance output. Dart Terminal does not upload the report or contact a
support service.

An explicitly exported `.ips` or `.sample.txt` file is intentionally outside
this content-free boundary. It can contain stack traces, process and binary
details, usernames, file paths, and other sensitive local context. Dart
Terminal neither displays that raw content in the incident window nor adds it
to ordinary diagnostics, logs, terminal state, or PTY traffic. There is no
background scan, automatic attachment, upload, or remote symbolication.

## Format and limits

The export is deterministic, indented UTF-8 JSON with one trailing newline:

- `format`: `dart-terminal-diagnostics`
- `version`: `1`
- sections, in order: `privacy`, `limits`, `application`, `hierarchy`,
  `focused_pane`, `parser`, `renderer`, `configuration`, and `features`
- parser records: at most 256
- retained parser metadata: at most 64 KiB
- inspector rendering: at most 256 KiB
- complete export: at most 1 MiB

The file is written to an exclusive sibling temporary file, flushed, and then
renamed over the confirmed destination. Cancellation writes nothing. Encoding,
native panel, and filesystem failures are reported only as stable path-free
classifications; an incomplete temporary file is removed and an existing
destination is preserved until replacement succeeds.

The local per-launch metadata described in [Runtime diagnostics](../../README.md#runtime-diagnostics)
is a separate lifecycle record. Its `features` section gains only four reviewed
incident fields: fixed state, bounded matching-report count, completed-operation
count, and failure count. Raw report/sample data, report identity, paths, PID,
timestamps, symbols, and errors are never silently added to this export.

Release operators may generate a separate offline dSYM package whose exact
source/dSYM architecture and UUID sets and SHA-256 hashes are verified. It is
not bundled with the application or update, is never uploaded by the product,
and does not claim source-line coverage when only function symbols exist.

## Verification

`make terminal-diagnostics-privacy-check` freezes all 190 reviewed schema keys,
the 11 top-level entries, the fixed privacy declaration, and seven source-owner
boundaries. `make RUNTIME_ARCH=arm64 runtime-diagnostics-integration` launches
the ordinary Developer JIT and Release AOT applications and verifies live
capture, focus handoff, menu/Command Palette routing, atomic canonical exports,
redaction, consent-before-access, isolated raw crash/sample publication, zero
PTY writes, singleton ownership, and teardown.

`make RUNTIME_ARCH=arm64 runtime-configuration-integration` separately verifies
configured axis and override availability diagnostics across immutable old/new
pane catalogs in both modes. Optional inspector checks remain
in the [Phase 10 checklist](../phase10/terminal-inspector-diagnostics-manual-checklist.md);
incident UI checks are in the
[local incident checklist](../phase11/local-incident-manual-checklist.md).
