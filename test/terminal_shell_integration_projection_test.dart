import 'dart:io';

import 'package:dart_pty_macos/dart_pty_macos.dart';
import 'package:dart_pty_macos/testing.dart';
import 'package:dart_terminal/dart_terminal.dart';
import 'package:dart_terminal/src/terminal_session.dart';

Future<void> main() => runTerminalShellIntegrationProjectionTests();

Future<void> runTerminalShellIntegrationProjectionTests() async {
  _testBundleResolutionAndFallback();
  await _testFakePtyProjectionAndNewSessionCapture();
  if (Platform.isMacOS) {
    await _testInstalledShellExecution();
  }
}

TerminalShellIntegrationBundle _reviewedBundle() =>
    TerminalShellIntegrationBundle.resolve(
      bundledContractPath: File(TerminalShellIntegrationContract.relativePath)
          .absolute
          .path,
    );

void _testBundleResolutionAndFallback() {
  final TerminalShellIntegrationBundle bundled = _reviewedBundle();
  final TerminalShellIntegrationBundle missing =
      TerminalShellIntegrationBundle.resolve();
  final TerminalShellIntegrationBundle wrongLayout =
      TerminalShellIntegrationBundle.resolve(
        bundledContractPath: File('resources/shell-integration/contract.json')
            .path,
      );
  _expect(
    bundled.usesBundledResources &&
        bundled.disposition ==
            TerminalShellIntegrationBundleDisposition.bundled &&
        bundled.fileCount == 5 &&
        bundled.machineLine() ==
            'TERMINAL_SHELL_INTEGRATION_BUNDLE disposition=bundled '
                'version=1 shells=4 files=5',
    'reviewed application-startup bundle state is complete and content-free',
  );
  _expect(
    missing.disposition ==
            TerminalShellIntegrationBundleDisposition.fallbackMissing &&
        wrongLayout.disposition ==
            TerminalShellIntegrationBundleDisposition.fallbackInvalid &&
        !missing.usesBundledResources &&
        missing.fileCount == 0 &&
        !missing.machineLine().contains('/') &&
        !wrongLayout.machineLine().contains('/'),
    'missing and non-bundle paths fail closed without publishing a path',
  );

  final Directory temporary = Directory.systemTemp.createTempSync(
    'dart-terminal-shell-bundle-',
  );
  try {
    final File copiedContract = File(
      '${temporary.path}/${TerminalShellIntegrationContract.relativePath}',
    );
    copiedContract.parent.createSync(recursive: true);
    File(TerminalShellIntegrationContract.relativePath)
        .copySync(copiedContract.path);
    for (final TerminalShellIntegrationFileRequirement required
        in TerminalShellIntegrationContract.requiredFiles) {
      final File target = File(
        '${copiedContract.parent.path}/${required.relativePath}',
      );
      target.parent.createSync(recursive: true);
      File('resources/shell-integration/${required.relativePath}')
          .copySync(target.path);
    }
    final File bash = File(
      '${copiedContract.parent.path}/'
      '${TerminalShellIntegrationResources.bashIntegrationRelativePath}',
    );
    bash.writeAsStringSync('${bash.readAsStringSync()}# corrupt\n');
    final TerminalShellIntegrationBundle corrupt =
        TerminalShellIntegrationBundle.resolve(
          bundledContractPath: copiedContract.absolute.path,
        );
    _expect(
      corrupt.disposition ==
              TerminalShellIntegrationBundleDisposition.fallbackInvalid &&
          corrupt
                  .createLaunchPlan(
                    executable: '/bin/zsh',
                    environment: const <String, String>{'KEEP': 'value'},
                    policy: TerminalConfiguredShellIntegration.detect,
                  )
                  .disposition ==
              TerminalShellIntegrationDisposition.resourcesUnavailable,
      'corrupt resources collapse to an ordinary shell launch plan',
    );
  } finally {
    temporary.deleteSync(recursive: true);
  }
}

