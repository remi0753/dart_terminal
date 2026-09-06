import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

const String defaultTerminalApplicationMatrixPath =
    'test/corpus/applications/matrix_v1.json';

enum TerminalApplicationObservationField {
  stream,
  screen,
  cursor,
  modes,
  replies,
  resize,
  exit,
}

enum TerminalApplicationDriverStatus {
  ok,
  unavailable,
  startFailure,
  timedOut,
  crashed,
  outputLimit,
  protocolError,
}

final class TerminalApplicationMatrixException implements FormatException {
  const TerminalApplicationMatrixException(this.message);

  @override
  final String message;

  @override
  int? get offset => null;

  @override
  Object? get source => null;

  @override
  String toString() => 'TerminalApplicationMatrixException: $message';
}

final class TerminalApplicationScenario {
  const TerminalApplicationScenario({
    required this.applicationId,
    required this.id,
    required this.description,
    required this.rows,
    required this.columns,
    required this.deadlineMs,
    required this.maximumOutputBytes,
    required this.requiredFields,
    required this.checks,
  });

  final String applicationId;
  final String id;
  final String description;
  final int rows;
  final int columns;
  final int deadlineMs;
  final int maximumOutputBytes;
  final List<TerminalApplicationObservationField> requiredFields;
  final List<String> checks;

  Map<String, Object?> toDriverRequest() => <String, Object?>{
    'format': 'dart-terminal-application-driver-request',
    'version': 1,
    'application_id': applicationId,
    'scenario': <String, Object?>{
      'id': id,
      'rows': rows,
      'columns': columns,
      'deadline_ms': deadlineMs,
      'maximum_output_bytes': maximumOutputBytes,
      'required_fields': <String>[
        for (final TerminalApplicationObservationField field in requiredFields)
          field.name,
      ],
      'checks': checks,
    },
  };
}

final class TerminalApplicationDefinition {
  const TerminalApplicationDefinition({
    required this.id,
    required this.displayName,
    required this.scenarios,
  });

  final String id;
  final String displayName;
  final List<TerminalApplicationScenario> scenarios;
}

final class TerminalApplicationMatrixManifest {
  const TerminalApplicationMatrixManifest({
    required this.version,
    required this.scope,
    required this.observationVersion,
    required this.applications,
  });

  static const int maximumManifestBytes = 1024 * 1024;
  static const int maximumApplications = 16;
  static const int maximumScenarios = 64;
  static const int maximumRows = 256;
  static const int maximumColumns = 512;
  static const int maximumCells = 65536;
  static const int maximumDeadlineMs = 30000;
  static const int maximumOutputBytes = 1024 * 1024;
  static const Set<String> requiredApplicationIds = <String>{
    'emacs',
    'fzf',
    'lazygit',
    'mosh',
    'ncurses',
    'neovim',
    'ssh',
    'tmux',
  };

  final int version;
  final String scope;
  final int observationVersion;
  final List<TerminalApplicationDefinition> applications;

  Iterable<TerminalApplicationScenario> get scenarios sync* {
    for (final TerminalApplicationDefinition application in applications) {
      yield* application.scenarios;
    }
  }

  static TerminalApplicationMatrixManifest load(File source) {
    _expect(source.existsSync(), 'manifest does not exist: ${source.path}');
    _expect(
      FileSystemEntity.typeSync(source.path, followLinks: false) ==
          FileSystemEntityType.file,
      'manifest must be a regular file',
    );
    final int length = source.lengthSync();
    _expect(
      length > 0 && length <= maximumManifestBytes,
      'manifest size $length is outside 1..$maximumManifestBytes',
    );
    return parse(source.readAsStringSync());
  }

