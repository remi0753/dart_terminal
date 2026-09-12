import 'dart:io';

import '../tool/terminal_localization_audit.dart';

Future<void> runTerminalLocalizationAuditTests() async {
  final TerminalLocalizationAuditResult result =
      await runTerminalLocalizationAudit(
        projectRoot: Directory.fromUri(Platform.script.resolve('../')),
      );
  _expect(
    result.sourceCount == 12 &&
        result.resourceFamilies == 4 &&
        result.resourceKeys == 21,
    'localization audit covers every declared source and resource family',
  );

  _expect(
    findForbiddenLocalizationLiterals(
          "const title = 'Command Palette';",
          const <String>['Command Palette'],
        ).single ==
        'Command Palette',
    'static audit rejects a direct presenter literal',
  );
  _expect(
    findForbiddenLocalizationLiterals(
      '// Command Palette\nfinal title = localization.commandPaletteTitle;',
      const <String>['Command Palette'],
    ).isEmpty,
    'static audit ignores documentation and localization identifiers',
  );
}

Future<void> main() => runTerminalLocalizationAuditTests();

void _expect(bool condition, String message) {
  if (!condition) throw StateError(message);
}
