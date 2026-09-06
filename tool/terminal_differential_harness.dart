import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dart_terminal/dart_terminal.dart';

import 'terminal_compatibility_inventory.dart';

const String defaultTerminalDifferentialManifestPath =
    'test/corpus/differential/contract_v1.json';

enum TerminalDifferentialField {
  screen,
  text,
  style,
  color,
  wrap,
  cursor,
  modes,
  replies,
}

enum TerminalDifferentialExpectation { agree, documentedGap }

enum TerminalDifferentialDriverStatus {
  ok,
  unavailable,
  startFailure,
  timedOut,
  crashed,
  outputLimit,
  protocolError,
}

final class TerminalDifferentialException implements FormatException {
  const TerminalDifferentialException(this.message);

  @override
  final String message;

  @override
  int? get offset => null;

  @override
  Object? get source => null;

  @override
  String toString() => 'TerminalDifferentialException: $message';
}

final class TerminalDifferentialCase {
  const TerminalDifferentialCase({
    required this.id,
    required this.description,
    required this.inventoryIds,
    required this.input,
    required this.rows,
    required this.columns,
    required this.fields,
    required this.expectation,
    required this.gapOwner,
  });

  final String id;
  final String description;
  final List<String> inventoryIds;
  final Uint8List input;
  final int rows;
  final int columns;
  final List<TerminalDifferentialField> fields;
  final TerminalDifferentialExpectation expectation;
  final String? gapOwner;

  Map<String, Object?> toDriverRequest() => <String, Object?>{
    'format': 'dart-terminal-differential-driver-request',
    'version': 1,
    'case': <String, Object?>{
      'id': id,
      'input_hex': _encodeHex(input),
      'rows': rows,
      'columns': columns,
      'initial_state': 'power-on',
      'fields': <String>[
        for (final TerminalDifferentialField field in fields) field.name,
      ],
    },
  };
}

final class TerminalDifferentialManifest {
  const TerminalDifferentialManifest({
    required this.version,
    required this.scope,
    required this.observationVersion,
    required this.cases,
  });

  static const int maximumManifestBytes = 1024 * 1024;
  static const int maximumCases = 128;
  static const int maximumInputBytesPerCase = 16 * 1024;
  static const int maximumAggregateInputBytes = 64 * 1024;
  static const int maximumAggregateSplitRuns = 65536;
  static const int maximumRows = 256;
  static const int maximumColumns = 512;
  static const int maximumCells = 65536;

  final int version;
  final String scope;
  final int observationVersion;
  final List<TerminalDifferentialCase> cases;

  static TerminalDifferentialManifest load(
    File source, {
    required Set<String> inventoryIds,
  }) {
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
    return parse(source.readAsStringSync(), inventoryIds: inventoryIds);
  }

  static TerminalDifferentialManifest parse(
    String source, {
    required Set<String> inventoryIds,
  }) {
    _expect(
      utf8.encode(source).length <= maximumManifestBytes,
      'manifest exceeds $maximumManifestBytes encoded bytes',
    );
    final Object? decoded;
    try {
      decoded = jsonDecode(source);
    } on Object catch (error) {
      throw TerminalDifferentialException('invalid JSON: $error');
    }
    final Map<String, Object?> root = _object(decoded, 'root');
    _expectKeys(root, const <String>{
      'format',
      'version',
      'scope',
      'observation_version',
      'cases',
    }, 'root');
    _expect(
      root['format'] == 'dart-terminal-black-box-differential',
      'unsupported manifest format',
    );
    final int version = _integer(root['version'], 'version');
    _expect(version == 1, 'unsupported manifest version $version');
    final String scope = _text(root['scope'], 'scope', 64);
    _expect(
      scope == 'contract-smoke' || scope == 'reviewed-corpus',
      'unsupported manifest scope $scope',
    );
    final int observationVersion = _integer(
      root['observation_version'],
      'observation_version',
    );
    _expect(
      observationVersion == TerminalDifferentialObservation.formatVersion,
      'unsupported observation version $observationVersion',
    );
    final List<Object?> values = _array(root['cases'], 'cases');
    _expect(
      values.isNotEmpty && values.length <= maximumCases,
      'case count ${values.length} is outside 1..$maximumCases',
    );
    final List<TerminalDifferentialCase> cases = <TerminalDifferentialCase>[];
    final Set<String> ids = <String>{};
    int aggregateInputBytes = 0;
    int aggregateSplitRuns = 0;
    String previousId = '';
    for (int index = 0; index < values.length; index++) {
      final TerminalDifferentialCase testCase = _decodeCase(
        _object(values[index], 'cases[$index]'),
        inventoryIds,
      );
      _expect(ids.add(testCase.id), 'duplicate case id ${testCase.id}');
      _expect(
        previousId.isEmpty || previousId.compareTo(testCase.id) < 0,
        'cases must be sorted by id',
      );
      previousId = testCase.id;
      aggregateInputBytes += testCase.input.length;
      aggregateSplitRuns += testCase.input.length + 2;
      _expect(
        aggregateInputBytes <= maximumAggregateInputBytes,
        'aggregate input exceeds $maximumAggregateInputBytes bytes',
      );
      _expect(
        aggregateSplitRuns <= maximumAggregateSplitRuns,
        'aggregate split runs exceed $maximumAggregateSplitRuns',
      );
      cases.add(testCase);
    }
    return TerminalDifferentialManifest(
      version: version,
      scope: scope,
      observationVersion: observationVersion,
      cases: List<TerminalDifferentialCase>.unmodifiable(cases),
    );
  }