  static TerminalApplicationMatrixManifest parse(String source) {
    _expect(
      utf8.encode(source).length <= maximumManifestBytes,
      'manifest exceeds $maximumManifestBytes encoded bytes',
    );
    final Object? decoded;
    try {
      decoded = jsonDecode(source);
    } on Object catch (error) {
      throw TerminalApplicationMatrixException('invalid JSON: $error');
    }
    final Map<String, Object?> root = _object(decoded, 'root');
    _expectKeys(root, const <String>{
      'format',
      'version',
      'scope',
      'observation_version',
      'applications',
    }, 'root');
    _expect(
      root['format'] == 'dart-terminal-real-application-matrix',
      'unsupported manifest format',
    );
    final int version = _integer(root['version'], 'version');
    _expect(version == 1, 'unsupported manifest version $version');
    final String scope = _text(root['scope'], 'scope', 64);
    _expect(scope == 'phase6-reviewed', 'unsupported manifest scope $scope');
    final int observationVersion = _integer(
      root['observation_version'],
      'observation_version',
    );
    _expect(
      observationVersion == TerminalApplicationObservation.formatVersion,
      'unsupported observation version $observationVersion',
    );
    final List<Object?> values = _array(root['applications'], 'applications');
    _expect(
      values.isNotEmpty && values.length <= maximumApplications,
      'application count is outside 1..$maximumApplications',
    );
    final List<TerminalApplicationDefinition> applications =
        <TerminalApplicationDefinition>[];
    final Set<String> applicationIds = <String>{};
    final Set<String> scenarioIds = <String>{};
    String previousApplicationId = '';
    int scenarioCount = 0;
    for (int index = 0; index < values.length; index++) {
      final Map<String, Object?> map = _object(
        values[index],
        'applications[$index]',
      );
      _expectKeys(map, const <String>{
        'id',
        'display_name',
        'scenarios',
      }, 'application');
      final String applicationId = _id(map['id'], 'application.id');
      _expect(
        applicationIds.add(applicationId),
        'duplicate application id $applicationId',
      );
      _expect(
        previousApplicationId.isEmpty ||
            previousApplicationId.compareTo(applicationId) < 0,
        'applications must be sorted by id',
      );
      previousApplicationId = applicationId;
      final String displayName = _text(
        map['display_name'],
        '$applicationId.display_name',
        64,
      );
      final List<Object?> scenarioValues = _array(
        map['scenarios'],
        '$applicationId.scenarios',
      );
      _expect(
        scenarioValues.isNotEmpty && scenarioValues.length <= 16,
        '$applicationId scenario count is outside 1..16',
      );
      final List<TerminalApplicationScenario> scenarios =
          <TerminalApplicationScenario>[];
      String previousScenarioId = '';
      for (
        int scenarioIndex = 0;
        scenarioIndex < scenarioValues.length;
        scenarioIndex++
      ) {
        final TerminalApplicationScenario scenario = _decodeScenario(
          applicationId,
          _object(
            scenarioValues[scenarioIndex],
            '$applicationId.scenarios[$scenarioIndex]',
          ),
        );
        _expect(
          scenarioIds.add(scenario.id),
          'duplicate scenario id ${scenario.id}',
        );
        _expect(
          previousScenarioId.isEmpty ||
              previousScenarioId.compareTo(scenario.id) < 0,
          '$applicationId scenarios must be sorted by id',
        );
        previousScenarioId = scenario.id;
        scenarios.add(scenario);
        scenarioCount++;
        _expect(
          scenarioCount <= maximumScenarios,
          'scenario count exceeds $maximumScenarios',
        );
      }
      applications.add(
        TerminalApplicationDefinition(
          id: applicationId,
          displayName: displayName,
          scenarios: List<TerminalApplicationScenario>.unmodifiable(scenarios),
        ),
      );
    }
    _expect(
      applicationIds.length == requiredApplicationIds.length &&
          applicationIds.containsAll(requiredApplicationIds),
      'manifest must contain exactly the eight required applications',
    );
    return TerminalApplicationMatrixManifest(
      version: version,
      scope: scope,
      observationVersion: observationVersion,
      applications: List<TerminalApplicationDefinition>.unmodifiable(
        applications,
      ),
    );
  }

