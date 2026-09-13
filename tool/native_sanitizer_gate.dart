import 'dart:async';
import 'dart:convert';
import 'dart:io';

const Duration _commandTimeout = Duration(minutes: 3);
const int _maximumCapturedBytes = 64 * 1024;

Future<void> main(List<String> arguments) async {
  if (arguments.isNotEmpty) {
    stderr.writeln('usage: dart run tool/native_sanitizer_gate.dart');
    exitCode = 64;
    return;
  }

  final Directory projectRoot = File.fromUri(Platform.script).parent.parent;
  final Directory appkitRoot = Directory(
    '${projectRoot.parent.path}/dart_appkit',
  );
  if (!appkitRoot.existsSync()) {
    throw StateError('required generic AppKit dependency is unavailable');
  }

  final _CommandRunner runner = _CommandRunner(projectRoot);
  final String clang = await runner.xcrunPath('clang');
  final String clangxx = await runner.xcrunPath('clang++');
  final String swiftc = await runner.xcrunPath('swiftc');
  final String sdk = await runner.captureXcrun(<String>[
    '--sdk',
    'macosx',
    '--show-sdk-path',
  ]);
  final String architecture = (await runner.runChecked(
    'host architecture',
    '/usr/bin/uname',
    const <String>['-m'],
  )).stdout.trim();
  if (architecture != 'arm64' && architecture != 'x86_64') {
    throw StateError('unsupported native sanitizer host architecture');
  }

  final Directory buildDirectory = Directory.systemTemp.createTempSync(
    'dart-terminal-native-sanitizers-',
  );
  try {
    final _NativeSanitizerGate gate = _NativeSanitizerGate(
      projectRoot: projectRoot,
      appkitRoot: appkitRoot,
      buildDirectory: buildDirectory,
      runner: runner,
      clang: clang,
      clangxx: clangxx,
      swiftc: swiftc,
      sdk: sdk,
      architecture: architecture,
    );
    await gate.run();
  } finally {
    if (buildDirectory.existsSync()) {
      buildDirectory.deleteSync(recursive: true);
    }
  }
}

final class _NativeSanitizerGate {
  _NativeSanitizerGate({
    required this.projectRoot,
    required this.appkitRoot,
    required this.buildDirectory,
    required this.runner,
    required this.clang,
    required this.clangxx,
    required this.swiftc,
    required this.sdk,
    required this.architecture,
  });

  final Directory projectRoot;
  final Directory appkitRoot;
  final Directory buildDirectory;
  final _CommandRunner runner;
  final String clang;
  final String clangxx;
  final String swiftc;
  final String sdk;
  final String architecture;

  static const Map<String, String> _runtimeEnvironment = <String, String>{
    'ASAN_OPTIONS': 'abort_on_error=1:halt_on_error=1:detect_leaks=0',
    'UBSAN_OPTIONS': 'halt_on_error=1:print_stacktrace=1',
    'MallocNanoZone': '0',
  };

  List<String> get _commonClangFlags => <String>[
    '-fsanitize=address,undefined',
    '-fno-sanitize-recover=all',
    '-fno-omit-frame-pointer',
    '-O1',
    '-g',
    '-Wall',
    '-Wextra',
    '-Wpedantic',
    '-Werror',
    '-fvisibility=hidden',
    '-fmodules-cache-path=${_path('clang-module-cache')}',
    '-isysroot',
    sdk,
    '-mmacosx-version-min=14.0',
  ];

  List<String> get _swiftFlags => <String>[
    '-sanitize=address,undefined',
    '-parse-as-library',
    '-swift-version',
    '6',
    '-warnings-as-errors',
    '-target',
    '$architecture-apple-macos14.0',
    '-sdk',
    sdk,
    '-module-cache-path',
    _path('swift-module-cache'),
    '-g',
  ];

  Future<void> run() async {
    Directory(_path('clang-module-cache')).createSync(recursive: true);
    final List<_InstrumentedArtifact> artifacts = <_InstrumentedArtifact>[];
    artifacts.addAll(await _runPtySuite());
    artifacts.addAll(await _runRendererSuite());
    artifacts.addAll(await _runAppleScriptSuite());
    artifacts.addAll(await _runAppIntentsSuite());

    var undefinedArtifacts = 0;
    final Set<String> ownersWithUndefinedInstrumentation = <String>{};
    for (final _InstrumentedArtifact artifact in artifacts) {
      final _Instrumentation instrumentation = await _inspect(artifact);
      if (instrumentation.undefinedMarkers > 0) {
        undefinedArtifacts += 1;
        ownersWithUndefinedInstrumentation.add(artifact.owner);
      }
      stdout.writeln(
        'NATIVE_SANITIZER_ARTIFACT_PASS owner=${artifact.owner} '
        'kind=${artifact.kind} asan=${instrumentation.addressMarkers} '
        'ubsan=${instrumentation.undefinedMarkers}',
      );
    }
    if (ownersWithUndefinedInstrumentation.length != 4) {
      throw StateError(
        'undefined-behavior instrumentation did not reach every native suite',
      );
    }
    stdout.writeln(
      'PRODUCT_NATIVE_SANITIZER_PASS suites=4 artifacts=${artifacts.length} '
      'asan_artifacts=${artifacts.length} '
      'ubsan_artifacts=$undefinedArtifacts architecture=$architecture',
    );
  }