  static TerminalDifferentialCase _decodeCase(
    Map<String, Object?> map,
    Set<String> inventoryIds,
  ) {
    _expectKeys(map, const <String>{
      'id',
      'description',
      'inventory_ids',
      'input_hex',
      'rows',
      'columns',
      'fields',
      'expectation',
      'gap_owner',
    }, 'case');
    final String id = _id(map['id'], 'case.id');
    final String description = _text(
      map['description'],
      '$id.description',
      256,
    );
    final List<Object?> inventoryValues = _array(
      map['inventory_ids'],
      '$id.inventory_ids',
    );
    _expect(
      inventoryValues.isNotEmpty && inventoryValues.length <= 32,
      '$id inventory_ids count is outside 1..32',
    );
    final List<String> caseInventoryIds = <String>[];
    String previousInventoryId = '';
    for (int index = 0; index < inventoryValues.length; index++) {
      final String value = _text(
        inventoryValues[index],
        '$id.inventory_ids[$index]',
        96,
      );
      _expect(
        inventoryIds.contains(value),
        '$id references unknown inventory id $value',
      );
      _expect(
        previousInventoryId.isEmpty || previousInventoryId.compareTo(value) < 0,
        '$id inventory_ids must be sorted and unique',
      );
      previousInventoryId = value;
      caseInventoryIds.add(value);
    }
    final Uint8List input = _decodeHex(
      _text(map['input_hex'], '$id.input_hex', maximumInputBytesPerCase * 3),
      '$id.input_hex',
      maximumBytes: maximumInputBytesPerCase,
      allowEmpty: false,
    );
    final int rows = _integer(map['rows'], '$id.rows');
    final int columns = _integer(map['columns'], '$id.columns');
    _expect(
      rows >= 1 && rows <= maximumRows,
      '$id rows are outside 1..$maximumRows',
    );
    _expect(
      columns >= 1 && columns <= maximumColumns,
      '$id columns are outside 1..$maximumColumns',
    );
    _expect(
      rows * columns <= maximumCells,
      '$id grid exceeds $maximumCells cells',
    );
    final List<Object?> fieldValues = _array(map['fields'], '$id.fields');
    _expect(
      fieldValues.isNotEmpty &&
          fieldValues.length <= TerminalDifferentialField.values.length,
      '$id fields count is invalid',
    );
    final List<TerminalDifferentialField> fields =
        <TerminalDifferentialField>[];
    int previousField = -1;
    for (int index = 0; index < fieldValues.length; index++) {
      final TerminalDifferentialField field = _field(
        _text(fieldValues[index], '$id.fields[$index]', 16),
        '$id.fields[$index]',
      );
      _expect(
        field.index > previousField,
        '$id fields must follow canonical order and be unique',
      );
      previousField = field.index;
      fields.add(field);
    }
    final TerminalDifferentialExpectation expectation = switch (_text(
      map['expectation'],
      '$id.expectation',
      32,
    )) {
      'agree' => TerminalDifferentialExpectation.agree,
      'documented-gap' => TerminalDifferentialExpectation.documentedGap,
      final String value => throw TerminalDifferentialException(
        '$id has unknown expectation $value',
      ),
    };
    final String? gapOwner = switch (map['gap_owner']) {
      null => null,
      final Object? value => _text(value, '$id.gap_owner', 160),
    };
    if (expectation == TerminalDifferentialExpectation.agree) {
      _expect(gapOwner == null, '$id agree expectation cannot have gap_owner');
    } else {
      _expect(
        gapOwner != null && _safeRelativeMarkdownPath(gapOwner),
        '$id documented-gap requires a safe docs gap_owner',
      );
    }
    return TerminalDifferentialCase(
      id: id,
      description: description,
      inventoryIds: List<String>.unmodifiable(caseInventoryIds),
      input: Uint8List.fromList(input),
      rows: rows,
      columns: columns,
      fields: List<TerminalDifferentialField>.unmodifiable(fields),
      expectation: expectation,
      gapOwner: gapOwner,
    );
  }
}

final class TerminalDifferentialProvenance {
  const TerminalDifferentialProvenance({
    required this.product,
    required this.productVersion,
    required this.implementationRevision,
    required this.executableSha256,
    required this.configId,
    required this.configSha256,
    required this.captureMethod,
    required this.operatingSystem,
    required this.architecture,
  });

  final String product;
  final String productVersion;
  final String implementationRevision;
  final String? executableSha256;
  final String configId;
  final String configSha256;
  final String captureMethod;
  final String operatingSystem;
  final String architecture;

  Map<String, Object?> toJson() => <String, Object?>{
    'product': product,
    'product_version': productVersion,
    'implementation_revision': implementationRevision,
    'executable_sha256': executableSha256,
    'config_id': configId,
    'config_sha256': configSha256,
    'capture_method': captureMethod,
    'os': operatingSystem,
    'architecture': architecture,
  };