Future<void> _testFakePtyProjectionAndNewSessionCapture() async {
  final TerminalShellIntegrationBundle bundle = _reviewedBundle();
  final List<({String executable, TerminalConfiguredShellIntegration policy})>
  integrated =
      <({String executable, TerminalConfiguredShellIntegration policy})>[
        (
          executable: '/bin/zsh',
          policy: TerminalConfiguredShellIntegration.detect,
        ),
        (
          executable: '/opt/homebrew/bin/bash',
          policy: TerminalConfiguredShellIntegration.bash,
        ),
        (
          executable: '/opt/homebrew/bin/fish',
          policy: TerminalConfiguredShellIntegration.fish,
        ),
        (
          executable: '/opt/homebrew/bin/nu',
          policy: TerminalConfiguredShellIntegration.nushell,
        ),
      ];
  for (final entry in integrated) {
    final TerminalShellLaunchPlan plan = bundle.createLaunchPlan(
      executable: entry.executable,
      environment: const <String, String>{
        'HOME': '/Users/test',
        'PATH': '/usr/bin:/bin',
        'KEEP': 'value',
      },
      policy: entry.policy,
    );
    _expect(plan.usesIntegration, '${entry.policy.name} plan is integrated');
    final PtyCommand command = await _captureCommand(plan);
    _expectCommandEqualsPlan(command, plan, entry.policy.name);
  }

  final TerminalShellLaunchPlan atomicPlan = bundle.createLaunchPlan(
    executable: '/bin/zsh',
    environment: const <String, String>{'KEEP': 'atomic'},
    policy: TerminalConfiguredShellIntegration.detect,
  );
  _expectThrowsArgument(
    () => TerminalSession(
      id: const TerminalSessionId(paneId: PaneId(879), generation: 1),
      shellLaunchPlan: atomicPlan,
      environment: const <String, String>{'KEEP': 'partial-override'},
      onChanged: () {},
      onTerminated: () {},
    ),
    'a launch plan cannot be partially overridden at session construction',
  );

  final List<TerminalShellLaunchPlan> fallbackPlans = <TerminalShellLaunchPlan>[
    bundle.createLaunchPlan(
      executable: '/bin/zsh',
      environment: const <String, String>{'KEEP': 'disabled'},
      policy: TerminalConfiguredShellIntegration.none,
    ),
    bundle.createLaunchPlan(
      executable: '/bin/sh',
      environment: const <String, String>{'KEEP': 'unsupported'},
      policy: TerminalConfiguredShellIntegration.detect,
    ),
    TerminalShellIntegrationBundle.resolve().createLaunchPlan(
      executable: '/bin/zsh',
      environment: const <String, String>{'KEEP': 'missing'},
      policy: TerminalConfiguredShellIntegration.detect,
    ),
    bundle.createLaunchPlan(
      executable: '/bin/bash',
      environment: const <String, String>{'KEEP': 'apple-bash'},
      policy: TerminalConfiguredShellIntegration.detect,
    ),
    bundle.createLaunchPlan(
      executable: '/bin/zsh',
      arguments: const <String>['-f'],
      environment: const <String, String>{'KEEP': 'arguments'},
      policy: TerminalConfiguredShellIntegration.detect,
    ),
    bundle.createLaunchPlan(
      executable: '/opt/homebrew/bin/fish',
      environment: const <String, String>{'KEEP': 'environment-limit'},
      policy: TerminalConfiguredShellIntegration.detect,
      planner: const TerminalShellIntegrationPlanner(
        maximumEnvironmentValueBytes: 8,
      ),
    ),
  ];
  for (final TerminalShellLaunchPlan plan in fallbackPlans) {
    _expect(!plan.usesIntegration, '${plan.disposition.name} remains ordinary');
    final PtyCommand command = await _captureCommand(plan);
    _expectCommandEqualsPlan(command, plan, plan.disposition.name);
  }

  TerminalConfigSnapshot candidate = _shellSnapshot(
    '/opt/homebrew/bin/fish',
    'fish',
  );
  final TerminalConfigSnapshot initial = _shellSnapshot('/bin/zsh', 'detect');
  final TerminalProductConfigurationAuthority authority =
      TerminalProductConfigurationAuthority(
        TerminalProductConfiguration.fromSnapshot(initial),
      );
  final TerminalConfigReloadController controller =
      TerminalConfigReloadController(
        initialSnapshot: initial,
        resolver: () => TerminalConfigResolution(
          snapshot: candidate,
          remainingArguments: const <String>[],
        ),
      );
  try {
    final TerminalProductConfiguration capturedBeforeReload =
        authority.newSessionConfiguration;
    final TerminalShellLaunchPlan before = bundle.createLaunchPlan(
      executable: capturedBeforeReload.shellExecutable,
      environment: const <String, String>{'GENERATION': 'before'},
      policy: capturedBeforeReload.shellIntegration,
    );
    authority.applyReload(await controller.reload());
    final TerminalProductConfiguration capturedAfterReload =
        authority.newSessionConfiguration;
    final TerminalShellLaunchPlan after = bundle.createLaunchPlan(
      executable: capturedAfterReload.shellExecutable,
      environment: const <String, String>{'GENERATION': 'after'},
      policy: capturedAfterReload.shellIntegration,
    );
    _expect(
      before.shell == TerminalShellKind.zsh &&
          before.environment['GENERATION'] == 'before' &&
          after.shell == TerminalShellKind.fish &&
          after.environment['GENERATION'] == 'after' &&
          capturedBeforeReload.shellExecutable == '/bin/zsh' &&
          capturedAfterReload.shellExecutable == '/opt/homebrew/bin/fish' &&
          !identical(capturedBeforeReload, capturedAfterReload),
      'accepted reload changes later plans without mutating a captured pane',
    );
  } finally {
    controller.dispose();
  }
}