  static TerminalApplicationScenario _decodeScenario(
    String applicationId,
    Map<String, Object?> map,
  ) {
    _expectKeys(map, const <String>{
      'id',
      'description',
      'rows',
      'columns',
      'deadline_ms',
      'maximum_output_bytes',
      'required_fields',
      'checks',
    }, 'scenario');
    final String id = _id(map['id'], 'scenario.id');
    _expect(
      id.startsWith('$applicationId-'),
      '$id must be prefixed by application id $applicationId',
    );
    final String description = _text(
      map['description'],
      '$id.description',
      256,
    );
    final int rows = _integer(map['rows'], '$id.rows');
    final int columns = _integer(map['columns'], '$id.columns');
    _expect(rows >= 1 && rows <= maximumRows, '$id rows are outside bounds');
    _expect(
      columns >= 1 && columns <= maximumColumns,
      '$id columns are outside bounds',
    );
    _expect(rows * columns <= maximumCells, '$id grid exceeds $maximumCells');
    final int deadlineMs = _integer(map['deadline_ms'], '$id.deadline_ms');
    _expect(
      deadlineMs >= 100 && deadlineMs <= maximumDeadlineMs,
      '$id deadline_ms is outside 100..$maximumDeadlineMs',
    );
    final int outputBytes = _integer(
      map['maximum_output_bytes'],
      '$id.maximum_output_bytes',
    );
    _expect(
      outputBytes >= 1 && outputBytes <= maximumOutputBytes,
      '$id maximum_output_bytes is outside bounds',
    );
    final List<Object?> fieldValues = _array(
      map['required_fields'],
      '$id.required_fields',
    );
    _expect(fieldValues.isNotEmpty, '$id required_fields cannot be empty');
    final List<TerminalApplicationObservationField> fields =
        <TerminalApplicationObservationField>[];
    int previousField = -1;
    for (int index = 0; index < fieldValues.length; index++) {
      final TerminalApplicationObservationField field = _field(
        _text(fieldValues[index], '$id.required_fields[$index]', 16),
        '$id.required_fields[$index]',
      );
      _expect(
        field.index > previousField,
        '$id required_fields must follow canonical order and be unique',
      );
      previousField = field.index;
      fields.add(field);
    }
    _expect(
      fields.contains(TerminalApplicationObservationField.stream) &&
          fields.contains(TerminalApplicationObservationField.screen) &&
          fields.contains(TerminalApplicationObservationField.exit),
      '$id must observe stream, screen, and exit',
    );
    final List<Object?> checkValues = _array(map['checks'], '$id.checks');
    _expect(
      checkValues.isNotEmpty && checkValues.length <= 32,
      '$id check count is outside 1..32',
    );
    final List<String> checks = <String>[];
    String previousCheck = '';
    for (int index = 0; index < checkValues.length; index++) {
      final String check = _id(checkValues[index], '$id.checks[$index]');
      _expect(
        previousCheck.isEmpty || previousCheck.compareTo(check) < 0,
        '$id checks must be sorted and unique',
      );
      previousCheck = check;
      checks.add(check);
    }
    return TerminalApplicationScenario(
      applicationId: applicationId,
      id: id,
      description: description,
      rows: rows,
      columns: columns,
      deadlineMs: deadlineMs,
      maximumOutputBytes: outputBytes,
      requiredFields: List<TerminalApplicationObservationField>.unmodifiable(
        fields,
      ),
      checks: List<String>.unmodifiable(checks),
    );
  }
}

final class TerminalApplicationProvenance {
  const TerminalApplicationProvenance({
    required this.product,
    required this.productVersion,
    required this.executableSha256,
    required this.configId,
    required this.configSha256,
    required this.captureMethod,
    required this.operatingSystem,
    required this.architecture,
  });

  final String product;
  final String productVersion;
  final String executableSha256;
  final String configId;
  final String configSha256;
  final String captureMethod;
  final String operatingSystem;
  final String architecture;