  static TerminalDifferentialProvenance parse(Object? value, String context) {
    final Map<String, Object?> map = _object(value, context);
    _expectKeys(map, const <String>{
      'product',
      'product_version',
      'implementation_revision',
      'executable_sha256',
      'config_id',
      'config_sha256',
      'capture_method',
      'os',
      'architecture',
    }, context);
    final String product = _id(map['product'], '$context.product');
    final String productVersion = _text(
      map['product_version'],
      '$context.product_version',
      96,
    );
    final String implementationRevision = _text(
      map['implementation_revision'],
      '$context.implementation_revision',
      128,
    );
    final String? executableSha256 = switch (map['executable_sha256']) {
      null => null,
      final Object? hash => _sha256(hash, '$context.executable_sha256'),
    };
    _expect(
      product == 'dart-terminal' || executableSha256 != null,
      '$context external product requires executable_sha256',
    );
    return TerminalDifferentialProvenance(
      product: product,
      productVersion: productVersion,
      implementationRevision: implementationRevision,
      executableSha256: executableSha256,
      configId: _id(map['config_id'], '$context.config_id'),
      configSha256: _sha256(map['config_sha256'], '$context.config_sha256'),
      captureMethod: _id(map['capture_method'], '$context.capture_method'),
      operatingSystem: _id(map['os'], '$context.os'),
      architecture: _token(map['architecture'], '$context.architecture'),
    );
  }
}

final class TerminalDifferentialCell {
  const TerminalDifferentialCell({
    required this.text,
    required this.width,
    required this.style,
    required this.foreground,
    required this.background,
  });

  final String text;
  final int width;
  final int style;
  final int foreground;
  final int background;

  Map<String, Object?> toJson() => <String, Object?>{
    'text': text,
    'width': width,
    'style': style,
    'foreground': foreground,
    'background': background,
  };
}

final class TerminalDifferentialRow {
  const TerminalDifferentialRow({required this.wrapped, required this.cells});

  final bool wrapped;
  final List<TerminalDifferentialCell> cells;

  Map<String, Object?> toJson() => <String, Object?>{
    'wrapped': wrapped,
    'cells': <Object?>[
      for (final TerminalDifferentialCell cell in cells) cell.toJson(),
    ],
  };
}

final class TerminalDifferentialCursor {
  const TerminalDifferentialCursor({
    required this.row,
    required this.column,
    required this.visible,
    required this.blinking,
    required this.shape,
  });

  final int row;
  final int column;
  final bool visible;
  final bool blinking;
  final String shape;

  Map<String, Object?> toJson() => <String, Object?>{
    'row': row,
    'column': column,
    'visible': visible,
    'blinking': blinking,
    'shape': shape,
  };
}

final class TerminalDifferentialObservation {
  const TerminalDifferentialObservation({
    required this.caseId,
    required this.backendId,
    required this.provenance,
    required this.activeScreen,
    required this.rows,
    required this.cursor,
    required this.modes,
    required this.replies,
  });

  static const String formatName = 'dart-terminal-differential-observation';
  static const int formatVersion = 1;
  static const int maximumEncodedBytes = 8 * 1024 * 1024;
  static const int maximumRepliesBytes = 4096;
  static const Set<String> modeKeys = <String>{
    'application_cursor',
    'application_keypad',
    'autowrap',
    'bracketed_paste',
    'horizontal_margins',
    'insert',
    'mouse_encoding',
    'mouse_tracking',
    'origin',
    'reverse_video',
  };

  final String caseId;
  final String backendId;
  final TerminalDifferentialProvenance provenance;
  final String activeScreen;
  final List<TerminalDifferentialRow> rows;
  final TerminalDifferentialCursor cursor;
  final Map<String, Object?> modes;
  final Uint8List replies;

  String encode() => '${jsonEncode(toJson())}\n';

  Map<String, Object?> toJson() => <String, Object?>{
    'format': formatName,
    'version': formatVersion,
    'case_id': caseId,
    'backend_id': backendId,
    'provenance': provenance.toJson(),
    'observation': <String, Object?>{
      'active_screen': activeScreen,
      'rows': <Object?>[
        for (final TerminalDifferentialRow row in rows) row.toJson(),
      ],
      'cursor': cursor.toJson(),
      'modes': modes,
      'replies_hex': _encodeHex(replies),
    },
  };

