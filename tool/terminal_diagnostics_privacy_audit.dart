import 'dart:io';

final class TerminalDiagnosticsPrivacyAuditException implements Exception {
  const TerminalDiagnosticsPrivacyAuditException(this.message);

  final String message;

  @override
  String toString() => 'TerminalDiagnosticsPrivacyAuditException: $message';
}

final class TerminalDiagnosticsPrivacyAuditResult {
  const TerminalDiagnosticsPrivacyAuditResult({
    required this.schemaKeyCount,
    required this.ownerCount,
    required this.topLevelKeyCount,
  });

  final int schemaKeyCount;
  final int ownerCount;
  final int topLevelKeyCount;

  String machineLine() =>
      'TERMINAL_DIAGNOSTICS_PRIVACY_AUDIT_PASS '
      'schema_keys=$schemaKeyCount owners=$ownerCount '
      'top_level_keys=$topLevelKeyCount';
}

final class TerminalDiagnosticsSchemaKeyDifference {
  TerminalDiagnosticsSchemaKeyDifference({
    required Iterable<String> unexpected,
    required Iterable<String> missing,
  }) : unexpected = List<String>.unmodifiable(unexpected),
       missing = List<String>.unmodifiable(missing);

  final List<String> unexpected;
  final List<String> missing;

  bool get isEmpty => unexpected.isEmpty && missing.isEmpty;
}

TerminalDiagnosticsSchemaKeyDifference compareDiagnosticsSchemaKeys(
  String diagnosticsSource,
  String traceSource,
) {
  final String model = _between(
    diagnosticsSource,
    "import 'dart:convert';",
    'final class TerminalDiagnosticsExportResult',
    'diagnostics schema source',
  );
  final String trace = _between(
    traceSource,
    'Map<String, Object?> observationSnapshot(',
    'List<int> _canonicalHeaderBytes(',
    'redacted parser observation source',
  );
  final Set<String> actual = <String>{
    ..._schemaKeys(model),
    ..._schemaKeys(trace),
  };
  final List<String> unexpected =
      actual.difference(_expectedSchemaKeys).toList()..sort();
  final List<String> missing = _expectedSchemaKeys.difference(actual).toList()
    ..sort();
  return TerminalDiagnosticsSchemaKeyDifference(
    unexpected: unexpected,
    missing: missing,
  );
}

