import 'dart:convert';
import 'dart:io';

final class TerminalLocalizationAuditException implements Exception {
  const TerminalLocalizationAuditException(this.message);

  final String message;

  @override
  String toString() => 'TerminalLocalizationAuditException: $message';
}

final class TerminalLocalizationAuditResult {
  const TerminalLocalizationAuditResult({
    required this.sourceCount,
    required this.resourceFamilies,
    required this.resourceKeys,
  });

  final int sourceCount;
  final int resourceFamilies;
  final int resourceKeys;

  String machineLine() =>
      'TERMINAL_LOCALIZATION_AUDIT_PASS sources=$sourceCount '
      'resource_families=$resourceFamilies resource_keys=$resourceKeys';
}

/// Returns catalog-owned phrases that occur in Dart string literals.
///
/// Comments and identifiers are intentionally ignored so an owner can name its
/// localization APIs without being treated as user-visible text.
List<String> findForbiddenLocalizationLiterals(
  String source,
  Iterable<String> forbidden,
) {
  final List<String> literals =
      RegExp(
        r'''(?<![A-Za-z0-9_])(?:r)?('(?:\\.|[^'\\])*'|"(?:\\.|[^"\\])*")''',
        dotAll: true,
      ).allMatches(source).map((RegExpMatch match) {
        final String literal = match.group(1)!;
        return literal
            .replaceAll(RegExp(r'\$\{[^}]*\}'), '')
            .replaceAll(RegExp(r'\$[A-Za-z_][A-Za-z0-9_]*'), '');
      }).toList();
  return <String>[
    for (final String phrase in forbidden)
      if (literals.any((String literal) => literal.contains(phrase))) phrase,
  ];
}

Future<TerminalLocalizationAuditResult> runTerminalLocalizationAudit({
  Directory? projectRoot,
}) async {
  final Directory root = (projectRoot ?? Directory.current).absolute;
  for (final _SourceRule rule in _sourceRules) {
    final String source = _read(root, rule.path);
    for (final String token in rule.requiredTokens) {
      _expect(
        source.contains(token),
        '${rule.path} is missing localization ownership token: $token',
      );
    }
    final List<String> leaks = findForbiddenLocalizationLiterals(
      source,
      rule.forbiddenPhrases,
    );
    _expect(
      leaks.isEmpty,
      '${rule.path} owns catalog UI literals: ${leaks.join(', ')}',
    );
  }
  final String applicationSource = _read(
    root,
    'lib/src/terminal_application.dart',
  );
  _expect(
    'localization: localization'.allMatches(applicationSource).length == 8,
    'production application localization injection count changed',
  );

  final String catalog = _read(root, 'lib/src/terminal_localization.dart');
  for (final String phrase in _catalogPhrases) {
    _expect(catalog.contains(phrase), 'catalog is missing UI phrase: $phrase');
  }

  final Map<String, Object?> manifest =
      jsonDecode(_read(root, 'macos_application.json')) as Map<String, Object?>;
  final Map<String, Object?> application =
      manifest['application']! as Map<String, Object?>;
  _expect(
    application['displayName'] == 'Dart Terminal',
    'manifest must inject the product display name',
  );
  final Set<String> resources = (manifest['resources']! as List<Object?>)
      .cast<String>()
      .toSet();
  _expect(
    resources.containsAll(_localizedResources),
    'manifest is missing a required localization resource',
  );
  final Set<String> declaredLocalizedResources = resources
      .where((String path) => path.contains('.lproj/'))
      .toSet();
  _expect(
    declaredLocalizedResources.length == _localizedResources.length &&
        declaredLocalizedResources.containsAll(_localizedResources),
    'manifest declares an unaudited localization resource',
  );
  final Set<String> sourceLocalizedResources = <String>{
    for (final String language in const <String>['en', 'ja'])
      for (final FileSystemEntity entity in Directory(
        '${root.path}/$language.lproj',
      ).listSync())
        if (entity is File) '$language.lproj/${entity.uri.pathSegments.last}',
  };
  _expect(
    sourceLocalizedResources.length == _localizedResources.length &&
        sourceLocalizedResources.containsAll(_localizedResources),
    'source locale directories contain missing or unaudited resources',
  );

  final Map<String, Map<String, String>> english =
      <String, Map<String, String>>{};
  var resourceKeys = 0;
  for (final String fileName in _resourceFiles) {
    final Map<String, String> en = _strings(_read(root, 'en.lproj/$fileName'));
    final Map<String, String> ja = _strings(_read(root, 'ja.lproj/$fileName'));
    _expect(en.isNotEmpty, '$fileName English catalog is empty');
    _expect(
      en.keys.toSet().difference(ja.keys.toSet()).isEmpty &&
          ja.keys.toSet().difference(en.keys.toSet()).isEmpty,
      '$fileName English/Japanese key sets differ',
    );
    _expect(
      en.values.every((String value) => value.isNotEmpty) &&
          ja.values.every((String value) => value.isNotEmpty),
      '$fileName contains an empty translation',
    );
    if (fileName != 'InfoPlist.strings') {
      _expect(
        en.keys.every((String key) => en[key] != ja[key]),
        '$fileName contains an untranslated Japanese value',
      );
    }
    english[fileName] = en;
    resourceKeys += en.length;
  }

  final Set<String> serviceTitles = (manifest['services']! as List<Object?>)
      .cast<Map<String, Object?>>()
      .map((Map<String, Object?> value) => value['menuItem']! as String)
      .toSet();
  _expect(
    english['ServicesMenu.strings']!.keys.toSet().length ==
            serviceTitles.length &&
        english['ServicesMenu.strings']!.keys.toSet().containsAll(
          serviceTitles,
        ),
    'Finder Service titles and ServicesMenu keys differ',
  );
  _expect(
    english['InfoPlist.strings']!.keys.toSet().containsAll(const <String>{
      'CFBundleDisplayName',
      'CFBundleName',
    }),
    'InfoPlist catalog does not cover both bundle display-name keys',
  );

  final String swift = _read(
    root,
    'packages/dart_terminal_app_intents_macos/native/'
    'TerminalAppIntents.swift',
  );
  _expect(
    english['Localizable.strings']!.keys.every(swift.contains) &&
        swift.contains('String(localized:'),
    'App Intent declarations or errors are not covered by Localizable.strings',
  );
  for (final String key in english['AppShortcuts.strings']!.keys) {
    final String swiftPhrase = key.replaceAll(
      r'${applicationName}',
      r'\(.applicationName)',
    );
    _expect(
      swift.contains(swiftPhrase),
      'AppShortcuts.strings has no Swift declaration for: $key',
    );
  }

  return TerminalLocalizationAuditResult(
    sourceCount: _sourceRules.length,
    resourceFamilies: _resourceFiles.length,
    resourceKeys: resourceKeys,
  );
}