  static TerminalDifferentialObservation parse(
    String source, {
    required TerminalDifferentialCase testCase,
  }) {
    _expect(
      utf8.encode(source).length <= maximumEncodedBytes,
      'observation exceeds $maximumEncodedBytes bytes',
    );
    final Object? decoded;
    try {
      decoded = jsonDecode(source);
    } on Object catch (error) {
      throw TerminalDifferentialException('invalid observation JSON: $error');
    }
    final Map<String, Object?> root = _object(decoded, 'observation root');
    _expectKeys(root, const <String>{
      'format',
      'version',
      'case_id',
      'backend_id',
      'provenance',
      'observation',
    }, 'observation root');
    _expect(root['format'] == formatName, 'unsupported observation format');
    _expect(
      root['version'] == formatVersion,
      'unsupported observation version',
    );
    final String caseId = _id(root['case_id'], 'case_id');
    _expect(caseId == testCase.id, 'observation case_id differs from request');
    final String backendId = _id(root['backend_id'], 'backend_id');
    final TerminalDifferentialProvenance provenance =
        TerminalDifferentialProvenance.parse(root['provenance'], 'provenance');
    final Map<String, Object?> observation = _object(
      root['observation'],
      'observation',
    );
    _expectKeys(observation, const <String>{
      'active_screen',
      'rows',
      'cursor',
      'modes',
      'replies_hex',
    }, 'observation');
    final String activeScreen = _text(
      observation['active_screen'],
      'active_screen',
      16,
    );
    _expect(
      activeScreen == 'primary' || activeScreen == 'alternate',
      'active_screen must be primary or alternate',
    );
    final List<Object?> rowValues = _array(observation['rows'], 'rows');
    _expect(rowValues.length == testCase.rows, 'observation row count differs');
    final List<TerminalDifferentialRow> rows = <TerminalDifferentialRow>[];
    for (int row = 0; row < rowValues.length; row++) {
      final Map<String, Object?> rowMap = _object(rowValues[row], 'rows[$row]');
      _expectKeys(rowMap, const <String>{'wrapped', 'cells'}, 'rows[$row]');
      final bool wrapped = _boolean(rowMap['wrapped'], 'rows[$row].wrapped');
      final List<Object?> cellValues = _array(
        rowMap['cells'],
        'rows[$row].cells',
      );
      _expect(
        cellValues.length == testCase.columns,
        'observation column count differs at row $row',
      );
      final List<TerminalDifferentialCell> cells = <TerminalDifferentialCell>[];
      for (int column = 0; column < cellValues.length; column++) {
        final String context = 'rows[$row].cells[$column]';
        final Map<String, Object?> cell = _object(cellValues[column], context);
        _expectKeys(cell, const <String>{
          'text',
          'width',
          'style',
          'foreground',
          'background',
        }, context);
        final String text = _text(
          cell['text'],
          '$context.text',
          128,
          allowEmpty: true,
        );
        final int width = _integer(cell['width'], '$context.width');
        final int style = _integer(cell['style'], '$context.style');
        final int foreground = _integer(
          cell['foreground'],
          '$context.foreground',
        );
        final int background = _integer(
          cell['background'],
          '$context.background',
        );
        _expect(width >= 0 && width <= 2, '$context width is outside 0..2');
        _expect(
          text.isEmpty ? width <= 1 : width >= 1,
          '$context width/text invariant failed',
        );
        _expect(
          style >= 0 && style <= 0xffff,
          '$context style is out of range',
        );
        _expect(
          foreground >= 0 && foreground <= 0xffffffff,
          '$context foreground is out of range',
        );
        _expect(
          background >= 0 && background <= 0xffffffff,
          '$context background is out of range',
        );
        cells.add(
          TerminalDifferentialCell(
            text: text,
            width: width,
            style: style,
            foreground: foreground,
            background: background,
          ),
        );
      }
      rows.add(
        TerminalDifferentialRow(
          wrapped: wrapped,
          cells: List<TerminalDifferentialCell>.unmodifiable(cells),
        ),
      );
    }
    final Map<String, Object?> cursorMap = _object(
      observation['cursor'],
      'cursor',
    );
    _expectKeys(cursorMap, const <String>{
      'row',
      'column',
      'visible',
      'blinking',
      'shape',
    }, 'cursor');
    final int cursorRow = _integer(cursorMap['row'], 'cursor.row');
    final int cursorColumn = _integer(cursorMap['column'], 'cursor.column');
    _expect(
      cursorRow >= 0 && cursorRow < testCase.rows,
      'cursor.row is out of range',
    );
    _expect(
      cursorColumn >= 0 && cursorColumn < testCase.columns,
      'cursor.column is out of range',
    );
    final String shape = _text(cursorMap['shape'], 'cursor.shape', 16);
    _expect(
      shape == 'block' || shape == 'underline' || shape == 'bar',
      'cursor.shape is unknown',
    );
    final TerminalDifferentialCursor cursor = TerminalDifferentialCursor(
      row: cursorRow,
      column: cursorColumn,
      visible: _boolean(cursorMap['visible'], 'cursor.visible'),
      blinking: _boolean(cursorMap['blinking'], 'cursor.blinking'),
      shape: shape,
    );
    final Map<String, Object?> modes = _object(observation['modes'], 'modes');
    _expectKeys(modes, modeKeys, 'modes');
    for (final MapEntry<String, Object?> entry in modes.entries) {
      if (entry.key == 'mouse_encoding' || entry.key == 'mouse_tracking') {
        _text(entry.value, 'modes.${entry.key}', 32);
      } else {
        _boolean(entry.value, 'modes.${entry.key}');
      }
    }
    final Uint8List replies = _decodeHex(
      _text(
        observation['replies_hex'],
        'replies_hex',
        maximumRepliesBytes * 3,
        allowEmpty: true,
      ),
      'replies_hex',
      maximumBytes: maximumRepliesBytes,
      allowEmpty: true,
    );
    return TerminalDifferentialObservation(
      caseId: caseId,
      backendId: backendId,
      provenance: provenance,
      activeScreen: activeScreen,
      rows: List<TerminalDifferentialRow>.unmodifiable(rows),
      cursor: cursor,
      modes: Map<String, Object?>.unmodifiable(modes),
      replies: Uint8List.fromList(replies),
    );
  }
}

final class DartTerminalDifferentialBackend {
  const DartTerminalDifferentialBackend();