  Future<List<_InstrumentedArtifact>> _runPtySuite() async {
    final String native = _projectPath('packages/dart_pty_macos/native');
    final String child = _path('pty-child.o');
    final String spawn = _path('pty-spawn.o');
    final String session = _path('pty-session.o');
    final String library = _path('libdart_pty_macos.dylib');
    final String tests = _path('dart_pty_macos_tests');
    await _compile(clang, <String>[
      ..._commonClangFlags,
      '-std=c11',
      '-c',
      '$native/PtyExecChild.c',
      '-I$native',
      '-o',
      child,
    ], 'PTY child sanitizer object');
    await _compile(clang, <String>[
      ..._commonClangFlags,
      '-std=c11',
      '-c',
      '$native/PtySpawn.c',
      '-I$native',
      '-o',
      spawn,
    ], 'PTY spawn sanitizer object');
    await _compile(clangxx, <String>[
      ..._commonClangFlags,
      '-std=c++20',
      '-pthread',
      '-c',
      '$native/PtySession.cc',
      '-I$native',
      '-o',
      session,
    ], 'PTY session sanitizer object');
    await _compile(clangxx, <String>[
      ..._commonClangFlags,
      '-std=c++20',
      '-pthread',
      '-dynamiclib',
      session,
      spawn,
      child,
      '-Wl,-install_name,@rpath/libdart_pty_macos.dylib',
      '-o',
      library,
    ], 'PTY sanitizer library');
    await _compile(clangxx, <String>[
      ..._commonClangFlags,
      '-std=c++20',
      '-pthread',
      '-I$native',
      '$native/test/PtyCapabilityTests.cc',
      '-o',
      tests,
    ], 'PTY sanitizer tests');
    await _expectSuitePass('PTY', tests, <String>[
      library,
    ], 'macOS PTY capability contract passed');
    return <_InstrumentedArtifact>[
      _InstrumentedArtifact('pty', 'library', library),
      _InstrumentedArtifact('pty', 'harness', tests),
    ];
  }

  Future<List<_InstrumentedArtifact>> _runRendererSuite() async {
    final String native = _projectPath(
      'packages/dart_terminal_renderer_macos/native',
    );
    final String bridgeInclude = _appkitPath('native/bridge/include');
    final String shader = _path('TerminalShaders.metallib');
    final String library = _path('libdart_terminal_renderer_macos.dylib');
    final String tests = _path('terminal_renderer_capability_tests');
    await _compile('xcrun', <String>[
      '-sdk',
      'macosx',
      'metal',
      '-target',
      'air64-apple-macos14.0',
      '-fmodules-cache-path=${_path('clang-module-cache')}',
      '$native/TerminalShaders.metal',
      '-o',
      shader,
    ], 'Metal shader');
    await _compile(clang, <String>[
      ..._commonClangFlags,
      '-fobjc-arc',
      '-fblocks',
      '-dynamiclib',
      '-I$bridgeInclude',
      '-I$native',
      '$native/TerminalRendererPlugin.m',
      '-framework',
      'AppKit',
      '-framework',
      'CoreText',
      '-framework',
      'Metal',
      '-framework',
      'MetalKit',
      '-Wl,-sectcreate,__DATA,__dtrlib,$shader',
      '-Wl,-install_name,@rpath/libdart_terminal_renderer_macos.dylib',
      '-o',
      library,
    ], 'renderer sanitizer library');
    await _compile(clangxx, <String>[
      ..._commonClangFlags,
      '-std=c++20',
      '-fobjc-arc',
      '-fblocks',
      '-I$bridgeInclude',
      '-I$native',
      '$native/test/TerminalRendererSanitizerTests.mm',
      '-framework',
      'AppKit',
      '-framework',
      'Metal',
      '-framework',
      'MetalKit',
      '-o',
      tests,
    ], 'renderer sanitizer tests');
    await _expectSuitePass('renderer', tests, <String>[
      library,
    ], 'Terminal renderer sanitizer-safe capabilities passed');
    return <_InstrumentedArtifact>[
      _InstrumentedArtifact('renderer', 'library', library),
      _InstrumentedArtifact('renderer', 'harness', tests),
    ];
  }

