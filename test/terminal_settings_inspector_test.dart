import 'dart:convert';

import 'package:dart_appkit/dart_appkit.dart';
import 'package:dart_terminal/dart_terminal.dart';

Future<void> main() => runTerminalSettingsInspectorTests();

Future<void> runTerminalSettingsInspectorTests() async {
  await _testSearchRenderingAndReloadProjection();
  _testJapaneseSearchProjection();
  _testKeyboardOwnershipAndBounds();
}

void _testJapaneseSearchProjection() {
  final TerminalConfigSnapshot initial = TerminalConfigLoader().resolve(
    const <String>['--no-config', '--font-size=15'],
    environment: const <String, String>{},
  ).snapshot;
  final TerminalConfigReloadController controller =
      TerminalConfigReloadController(
        initialSnapshot: initial,
        resolver: () => TerminalConfigResolution(
          snapshot: initial,
          remainingArguments: const <String>[],
        ),
      );
  final TerminalSettingsInspectorState state = TerminalSettingsInspectorState(
    controller: controller,
    localization: TerminalLocalization.japanese,
  )..open();
  try {
    state.setQuery('フォントサイズ');
    final String rendered = state.render();
    _expect(
      state.selectedEntry?.option.name == 'font-size' &&
          rendered.contains('設定 — 有効な構成') &&
          rendered.contains('値: 15') &&
          rendered.contains('適用方針: 新規セッション') &&
          rendered.contains('ターミナルのフォントサイズ'),
      'Japanese inspector copy and localized description search are incomplete',
    );
  } finally {
    state.dismiss();
    controller.dispose();
  }
}

Future<void> _testSearchRenderingAndReloadProjection() async {
  final TerminalConfigLoader loader = TerminalConfigLoader(
    fileSystem: _MemoryFileSystem(const <String, String>{
      '/invalid': 'font-size = enormous\n',
      '/valid': 'font-size = 18\n',
    }),
  );
  final TerminalConfigSnapshot initial = loader.resolve(const <String>[
    '--no-config',
    '--theme=default',
    '--font-size=15',
    '--working-directory=/private/tmp/inspector',
  ], environment: const <String, String>{}).snapshot;
  final List<TerminalConfigResolution> candidates = <TerminalConfigResolution>[
    loader.resolve(const <String>[
      '--config=/invalid',
    ], environment: const <String, String>{}),
    loader.resolve(const <String>[
      '--config=/valid',
    ], environment: const <String, String>{}),
  ];
  var nextCandidate = 0;
  final TerminalConfigReloadController controller =
      TerminalConfigReloadController(
        initialSnapshot: initial,
        resolver: () => candidates[nextCandidate++],
      );
  final TerminalSettingsInspectorState state = TerminalSettingsInspectorState(
    controller: controller,
  )..open();
  try {
    _expect(
      state.effectiveSnapshot.entries.length == 53 &&
          state.results.length == 53 &&
          state.matchingEntryCount == 53 &&
          state.diagnostics.single.code == 'CFG_DEPRECATED_VALUE' &&
          state.diagnosticContext == 'effective configuration' &&
          state.render().contains('Showing 1-8 of 53'),
      'opening does not project every schema entry and startup diagnostic',
    );

    state.setQuery('font size command-line');
    final TerminalEffectiveConfigEntry selected = state.selectedEntry!;
    final String fontRendering = state.render();
    _expect(
      state.results.length == 1 &&
          selected.option.name == 'font-size' &&
          selected.canonicalValue == '15' &&
          selected.source.kind == TerminalConfigSourceKind.commandLine &&
          fontRendering.contains('Policy: new-session') &&
          fontRendering.contains('Value: 15') &&
          fontRendering.contains('Source: command-line'),
      'search loses canonical value, source, policy, or selected detail',
    );
    state.setQuery('keybind');
    _expect(
      state.selectedEntry?.option.name == 'keybind' &&
          state.selectedEntry?.canonicalValue == null &&
          state.render().contains('Value: <none>'),
      'empty repeatable option is not searchable or inspectable',
    );
    state.setQuery('font codepoint override');
    _expect(
      state.selectedEntry?.option.name == 'font-codepoint-override' &&
          state.selectedEntry?.canonicalValue == null &&
          state.render().contains('U+<hex>[..U+<hex>]=<family>') &&
          state.render().contains('Policy: new-session'),
      'font override syntax and new-session policy are not inspectable',
    );

    final TerminalConfigReloadResult rejected = await controller.reload();
    state.refresh();
    state.setQuery('font-size');
    _expect(
      rejected.disposition == TerminalConfigReloadDisposition.rejected &&
          state.acceptedGeneration == 0 &&
          state.selectedEntry?.canonicalValue == '15' &&
          state.diagnosticContext == 'latest reload attempt' &&
          state.diagnostics.single.code == 'CFG_INVALID_VALUE' &&
          state.render().contains('Fix:'),
      'rejected reload replaced accepted state or hid its diagnostic',
    );

    final TerminalConfigReloadResult applied = await controller.reload();
    state.refresh();
    state.setQuery('font-size');
    _expect(
      applied.disposition == TerminalConfigReloadDisposition.applied &&
          state.acceptedGeneration == 1 &&
          state.selectedEntry?.canonicalValue == '18' &&
          state.diagnostics.isEmpty &&
          state.render().contains('Diagnostics — latest reload attempt (0)'),
      'accepted reload is not reflected by the same inspector state',
    );
  } finally {
    state.dismiss();
    controller.dispose();
  }
}