  TerminalDifferentialObservation capture(
    TerminalDifferentialCase testCase, {
    List<int>? chunkLengths,
    TerminalDifferentialProvenance
    provenance = const TerminalDifferentialProvenance(
      product: 'dart-terminal',
      productVersion: 'workspace',
      implementationRevision: 'working-tree',
      executableSha256: null,
      configId: 'defaults-v1',
      configSha256:
          'e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855',
      captureMethod: 'in-process-screen-v1',
      operatingSystem: 'macos',
      architecture: 'arm64',
    ),
  }) {
    final TerminalScreenSet screens = TerminalScreenSet(
      rows: testCase.rows,
      columns: testCase.columns,
    );
    final BytesBuilder replies = BytesBuilder(copy: false);
    bool repliesOverflow = false;
    final TerminalScreenParserSink sink = TerminalScreenParserSink.forScreenSet(
      screens,
      onReply: (Uint8List value) {
        if (replies.length + value.length >
            TerminalDifferentialObservation.maximumRepliesBytes) {
          repliesOverflow = true;
          return false;
        }
        replies.add(value);
        return true;
      },
    );
    final VtParser parser = VtParser(sink: sink);
    final List<int> chunks = chunkLengths ?? <int>[testCase.input.length];
    int offset = 0;
    for (final int length in chunks) {
      _expect(
        length >= 0 && offset + length <= testCase.input.length,
        '${testCase.id} has invalid chunk plan at $offset+$length',
      );
      parser.parse(testCase.input, offset, offset + length);
      offset += length;
    }
    _expect(
      offset == testCase.input.length,
      '${testCase.id} chunk plan consumed $offset/${testCase.input.length}',
    );
    parser.finish();
    _expect(
      parser.isGround,
      '${testCase.id} parser did not finish in ground state',
    );
    _expect(
      !repliesOverflow,
      '${testCase.id} replies exceeded the observation cap',
    );
    screens.primary.validateCellTopology();
    screens.alternate.validateCellTopology();
    screens.scrollback.validateCellTopology();

    final TerminalScreen screen = screens.activeScreen;
    final List<TerminalDifferentialRow> rows = <TerminalDifferentialRow>[];
    for (int row = 0; row < screen.rows; row++) {
      final List<TerminalDifferentialCell> cells = <TerminalDifferentialCell>[];
      for (int column = 0; column < screen.columns; column++) {
        final int flags = screen.widthFlagsAt(row, column);
        final int width = flags & TerminalCellFlags.widthMask;
        final int content = screen.contentAt(row, column);
        final String text;
        if (width == TerminalCellFlags.continuation || content == 0) {
          text = '';
        } else if (flags & TerminalCellFlags.grapheme != 0) {
          text = String.fromCharCodes(screen.graphemeTable.scalarsAt(content));
        } else {
          text = String.fromCharCode(content);
        }
        cells.add(
          TerminalDifferentialCell(
            text: text,
            width: width,
            style: screen.styleTable.attributesAt(screen.styleAt(row, column)),
            foreground: screen.foregroundAt(row, column),
            background: screen.backgroundAt(row, column),
          ),
        );
      }
      rows.add(
        TerminalDifferentialRow(
          wrapped: screen.rowFlagsAt(row) & TerminalRowFlags.softWrapped != 0,
          cells: List<TerminalDifferentialCell>.unmodifiable(cells),
        ),
      );
    }
    final TerminalKeyboardModes keyboard = screens.keyboardModes;
    final TerminalMouseModes mouse = screens.mouseModes;
    return TerminalDifferentialObservation(
      caseId: testCase.id,
      backendId: 'dart-terminal',
      provenance: provenance,
      activeScreen: screens.activeKind.name,
      rows: List<TerminalDifferentialRow>.unmodifiable(rows),
      cursor: TerminalDifferentialCursor(
        row: screen.cursorRow,
        column: screen.cursorColumn,
        visible: screen.cursorVisible,
        blinking: screen.cursorBlinking,
        shape: screen.cursorShape.name,
      ),
      modes: Map<String, Object?>.unmodifiable(<String, Object?>{
        'application_cursor': keyboard.applicationCursorKeys,
        'application_keypad': keyboard.applicationKeypad,
        'autowrap': screen.modeEnabled(TerminalScreenMode.autoWrap),
        'bracketed_paste': screens.bracketedPasteMode,
        'horizontal_margins': screen.modeEnabled(
          TerminalScreenMode.horizontalMargins,
        ),
        'insert': screen.modeEnabled(TerminalScreenMode.insert),
        'mouse_encoding': mouse.encoding.name,
        'mouse_tracking': mouse.tracking.name,
        'origin': screen.modeEnabled(TerminalScreenMode.origin),
        'reverse_video': screen.modeEnabled(TerminalScreenMode.reverseVideo),
      }),
      replies: replies.takeBytes(),
    );
  }
}

final class TerminalDifferentialComparison {
  const TerminalDifferentialComparison({
    required this.caseId,
    required this.matches,
    required this.accepted,
    required this.differences,
  });

  final String caseId;
  final bool matches;
  final bool accepted;
  final List<String> differences;

  String machineLine() =>
      'TERMINAL_DIFFERENTIAL_COMPARE case=$caseId matches=$matches '
      'accepted=$accepted differences=${differences.length}';
}

final class TerminalDifferentialComparator {
  const TerminalDifferentialComparator();