  Map<String, Object?> toJson() => <String, Object?>{
    'product': product,
    'product_version': productVersion,
    'executable_sha256': executableSha256,
    'config_id': configId,
    'config_sha256': configSha256,
    'capture_method': captureMethod,
    'os': operatingSystem,
    'architecture': architecture,
  };

  static TerminalApplicationProvenance parse(Object? value, String context) {
    final Map<String, Object?> map = _object(value, context);
    _expectKeys(map, const <String>{
      'product',
      'product_version',
      'executable_sha256',
      'config_id',
      'config_sha256',
      'capture_method',
      'os',
      'architecture',
    }, context);
    return TerminalApplicationProvenance(
      product: _id(map['product'], '$context.product'),
      productVersion: _text(
        map['product_version'],
        '$context.product_version',
        96,
      ),
      executableSha256: _sha256(
        map['executable_sha256'],
        '$context.executable_sha256',
      ),
      configId: _id(map['config_id'], '$context.config_id'),
      configSha256: _sha256(map['config_sha256'], '$context.config_sha256'),
      captureMethod: _id(map['capture_method'], '$context.capture_method'),
      operatingSystem: _id(map['os'], '$context.os'),
      architecture: _token(map['architecture'], '$context.architecture'),
    );
  }
}

final class TerminalApplicationCheckResult {
  const TerminalApplicationCheckResult({
    required this.id,
    required this.passed,
  });

  final String id;
  final bool passed;

  Map<String, Object?> toJson() => <String, Object?>{
    'id': id,
    'passed': passed,
  };
}

final class TerminalApplicationObservation {
  const TerminalApplicationObservation({
    required this.applicationId,
    required this.scenarioId,
    required this.driverId,
    required this.provenance,
    required this.capturedFields,
    required this.outputBytes,
    required this.outputSha256,
    required this.rawEvidenceSha256,
    required this.checks,
  });

  static const String formatName = 'dart-terminal-application-observation';
  static const int formatVersion = 1;
  static const int maximumEncodedBytes = 256 * 1024;

  final String applicationId;
  final String scenarioId;
  final String driverId;
  final TerminalApplicationProvenance provenance;
  final List<TerminalApplicationObservationField> capturedFields;
  final int outputBytes;
  final String outputSha256;
  final String rawEvidenceSha256;
  final List<TerminalApplicationCheckResult> checks;

  bool get passed =>
      checks.every((TerminalApplicationCheckResult result) => result.passed);

