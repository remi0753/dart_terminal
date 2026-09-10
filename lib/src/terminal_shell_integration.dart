import 'dart:convert';
import 'dart:io';

import 'terminal_config.dart';
import 'terminal_sha256.dart';

enum TerminalShellKind { zsh, bash, fish, nushell }

enum TerminalShellIntegrationDisposition {
  integrated,
  disabled,
  unsupportedShell,
  unsupportedArguments,
  appleBashUnsupported,
  resourcesUnavailable,
  environmentLimitExceeded,
}

final class TerminalShellIntegrationException implements FormatException {
  const TerminalShellIntegrationException(this.message);

  @override
  final String message;

  @override
  int? get offset => null;

  @override
  Object? get source => null;

  @override
  String toString() => 'TerminalShellIntegrationException: $message';
}

final class TerminalShellIntegrationFileRequirement {
  const TerminalShellIntegrationFileRequirement({
    required this.shell,
    required this.relativePath,
  });

  final TerminalShellKind shell;
  final String relativePath;
}

final class TerminalShellIntegrationFileContract {
  const TerminalShellIntegrationFileContract({
    required this.shell,
    required this.relativePath,
    required this.byteLength,
    required this.sha256,
  });

  final TerminalShellKind shell;
  final String relativePath;
  final int byteLength;
  final String sha256;
}

/// Versioned, hash-pinned contract for bundled shell bootstrap resources.
final class TerminalShellIntegrationContract {
  TerminalShellIntegrationContract._({
    required Iterable<TerminalShellIntegrationFileContract> files,
  }) : files = List<TerminalShellIntegrationFileContract>.unmodifiable(files);

  static const String relativePath =
      'resources/shell-integration/contract.json';
  static const String format = 'dart-terminal-shell-integration-contract';
  static const int version = 1;
  static const int integrationVersion = 1;
  static const int maximumContractBytes = 32 * 1024;
  static const int maximumResourceBytes = 32 * 1024;
  static const int maximumTotalResourceBytes = 128 * 1024;
  static const String markerEnvironment = 'DART_TERMINAL_SHELL_INTEGRATION';
  static const String versionEnvironment =
      'DART_TERMINAL_SHELL_INTEGRATION_VERSION';
  static const List<TerminalShellIntegrationFileRequirement> requiredFiles =
      <TerminalShellIntegrationFileRequirement>[
        TerminalShellIntegrationFileRequirement(
          shell: TerminalShellKind.zsh,
          relativePath:
              TerminalShellIntegrationResources.zshBootstrapRelativePath,
        ),
        TerminalShellIntegrationFileRequirement(
          shell: TerminalShellKind.zsh,
          relativePath:
              TerminalShellIntegrationResources.zshIntegrationRelativePath,
        ),
        TerminalShellIntegrationFileRequirement(
          shell: TerminalShellKind.bash,
          relativePath:
              TerminalShellIntegrationResources.bashIntegrationRelativePath,
        ),
        TerminalShellIntegrationFileRequirement(
          shell: TerminalShellKind.fish,
          relativePath:
              TerminalShellIntegrationResources.fishIntegrationRelativePath,
        ),
        TerminalShellIntegrationFileRequirement(
          shell: TerminalShellKind.nushell,
          relativePath:
              TerminalShellIntegrationResources.nushellIntegrationRelativePath,
        ),
      ];

  final List<TerminalShellIntegrationFileContract> files;

  static TerminalShellIntegrationContract load(File source) {
    _contractExpect(source.existsSync(), 'contract does not exist');
    _contractExpect(
      FileSystemEntity.typeSync(source.path, followLinks: false) ==
          FileSystemEntityType.file,
      'contract must be a regular file',
    );
    final List<int> bytes = source.readAsBytesSync();
    _contractExpect(
      bytes.isNotEmpty && bytes.length <= maximumContractBytes,
      'contract size is outside 1..$maximumContractBytes',
    );
    return parse(utf8.decode(bytes));
  }