  TerminalDifferentialComparison compare(
    TerminalDifferentialCase testCase,
    TerminalDifferentialObservation product,
    TerminalDifferentialObservation reference,
  ) {
    _expect(product.caseId == testCase.id, 'product observation case differs');
    _expect(
      reference.caseId == testCase.id,
      'reference observation case differs',
    );
    final List<String> differences = <String>[];
    void difference(String value) {
      if (differences.length < 64) differences.add(value);
    }

    for (final TerminalDifferentialField field in testCase.fields) {
      switch (field) {
        case TerminalDifferentialField.screen:
          if (product.activeScreen != reference.activeScreen) {
            difference('screen');
          }
        case TerminalDifferentialField.text:
          for (int row = 0; row < testCase.rows; row++) {
            for (int column = 0; column < testCase.columns; column++) {
              final TerminalDifferentialCell left =
                  product.rows[row].cells[column];
              final TerminalDifferentialCell right =
                  reference.rows[row].cells[column];
              if (left.text != right.text || left.width != right.width) {
                difference('text@$row,$column');
              }
            }
          }
        case TerminalDifferentialField.style:
          _compareCells(
            testCase,
            product,
            reference,
            difference,
            (TerminalDifferentialCell left, TerminalDifferentialCell right) =>
                left.style == right.style,
            'style',
          );
        case TerminalDifferentialField.color:
          _compareCells(
            testCase,
            product,
            reference,
            difference,
            (TerminalDifferentialCell left, TerminalDifferentialCell right) =>
                left.foreground == right.foreground &&
                left.background == right.background,
            'color',
          );
        case TerminalDifferentialField.wrap:
          for (int row = 0; row < testCase.rows; row++) {
            if (product.rows[row].wrapped != reference.rows[row].wrapped) {
              difference('wrap@$row');
            }
          }
        case TerminalDifferentialField.cursor:
          if (jsonEncode(product.cursor.toJson()) !=
              jsonEncode(reference.cursor.toJson())) {
            difference('cursor');
          }
        case TerminalDifferentialField.modes:
          for (final String key in TerminalDifferentialObservation.modeKeys) {
            if (product.modes[key] != reference.modes[key]) {
              difference('modes');
              break;
            }
          }
        case TerminalDifferentialField.replies:
          if (!_bytesEqual(product.replies, reference.replies)) {
            difference('replies');
          }
      }
    }
    final bool matches = differences.isEmpty;
    final bool accepted = switch (testCase.expectation) {
      TerminalDifferentialExpectation.agree => matches,
      TerminalDifferentialExpectation.documentedGap => !matches,
    };
    return TerminalDifferentialComparison(
      caseId: testCase.id,
      matches: matches,
      accepted: accepted,
      differences: List<String>.unmodifiable(differences),
    );
  }

  static void _compareCells(
    TerminalDifferentialCase testCase,
    TerminalDifferentialObservation product,
    TerminalDifferentialObservation reference,
    void Function(String) difference,
    bool Function(TerminalDifferentialCell, TerminalDifferentialCell) equal,
    String name,
  ) {
    for (int row = 0; row < testCase.rows; row++) {
      for (int column = 0; column < testCase.columns; column++) {
        if (!equal(
          product.rows[row].cells[column],
          reference.rows[row].cells[column],
        )) {
          difference('$name@$row,$column');
        }
      }
    }
  }
}

final class TerminalDifferentialDriverResult {
  const TerminalDifferentialDriverResult({
    required this.status,
    required this.observation,
    required this.exitCode,
    required this.stdoutBytes,
    required this.stderrBytes,
  });

  final TerminalDifferentialDriverStatus status;
  final TerminalDifferentialObservation? observation;
  final int? exitCode;
  final int stdoutBytes;
  final int stderrBytes;

  String machineLine(String caseId) =>
      'TERMINAL_DIFFERENTIAL_DRIVER case=$caseId status=${status.name} '
      'exit_code=${exitCode ?? -1} stdout_bytes=$stdoutBytes '
      'stderr_bytes=$stderrBytes';
}

final class TerminalDifferentialSubprocessDriver {
  const TerminalDifferentialSubprocessDriver({
    this.timeout = const Duration(seconds: 10),
    this.maximumOutputBytes =
        TerminalDifferentialObservation.maximumEncodedBytes,
    this.maximumStderrBytes = 64 * 1024,
  });

  final Duration timeout;
  final int maximumOutputBytes;
  final int maximumStderrBytes;