Future<TerminalDiagnosticsPrivacyAuditResult>
runTerminalDiagnosticsPrivacyAudit({Directory? projectRoot}) async {
  final Directory root = (projectRoot ?? Directory.current).absolute;
  final String diagnostics = _read(root, 'lib/src/terminal_diagnostics.dart');
  final String trace = _read(
    root,
    'lib/src/terminal_core/vt_parser_trace.dart',
  );
  final TerminalDiagnosticsSchemaKeyDifference schema =
      compareDiagnosticsSchemaKeys(diagnostics, trace);
  _expect(
    schema.isEmpty,
    'diagnostics schema changed; unexpected=${schema.unexpected.join(',')} '
    'missing=${schema.missing.join(',')}',
  );

  final String report = _between(
    diagnostics,
    'Map<String, Object?> _report(',
    'final class TerminalDiagnosticsExportResult',
    'top-level diagnostics report',
  );
  var cursor = 0;
  for (final String key in _expectedTopLevelKeys) {
    final int next = report.indexOf("'$key':", cursor);
    _expect(
      next >= cursor,
      'top-level diagnostics key is missing/out of order: $key',
    );
    cursor = next + key.length + 3;
  }
  _expect(
    report.contains("'printable_text': 'count_only'") &&
        report.contains("'string_payloads': 'length_only'") &&
        report.contains("'paths': 'omitted'") &&
        report.contains("'arguments': 'omitted'") &&
        report.contains("'environment': 'omitted'") &&
        report.contains("'clipboard': 'omitted'") &&
        report.contains("'timestamps': 'omitted'") &&
        report.contains("'stable_identifiers': 'omitted'") &&
        report.contains("'raw_errors': 'omitted'"),
    'fixed privacy declaration changed',
  );
  _expect(
    !report.contains('jsonEncode(snapshot)') &&
        !report.contains('snapshot.toJson()') &&
        report.contains('snapshot.application.toJson()') &&
        report.contains('snapshot.features.toJson()'),
    'report must serialize only the reviewed typed sections',
  );

  final String application = _read(root, 'lib/src/terminal_application.dart');
  final String applicationSnapshot = _between(
    application,
    'TerminalDiagnosticsSnapshot captureDiagnosticsSnapshot(',
    'TerminalDiagnosticsFocusTarget? activeDiagnosticsTarget()',
    'application diagnostics assembly',
  );
  _requireAll(applicationSnapshot, const <String>[
    'TerminalDiagnosticsApplicationSnapshot(',
    'TerminalDiagnosticsHierarchySnapshot(',
    'captureFocusedPaneDiagnostics(',
    'captureParserDiagnostics()',
    'TerminalDiagnosticsRendererSnapshot.fromLiveSurface(',
    'TerminalDiagnosticsConfigurationSnapshot(',
    'TerminalDiagnosticsFeaturesSnapshot(',
  ], 'application diagnostics assembly');
  _rejectAll(applicationSnapshot, const <String>[
    '.workingDirectory',
    '.contextDock',
    '.query',
    '.path',
    '.processId',
    '.failure',
    'Platform.environment',
    '.title',
    '.command',
    '.arguments',
  ], 'application diagnostics assembly');

  final String session = _read(root, 'lib/src/terminal_session.dart');
  final String sessionSnapshot = _between(
    session,
    'TerminalDiagnosticsFocusedPaneSnapshot captureFocusedPaneDiagnostics(',
    'bool projectColorScheme(',
    'session diagnostics assembly',
  );
  _requireAll(sessionSnapshot, const <String>[
    'TerminalDiagnosticsFocusedPaneSnapshot(',
    'TerminalDiagnosticsParserSnapshot.capture(',
    'inspector: parserInspector',
    'sink: terminalParserSink',
  ], 'session diagnostics assembly');
  _rejectAll(sessionSnapshot, const <String>[
    'processId',
    'failure',
    'workingDirectory',
    'environment',
    'metadata.title',
    'visibleText',
  ], 'session diagnostics assembly');

  final String presenter = _read(
    root,
    'lib/src/terminal_diagnostics_presenter.dart',
  );
  final String resultType = _between(
    presenter,
    'final class TerminalDiagnosticsPresentationExportResult',
    'typedef TerminalDiagnosticsPresentationExportObserver',
    'path-free presentation result',
  );
  _requireAll(resultType, const <String>[
    'TerminalDiagnosticsPresentationExportDisposition disposition',
    'final int byteCount',
  ], 'path-free presentation result');
  _rejectAll(resultType, const <String>[
    'path',
    'error',
    'StackTrace',
    'destination',
  ], 'path-free presentation result');
  final String exportFlow = _between(
    presenter,
    'Future<TerminalDiagnosticsPresentationExportResult> export()',
    'Future<void> dismiss()',
    'diagnostics export flow',
  );
  _requireOrdered(exportFlow, const <String>[
    '_formatter.encode(target.snapshot())',
    '_chooseSaveDestination(',
    'selection.path',
    '_writer.write(',
  ], 'diagnostics export flow');
  _rejectAll(exportFlow, const <String>[
    'stdout',
    'stderr',
    'toString()',
    'stackTrace',
    'onError',
  ], 'diagnostics export flow');
  final String renderFlow = _between(
    presenter,
    'void _render()',
    'void _handleWindowEvent(',
    'diagnostics presentation flow',
  );
  _requireAll(renderFlow, const <String>[
    '_formatter.formatInspector(target.snapshot())',
    'maximumInspectorTextUtf8Bytes',
  ], 'diagnostics presentation flow');
  _rejectAll(renderFlow, const <String>[
    'terminalScreenSet',
    'visibleText',
    'workingDirectory',
    'clipboard',
  ], 'diagnostics presentation flow');

  final String incident = _read(
    root,
    'lib/src/terminal_incident_controller.dart',
  );
  final String incidentStatus = _between(
    incident,
    'final class TerminalIncidentStatusSnapshot',
    'typedef TerminalIncidentStatusListener',
    'incident diagnostics status',
  );
  _requireAll(incidentStatus, const <String>[
    'TerminalIncidentStatus status',
    'final int matchingReportCount',
    'final int completedOperationCount',
    'final int unsuccessfulOperationCount',
  ], 'incident diagnostics status');
  _rejectAll(incidentStatus, const <String>[
    'path',
    'timestamp',
    'processId',
    'uuid',
    'error',
    'StackTrace',
    'bytes',
  ], 'incident diagnostics status');
  final String incidentConsent = _between(
    incident,
    'Future<TerminalIncidentOperationResult> _runWithConsent(',
    'void _render()',
    'incident consent flow',
  );
  _requireOrdered(incidentConsent, const <String>[
    '_chooseSaveDestination(configuration)',
    'selection.path',
    'await open()',
    'await operation(',
  ], 'incident consent flow');
  _rejectAll(incidentConsent, const <String>[
    'stdout',
    'stderr',
    'toString()',
    'stackTrace',
    'onError',
  ], 'incident consent flow');
  final String incidentRender = _between(
    incident,
    'void _render()',
    'void _handleWindowEvent(',
    'incident status presentation',
  );
  _requireAll(incidentRender, const <String>[
    'controller.snapshot',
    '_localization.incidentStatus(',
    'snapshot.matchingReportCount',
    'snapshot.completedOperationCount',
    'snapshot.unsuccessfulOperationCount',
  ], 'incident status presentation');
  _rejectAll(incidentRender, const <String>[
    'File(',
    'selection',
    'destination',
    'timestamp',
    'processId',
    'uuid',
    'StackTrace',
  ], 'incident status presentation');

  final String inspector = _read(
    root,
    'lib/src/terminal_core/vt_parser_inspector.dart',
  );
  _requireAll(inspector, const <String>[
    'if (!_captureEnabled) return;',
    '_onEvent = null;',
    '_events.clear();',
    '_printableScalarCount = 0;',
  ], 'parser capture lifecycle');
  _expect(
    inspector.indexOf('downstream.execute(controlByte);') <
        inspector.indexOf('if (!_captureEnabled) return;'),
    'disabled parser capture must forward before returning',
  );

  final String contextDockDirectory = _read(
    root,
    'lib/src/terminal_context_dock_directory.dart',
  );
  _requireAll(contextDockDirectory, const <String>[
    'int get activeOperationCount',
    'TerminalContextDockDirectoryStatus.privacyUnavailable',
    'retained?.cancel();',
    'window.cancelSearch();',
    'TerminalContextDockLimits.maximumResults',
  ], 'Context Dock filesystem lifecycle');
  _rejectAll(contextDockDirectory, const <String>[
    '.listSync(',
    '.statSync(',
    '.readAsStringSync(',
    'Process.run(',
    'runInShell: true',
  ], 'Context Dock filesystem lifecycle');

  final String fileSearch = _read(root, 'lib/src/terminal_file_search.dart');
  _requireAll(fileSearch, const <String>[
    'static const int maximumResults = 512;',
    'static const int maximumDirectories = 512;',
    'static const int maximumScannedEntries = 4096;',
    'static const int maximumRetainedPathUtf8Bytes = 1024 * 1024;',
    'static const Duration deadline = Duration(seconds: 3);',
    "Process.start('/usr/bin/mdfind'",
    'maximumSystemIndexOutputBytes',
    '_directoryOperation?.cancel();',
  ], 'Context Dock bounded search');
  _rejectAll(fileSearch, const <String>[
    '.listSync(',
    '.statSync(',
    'Process.run(',
    'runInShell: true',
    "Directory('/')",
  ], 'Context Dock bounded search');

  final String pathHandoff = _read(
    root,
    'lib/src/terminal_context_dock_path_handoff.dart',
  );
  _requireAll(pathHandoff, const <String>[
    'appendTrailingSeparator: false',
    'target.insertionBlock',
    '_pasteController.submit(',
    'process.disposition == TerminalPaneProcessDisposition.idleShell',
    'secureInput!.manualRequested',
  ], 'Context Dock explicit path handoff');
  _rejectAll(pathHandoff, const <String>[
    'Process.run(',
    'Process.start(',
    '.sendInput(',
    "'cd ",
    'workingDirectorySnapshot()',
  ], 'Context Dock explicit path handoff');

  return TerminalDiagnosticsPrivacyAuditResult(
    schemaKeyCount: _expectedSchemaKeys.length,
    ownerCount: 10,
    topLevelKeyCount: _expectedTopLevelKeys.length,
  );
}