  String encode() =>
      '${jsonEncode(<String, Object?>{
        'format': formatName,
        'version': formatVersion,
        'application_id': applicationId,
        'scenario_id': scenarioId,
        'driver_id': driverId,
        'provenance': provenance.toJson(),
        'captured_fields': <String>[for (final TerminalApplicationObservationField field in capturedFields) field.name],
        'output_bytes': outputBytes,
        'output_sha256': outputSha256,
        'raw_evidence_sha256': rawEvidenceSha256,
        'checks': <Object?>[for (final TerminalApplicationCheckResult result in checks) result.toJson()],
      })}\n';

  static TerminalApplicationObservation parse(
    String source, {
    required TerminalApplicationScenario scenario,
  }) {
    _expect(
      utf8.encode(source).length <= maximumEncodedBytes,
      'observation exceeds $maximumEncodedBytes encoded bytes',
    );
    final Object? decoded;
    try {
      decoded = jsonDecode(source);
    } on Object catch (error) {
      throw TerminalApplicationMatrixException(
        'invalid observation JSON: $error',
      );
    }
    final Map<String, Object?> root = _object(decoded, 'observation root');
    _expectKeys(root, const <String>{
      'format',
      'version',
      'application_id',
      'scenario_id',
      'driver_id',
      'provenance',
      'captured_fields',
      'output_bytes',
      'output_sha256',
      'raw_evidence_sha256',
      'checks',
    }, 'observation root');
    _expect(root['format'] == formatName, 'unsupported observation format');
    _expect(
      root['version'] == formatVersion,
      'unsupported observation version',
    );
    final String applicationId = _id(root['application_id'], 'application_id');
    final String scenarioId = _id(root['scenario_id'], 'scenario_id');
    _expect(
      applicationId == scenario.applicationId,
      'observation application_id differs from request',
    );
    _expect(
      scenarioId == scenario.id,
      'observation scenario_id differs from request',
    );
    final List<Object?> fieldValues = _array(
      root['captured_fields'],
      'captured_fields',
    );
    final List<TerminalApplicationObservationField> capturedFields =
        <TerminalApplicationObservationField>[];
    for (int index = 0; index < fieldValues.length; index++) {
      capturedFields.add(
        _field(
          _text(fieldValues[index], 'captured_fields[$index]', 16),
          'captured_fields[$index]',
        ),
      );
    }
    _expect(
      _fieldListsEqual(capturedFields, scenario.requiredFields),
      'captured_fields differ from required_fields',
    );
    final int outputBytes = _integer(root['output_bytes'], 'output_bytes');
    _expect(
      outputBytes >= 1 && outputBytes <= scenario.maximumOutputBytes,
      'output_bytes are outside scenario bounds',
    );
    final List<Object?> checkValues = _array(root['checks'], 'checks');
    _expect(
      checkValues.length == scenario.checks.length,
      'check count differs from scenario',
    );
    final List<TerminalApplicationCheckResult> checks =
        <TerminalApplicationCheckResult>[];
    for (int index = 0; index < checkValues.length; index++) {
      final Map<String, Object?> map = _object(
        checkValues[index],
        'checks[$index]',
      );
      _expectKeys(map, const <String>{'id', 'passed'}, 'checks[$index]');
      final String id = _id(map['id'], 'checks[$index].id');
      _expect(
        id == scenario.checks[index],
        'check id/order differs from scenario',
      );
      checks.add(
        TerminalApplicationCheckResult(
          id: id,
          passed: _boolean(map['passed'], 'checks[$index].passed'),
        ),
      );
    }
    return TerminalApplicationObservation(
      applicationId: applicationId,
      scenarioId: scenarioId,
      driverId: _id(root['driver_id'], 'driver_id'),
      provenance: TerminalApplicationProvenance.parse(
        root['provenance'],
        'provenance',
      ),
      capturedFields: List<TerminalApplicationObservationField>.unmodifiable(
        capturedFields,
      ),
      outputBytes: outputBytes,
      outputSha256: _sha256(root['output_sha256'], 'output_sha256'),
      rawEvidenceSha256: _sha256(
        root['raw_evidence_sha256'],
        'raw_evidence_sha256',
      ),
      checks: List<TerminalApplicationCheckResult>.unmodifiable(checks),
    );
  }
}

final class TerminalApplicationDriverResult {
  const TerminalApplicationDriverResult({
    required this.status,
    required this.observation,
    required this.exitCode,
    required this.stdoutBytes,
    required this.stderrBytes,
  });

  final TerminalApplicationDriverStatus status;
  final TerminalApplicationObservation? observation;
  final int? exitCode;
  final int stdoutBytes;
  final int stderrBytes;

  String machineLine(TerminalApplicationScenario scenario) =>
      'TERMINAL_APPLICATION_DRIVER application=${scenario.applicationId} '
      'scenario=${scenario.id} status=${status.name} '
      'exit_code=${exitCode ?? -1} stdout_bytes=$stdoutBytes '
      'stderr_bytes=$stderrBytes';
}

final class TerminalApplicationSubprocessDriver {
  const TerminalApplicationSubprocessDriver({
    this.timeout = const Duration(seconds: 35),
    this.maximumOutputBytes =
        TerminalApplicationObservation.maximumEncodedBytes,
    this.maximumStderrBytes = 64 * 1024,
  });

  final Duration timeout;
  final int maximumOutputBytes;
  final int maximumStderrBytes;

