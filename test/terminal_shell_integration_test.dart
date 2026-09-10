import 'package:dart_terminal/dart_terminal.dart';

void main() => runTerminalShellIntegrationTests();

void runTerminalShellIntegrationTests() {
  _testTypedConfiguration();
  _testResourceSetValidation();
  _testDisabledAndUnsupportedFallbacks();
  _testZshPlanPreservesStartupDirectory();
  _testBashDetectionAndForcedPlan();
  _testFishAndNushellXdgPlans();
  _testArgumentsAndEnvironmentLimitsFailTransactionally();
}

void _testTypedConfiguration() {
  final TerminalConfigSnapshot configured = TerminalConfigLoader().resolve(
    const <String>[
      '--no-config',
      '--shell=/opt/homebrew/bin/fish',
      '--shell-integration=nushell',
    ],
    environment: const <String, String>{},
  ).snapshot;
  final TerminalProductConfiguration profile =
      TerminalProductConfiguration.fromSnapshot(configured);
  _expect(
    configured.diagnostics.isEmpty &&
        profile.shellExecutable == '/opt/homebrew/bin/fish' &&
        profile.shellIntegration == TerminalConfiguredShellIntegration.nushell,
    'shell and integration policy resolve through the immutable profile',
  );
  for (final String value in <String>[
    'detect',
    'none',
    'zsh',
    'bash',
    'fish',
    'nushell',
  ]) {
    final TerminalConfigSnapshot snapshot = TerminalConfigLoader().resolve(
      <String>['--no-config', '--shell-integration=$value'],
      environment: const <String, String>{},
    ).snapshot;
    _expect(
      snapshot.diagnostics.isEmpty,
      'integration policy $value is accepted',
    );
  }
  final TerminalConfigDecodeResult<String> invalidShell =
      TerminalProductConfigSchema.shell.decode('zsh');
  final TerminalConfigDecodeResult<TerminalConfiguredShellIntegration>
  invalidPolicy = TerminalProductConfigSchema.shellIntegration.decode('auto');
  final TerminalConfigSnapshot defaults = TerminalConfigLoader().resolve(
    const <String>['--no-config'],
    environment: const <String, String>{},
  ).snapshot;
  _expect(
    !invalidShell.isSuccess &&
        invalidShell.hint != null &&
        !invalidPolicy.isSuccess &&
        invalidPolicy.hint != null &&
        TerminalConfigChangePlan.between(defaults, configured).newSessionChanges
                .map((TerminalConfigChange change) => change.option.name)
                .join(',') ==
            'shell,shell-integration',
    'invalid values are actionable and both shell options are new-session changes',
  );
  _expectThrowsFormat(
    () => TerminalConfigLoader().resolve(const <String>[
      '--no-config',
      '--shell=zsh',
    ], environment: const <String, String>{}),
    'invalid command-line shell remains a fatal argument error',
  );
}

TerminalShellIntegrationResources _resources({
  Iterable<TerminalShellKind> shells = TerminalShellKind.values,
}) => TerminalShellIntegrationResources(
  rootPath: '/Applications/DartTerminal.app/Contents/Resources/resources/shell-integration',
  availableShells: shells,
);

void _testResourceSetValidation() {
  final TerminalShellIntegrationResources resources = _resources();
  _expect(
    resources.availableShells.length == 4 &&
        resources.supports(TerminalShellKind.zsh) &&
        resources.path(
              TerminalShellIntegrationResources.bashIntegrationRelativePath,
            ) ==
            '${resources.rootPath}/bash/dart-terminal-integration.bash',
    'validated resources expose bounded stable relative paths',
  );
  _expectThrows(
    () => TerminalShellIntegrationResources(
      rootPath: 'relative/resources',
      availableShells: TerminalShellKind.values,
    ),
    'resource root rejects relative paths',
  );
  _expectThrows(
    () => TerminalShellIntegrationResources(
      rootPath: '/${List<String>.filled(4097, 'x').join()}',
      availableShells: TerminalShellKind.values,
    ),
    'resource root rejects oversized paths',
  );
}

