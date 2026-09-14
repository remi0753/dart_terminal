import 'dart:io';

import '../tool/terminal_diagnostics_privacy_audit.dart';

Future<void> runTerminalDiagnosticsPrivacyAuditTests() async {
  final Directory root = Directory.fromUri(Platform.script.resolve('../'));
  final TerminalDiagnosticsPrivacyAuditResult result =
      await runTerminalDiagnosticsPrivacyAudit(projectRoot: root);
  _expect(
    result.schemaKeyCount == 190 &&
        result.ownerCount == 10 &&
        result.topLevelKeyCount == 11,
    'privacy audit covers the frozen schema and every export owner',
  );

  final String diagnostics = File(
    '${root.path}/lib/src/terminal_diagnostics.dart',
  ).readAsStringSync();
  final String trace = File(
    '${root.path}/lib/src/terminal_core/vt_parser_trace.dart',
  ).readAsStringSync();
  final TerminalDiagnosticsSchemaKeyDifference expanded =
      compareDiagnosticsSchemaKeys(
        diagnostics.replaceFirst(
          "'features': snapshot.features.toJson(),",
          "'features': snapshot.features.toJson(), 'cwd': 'leak',",
        ),
        trace,
      );
  _expect(
    expanded.unexpected.length == 1 && expanded.unexpected.single == 'cwd',
    'privacy audit rejects an unreviewed schema field',
  );

  final TerminalDiagnosticsSchemaKeyDifference removed =
      compareDiagnosticsSchemaKeys(
        diagnostics.replaceFirst("'raw_errors': 'omitted',", ''),
        trace,
      );
  _expect(
    removed.missing.length == 1 && removed.missing.single == 'raw_errors',
    'privacy audit rejects removal of a fixed privacy declaration',
  );
}

Future<void> main() => runTerminalDiagnosticsPrivacyAuditTests();

void _expect(bool condition, String message) {
  if (!condition) throw StateError(message);
}