Future<void> main(List<String> arguments) async {
  try {
    _expect(arguments.isEmpty, 'this audit takes no arguments');
    final TerminalLocalizationAuditResult result =
        await runTerminalLocalizationAudit();
    stdout.writeln(result.machineLine());
  } on Object catch (error) {
    stderr.writeln('TERMINAL_LOCALIZATION_AUDIT_FAIL error=$error');
    exitCode = 1;
  }
}

String _read(Directory root, String relativePath) {
  final File file = File('${root.path}/$relativePath');
  _expect(file.existsSync(), 'required file is missing: $relativePath');
  return file.readAsStringSync();
}

Map<String, String> _strings(String source) => <String, String>{
  for (final RegExpMatch match in RegExp(
    r'^"((?:[^"\\]|\\.)+)"\s*=\s*"((?:[^"\\]|\\.)*)"\s*;',
    multiLine: true,
  ).allMatches(source))
    match.group(1)!: match.group(2)!,
};

void _expect(bool condition, String message) {
  if (!condition) throw TerminalLocalizationAuditException(message);
}

final class _SourceRule {
  const _SourceRule(
    this.path, {
    required this.requiredTokens,
    required this.forbiddenPhrases,
  });

  final String path;
  final List<String> requiredTokens;
  final List<String> forbiddenPhrases;
}

const List<String> _catalogPhrases = <String>[
  'Command Palette…',
  'No matching actions',
  'OSC 52 Clipboard Request',
  'Quick Terminal shortcut:',
  'Secure Keyboard Entry:',
  'Notifications:',
  'Settings — Effective Configuration',
  'No setting at the cursor',
  'SECURE AUTO',
  'Keyboard input is protected from other applications.',
];