void _testKeyboardOwnershipAndBounds() {
  final TerminalConfigSnapshot initial = TerminalConfigLoader().resolve(
    const <String>[
      '--no-config',
      '--working-directory=/private/tmp/a-very-long-working-directory',
    ],
    environment: const <String, String>{},
  ).snapshot;
  final TerminalConfigReloadController controller =
      TerminalConfigReloadController(
        initialSnapshot: initial,
        resolver: () => TerminalConfigResolution(
          snapshot: initial,
          remainingArguments: const <String>[],
        ),
      );
  final TerminalSettingsInspectorState state = TerminalSettingsInspectorState(
    controller: controller,
    limits: const TerminalSettingsInspectorLimits(
      maxQueryCharacters: 4,
      maxVisibleResults: 2,
      maxVisibleDiagnostics: 1,
      maxFieldCharacters: 12,
    ),
  )..open();
  final TerminalSettingsInspectorKeyController keys =
      TerminalSettingsInspectorKeyController(state);
  _expect(
    keys.handle(_key(keyCode: 3, characters: 'font')) ==
            TerminalSettingsInspectorKeyDisposition.updated &&
        state.query == 'font',
    'printable multi-scalar input does not update search exactly once',
  );
  _expect(
    keys.handle(_key(keyCode: 0, characters: 'x')) ==
            TerminalSettingsInspectorKeyDisposition.overflow &&
        state.query == 'font',
    'query overflow changes bounded state',
  );
  _expect(
    keys.handle(_key(keyCode: 51)) ==
            TerminalSettingsInspectorKeyDisposition.updated &&
        state.query == 'fon',
    'Backspace does not remove one scalar',
  );
  final int beforeMove = state.selectedIndex;
  keys.handle(_key(keyCode: 125));
  _expect(
    state.results.length < 2 || state.selectedIndex != beforeMove,
    'Down Arrow does not move a multi-result selection',
  );
  _expect(
    keys.handle(
          _key(
            keyCode: 15,
            characters: 'r',
            modifiers: const ModifierKeys(ModifierKeys.commandBit),
          ),
        ) ==
        TerminalSettingsInspectorKeyDisposition.reloadRequested,
    'Command-R is not reserved for shared reload dispatch',
  );
  state.setQuery('work');
  final String clipped = state.render();
  _expect(
    clipped.contains('…') &&
        !clipped.contains('/private/tmp/a-very-long-working-directory') &&
        clipped.length <= 64 * 1024,
    'long fields are not visibly clipped within the render bound',
  );
  _expect(
    keys.handle(_key(keyCode: 53, characters: '\u001b')) ==
            TerminalSettingsInspectorKeyDisposition.dismissed &&
        !state.isOpen &&
        keys.handle(_key(keyCode: 0, characters: 'z')) ==
            TerminalSettingsInspectorKeyDisposition.ignored,
    'Escape does not dismiss or closed state still consumes keys',
  );
  _expectThrows<TerminalSettingsInspectorLimitException>(
    () =>
        TerminalSettingsInspectorState(
            controller: controller,
            limits: const TerminalSettingsInspectorLimits(
              maxRenderedCharacters: 32,
            ),
          )
          ..open()
          ..render(),
    'render overflow does not fail with a typed limit',
  );
  controller.dispose();
}

AppKitKeyEvent _key({
  required int keyCode,
  String characters = '',
  ModifierKeys modifiers = const ModifierKeys(0),
}) => AppKitKeyEvent(
  windowHandle: 1,
  monotonicMicros: 1,
  kind: AppKitKeyEventKind.down,
  keyCode: keyCode,
  modifiers: modifiers,
  isRepeat: false,
  characters: characters,
  charactersIgnoringModifiers: characters,
);

final class _MemoryFileSystem implements TerminalConfigFileSystem {
  _MemoryFileSystem(Map<String, String> files)
    : _files = <String, List<int>>{
        for (final MapEntry<String, String> entry in files.entries)
          entry.key: utf8.encode(entry.value),
      };

  final Map<String, List<int>> _files;

  @override
  String absolutePath(String path) => path.startsWith('/') ? path : '/$path';

  @override
  bool exists(String path) => _files.containsKey(path);

  @override
  List<int> readBytes(String path) => List<int>.from(_files[path]!);

  @override
  String resolvePath(String containingFile, String includedPath) =>
      includedPath.startsWith('/') ? includedPath : '/$includedPath';
}

void _expectThrows<T extends Object>(void Function() body, String description) {
  try {
    body();
  } on T {
    return;
  }
  throw StateError('expected $T: $description');
}

void _expect(bool condition, String description) {
  if (!condition) {
    throw StateError(
      'terminal settings inspector expectation failed: $description',
    );
  }
}
