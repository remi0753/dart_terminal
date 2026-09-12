# Terminal inspector and diagnostics reference

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

## Privacy boundary

The inspector and exported version-1 report contain only reviewed enums,
booleans, bounded counters, generations, dimensions, scale, resource counts,
and redacted parser metadata. Printable characters are counted but not copied.
OSC, DCS, APC, and related string payloads contribute only their byte length.
Recognized CSI/DCS headers may contain canonical numeric parameters and control
bytes needed to identify a protocol action.

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
is a separate lifecycle record. Crash report discovery, hang sampling,
symbolication, consent, signing, and update diagnostics remain Phase 11 work and
are not silently added to this export.

## Verification

`make terminal-diagnostics-privacy-check` freezes all 168 reviewed schema keys,
the 11 top-level entries, the fixed privacy declaration, and six source-owner
boundaries. `make RUNTIME_ARCH=arm64 runtime-diagnostics-integration` launches
the ordinary Developer JIT and Release AOT applications and verifies live
capture, focus handoff, menu/Command Palette routing, atomic canonical exports,
redaction, and teardown. Optional visual checks are in the
[manual checklist](../phase10/terminal-inspector-diagnostics-manual-checklist.md).