  Future<List<_InstrumentedArtifact>> _runAppleScriptSuite() async {
    final String native = _projectPath(
      'packages/dart_terminal_applescript_macos/native',
    );
    final String bridgeInclude = _appkitPath('native/bridge/include');
    final String library = _path('libdart_terminal_applescript_macos.dylib');
    final String testingObject = _path('terminal-applescript-testing.o');
    final String tests = _path('terminal_applescript_capability_tests');
    await _compile(clang, <String>[
      ..._commonClangFlags,
      '-fobjc-arc',
      '-fblocks',
      '-dynamiclib',
      '-I$bridgeInclude',
      '-I$native',
      '$native/TerminalAppleScriptPlugin.m',
      '-framework',
      'AppKit',
      '-framework',
      'Foundation',
      '-Wl,-install_name,@rpath/libdart_terminal_applescript_macos.dylib',
      '-o',
      library,
    ], 'AppleScript sanitizer library');
    await _compile(clang, <String>[
      ..._commonClangFlags,
      '-fobjc-arc',
      '-fblocks',
      '-DDTAS_TESTING',
      '-I$bridgeInclude',
      '-I$native',
      '-c',
      '$native/TerminalAppleScriptPlugin.m',
      '-o',
      testingObject,
    ], 'AppleScript sanitizer testing object');
    await _compile(clangxx, <String>[
      ..._commonClangFlags,
      '-std=c++20',
      '-fobjc-arc',
      '-fblocks',
      '-DDTAS_TESTING',
      '-I$bridgeInclude',
      '-I$native',
      '$native/test/TerminalAppleScriptCapabilityTests.mm',
      testingObject,
      '-framework',
      'AppKit',
      '-framework',
      'Foundation',
      '-o',
      tests,
    ], 'AppleScript sanitizer tests');
    await _expectSuitePass(
      'AppleScript',
      tests,
      const <String>[],
      'terminal AppleScript native capability tests passed',
    );
    return <_InstrumentedArtifact>[
      _InstrumentedArtifact('applescript', 'library', library),
      _InstrumentedArtifact('applescript', 'harness', tests),
    ];
  }

  Future<List<_InstrumentedArtifact>> _runAppIntentsSuite() async {
    final String native = _projectPath(
      'packages/dart_terminal_app_intents_macos/native',
    );
    final String moduleCache = _path('swift-module-cache');
    Directory(moduleCache).createSync(recursive: true);
    final String library = _path('libdart_terminal_app_intents_macos.dylib');
    final String abiTests = _path('terminal_app_intents_capability_tests');
    final String performTests = _path('terminal_app_intents_perform_tests');
    await _compile(swiftc, <String>[
      ..._swiftFlags,
      '-emit-library',
      '-module-name',
      'DartTerminalAppIntents',
      '-Xlinker',
      '-install_name',
      '-Xlinker',
      '@rpath/libdart_terminal_app_intents_macos.dylib',
      '-o',
      library,
      '$native/TerminalAppIntents.swift',
    ], 'App Intents sanitizer library');
    await _compile(clangxx, <String>[
      ..._commonClangFlags,
      '-std=c++20',
      '-I$native',
      '$native/test/TerminalAppIntentsCapabilityTests.cc',
      library,
      '-Wl,-rpath,${buildDirectory.path}',
      '-o',
      abiTests,
    ], 'App Intents sanitizer ABI tests');
    await _compile(swiftc, <String>[
      ..._swiftFlags,
      '-module-name',
      'DartTerminalAppIntentsPerformTests',
      '$native/TerminalAppIntents.swift',
      '$native/test/TerminalAppIntentsPerformTests.swift',
      '-o',
      performTests,
    ], 'App Intents sanitizer perform tests');
    await _expectSuitePass(
      'App Intents ABI',
      abiTests,
      const <String>[],
      'terminal App Intents native capability tests passed',
    );
    await _expectSuitePass(
      'App Intents perform',
      performTests,
      const <String>[],
      'terminal App Intents perform lifecycle tests passed',
    );
    return <_InstrumentedArtifact>[
      _InstrumentedArtifact('app-intents', 'library', library),
      _InstrumentedArtifact('app-intents', 'abi-harness', abiTests),
      _InstrumentedArtifact('app-intents', 'perform-harness', performTests),
    ];
  }

  Future<void> _compile(
    String executable,
    List<String> arguments,
    String label,
  ) async {
    await runner.runChecked(label, executable, arguments);
  }

