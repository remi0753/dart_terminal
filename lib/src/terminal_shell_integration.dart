import 'dart:convert';

import 'terminal_config.dart';

enum TerminalShellKind { zsh, bash, fish, nushell }

enum TerminalShellIntegrationDisposition {
  integrated,
  disabled,
  unsupportedShell,
  unsupportedArguments,
  automaticAppleBash,
  resourcesUnavailable,
  environmentLimitExceeded,
}

/// A validated bundle-resource root and the shell integrations it contains.
///
/// The resource-contract loader introduced by the next implementation step is
/// responsible for checking file type, size, and content hash before creating
/// this value. Keeping that validation outside the planner makes a failed load
/// indistinguishable from an unavailable integration and preserves the
/// ordinary shell launch transaction.
final class TerminalShellIntegrationResources {
  TerminalShellIntegrationResources({
    required this.rootPath,
    required Iterable<TerminalShellKind> availableShells,
  }) : availableShells = Set<TerminalShellKind>.unmodifiable(availableShells) {
    final int byteLength = utf8.encode(rootPath).length;
    if (!rootPath.startsWith('/') ||
        rootPath.contains('\u0000') ||
        byteLength == 0 ||
        byteLength > maximumRootPathBytes) {
      throw ArgumentError.value(
        rootPath,
        'rootPath',
        'must be an absolute NUL-free UTF-8 path within '
            '$maximumRootPathBytes bytes',
      );
    }
  }

  static const int maximumRootPathBytes = 4096;
  static const String zshBootstrapRelativePath = 'zsh/.zshenv';
  static const String zshIntegrationRelativePath =
      'zsh/dart-terminal-integration.zsh';
  static const String bashIntegrationRelativePath =
      'bash/dart-terminal-integration.bash';
  static const String fishIntegrationRelativePath =
      'fish/vendor_conf.d/dart-terminal-integration.fish';
  static const String nushellIntegrationRelativePath =
      'nushell/vendor/autoload/dart_terminal.nu';

  final String rootPath;
  final Set<TerminalShellKind> availableShells;

  bool supports(TerminalShellKind shell) => availableShells.contains(shell);

  String path(String relativePath) => '$rootPath/$relativePath';
}

/// Immutable executable, argv, and environment selected for one new pane.
final class TerminalShellLaunchPlan {
  TerminalShellLaunchPlan._({
    required this.executable,
    required Iterable<String> arguments,
    required Map<String, String> environment,
    required this.loginShell,
    required this.disposition,
    required this.shell,
  }) : arguments = List<String>.unmodifiable(arguments),
       environment = Map<String, String>.unmodifiable(environment);

  final String executable;
  final List<String> arguments;
  final Map<String, String> environment;
  final bool loginShell;
  final TerminalShellIntegrationDisposition disposition;
  final TerminalShellKind? shell;

  bool get usesIntegration =>
      disposition == TerminalShellIntegrationDisposition.integrated;

  String machineLine() =>
      'TERMINAL_SHELL_INTEGRATION '
      'disposition=${disposition.name} '
      'shell=${shell?.name ?? 'unknown'} integrated=$usesIntegration';
}

/// Builds a bounded, transactional shell-integration launch plan.
final class TerminalShellIntegrationPlanner {
  const TerminalShellIntegrationPlanner({
    this.isDarwin = true,
    this.maximumEnvironmentValueBytes = 64 * 1024,
  }) : assert(maximumEnvironmentValueBytes > 0);

  final bool isDarwin;
  final int maximumEnvironmentValueBytes;