  Future<TerminalDifferentialDriverResult> run({
    required String executable,
    required List<String> arguments,
    required TerminalDifferentialCase testCase,
    String? workingDirectory,
  }) async {
    if (timeout <= Duration.zero || timeout > const Duration(minutes: 2)) {
      throw ArgumentError.value(timeout, 'timeout');
    }
    if (maximumOutputBytes < 1 ||
        maximumOutputBytes >
            TerminalDifferentialObservation.maximumEncodedBytes) {
      throw ArgumentError.value(maximumOutputBytes, 'maximumOutputBytes');
    }
    if (maximumStderrBytes < 0 || maximumStderrBytes > 1024 * 1024) {
      throw ArgumentError.value(maximumStderrBytes, 'maximumStderrBytes');
    }
    if (!executable.startsWith('/') || executable.length > 4096) {
      throw ArgumentError.value(
        executable,
        'executable',
        'must be an absolute path',
      );
    }
    if (arguments.length > 32 ||
        arguments.any(
          (String value) => value.length > 4096 || _hasNul(value),
        )) {
      throw ArgumentError.value(arguments, 'arguments');
    }
    final File executableFile = File(executable);
    if (!executableFile.existsSync()) {
      return const TerminalDifferentialDriverResult(
        status: TerminalDifferentialDriverStatus.unavailable,
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
      return const TerminalDifferentialDriverResult(
        status: TerminalDifferentialDriverStatus.startFailure,
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
        utf8.encode('${jsonEncode(testCase.toDriverRequest())}\n'),
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
          throw TimeoutException('differential driver deadline');
        },
      );
    } on TimeoutException {
      try {
        await Future.wait<void>(<Future<void>>[stdoutDone, stderrDone])
            .timeout(const Duration(seconds: 2));
      } on TimeoutException {
        // SIGKILL was already requested. The classified timeout result must
        // remain bounded even if an inherited pipe is held by another process.
      }
      return TerminalDifferentialDriverResult(
        status: TerminalDifferentialDriverStatus.timedOut,
        observation: null,
        exitCode: null,
        stdoutBytes: stdoutCollector.length,
        stderrBytes: stderrCollector.length,
      );
    }
    try {
      await Future.wait<void>(<Future<void>>[stdoutDone, stderrDone])
          .timeout(const Duration(seconds: 2));
    } on TimeoutException {
      process.kill(ProcessSignal.sigkill);
      return TerminalDifferentialDriverResult(
        status: TerminalDifferentialDriverStatus.timedOut,
        observation: null,
        exitCode: exitCode,
        stdoutBytes: stdoutCollector.length,
        stderrBytes: stderrCollector.length,
      );
    }
    if (stdoutCollector.overflowed || stderrCollector.overflowed) {
      return TerminalDifferentialDriverResult(
        status: TerminalDifferentialDriverStatus.outputLimit,
        observation: null,
        exitCode: exitCode,
        stdoutBytes: stdoutCollector.length,
        stderrBytes: stderrCollector.length,
      );
    }
    if (exitCode != 0) {
      return TerminalDifferentialDriverResult(
        status: TerminalDifferentialDriverStatus.crashed,
        observation: null,
        exitCode: exitCode,
        stdoutBytes: stdoutCollector.length,
        stderrBytes: stderrCollector.length,
      );
    }
    final TerminalDifferentialObservation observation;
    try {
      observation = TerminalDifferentialObservation.parse(
        utf8.decode(stdoutCollector.bytes, allowMalformed: false),
        testCase: testCase,
      );
    } on Object {
      return TerminalDifferentialDriverResult(
        status: TerminalDifferentialDriverStatus.protocolError,
        observation: null,
        exitCode: exitCode,
        stdoutBytes: stdoutCollector.length,
        stderrBytes: stderrCollector.length,
      );
    }
    return TerminalDifferentialDriverResult(
      status: TerminalDifferentialDriverStatus.ok,
      observation: observation,
      exitCode: exitCode,
      stdoutBytes: stdoutCollector.length,
      stderrBytes: stderrCollector.length,
    );
  }
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
      onError: (Object _, StackTrace __) {
        if (!done.isCompleted) done.complete();
      },
      onDone: () {
        if (!done.isCompleted) done.complete();
      },
      cancelOnError: true,
    );
    return done.future.whenComplete(subscription.cancel);
  }
}

final class TerminalDifferentialContractResult {
  const TerminalDifferentialContractResult({
    required this.caseCount,
    required this.inputBytes,
    required this.splitRuns,
  });

  final int caseCount;
  final int inputBytes;
  final int splitRuns;

  String machineLine() =>
      'TERMINAL_DIFFERENTIAL_CONTRACT_PASS cases=$caseCount '
      'input_bytes=$inputBytes split_runs=$splitRuns';
}

TerminalDifferentialContractResult runTerminalDifferentialContractChecks({
  String manifestPath = defaultTerminalDifferentialManifestPath,
  String inventoryPath = defaultTerminalCompatibilityInventoryPath,
}) {
  final TerminalCompatibilityInventory inventory =
      TerminalCompatibilityInventory.load(
        File(inventoryPath),
        repositoryRoot: Directory.current,
      );
  final Set<String> inventoryIds = <String>{
    for (final TerminalCompatibilityRecord record in inventory.records)
      record.id,
  };
  final TerminalDifferentialManifest manifest =
      TerminalDifferentialManifest.load(
        File(manifestPath),
        inventoryIds: inventoryIds,
      );
  _expect(
    manifest.scope == 'contract-smoke',
    'contract check requires contract-smoke scope',
  );
  const DartTerminalDifferentialBackend backend =
      DartTerminalDifferentialBackend();
  const TerminalDifferentialComparator comparator =
      TerminalDifferentialComparator();
  int inputBytes = 0;
  int splitRuns = 0;
  for (final TerminalDifferentialCase testCase in manifest.cases) {
    inputBytes += testCase.input.length;
    final TerminalDifferentialObservation whole = backend.capture(testCase);
    final TerminalDifferentialObservation decoded =
        TerminalDifferentialObservation.parse(
          whole.encode(),
          testCase: testCase,
        );
    _expect(
      comparator.compare(testCase, whole, decoded).matches,
      '${testCase.id} observation encode/decode differs',
    );
    for (int split = 0; split <= testCase.input.length; split++) {
      final TerminalDifferentialObservation actual = backend.capture(
        testCase,
        chunkLengths: <int>[split, testCase.input.length - split],
      );
      _expect(
        comparator.compare(testCase, whole, actual).matches,
        '${testCase.id} differs at split $split',
      );
      splitRuns++;
    }
    final TerminalDifferentialObservation bytewise = backend.capture(
      testCase,
      chunkLengths: List<int>.filled(testCase.input.length, 1),
    );
    _expect(
      comparator.compare(testCase, whole, bytewise).matches,
      '${testCase.id} differs under bytewise input',
    );
    splitRuns++;
  }
  return TerminalDifferentialContractResult(
    caseCount: manifest.cases.length,
    inputBytes: inputBytes,
    splitRuns: splitRuns,
  );
}

String _encodeHex(List<int> bytes) => <String>[
  for (final int byte in bytes) byte.toRadixString(16).padLeft(2, '0'),
].join();