Future<void> main(List<String> arguments) async {
  try {
    _expect(arguments.isEmpty, 'this audit takes no arguments');
    final TerminalDiagnosticsPrivacyAuditResult result =
        await runTerminalDiagnosticsPrivacyAudit();
    stdout.writeln(result.machineLine());
  } on Object catch (error) {
    stderr.writeln('TERMINAL_DIAGNOSTICS_PRIVACY_AUDIT_FAIL error=$error');
    exitCode = 1;
  }
}

Set<String> _schemaKeys(String source) =>
    RegExp(r"'([a-z][a-z0-9_]*)'\s*(?=:|\])")
        .allMatches(source)
        .map((RegExpMatch match) => match.group(1)!)
        .toSet();

String _between(String source, String start, String end, String owner) {
  final int startIndex = source.indexOf(start);
  final int endIndex = source.indexOf(end, startIndex + start.length);
  _expect(
    startIndex >= 0 && endIndex > startIndex,
    '$owner boundaries changed',
  );
  return source.substring(startIndex, endIndex);
}

String _read(Directory root, String relativePath) {
  final File file = File('${root.path}/$relativePath');
  _expect(file.existsSync(), 'required source is missing: $relativePath');
  return file.readAsStringSync();
}

void _requireAll(String source, Iterable<String> tokens, String owner) {
  for (final String token in tokens) {
    _expect(source.contains(token), '$owner is missing required token: $token');
  }
}