  Future<TerminalApplicationDriverResult> run({
    required String executable,
    required List<String> arguments,
    required TerminalApplicationScenario scenario,
    String? workingDirectory,
  }) async {
    if (timeout <= Duration.zero || timeout > const Duration(minutes: 2)) {
      throw ArgumentError.value(timeout, 'timeout');
    }
    if (maximumOutputBytes < 1 ||
        maximumOutputBytes >
            TerminalApplicationObservation.maximumEncodedBytes) {
      throw ArgumentError.value(maximumOutputBytes, 'maximumOutputBytes');
    }
    if (maximumStderrBytes < 0 || maximumStderrBytes > 1024 * 1024) {
      throw ArgumentError.value(maximumStderrBytes, 'maximumStderrBytes');
    }
    if (!executable.startsWith('/') ||
        executable.length > 4096 ||
        _hasNul(executable)) {
      throw ArgumentError.value(executable, 'executable');
    }
    if (arguments.length > 32 ||
        arguments.any(
          (String value) => value.length > 4096 || _hasNul(value),
        )) {
      throw ArgumentError.value(arguments, 'arguments');
    }
    if (!File(executable).existsSync()) {
      return const TerminalApplicationDriverResult(
        status: TerminalApplicationDriverStatus.unavailable,
        observation: null,
        exitCode: null,
        stdoutBytes: 0,
        stderrBytes: 0,
      );
    }
    final Process process;
    try {
      process = await Process.start(
        executable,
        arguments,
        workingDirectory: workingDirectory,
        runInShell: false,
        mode: ProcessStartMode.normal,
      );
    } on ProcessException {
      return const TerminalApplicationDriverResult(
        status: TerminalApplicationDriverStatus.startFailure,
        observation: null,
        exitCode: null,
        stdoutBytes: 0,
        stderrBytes: 0,
      );
    }
    final _BoundedByteCollector stdoutCollector = _BoundedByteCollector(
      maximumOutputBytes,
      onOverflow: () => process.kill(ProcessSignal.sigkill),
    );
    final _BoundedByteCollector stderrCollector = _BoundedByteCollector(
      maximumStderrBytes,
      onOverflow: () => process.kill(ProcessSignal.sigkill),
    );
    final Future<void> stdoutDone = stdoutCollector.collect(process.stdout);
    final Future<void> stderrDone = stderrCollector.collect(process.stderr);
    try {
      process.stdin.add(
        utf8.encode('${jsonEncode(scenario.toDriverRequest())}\n'),
      );
      await process.stdin.close();
    } on Object {
      process.kill(ProcessSignal.sigkill);
    }
    final int exitCode;
    try {
      exitCode = await process.exitCode.timeout(
        timeout,
        onTimeout: () {
          process.kill(ProcessSignal.sigkill);
          throw TimeoutException('application matrix driver deadline');
        },
      );
    } on TimeoutException {
      await _boundedDrain(stdoutDone, stderrDone);
      return TerminalApplicationDriverResult(
        status: TerminalApplicationDriverStatus.timedOut,
        observation: null,
        exitCode: null,
        stdoutBytes: stdoutCollector.length,
        stderrBytes: stderrCollector.length,
      );
    }
    if (!await _boundedDrain(stdoutDone, stderrDone)) {
      process.kill(ProcessSignal.sigkill);
      return TerminalApplicationDriverResult(
        status: TerminalApplicationDriverStatus.timedOut,
        observation: null,
        exitCode: exitCode,
        stdoutBytes: stdoutCollector.length,
        stderrBytes: stderrCollector.length,
      );
    }
    if (stdoutCollector.overflowed || stderrCollector.overflowed) {
      return TerminalApplicationDriverResult(
        status: TerminalApplicationDriverStatus.outputLimit,
        observation: null,
        exitCode: exitCode,
        stdoutBytes: stdoutCollector.length,
        stderrBytes: stderrCollector.length,
      );
    }
    if (exitCode != 0) {
      return TerminalApplicationDriverResult(
        status: TerminalApplicationDriverStatus.crashed,
        observation: null,
        exitCode: exitCode,
        stdoutBytes: stdoutCollector.length,
        stderrBytes: stderrCollector.length,
      );
    }
    final TerminalApplicationObservation observation;
    try {
      observation = TerminalApplicationObservation.parse(
        utf8.decode(stdoutCollector.bytes, allowMalformed: false),
        scenario: scenario,
      );
    } on Object {
      return TerminalApplicationDriverResult(
        status: TerminalApplicationDriverStatus.protocolError,
        observation: null,
        exitCode: exitCode,
        stdoutBytes: stdoutCollector.length,
        stderrBytes: stderrCollector.length,
      );
    }
    return TerminalApplicationDriverResult(
      status: TerminalApplicationDriverStatus.ok,
      observation: observation,
      exitCode: exitCode,
      stdoutBytes: stdoutCollector.length,
      stderrBytes: stderrCollector.length,
    );
  }
}