  static TerminalShellIntegrationContract parse(String source) {
    _contractExpect(
      utf8.encode(source).length <= maximumContractBytes,
      'contract exceeds $maximumContractBytes encoded bytes',
    );
    final Object? decoded;
    try {
      decoded = jsonDecode(source);
    } on Object catch (error) {
      throw TerminalShellIntegrationException('invalid JSON: $error');
    }
    final Map<String, Object?> root = _contractObject(decoded, 'root');
    _contractKeys(root, const <String>{
      'format',
      'version',
      'integration_version',
      'marker_environment',
      'version_environment',
      'files',
    }, 'root');
    _contractExpect(root['format'] == format, 'unsupported contract format');
    _contractExpect(root['version'] == version, 'unsupported contract version');
    _contractExpect(
      root['integration_version'] == integrationVersion,
      'unsupported integration version',
    );
    _contractExpect(
      root['marker_environment'] == markerEnvironment,
      'marker environment differs from the runtime contract',
    );
    _contractExpect(
      root['version_environment'] == versionEnvironment,
      'version environment differs from the runtime contract',
    );
    final Object? fileValue = root['files'];
    _contractExpect(fileValue is List<Object?>, 'files must be an array');
    final List<Object?> fileMaps = fileValue! as List<Object?>;
    _contractExpect(
      fileMaps.length == requiredFiles.length,
      'files must contain exactly ${requiredFiles.length} entries',
    );
    final List<TerminalShellIntegrationFileContract> files =
        <TerminalShellIntegrationFileContract>[];
    for (var index = 0; index < requiredFiles.length; index += 1) {
      final Map<String, Object?> map = _contractObject(
        fileMaps[index],
        'files[$index]',
      );
      _contractKeys(map, const <String>{
        'shell',
        'path',
        'bytes',
        'sha256',
      }, 'files[$index]');
      final TerminalShellIntegrationFileRequirement required =
          requiredFiles[index];
      _contractExpect(
        map['shell'] == required.shell.name,
        'files[$index].shell differs from the required order',
      );
      _contractExpect(
        map['path'] == required.relativePath,
        'files[$index].path differs from the required path',
      );
      final Object? byteValue = map['bytes'];
      _contractExpect(
        byteValue is int && byteValue > 0 && byteValue <= maximumResourceBytes,
        'files[$index].bytes is outside 1..$maximumResourceBytes',
      );
      final Object? shaValue = map['sha256'];
      _contractExpect(
        shaValue is String && RegExp(r'^[0-9a-f]{64}$').hasMatch(shaValue),
        'files[$index].sha256 must be lowercase SHA-256',
      );
      files.add(
        TerminalShellIntegrationFileContract(
          shell: required.shell,
          relativePath: required.relativePath,
          byteLength: byteValue as int,
          sha256: shaValue as String,
        ),
      );
    }
    _contractExpect(
      files.fold<int>(
            0,
            (int total, TerminalShellIntegrationFileContract file) =>
                total + file.byteLength,
          ) <=
          maximumTotalResourceBytes,
      'total resource bytes exceed $maximumTotalResourceBytes',
    );
    return TerminalShellIntegrationContract._(files: files);
  }

  TerminalShellIntegrationResources validateResources(Directory root) {
    final Directory absoluteRoot = root.absolute;
    final Set<TerminalShellKind> shells = <TerminalShellKind>{};
    for (final TerminalShellIntegrationFileContract contract in files) {
      final File file = File('${absoluteRoot.path}/${contract.relativePath}');
      _contractExpect(
        file.existsSync(),
        'resource is missing: ${contract.relativePath}',
      );
      _contractExpect(
        FileSystemEntity.typeSync(file.path, followLinks: false) ==
            FileSystemEntityType.file,
        'resource must be a regular file: ${contract.relativePath}',
      );
      final List<int> bytes = file.readAsBytesSync();
      _contractExpect(
        bytes.length == contract.byteLength,
        'resource byte length differs: ${contract.relativePath}',
      );
      _contractExpect(
        terminalSha256(bytes) == contract.sha256,
        'resource hash differs: ${contract.relativePath}',
      );
      final String text;
      try {
        text = utf8.decode(bytes);
      } on FormatException {
        throw TerminalShellIntegrationException(
          'resource is not UTF-8: ${contract.relativePath}',
        );
      }
      _contractExpect(
        text.startsWith('# Dart Terminal ') &&
            text.contains('resource contract version 1.') &&
            text.endsWith('\n') &&
            !text.contains('\r') &&
            !text.contains('\u0000') &&
            !text.contains('GHOSTTY') &&
            !text.contains('kitty'),
        'resource header/content policy failed: ${contract.relativePath}',
      );
      shells.add(contract.shell);
    }
    _contractExpect(
      shells.length == TerminalShellKind.values.length,
      'validated resources do not cover every supported shell',
    );
    return TerminalShellIntegrationResources(
      rootPath: absoluteRoot.path,
      availableShells: shells,
    );
  }
}

enum TerminalShellIntegrationBundleDisposition {
  bundled,
  fallbackMissing,
  fallbackInvalid,
}

/// Immutable application-startup result for bundled integration resources.
///
/// File-system failures are reduced to a content-free fallback disposition.
/// New panes can therefore use one reviewed resource generation without doing
/// file I/O or exposing a private bundle path in diagnostics.
final class TerminalShellIntegrationBundle {
  const TerminalShellIntegrationBundle._({
    required this.disposition,
    required TerminalShellIntegrationResources? resources,
    required this.fileCount,
  }) : _resources = resources;