  Future<void> _expectSuitePass(
    String suite,
    String executable,
    List<String> arguments,
    String expectedMarker,
  ) async {
    final _CommandResult result = await runner.runChecked(
      '$suite sanitizer execution',
      executable,
      arguments,
      environment: _runtimeEnvironment,
    );
    if (!result.stdout.contains(expectedMarker)) {
      throw StateError('$suite sanitizer suite omitted its success marker');
    }
    stdout.writeln('NATIVE_SANITIZER_SUITE_PASS owner=$suite');
  }

  Future<_Instrumentation> _inspect(_InstrumentedArtifact artifact) async {
    final _CommandResult libraries = await runner.runChecked(
      '${artifact.owner} ${artifact.kind} ASan runtime audit',
      '/usr/bin/otool',
      <String>['-L', artifact.path],
    );
    if (!libraries.stdout.contains('libclang_rt.asan_osx_dynamic.dylib')) {
      throw StateError(
        '${artifact.owner} ${artifact.kind} omits the ASan runtime',
      );
    }
    final _CommandResult symbols = await runner.runChecked(
      '${artifact.owner} ${artifact.kind} instrumentation audit',
      '/usr/bin/nm',
      <String>['-u', artifact.path],
    );
    final int address = '__asan_'.allMatches(symbols.stdout).length;
    final int undefined = '__ubsan_'.allMatches(symbols.stdout).length;
    if (address == 0) {
      throw StateError(
        '${artifact.owner} ${artifact.kind} has no ASan instrumentation marker',
      );
    }
    return _Instrumentation(address, undefined);
  }

  String _projectPath(String relative) => '${projectRoot.path}/$relative';

  String _appkitPath(String relative) => '${appkitRoot.path}/$relative';

  String _path(String relative) => '${buildDirectory.path}/$relative';
}

final class _InstrumentedArtifact {
  const _InstrumentedArtifact(this.owner, this.kind, this.path);

  final String owner;
  final String kind;
  final String path;
}

final class _Instrumentation {
  const _Instrumentation(this.addressMarkers, this.undefinedMarkers);

  final int addressMarkers;
  final int undefinedMarkers;
}

final class _CommandRunner {
  const _CommandRunner(this.workingDirectory);

  final Directory workingDirectory;

  Future<String> xcrunPath(String tool) async =>
      captureXcrun(<String>['--find', tool]);

  Future<String> captureXcrun(List<String> arguments) async =>
      (await runChecked('xcrun discovery', 'xcrun', arguments)).stdout.trim();

  Future<_CommandResult> runChecked(
    String label,
    String executable,
    List<String> arguments, {
    Map<String, String> environment = const <String, String>{},
  }) async {
    final Process process = await Process.start(
      executable,
      arguments,
      workingDirectory: workingDirectory.path,
      environment: environment,
      includeParentEnvironment: true,
    );
    final Future<String> stdoutFuture = _capture(process.stdout);
    final Future<String> stderrFuture = _capture(process.stderr);
    var timedOut = false;
    final int status = await process.exitCode.timeout(
      _commandTimeout,
      onTimeout: () {
        timedOut = true;
        process.kill(ProcessSignal.sigkill);
        return 124;
      },
    );
    final String standardOutput = await stdoutFuture;
    final String standardError = await stderrFuture;
    if (status != 0) {
      throw StateError(
        '$label failed${timedOut ? ' after the bounded timeout' : ''} '
        '(status $status)\n'
        '${_boundedDiagnostic(standardOutput, standardError)}',
      );
    }
    return _CommandResult(standardOutput, standardError);
  }

  Future<String> _capture(Stream<List<int>> stream) async {
    final List<int> bytes = <int>[];
    var truncated = false;
    await for (final List<int> chunk in stream) {
      final int remaining = _maximumCapturedBytes - bytes.length;
      if (remaining <= 0) {
        truncated = true;
        continue;
      }
      final int accepted = chunk.length < remaining ? chunk.length : remaining;
      bytes.addAll(chunk.take(accepted));
      if (accepted != chunk.length) {
        truncated = true;
      }
    }
    final String decoded = utf8.decode(bytes, allowMalformed: true);
    return truncated ? '$decoded\n[output truncated]' : decoded;
  }

  String _boundedDiagnostic(String standardOutput, String standardError) {
    final String combined = <String>[
      if (standardOutput.trim().isNotEmpty) standardOutput.trim(),
      if (standardError.trim().isNotEmpty) standardError.trim(),
    ].join('\n');
    return combined.isEmpty ? '[no process output]' : combined;
  }
}

final class _CommandResult {
  const _CommandResult(this.stdout, this.stderr);

  final String stdout;
  final String stderr;
}