Uint8List _decodeHex(
  String source,
  String context, {
  required int maximumBytes,
  required bool allowEmpty,
}) {
  final BytesBuilder result = BytesBuilder(copy: false);
  int high = -1;
  for (int index = 0; index < source.length; index++) {
    final int unit = source.codeUnitAt(index);
    if (unit == 0x20 || unit == 0x09 || unit == 0x0a || unit == 0x0d) continue;
    final int nibble = _hexNibble(unit);
    _expect(nibble >= 0, '$context contains invalid hex at $index');
    if (high < 0) {
      high = nibble;
    } else {
      _expect(
        result.length < maximumBytes,
        '$context exceeds $maximumBytes bytes',
      );
      result.addByte((high << 4) | nibble);
      high = -1;
    }
  }
  _expect(high < 0, '$context has an odd hex digit count');
  _expect(allowEmpty || result.length > 0, '$context must not be empty');
  return result.takeBytes();
}

int _hexNibble(int unit) {
  if (unit >= 0x30 && unit <= 0x39) return unit - 0x30;
  if (unit >= 0x41 && unit <= 0x46) return unit - 0x41 + 10;
  if (unit >= 0x61 && unit <= 0x66) return unit - 0x61 + 10;
  return -1;
}

TerminalDifferentialField _field(String value, String context) =>
    switch (value) {
      'screen' => TerminalDifferentialField.screen,
      'text' => TerminalDifferentialField.text,
      'style' => TerminalDifferentialField.style,
      'color' => TerminalDifferentialField.color,
      'wrap' => TerminalDifferentialField.wrap,
      'cursor' => TerminalDifferentialField.cursor,
      'modes' => TerminalDifferentialField.modes,
      'replies' => TerminalDifferentialField.replies,
      _ => throw TerminalDifferentialException(
        '$context has unknown field $value',
      ),
    };

Map<String, Object?> _object(Object? value, String context) {
  if (value is! Map<Object?, Object?>) {
    throw TerminalDifferentialException('$context must be an object');
  }
  final Map<String, Object?> result = <String, Object?>{};
  for (final MapEntry<Object?, Object?> entry in value.entries) {
    _expect(entry.key is String, '$context has a non-string key');
    result[entry.key! as String] = entry.value;
  }
  return result;
}

List<Object?> _array(Object? value, String context) {
  if (value is! List<Object?>) {
    throw TerminalDifferentialException('$context must be an array');
  }
  return value;
}

String _text(
  Object? value,
  String context,
  int maximumCharacters, {
  bool allowEmpty = false,
}) {
  if (value is! String) {
    throw TerminalDifferentialException('$context must be a string');
  }
  _expect(
    (allowEmpty || value.isNotEmpty) && value.length <= maximumCharacters,
    '$context length is invalid',
  );
  for (int index = 0; index < value.length; index++) {
    final int unit = value.codeUnitAt(index);
    _expect(
      unit >= 0x20 && unit != 0x7f,
      '$context contains a control character',
    );
  }
  return value;
}

String _id(Object? value, String context) {
  final String result = _text(value, context, 128);
  _expect(
    RegExp(r'^[a-z0-9]+(?:-[a-z0-9]+)*$').hasMatch(result),
    '$context is not a canonical id',
  );
  return result;
}

String _token(Object? value, String context) {
  final String result = _text(value, context, 128);
  _expect(
    RegExp(r'^[A-Za-z0-9][A-Za-z0-9._-]*$').hasMatch(result),
    '$context is not a safe token',
  );
  return result;
}

String _sha256(Object? value, String context) {
  final String result = _text(value, context, 64);
  _expect(
    RegExp(r'^[0-9a-f]{64}$').hasMatch(result),
    '$context is not SHA-256',
  );
  return result;
}

int _integer(Object? value, String context) {
  if (value is! int)
    throw TerminalDifferentialException('$context must be an integer');
  return value;
}

bool _boolean(Object? value, String context) {
  if (value is! bool)
    throw TerminalDifferentialException('$context must be a boolean');
  return value;
}

void _expectKeys(
  Map<String, Object?> map,
  Set<String> expected,
  String context,
) {
  final Set<String> actual = map.keys.toSet();
  if (actual.length == expected.length && actual.containsAll(expected)) return;
  final List<String> missing = expected.difference(actual).toList()..sort();
  final List<String> unknown = actual.difference(expected).toList()..sort();
  throw TerminalDifferentialException(
    '$context keys differ; missing=${missing.join(',')} unknown=${unknown.join(',')}',
  );
}

bool _safeRelativeMarkdownPath(String value) {
  if (!value.startsWith('docs/') ||
      !value.endsWith('.md') ||
      value.contains('\\')) {
    return false;
  }
  return value
      .split('/')
      .every(
        (String segment) =>
            segment.isNotEmpty && segment != '.' && segment != '..',
      );
}

bool _hasNul(String value) => value.codeUnits.contains(0);

bool _bytesEqual(List<int> left, List<int> right) {
  if (left.length != right.length) return false;
  for (int index = 0; index < left.length; index++) {
    if (left[index] != right[index]) return false;
  }
  return true;
}

void _expect(bool condition, String message) {
  if (!condition) throw TerminalDifferentialException(message);
}

void main(List<String> arguments) {
  if (arguments.length > 1 ||
      (arguments.isNotEmpty && arguments.single != '--check')) {
    stderr.writeln(
      'TERMINAL_DIFFERENTIAL_CONTRACT_FAIL usage: '
      'dart run tool/terminal_differential_harness.dart [--check]',
    );
    exitCode = 64;
    return;
  }
  try {
    stdout.writeln(runTerminalDifferentialContractChecks().machineLine());
  } on Object catch (error) {
    stderr.writeln('TERMINAL_DIFFERENTIAL_CONTRACT_FAIL $error');
    exitCode = 1;
  }
}