TerminalConfigSnapshot _shellSnapshot(String executable, String policy) =>
    TerminalConfigLoader().resolve(<String>[
      '--no-config',
      '--shell=$executable',
      '--shell-integration=$policy',
    ], environment: const <String, String>{}).snapshot;

Future<PtyCommand> _captureCommand(TerminalShellLaunchPlan plan) async {
  final FakePtyBackend backend = FakePtyBackend();
  final TerminalSession session = TerminalSession(
    id: const TerminalSessionId(paneId: PaneId(880), generation: 1),
    ptyBackend: backend,
    shellLaunchPlan: plan,
    onChanged: () {},
    onTerminated: () {},
  );
  try {
    await session.start();
    return backend.commands.single;
  } finally {
    await session.dispose();
  }
}

void _expectCommandEqualsPlan(
  PtyCommand command,
  TerminalShellLaunchPlan plan,
  String description,
) {
  _expect(
    command.executable == plan.executable &&
        command.arguments.join('\u0000') == plan.arguments.join('\u0000') &&
        command.environment.length ==
            plan.environment.length +
                (plan.environment.containsKey('COLORTERM') ? 0 : 1) +
                (plan.environment.containsKey('TERM') ? 0 : 1) &&
        plan.environment.entries.every(
          (MapEntry<String, String> entry) =>
              command.environment[entry.key] == entry.value,
        ) &&
        command.loginShell == plan.loginShell &&
        !command.includeParentEnvironment,
    '$description plan projects atomically into one PTY command',
  );
}