void _testDisabledAndUnsupportedFallbacks() {
  const TerminalShellIntegrationPlanner planner =
      TerminalShellIntegrationPlanner();
  final Map<String, String> environment = <String, String>{'KEEP': 'value'};
  final TerminalShellLaunchPlan disabled = planner.plan(
    executable: '/bin/zsh',
    environment: environment,
    policy: TerminalConfiguredShellIntegration.none,
    resources: _resources(),
  );
  final TerminalShellLaunchPlan unsupported = planner.plan(
    executable: '/bin/sh',
    environment: environment,
    policy: TerminalConfiguredShellIntegration.detect,
    resources: _resources(),
  );
  final TerminalShellLaunchPlan missing = planner.plan(
    executable: '/bin/zsh',
    environment: environment,
    policy: TerminalConfiguredShellIntegration.detect,
  );
  _expect(
    disabled.disposition == TerminalShellIntegrationDisposition.disabled &&
        unsupported.disposition ==
            TerminalShellIntegrationDisposition.unsupportedShell &&
        missing.disposition ==
            TerminalShellIntegrationDisposition.resourcesUnavailable &&
        disabled.arguments.isEmpty &&
        disabled.environment['KEEP'] == 'value' &&
        !disabled.usesIntegration &&
        !unsupported.usesIntegration &&
        !missing.usesIntegration,
    'disabled, unsupported, and unavailable integrations keep an ordinary shell',
  );
  environment['KEEP'] = 'changed';
  _expect(
    disabled.environment['KEEP'] == 'value',
    'fallback environment is immutable and detached from its caller',
  );
  _expect(
    disabled.machineLine() == 'TERMINAL_SHELL_INTEGRATION disposition=disabled shell=unknown integrated=false',
    'diagnostics contain classification but no executable or resource path',
  );
}

void _testZshPlanPreservesStartupDirectory() {
  const TerminalShellIntegrationPlanner planner =
      TerminalShellIntegrationPlanner();
  final TerminalShellLaunchPlan plan = planner.plan(
    executable: '/bin/zsh',
    environment: const <String, String>{
      'ZDOTDIR': '/Users/test/.config/zsh',
      'KEEP': 'value',
      'DART_TERMINAL_BASH_INJECT': 'stale',
      'DART_TERMINAL_SHELL_INTEGRATION_XDG_DIR': '/stale',
    },
    policy: TerminalConfiguredShellIntegration.detect,
    resources: _resources(),
  );
  _expect(
    plan.usesIntegration &&
        plan.shell == TerminalShellKind.zsh &&
        plan.executable == '/bin/zsh' &&
        plan.arguments.isEmpty &&
        plan.loginShell &&
        plan.environment['ZDOTDIR'] == '${_resources().rootPath}/zsh' &&
        plan.environment['DART_TERMINAL_ZDOTDIR_SET'] == '1' &&
        plan.environment['DART_TERMINAL_ZDOTDIR'] ==
            '/Users/test/.config/zsh' &&
        !plan.environment.containsKey('DART_TERMINAL_BASH_INJECT') &&
        !plan.environment.containsKey(
          'DART_TERMINAL_SHELL_INTEGRATION_XDG_DIR',
        ) &&
        plan.environment['KEEP'] == 'value',
    'zsh plan temporarily replaces and exactly preserves ZDOTDIR',
  );
}

void _testBashDetectionAndForcedPlan() {
  const TerminalShellIntegrationPlanner planner =
      TerminalShellIntegrationPlanner();
  final Map<String, String> original = <String, String>{
    'ENV': '/Users/test/.env',
    'KEEP': 'value',
  };
  final TerminalShellLaunchPlan automatic = planner.plan(
    executable: '/bin/bash',
    environment: original,
    policy: TerminalConfiguredShellIntegration.detect,
    resources: _resources(),
  );
  _expect(
    automatic.disposition ==
            TerminalShellIntegrationDisposition.appleBashUnsupported &&
        automatic.shell == TerminalShellKind.bash &&
        automatic.arguments.isEmpty &&
        automatic.environment['ENV'] == '/Users/test/.env' &&
        !automatic.environment.containsKey('DART_TERMINAL_BASH_INJECT'),
    'Darwin detect mode leaves Apple bash startup untouched',
  );

  final TerminalShellLaunchPlan forced = planner.plan(
    executable: '/opt/homebrew/bin/bash',
    environment: original,
    policy: TerminalConfiguredShellIntegration.bash,
    resources: _resources(),
  );
  _expect(
    forced.usesIntegration &&
        forced.arguments.length == 1 &&
        forced.arguments.single == '--posix' &&
        forced.environment['DART_TERMINAL_BASH_INJECT'] == '1' &&
        forced.environment['DART_TERMINAL_BASH_HISTFILE_WAS_UNSET'] == '1' &&
        forced.environment['DART_TERMINAL_BASH_ENV_SET'] == '1' &&
        forced.environment['DART_TERMINAL_BASH_ENV'] == '/Users/test/.env' &&
        forced.environment['ENV'] ==
            '${_resources().rootPath}/bash/dart-terminal-integration.bash',
    'explicit bash policy constructs the documented POSIX ENV bootstrap',
  );

  final TerminalShellLaunchPlan forcedApple = planner.plan(
    executable: '/bin/bash',
    environment: original,
    policy: TerminalConfiguredShellIntegration.bash,
    resources: _resources(),
  );
  _expect(
    forcedApple.disposition ==
            TerminalShellIntegrationDisposition.appleBashUnsupported &&
        forcedApple.arguments.isEmpty &&
        forcedApple.environment['ENV'] == '/Users/test/.env' &&
        !forcedApple.environment.containsKey('DART_TERMINAL_BASH_INJECT'),
    'explicit policy cannot bypass the Apple bash ENV startup limitation',
  );

  final TerminalShellLaunchPlan portable =
      const TerminalShellIntegrationPlanner(isDarwin: false).plan(
        executable: '/usr/local/bin/bash',
        environment: const <String, String>{},
        policy: TerminalConfiguredShellIntegration.detect,
        resources: _resources(),
      );
  _expect(
    portable.usesIntegration && portable.shell == TerminalShellKind.bash,
    'non-Apple bash is eligible for automatic integration',
  );
}