const List<_SourceRule> _sourceRules = <_SourceRule>[
  _SourceRule(
    'lib/src/terminal_action_registry.dart',
    requiredTokens: <String>['messages.action(_actionMessageId(id))'],
    forbiddenPhrases: <String>[
      'Command Palette…',
      'Settings…',
      'Reload Configuration',
      'Toggle Quick Terminal',
      'Secure Keyboard Entry',
      'Quit Dart Terminal',
      'New Window',
      'Close Window',
      'Copy',
      'Paste',
      'Allow OSC 52 Clipboard Request',
      'Deny OSC 52 Clipboard Request',
      'New Tab',
      'Split Pane Right',
      'Split Pane Down',
      'Quick Look',
      'Toggle Pane Zoom',
      'Equalize Splits',
      'Move Split Divider',
      'Jump to Previous Prompt',
      'Jump to Next Prompt',
      'Focus Previous Pane',
      'Focus Next Pane',
      'Select Previous Tab',
      'Select Next Tab',
    ],
  ),
  _SourceRule(
    'lib/src/terminal_action_menu.dart',
    requiredTokens: <String>[
      'messages.menuTitle(TerminalMenuMessageId.context)',
      'localization.menuTitle(',
    ],
    forbiddenPhrases: <String>[
      'Dart Terminal',
      'File',
      'Edit',
      'Shell',
      'View',
      'Window',
    ],
  ),
  _SourceRule(
    'lib/src/terminal_command_palette.dart',
    requiredTokens: <String>[
      '_localization.commandPaletteTitle',
      '_localization.commandPaletteNoMatches',
      '_localization.commandPaletteInstructions',
    ],
    forbiddenPhrases: <String>[
      'Command Palette',
      'No matching actions',
      'Unavailable',
      'Return Run',
    ],
  ),
  _SourceRule(
    'lib/src/terminal_settings_editor.dart',
    requiredTokens: <String>[
      'localization.settingsSaveState(',
      'localization.settingsOptionDescription(',
      'localization.settingsDiagnosticSeverity(',
    ],
    forbiddenPhrases: <String>[
      'No setting at the cursor',
      'Current value',
      'After save',
      'Open terminals',
      'New terminals',
      'Change immediately',
      'Keep current value',
      'Use saved value',
      'FIX ERRORS',
      'SAVE FAILED',
    ],
  ),
  _SourceRule(
    'lib/src/terminal_settings_inspector.dart',
    requiredTokens: <String>[
      'localization.settingsInspectorTitle',
      'localization.settingsInspectorDiagnosticContext(',
      '_localization.textDirection',
    ],
    forbiddenPhrases: <String>[
      'Settings — Effective Configuration',
      'No matching configuration entries',
      'Accepted generation:',
      'latest reload attempt',
      'effective configuration',
      'Selected entry',
      'Reload failure:',
      'Type to search',
    ],
  ),
  _SourceRule(
    'lib/src/terminal_osc52_confirmation.dart',
    requiredTokens: <String>[
      '_localization.osc52Title',
      '_localization.osc52Instructions',
      '_localization.osc52PolicyHint',
    ],
    forbiddenPhrases: <String>[
      'OSC 52 Clipboard Request',
      'Read clipboard',
      'Write clipboard',
      'Clear clipboard',
      'Return  Allow',
      'matching clipboard policy',
    ],
  ),
  _SourceRule(
    'lib/src/terminal_quick_terminal.dart',
    requiredTokens: <String>[
      'settingsLineFor(TerminalLocalization localization)',
    ],
    forbiddenPhrases: <String>['Quick Terminal shortcut:'],
  ),
  _SourceRule(
    'lib/src/terminal_secure_keyboard_entry.dart',
    requiredTokens: <String>[
      'localization.secureKeyboardStatus(',
      'TerminalLocalization.englishSecureAutomaticBadgeText',
      'messages.secureBadgeText(',
    ],
    forbiddenPhrases: <String>[
      'SECURE AUTO',
      'SECURE MANUAL',
      'Secure Keyboard Entry — Automatic',
      'Secure Keyboard Entry — Manual',
      'Keyboard input is protected from other applications.',
    ],
  ),
  _SourceRule(
    'lib/src/terminal_notification_product.dart',
    requiredTokens: <String>['localization.notificationStatus('],
    forbiddenPhrases: <String>['Notifications:'],
  ),
  _SourceRule(
    'lib/src/terminal_app_intents_product.dart',
    requiredTokens: <String>['localization.appIntentsStatus('],
    forbiddenPhrases: <String>['App Intents:'],
  ),
  _SourceRule(
    'lib/src/terminal_native_hierarchy.dart',
    requiredTokens: <String>['TerminalLocalization.english.applicationName'],
    forbiddenPhrases: <String>['Dart Terminal —'],
  ),
  _SourceRule(
    'lib/src/terminal_application.dart',
    requiredTokens: <String>[
      'TerminalLocalization.fromEnvironment(selectedEnvironment)',
      'final String productWindowTitle = localization.applicationName',
      'required TerminalLocalization localization',
      'TerminalActionCatalog.standard(\n        localization: localization',
      'TerminalAppKitContextMenuProjection.install(',
      'TerminalOsc52ConfirmationPresenter(',
      'TerminalSettingsInspectorPresenter(',
      'TerminalCommandPalettePresenter.withFocusTarget(',
      'TerminalAppKitMenuProjection.install(',
      'appKitSecureInputBadge(',
      'settingsLineFor(localization)',
    ],
    forbiddenPhrases: <String>[],
  ),
];

const List<String> _resourceFiles = <String>[
  'InfoPlist.strings',
  'Localizable.strings',
  'AppShortcuts.strings',
  'ServicesMenu.strings',
];

const Set<String> _localizedResources = <String>{
  'en.lproj/InfoPlist.strings',
  'en.lproj/Localizable.strings',
  'en.lproj/AppShortcuts.strings',
  'en.lproj/ServicesMenu.strings',
  'ja.lproj/InfoPlist.strings',
  'ja.lproj/Localizable.strings',
  'ja.lproj/AppShortcuts.strings',
  'ja.lproj/ServicesMenu.strings',
};