  static TerminalShellIntegrationBundle resolve({String? bundledContractPath}) {
    if (bundledContractPath == null) {
      return const TerminalShellIntegrationBundle._(
        disposition: TerminalShellIntegrationBundleDisposition.fallbackMissing,
        resources: null,
        fileCount: 0,
      );
    }
    if (!bundledContractPath.startsWith('/') ||
        !bundledContractPath.endsWith(
          '/${TerminalShellIntegrationContract.relativePath}',
        )) {
      return const TerminalShellIntegrationBundle._(
        disposition: TerminalShellIntegrationBundleDisposition.fallbackInvalid,
        resources: null,
        fileCount: 0,
      );
    }
    try {
      final File contractFile = File(bundledContractPath);
      final TerminalShellIntegrationContract contract =
          TerminalShellIntegrationContract.load(contractFile);
      final TerminalShellIntegrationResources resources = contract
          .validateResources(contractFile.parent);
      return TerminalShellIntegrationBundle._(
        disposition: TerminalShellIntegrationBundleDisposition.bundled,
        resources: resources,
        fileCount: contract.files.length,
      );
    } on TerminalShellIntegrationException {
      return const TerminalShellIntegrationBundle._(
        disposition: TerminalShellIntegrationBundleDisposition.fallbackInvalid,
        resources: null,
        fileCount: 0,
      );
    } on FileSystemException {
      return const TerminalShellIntegrationBundle._(
        disposition: TerminalShellIntegrationBundleDisposition.fallbackInvalid,
        resources: null,
        fileCount: 0,
      );
    } on ArgumentError {
      return const TerminalShellIntegrationBundle._(
        disposition: TerminalShellIntegrationBundleDisposition.fallbackInvalid,
        resources: null,
        fileCount: 0,
      );
    }
  }

  final TerminalShellIntegrationBundleDisposition disposition;
  final TerminalShellIntegrationResources? _resources;
  final int fileCount;

  bool get usesBundledResources =>
      disposition == TerminalShellIntegrationBundleDisposition.bundled;

  TerminalShellLaunchPlan createLaunchPlan({
    required String executable,
    Iterable<String> arguments = const <String>[],
    required Map<String, String> environment,
    required TerminalConfiguredShellIntegration policy,
    TerminalShellIntegrationPlanner planner =
        const TerminalShellIntegrationPlanner(),
  }) => planner.plan(
    executable: executable,
    arguments: arguments,
    environment: environment,
    policy: policy,
    resources: _resources,
  );

  String machineLine() =>
      'TERMINAL_SHELL_INTEGRATION_BUNDLE '
      'disposition=${disposition.name} '
      'version=${usesBundledResources ? TerminalShellIntegrationContract.integrationVersion : 0} '
      'shells=${usesBundledResources ? TerminalShellKind.values.length : 0} '
      'files=$fileCount';
}

/// A validated bundle-resource root and the shell integrations it contains.
///
/// [TerminalShellIntegrationContract.validateResources] checks file type, size,
/// and content hash before creating this value. Keeping that validation outside
/// the planner makes a failed load indistinguishable from an unavailable
/// integration and preserves the ordinary shell launch transaction.
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
    if (isDarwin &&
        shell == TerminalShellKind.bash &&
        executable == '/bin/bash') {
      return fallback(
        TerminalShellIntegrationDisposition.appleBashUnsupported,
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
    for (final String key in <String>[
      'DART_TERMINAL_ZDOTDIR_SET',
      'DART_TERMINAL_ZDOTDIR',
      'DART_TERMINAL_BASH_ENV_SET',
      'DART_TERMINAL_BASH_ENV',
      'DART_TERMINAL_BASH_INJECT',
      'DART_TERMINAL_BASH_HISTFILE_WAS_UNSET',
      'DART_TERMINAL_SHELL_INTEGRATION_XDG_DIR',
    ]) {
      integrated.remove(key);
    }
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
        if (!integrated.containsKey('HISTFILE')) {
          integrated['DART_TERMINAL_BASH_HISTFILE_WAS_UNSET'] = '1';
        }
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

Map<String, Object?> _contractObject(Object? value, String name) {
  _contractExpect(value is Map<String, Object?>, '$name must be an object');
  return value! as Map<String, Object?>;
}

void _contractKeys(
  Map<String, Object?> value,
  Set<String> expected,
  String name,
) {
  _contractExpect(
    value.keys.toSet().difference(expected).isEmpty &&
        expected.difference(value.keys.toSet()).isEmpty,
    '$name keys differ from the versioned contract',
  );
}

void _contractExpect(bool condition, String message) {
  if (!condition) {
    throw TerminalShellIntegrationException(message);
  }
}