void _testFishAndNushellXdgPlans() {
  const TerminalShellIntegrationPlanner planner =
      TerminalShellIntegrationPlanner();
  final TerminalShellLaunchPlan fish = planner.plan(
    executable: '/opt/homebrew/bin/fish',
    environment: const <String, String>{'XDG_DATA_DIRS': '/opt/share'},
    policy: TerminalConfiguredShellIntegration.detect,
    resources: _resources(),
  );
  final TerminalShellLaunchPlan nushell = planner.plan(
    executable: '/opt/homebrew/bin/nu',
    environment: const <String, String>{},
    policy: TerminalConfiguredShellIntegration.detect,
    resources: _resources(),
  );
  _expect(
    fish.usesIntegration &&
        fish.shell == TerminalShellKind.fish &&
        fish.arguments.isEmpty &&
        fish.environment['DART_TERMINAL_SHELL_INTEGRATION_XDG_DIR'] ==
            _resources().rootPath &&
        fish.environment['XDG_DATA_DIRS'] ==
            '${_resources().rootPath}:/opt/share',
    'fish plan prepends the temporary vendor configuration root',
  );
  _expect(
    nushell.usesIntegration &&
        nushell.shell == TerminalShellKind.nushell &&
        nushell.arguments.join('|') == '--execute|use dart_terminal *' &&
        nushell.environment['XDG_DATA_DIRS'] ==
            '${_resources().rootPath}:/usr/local/share:/usr/share',
    'nushell plan imports the vendor module and retains default XDG roots',
  );
}

void _testArgumentsAndEnvironmentLimitsFailTransactionally() {
  const TerminalShellIntegrationPlanner planner =
      TerminalShellIntegrationPlanner(maximumEnvironmentValueBytes: 32);
  final TerminalShellLaunchPlan arguments = planner.plan(
    executable: '/bin/zsh',
    arguments: const <String>['-f'],
    environment: const <String, String>{'KEEP': 'value'},
    policy: TerminalConfiguredShellIntegration.detect,
    resources: _resources(),
  );
  final TerminalShellLaunchPlan environment = planner.plan(
    executable: '/opt/homebrew/bin/fish',
    environment: <String, String>{
      'XDG_DATA_DIRS': List<String>.filled(40, 'x').join(),
      'KEEP': 'value',
    },
    policy: TerminalConfiguredShellIntegration.detect,
    resources: _resources(),
  );
  final TerminalShellLaunchPlan partial = planner.plan(
    executable: '/bin/zsh',
    environment: const <String, String>{'KEEP': 'value'},
    policy: TerminalConfiguredShellIntegration.detect,
    resources: _resources(shells: const <TerminalShellKind>[]),
  );
  _expect(
    arguments.disposition ==
            TerminalShellIntegrationDisposition.unsupportedArguments &&
        arguments.arguments.single == '-f' &&
        environment.disposition ==
            TerminalShellIntegrationDisposition.environmentLimitExceeded &&
        environment.environment.keys.length == 2 &&
        environment.environment['KEEP'] == 'value' &&
        partial.disposition ==
            TerminalShellIntegrationDisposition.resourcesUnavailable,
    'unsupported arguments, bounds, and partial resources cannot partially inject',
  );
}

void _expectThrows(void Function() operation, String description) {
  try {
    operation();
  } on ArgumentError {
    return;
  }
  throw StateError('shell integration expectation failed: $description');
}

void _expectThrowsFormat(void Function() operation, String description) {
  try {
    operation();
  } on FormatException {
    return;
  }
  throw StateError('shell integration expectation failed: $description');
}

void _expect(bool condition, String description) {
  if (!condition) {
    throw StateError('shell integration expectation failed: $description');
  }
}