void _rejectAll(String source, Iterable<String> tokens, String owner) {
  for (final String token in tokens) {
    _expect(!source.contains(token), '$owner contains excluded token: $token');
  }
}

void _requireOrdered(String source, Iterable<String> tokens, String owner) {
  var cursor = 0;
  for (final String token in tokens) {
    final int next = source.indexOf(token, cursor);
    _expect(next >= cursor, '$owner is missing/out of order: $token');
    cursor = next + token.length;
  }
}

void _expect(bool condition, String message) {
  if (!condition) throw TerminalDiagnosticsPrivacyAuditException(message);
}

const List<String> _expectedTopLevelKeys = <String>[
  'format',
  'version',
  'privacy',
  'limits',
  'application',
  'hierarchy',
  'focused_pane',
  'parser',
  'renderer',
  'configuration',
  'features',
];

final Set<String> _expectedSchemaKeys =
    '''
accepted_clipboard_clears
accepted_clipboard_reads
accepted_clipboard_writes
accepted_frames
accepted_graphics_commands
accepted_hyperlinks
accepted_notifications
accepted_progress_updates
accepted_replies
accessibility_generation
active_screen
active_window_role
app_intents
appkit_event_protocol
apple_script
application
application_cursor_keys
application_escape
application_keypad
arguments
atlas_generation
attempt_generation
available
bracketed_paste
byte_hex
cancel
canonical_bytes_hex
canonical_prefix_hex
canonical_terminator_hex
capture_enabled
clipboard
color_scheme_reporting
columns
concurrent_paste_input_rejections
configuration
content_offset_x
content_offset_y
content_viewport_height
content_viewport_width
denied_clipboard_clears
denied_clipboard_reads
denied_clipboard_writes
diagnostic_errors
diagnostic_warnings
differentiate_without_color
direction
disposed
effective_generation
environment
event_counts
events
events_evicted
events_oversized
events_retained
events_total
features
final_byte_hex
focus_reporting
focused_pane
format
frame_builds
full_utf8_bytes
generations
grapheme_definitions
grapheme_scalars
hierarchy
hyperlink_definitions
hyperlink_refusals
in_band_size_reporting
incomplete
increase_contrast
inspection
inspector_text_bytes
intermediates_hex
keyboard_modes
kind
kitty_atlas_entries
kitty_atlas_evictions
kitty_evicted_bytes
kitty_evicted_placements
kitty_flags
kitty_images
kitty_placements
kitty_resource_evictions
kitty_stack_depth
kitty_tiles
language
last_damage_generation
last_frame_generation
last_model_revision
lifecycle
limit
limits
live_atlas_pins
live_options
live_panes
local_incident_completed_operations
local_incident_failures
local_incident_matching_reports
local_incident_state
malformed
metadata_bytes
modes
modify_other_keys
mouse_encoding
mouse_tracking
new_session_options
notifications
observer_failures
ordinal
osc52
output_bytes
panes
parameters
parser
parser_metadata_bytes
parser_records
paths
payload_redacted_bytes
pending_frames
pending_notification_requests
pending_osc52_requests
present
printable_scalars
printable_text
privacy
private_marker_hex
quick_window_shortcut
raw_errors
reduce_motion
rejected_clipboard_requests
rejected_graphics_commands
rejected_hyperlinks
rejected_replies
renderer
renderer_generation
reply_backpressure
reset
resources
retained_metadata_bytes
rows
runtime
scale_16_16
scheduled_work
schema_options
scrollback_rows
secure_input
semantics
stable_identifiers
state
string_kind
string_payloads
style_definitions
subparameters
synchronized_output
synchronized_output_held
synchronized_output_mode
synchronized_output_releases
synchronized_output_timeouts
tabs
timestamps
transition
transport
truncated
unsupported_controls
unsupported_sequences
version
viewport_height
viewport_offset
viewport_width
windows
write_backpressure
applied_variations
available_overrides
catalog_generation
configured_overrides
configured_variations
coretext_fallbacks
flags
font_diagnostics
missing_glyphs
occurrences
override_applied
override_fallbacks
override_matches
postscript_name
resolution_records
source
unavailable_overrides
unavailable_variations
'''
        .trim()
        .split('\n')
        .toSet();