final class TerminalApplicationMatrixContractResult {
  const TerminalApplicationMatrixContractResult({
    required this.applications,
    required this.scenarios,
    required this.requiredFields,
    required this.checks,
  });

  final int applications;
  final int scenarios;
  final int requiredFields;
  final int checks;

  String machineLine() =>
      'TERMINAL_APPLICATION_MATRIX_CONTRACT_PASS '
      'applications=$applications scenarios=$scenarios '
      'required_fields=$requiredFields checks=$checks';
}

TerminalApplicationMatrixContractResult
runTerminalApplicationMatrixContractChecks({Directory? repositoryRoot}) {
  final Directory root = repositoryRoot ?? Directory.current.absolute;
  final TerminalApplicationMatrixManifest manifest =
      TerminalApplicationMatrixManifest.load(
        File.fromUri(root.uri.resolve(defaultTerminalApplicationMatrixPath)),
      );
  final List<TerminalApplicationScenario> scenarios = manifest.scenarios
      .toList();
  final int fieldCount = scenarios.fold<int>(
    0,
    (int total, TerminalApplicationScenario scenario) =>
        total + scenario.requiredFields.length,
  );
  final int checkCount = scenarios.fold<int>(
    0,
    (int total, TerminalApplicationScenario scenario) =>
        total + scenario.checks.length,
  );
  _expect(
    manifest.applications.length == 8 &&
        scenarios.length == 8 &&
        fieldCount == 48 &&
        checkCount == 48,
    'reviewed matrix contract totals differ',
  );
  for (final TerminalApplicationScenario scenario in scenarios) {
    final Map<String, Object?> request = _object(
      scenario.toDriverRequest(),
      'driver request',
    );
    _expect(
      request['application_id'] == scenario.applicationId &&
          _object(request['scenario'], 'scenario')['id'] == scenario.id,
      '${scenario.id} driver request identity differs',
    );
  }
  return TerminalApplicationMatrixContractResult(
    applications: manifest.applications.length,
    scenarios: scenarios.length,
    requiredFields: fieldCount,
    checks: checkCount,
  );
}

final class _BoundedByteCollector {
  _BoundedByteCollector(this.maximumBytes, {required this.onOverflow});

  final int maximumBytes;
  final bool Function() onOverflow;
  final BytesBuilder _bytes = BytesBuilder(copy: false);
  bool overflowed = false;

  int get length => _bytes.length;
  Uint8List get bytes => _bytes.toBytes();

  Future<void> collect(Stream<List<int>> stream) {
    final Completer<void> done = Completer<void>();
    late final StreamSubscription<List<int>> subscription;
    subscription = stream.listen(
      (List<int> chunk) {
        if (overflowed) return;
        final int remaining = maximumBytes - _bytes.length;
        if (chunk.length > remaining) {
          if (remaining > 0) _bytes.add(chunk.sublist(0, remaining));
          overflowed = true;
          onOverflow();
          return;
        }
        _bytes.add(chunk);
      },
      onError: (Object error, StackTrace stackTrace) {
        if (!done.isCompleted) done.completeError(error, stackTrace);
      },
      onDone: () {
        if (!done.isCompleted) done.complete();
      },
      cancelOnError: true,
    );
    return done.future.whenComplete(subscription.cancel);
  }
}