Future<void> _testInstalledShellExecution() async {
  final TerminalShellIntegrationBundle bundle = _reviewedBundle();
  final Directory temporary = Directory.systemTemp.createTempSync(
    'dart-terminal-shell-execution-',
  );
  try {
    final Directory zshDirectory = Directory('${temporary.path}/zsh')
      ..createSync();
    File('${zshDirectory.path}/.zshenv')
        .writeAsStringSync('export DT_TEST_ZSHENV=loaded\n');
    File('${zshDirectory.path}/.zshrc')
        .writeAsStringSync('export DT_TEST_ZSHRC=loaded\n');
    final Map<String, String> zshEnvironment = <String, String>{
      'HOME': temporary.path,
      'PATH': '/usr/bin:/bin',
      'TERM': 'dumb',
      'LC_ALL': 'C',
      'PS1': '__DT_SHELL_PROMPT__ ',
      'RPS1': '',
      'ZDOTDIR': zshDirectory.path,
      'HISTFILE': '/dev/null',
    };
    final TerminalShellLaunchPlan zsh = bundle.createLaunchPlan(
      executable: '/bin/zsh',
      environment: zshEnvironment,
      policy: TerminalConfiguredShellIntegration.detect,
    );
    final String zshOutput = await _runRealShell(
      zsh,
      temporary.path,
      'printf "__DT_ZSH_EXEC__:%s:%s:%s:%s:%s:%s\\n" '
      '"\$DART_TERMINAL_SHELL_INTEGRATION" '
      '"\$DART_TERMINAL_SHELL_INTEGRATION_VERSION" '
      '"\$DART_TERMINAL_SHELL_INTEGRATION_SHELL" '
      '"\$DT_TEST_ZSHENV" "\$DT_TEST_ZSHRC" '
      '"\${DART_TERMINAL_ZDOTDIR_SET-unset}"; exit',
    );
    _expect(
      zshOutput.contains('__DT_ZSH_EXEC__:1:1:zsh:loaded:loaded:unset'),
      'installed zsh executes integration and ordinary user startup exactly',
    );

    final TerminalShellLaunchPlan disabled = bundle.createLaunchPlan(
      executable: '/bin/zsh',
      environment: zshEnvironment,
      policy: TerminalConfiguredShellIntegration.none,
    );
    final String disabledOutput = await _runRealShell(
      disabled,
      temporary.path,
      'printf "__DT_ZSH_DISABLED__:%s:%s:%s\\n" '
      '"\${DART_TERMINAL_SHELL_INTEGRATION-unset}" '
      '"\$DT_TEST_ZSHENV" "\$DT_TEST_ZSHRC"; exit',
    );
    _expect(
      disabledOutput.contains('__DT_ZSH_DISABLED__:unset:loaded:loaded'),
      'disabled installed zsh keeps normal startup without integration',
    );

    final Directory bashHome = Directory('${temporary.path}/bash')
      ..createSync();
    final String bashResource = File(
      'resources/shell-integration/'
      '${TerminalShellIntegrationResources.bashIntegrationRelativePath}',
    ).absolute.path;
    File('${bashHome.path}/.bash_profile').writeAsStringSync(
      'export DT_TEST_BASH_PROFILE=loaded\n'
      'builtin source "$bashResource"\n',
    );
    final TerminalShellLaunchPlan bash = bundle.createLaunchPlan(
      executable: '/bin/bash',
      environment: <String, String>{
        'HOME': bashHome.path,
        'PATH': '/usr/bin:/bin',
        'TERM': 'dumb',
        'LC_ALL': 'C',
        'PS1': '__DT_SHELL_PROMPT__ ',
        'ENV': '/original/bash-env',
        'BASH_SILENCE_DEPRECATION_WARNING': '1',
      },
      policy: TerminalConfiguredShellIntegration.bash,
    );
    _expect(
      bash.disposition ==
          TerminalShellIntegrationDisposition.appleBashUnsupported,
      'Apple bash remains an ordinary login shell even when forced',
    );
    final String bashOutput = await _runRealShell(
      bash,
      temporary.path,
      'printf "__DT_BASH_EXEC__:%s:%s:%s:%s:%s:%s\\n" '
      '"\$DART_TERMINAL_SHELL_INTEGRATION" '
      '"\$DART_TERMINAL_SHELL_INTEGRATION_VERSION" '
      '"\$DART_TERMINAL_SHELL_INTEGRATION_SHELL" '
      '"\$DT_TEST_BASH_PROFILE" "\$ENV" '
      '"\${DART_TERMINAL_BASH_INJECT-unset}"; exit',
    );
    _expect(
      bashOutput.contains(
        '__DT_BASH_EXEC__:1:1:bash:loaded:/original/bash-env:unset',
      ),
      'installed Apple bash manual opt-in executes integration and startup; '
      'output=${bashOutput.replaceAll('\n', r'\n')}',
    );
  } finally {
    temporary.deleteSync(recursive: true);
  }
}

Future<String> _runRealShell(
  TerminalShellLaunchPlan plan,
  String workingDirectory,
  String command,
) async {
  var terminated = false;
  final TerminalSession session = TerminalSession(
    id: const TerminalSessionId(paneId: PaneId(881), generation: 1),
    initialWorkingDirectory: workingDirectory,
    shellLaunchPlan: plan,
    onChanged: () {},
    onTerminated: () {
      terminated = true;
    },
  );
  try {
    await session.start().timeout(const Duration(seconds: 5));
    session.insertText(command);
    await session.submit();
    await session.waitForTermination().timeout(const Duration(seconds: 8));
    _expect(
      session.exit?.exitCode == 0 &&
          session.exitDisposition == TerminalPaneSessionExitDisposition.clean &&
          terminated,
      '${plan.shell?.name ?? 'ordinary'} shell exits and is reaped once',
    );
    return session.buffer.outputText;
  } finally {
    await session.dispose();
  }
}

void _expect(bool condition, String description) {
  if (!condition) {
    throw StateError('shell integration projection failed: $description');
  }
}

void _expectThrowsArgument(void Function() operation, String description) {
  try {
    operation();
  } on ArgumentError {
    return;
  }
  throw StateError('shell integration projection failed: $description');
}