  TerminalShellLaunchPlan plan({
    required String executable,
    Iterable<String> arguments = const <String>[],
    required Map<String, String> environment,
    required TerminalConfiguredShellIntegration policy,
    TerminalShellIntegrationResources? resources,
  }) {
    final List<String> originalArguments = List<String>.of(arguments);
    TerminalShellLaunchPlan fallback(
      TerminalShellIntegrationDisposition disposition, {
      TerminalShellKind? shell,
    }) => TerminalShellLaunchPlan._(
      executable: executable,
      arguments: originalArguments,
      environment: environment,
      loginShell: true,
      disposition: disposition,
      shell: shell,
    );

    if (policy == TerminalConfiguredShellIntegration.none) {
      return fallback(TerminalShellIntegrationDisposition.disabled);
    }
    if (originalArguments.isNotEmpty) {
      return fallback(TerminalShellIntegrationDisposition.unsupportedArguments);
    }

    final bool forced = policy != TerminalConfiguredShellIntegration.detect;
    final TerminalShellKind? shell = forced
        ? _forcedShell(policy)
        : _detectShell(executable);
    if (shell == null) {
      return fallback(TerminalShellIntegrationDisposition.unsupportedShell);
    }
    if (!forced &&
        isDarwin &&
        shell == TerminalShellKind.bash &&
        executable == '/bin/bash') {
      return fallback(
        TerminalShellIntegrationDisposition.automaticAppleBash,
        shell: shell,
      );
    }
    if (resources == null || !resources.supports(shell)) {
      return fallback(
        TerminalShellIntegrationDisposition.resourcesUnavailable,
        shell: shell,
      );
    }

    final Map<String, String> integrated = <String, String>{...environment};
    final List<String> integratedArguments = <String>[];
    switch (shell) {
      case TerminalShellKind.zsh:
        if (integrated.containsKey('ZDOTDIR')) {
          integrated['DART_TERMINAL_ZDOTDIR_SET'] = '1';
          integrated['DART_TERMINAL_ZDOTDIR'] = integrated['ZDOTDIR']!;
        }
        integrated['ZDOTDIR'] = '${resources.rootPath}/zsh';
      case TerminalShellKind.bash:
        if (integrated.containsKey('ENV')) {
          integrated['DART_TERMINAL_BASH_ENV_SET'] = '1';
          integrated['DART_TERMINAL_BASH_ENV'] = integrated['ENV']!;
        }
        integrated['DART_TERMINAL_BASH_INJECT'] = '1';
        integrated['ENV'] = resources.path(
          TerminalShellIntegrationResources.bashIntegrationRelativePath,
        );
        integratedArguments.add('--posix');
      case TerminalShellKind.fish:
        if (!_prependXdgDataDirectories(integrated, resources.rootPath)) {
          return fallback(
            TerminalShellIntegrationDisposition.environmentLimitExceeded,
            shell: shell,
          );
        }
      case TerminalShellKind.nushell:
        if (!_prependXdgDataDirectories(integrated, resources.rootPath)) {
          return fallback(
            TerminalShellIntegrationDisposition.environmentLimitExceeded,
            shell: shell,
          );
        }
        integratedArguments.addAll(const <String>[
          '--execute',
          'use dart_terminal *',
        ]);
    }
    if (!_environmentValuesAreBounded(integrated)) {
      return fallback(
        TerminalShellIntegrationDisposition.environmentLimitExceeded,
        shell: shell,
      );
    }
    return TerminalShellLaunchPlan._(
      executable: executable,
      arguments: integratedArguments,
      environment: integrated,
      loginShell: true,
      disposition: TerminalShellIntegrationDisposition.integrated,
      shell: shell,
    );
  }

  bool _prependXdgDataDirectories(
    Map<String, String> environment,
    String rootPath,
  ) {
    const String defaultDirectories = '/usr/local/share:/usr/share';
    final String previous = environment['XDG_DATA_DIRS'] ?? defaultDirectories;
    final String combined = previous.isEmpty ? rootPath : '$rootPath:$previous';
    if (!_environmentValueIsBounded(combined)) return false;
    environment['DART_TERMINAL_SHELL_INTEGRATION_XDG_DIR'] = rootPath;
    environment['XDG_DATA_DIRS'] = combined;
    return true;
  }

  bool _environmentValuesAreBounded(Map<String, String> environment) =>
      environment.entries.every(
        (MapEntry<String, String> entry) =>
            entry.key.isNotEmpty &&
            !entry.key.contains('=') &&
            !entry.key.contains('\u0000') &&
            _environmentValueIsBounded(entry.value),
      );

  bool _environmentValueIsBounded(String value) =>
      !value.contains('\u0000') &&
      utf8.encode(value).length <= maximumEnvironmentValueBytes;
}

TerminalShellKind? _forcedShell(TerminalConfiguredShellIntegration policy) =>
    switch (policy) {
      TerminalConfiguredShellIntegration.zsh => TerminalShellKind.zsh,
      TerminalConfiguredShellIntegration.bash => TerminalShellKind.bash,
      TerminalConfiguredShellIntegration.fish => TerminalShellKind.fish,
      TerminalConfiguredShellIntegration.nushell => TerminalShellKind.nushell,
      TerminalConfiguredShellIntegration.detect ||
      TerminalConfiguredShellIntegration.none => null,
    };

TerminalShellKind? _detectShell(String executable) {
  final String name = executable.split('/').last;
  return switch (name) {
    'zsh' => TerminalShellKind.zsh,
    'bash' => TerminalShellKind.bash,
    'fish' => TerminalShellKind.fish,
    'nu' => TerminalShellKind.nushell,
    _ => null,
  };
}