Future<bool> _boundedDrain(Future<void> stdout, Future<void> stderr) async {
  try {
    await Future.wait<void>(<Future<void>>[stdout, stderr])
        .timeout(const Duration(seconds: 2));
    return true;
  } on TimeoutException {
    return false;
  }
}

bool _fieldListsEqual(
  List<TerminalApplicationObservationField> left,
  List<TerminalApplicationObservationField> right,
) {
  if (left.length != right.length) return false;
  for (int index = 0; index < left.length; index++) {
    if (left[index] != right[index]) return false;
  }
  return true;
}

TerminalApplicationObservationField _field(String value, String context) {
  for (final TerminalApplicationObservationField field
      in TerminalApplicationObservationField.values) {
    if (field.name == value) return field;
  }
  throw TerminalApplicationMatrixException('$context has unknown field $value');
}

Map<String, Object?> _object(Object? value, String context) {
  if (value is! Map<Object?, Object?>) {
    throw TerminalApplicationMatrixException('$context must be an object');
  }
  final Map<String, Object?> result = <String, Object?>{};
  for (final MapEntry<Object?, Object?> entry in value.entries) {
    if (entry.key is! String) {
      throw TerminalApplicationMatrixException('$context has a non-string key');
    }
    result[entry.key! as String] = entry.value;
  }
  return result;
}

List<Object?> _array(Object? value, String context) {
  if (value is! List<Object?>) {
    throw TerminalApplicationMatrixException('$context must be an array');
  }
  return value;
}

String _text(Object? value, String context, int maximumLength) {
  if (value is! String ||
      value.isEmpty ||
      value.length > maximumLength ||
      _hasNul(value)) {
    throw TerminalApplicationMatrixException('$context is invalid text');
  }
  return value;
}

String _id(Object? value, String context) {
  final String text = _text(value, context, 96);
  if (!RegExp(r'^[a-z0-9]+(?:-[a-z0-9]+)*$').hasMatch(text)) {
    throw TerminalApplicationMatrixException('$context is not an identifier');
  }
  return text;
}

String _token(Object? value, String context) {
  final String text = _text(value, context, 96);
  if (!RegExp(r'^[A-Za-z0-9._+-]+$').hasMatch(text)) {
    throw TerminalApplicationMatrixException('$context is not a token');
  }
  return text;
}

String _sha256(Object? value, String context) {
  final String text = _text(value, context, 64);
  if (!RegExp(r'^[0-9a-f]{64}$').hasMatch(text)) {
    throw TerminalApplicationMatrixException('$context is not SHA-256');
  }
  return text;
}

int _integer(Object? value, String context) {
  if (value is! int) {
    throw TerminalApplicationMatrixException('$context must be an integer');
  }
  return value;
}

bool _boolean(Object? value, String context) {
  if (value is! bool) {
    throw TerminalApplicationMatrixException('$context must be a boolean');
  }
  return value;
}

void _expectKeys(
  Map<String, Object?> value,
  Set<String> expected,
  String context,
) {
  final Set<String> actual = value.keys.toSet();
  if (actual.length != expected.length || !actual.containsAll(expected)) {
    throw TerminalApplicationMatrixException('$context keys differ');
  }
}

bool _hasNul(String value) => value.codeUnits.contains(0);

void _expect(bool condition, String message) {
  if (!condition) throw TerminalApplicationMatrixException(message);
}

void main(List<String> arguments) {
  try {
    if (arguments.isNotEmpty &&
        !(arguments.length == 1 && arguments.single == '--check')) {
      throw const TerminalApplicationMatrixException(
        'usage: terminal_application_matrix.dart [--check]',
      );
    }
    stdout.writeln(runTerminalApplicationMatrixContractChecks().machineLine());
  } on Object catch (error) {
    stderr.writeln('TERMINAL_APPLICATION_MATRIX_CONTRACT_FAIL $error');
    exitCode = 1;
  }
}
