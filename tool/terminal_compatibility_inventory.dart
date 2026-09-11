import 'dart:convert';
import 'dart:io';

const String defaultTerminalCompatibilityInventoryPath =
    'compatibility/sequence_mode_inventory.json';
const String defaultTerminalImplementationSurfacePath =
    'compatibility/implemented_sequence_manifest.json';

enum TerminalCompatibilitySourceFamily {
  contour,
  dec,
  ecma48,
  ghostty,
  iterm2,
  kitty,
  mintty,
  xterm,
}

enum TerminalCompatibilitySelectorKind {
  c0,
  c1,
  esc,
  csi,
  osc,
  dcs,
  sos,
  pm,
  apc,
  mode,
}

enum TerminalCompatibilitySupport {
  implemented,
  partial,
  safeIgnore,
  unsupported,
}

enum TerminalCompatibilityDisposition { execute, reply, ignore, reject }

final class TerminalCompatibilityInventoryException implements FormatException {
  const TerminalCompatibilityInventoryException(this.message);

  @override
  final String message;

  @override
  int? get offset => null;

  @override
  Object? get source => null;

  @override
  String toString() => 'TerminalCompatibilityInventoryException: $message';
}

final class TerminalCompatibilitySourcePin {
  const TerminalCompatibilitySourcePin({
    required this.id,
    required this.family,
    required this.title,
    required this.edition,
    required this.artifactUrl,
    required this.artifactBytes,
    required this.artifactSha256,
    required this.documentPath,
    required this.documentSha256,
    required this.retrievedOn,
  });

  final String id;
  final TerminalCompatibilitySourceFamily family;
  final String title;
  final String edition;
  final Uri artifactUrl;
  final int artifactBytes;
  final String artifactSha256;
  final String? documentPath;
  final String? documentSha256;
  final String retrievedOn;
}

final class TerminalCompatibilitySourceReference {
  const TerminalCompatibilitySourceReference({
    required this.source,
    required this.locator,
  });

  final String source;
  final String locator;
}

final class TerminalCompatibilitySelector {
  const TerminalCompatibilitySelector({
    required this.kind,
    required this.canonicalKey,
    this.code,
    this.privateMarker,
    this.intermediates = const <int>[],
    this.finalByte,
    this.command,
    this.privateMode,
    this.modeNumber,
  });

  final TerminalCompatibilitySelectorKind kind;
  final String canonicalKey;
  final int? code;
  final int? privateMarker;
  final List<int> intermediates;
  final int? finalByte;
  final int? command;
  final bool? privateMode;
  final int? modeNumber;
}

final class TerminalCompatibilityRecord {
  const TerminalCompatibilityRecord({
    required this.id,
    required this.mnemonic,
    required this.syntax,
    required this.selector,
    required this.support,
    required this.disposition,
    required this.sourceReferences,
    required this.implementationEvidence,
    required this.testEvidence,
    required this.notes,
  });

  final String id;
  final String mnemonic;
  final String syntax;
  final TerminalCompatibilitySelector selector;
  final TerminalCompatibilitySupport support;
  final TerminalCompatibilityDisposition disposition;
  final List<TerminalCompatibilitySourceReference> sourceReferences;
  final List<String> implementationEvidence;
  final List<String> testEvidence;
  final String notes;
}

final class TerminalCompatibilityInventory {
  const TerminalCompatibilityInventory._({
    required this.version,
    required this.inventoryRevision,
    required this.scope,
    required this.sourcePins,
    required this.records,
  });

  static const String formatName = 'dart-terminal-sequence-mode-inventory';
  static const int formatVersion = 1;
  static const int maximumManifestBytes = 1024 * 1024;
  static const int maximumSourcePins = 32;
  static const int maximumRecords = 4096;
  static const int maximumReferencesPerRecord = 8;
  static const int maximumEvidencePerRecord = 16;
  static const int maximumArtifactBytes = 64 * 1024 * 1024;
  static const int maximumModeNumber = 65535;
  static const int maximumOscCommand = 65535;

  final int version;
  final int inventoryRevision;
  final String scope;
  final List<TerminalCompatibilitySourcePin> sourcePins;
  final List<TerminalCompatibilityRecord> records;

  Map<TerminalCompatibilitySelectorKind, int> get selectorKindCounts {
    final Map<TerminalCompatibilitySelectorKind, int> result =
        <TerminalCompatibilitySelectorKind, int>{
          for (final TerminalCompatibilitySelectorKind kind
              in TerminalCompatibilitySelectorKind.values)
            kind: 0,
        };
    for (final TerminalCompatibilityRecord record in records) {
      result[record.selector.kind] = result[record.selector.kind]! + 1;
    }
    return Map<TerminalCompatibilitySelectorKind, int>.unmodifiable(result);
  }

  Map<TerminalCompatibilitySupport, int> get supportCounts {
    final Map<TerminalCompatibilitySupport, int> result =
        <TerminalCompatibilitySupport, int>{
          for (final TerminalCompatibilitySupport support
              in TerminalCompatibilitySupport.values)
            support: 0,
        };
    for (final TerminalCompatibilityRecord record in records) {
      result[record.support] = result[record.support]! + 1;
    }
    return Map<TerminalCompatibilitySupport, int>.unmodifiable(result);
  }

  String machineLine() {
    final Map<TerminalCompatibilitySupport, int> counts = supportCounts;
    return 'TERMINAL_COMPATIBILITY_INVENTORY_CHECK '
        'version=$version revision=$inventoryRevision '
        'sources=${sourcePins.length} records=${records.length} '
        'implemented=${counts[TerminalCompatibilitySupport.implemented]} '
        'partial=${counts[TerminalCompatibilitySupport.partial]} '
        'safe_ignore=${counts[TerminalCompatibilitySupport.safeIgnore]} '
        'unsupported=${counts[TerminalCompatibilitySupport.unsupported]}';
  }

  String reconcileImplementationSurface(File manifest) {
    _expect(
      scope == 'complete-baseline',
      'implementation reconciliation requires complete-baseline scope',
    );
    _expect(manifest.existsSync(), 'implementation manifest does not exist');
    _expect(
      manifest.lengthSync() > 0 &&
          manifest.lengthSync() <= maximumManifestBytes,
      'implementation manifest size is invalid',
    );
    final Object? decoded;
    try {
      decoded = jsonDecode(manifest.readAsStringSync());
    } on Object catch (error) {
      throw TerminalCompatibilityInventoryException(
        'invalid implementation manifest JSON: $error',
      );
    }
    final Map<String, Object?> root = _object(decoded, 'implementation root');
    _expectKeys(root, const <String>{
      'format',
      'version',
      'selectors',
      'modes',
      'boundedUnsupportedFamilies',
    }, 'implementation root');
    _expect(
      root['format'] == 'dart-terminal-implementation-surface' &&
          root['version'] == 1,
      'unsupported implementation manifest format/version',
    );
    final Set<String> implementationKeys = <String>{};
    for (final String collectionName in const <String>['selectors', 'modes']) {
      final List<Object?> values = _array(root[collectionName], collectionName);
      _expect(
        values.isNotEmpty && values.length <= maximumRecords,
        '$collectionName count is invalid',
      );
      for (int index = 0; index < values.length; index++) {
        final Map<String, Object?> entry = _object(
          values[index],
          '$collectionName[$index]',
        );
        final String key = _boundedText(
          entry['key'],
          '$collectionName[$index].key',
          96,
        );
        _expect(
          implementationKeys.add(key),
          'duplicate implementation key $key',
        );
      }
    }
    final Set<String> inventoriedImplementationKeys = <String>{
      for (final TerminalCompatibilityRecord record in records)
        if (record.support == TerminalCompatibilitySupport.implemented ||
            record.support == TerminalCompatibilitySupport.partial)
          record.selector.canonicalKey,
    };
    final List<String> missing =
        implementationKeys.difference(inventoriedImplementationKeys).toList()
          ..sort();
    final List<String> extra =
        inventoriedImplementationKeys.difference(implementationKeys).toList()
          ..sort();
    _expect(
      missing.isEmpty && extra.isEmpty,
      'implementation reconciliation differs; '
      'missing=${missing.join(',')} extra=${extra.join(',')}',
    );

    final List<Object?> familyValues = _array(
      root['boundedUnsupportedFamilies'],
      'boundedUnsupportedFamilies',
    );
    final Set<String> families = <String>{
      for (int index = 0; index < familyValues.length; index++)
        _boundedText(
          familyValues[index],
          'boundedUnsupportedFamilies[$index]',
          8,
        ),
    };
    _expect(
      families.length == familyValues.length &&
          families.length == 4 &&
          families.containsAll(const <String>{'dcs', 'sos', 'pm', 'apc'}),
      'bounded unsupported families must be dcs, sos, pm, and apc',
    );
    for (final String family in families) {
      _expect(
        records.any(
          (TerminalCompatibilityRecord record) =>
              record.selector.kind.name == family &&
              record.support == TerminalCompatibilitySupport.safeIgnore &&
              record.disposition == TerminalCompatibilityDisposition.ignore,
        ),
        'bounded unsupported family $family lacks safe-ignore evidence',
      );
    }
    return 'TERMINAL_COMPATIBILITY_RECONCILIATION_PASS '
        'implementation=${implementationKeys.length} '
        'safe_ignore_families=${families.length}';
  }

  static TerminalCompatibilityInventory load(
    File manifest, {
    required Directory repositoryRoot,
  }) {
    _expect(manifest.existsSync(), 'manifest does not exist: ${manifest.path}');
    _expect(
      FileSystemEntity.typeSync(manifest.path, followLinks: false) ==
          FileSystemEntityType.file,
      'manifest must be a regular file',
    );
    final int length = manifest.lengthSync();
    _expect(
      length > 0 && length <= maximumManifestBytes,
      'manifest size $length is outside 1..$maximumManifestBytes',
    );
    return parse(manifest.readAsStringSync(), repositoryRoot: repositoryRoot);
  }

  static TerminalCompatibilityInventory parse(
    String source, {
    required Directory repositoryRoot,
  }) {
    _expect(
      utf8.encode(source).length <= maximumManifestBytes,
      'manifest exceeds $maximumManifestBytes encoded bytes',
    );
    final Object? decoded;
    try {
      decoded = jsonDecode(source);
    } on Object catch (error) {
      throw TerminalCompatibilityInventoryException('invalid JSON: $error');
    }
    final Map<String, Object?> root = _object(decoded, 'root');
    _expectKeys(root, const <String>{
      'format',
      'version',
      'inventoryRevision',
      'scope',
      'sourcePins',
      'records',
    }, 'root');
    _expect(root['format'] == formatName, 'unsupported inventory format');
    final int version = _integer(root['version'], 'version');
    _expect(version == formatVersion, 'unsupported inventory version $version');
    final int revision = _integer(
      root['inventoryRevision'],
      'inventoryRevision',
    );
    _expect(revision > 0, 'inventoryRevision must be positive');
    final String scope = _boundedText(root['scope'], 'scope', 64);
    _expect(
      scope == 'schema-foundation' || scope == 'complete-baseline',
      'unsupported inventory scope $scope',
    );

    final List<Object?> sourceValues = _array(root['sourcePins'], 'sourcePins');
    _expect(
      sourceValues.isNotEmpty && sourceValues.length <= maximumSourcePins,
      'sourcePins count is outside 1..$maximumSourcePins',
    );
    final List<TerminalCompatibilitySourcePin> sourcePins =
        <TerminalCompatibilitySourcePin>[];
    final Set<String> sourceIds = <String>{};
    final Set<TerminalCompatibilitySourceFamily> sourceFamilies =
        <TerminalCompatibilitySourceFamily>{};
    String? previousSourceId;
    for (int index = 0; index < sourceValues.length; index++) {
      final TerminalCompatibilitySourcePin pin = _decodeSourcePin(
        _object(sourceValues[index], 'sourcePins[$index]'),
        index,
      );
      _expect(sourceIds.add(pin.id), 'duplicate source pin ${pin.id}');
      _expect(
        previousSourceId == null || previousSourceId.compareTo(pin.id) < 0,
        'source pins must be sorted by id',
      );
      previousSourceId = pin.id;
      sourceFamilies.add(pin.family);
      sourcePins.add(pin);
    }
    _expect(
      sourceFamilies.length == TerminalCompatibilitySourceFamily.values.length,
      'source pins must include every supported source family',
    );

    final Map<String, TerminalCompatibilitySourcePin> pinsById =
        <String, TerminalCompatibilitySourcePin>{
          for (final TerminalCompatibilitySourcePin pin in sourcePins)
            pin.id: pin,
        };
    final List<Object?> recordValues = _array(root['records'], 'records');
    _expect(
      recordValues.isNotEmpty && recordValues.length <= maximumRecords,
      'records count is outside 1..$maximumRecords',
    );
    final List<TerminalCompatibilityRecord> records =
        <TerminalCompatibilityRecord>[];
    final Set<String> recordIds = <String>{};
    final Set<String> selectorKeys = <String>{};
    String? previousRecordId;
    for (int index = 0; index < recordValues.length; index++) {
      final TerminalCompatibilityRecord record = _decodeRecord(
        _object(recordValues[index], 'records[$index]'),
        index,
        pinsById,
        repositoryRoot,
      );
      _expect(recordIds.add(record.id), 'duplicate record id ${record.id}');
      _expect(
        selectorKeys.add(record.selector.canonicalKey),
        'duplicate selector ${record.selector.canonicalKey}',
      );
      _expect(
        previousRecordId == null || previousRecordId.compareTo(record.id) < 0,
        'records must be sorted by id',
      );
      previousRecordId = record.id;
      records.add(record);
    }
    final Set<TerminalCompatibilitySelectorKind> representedKinds = records
        .map((TerminalCompatibilityRecord record) => record.selector.kind)
        .toSet();
    _expect(
      representedKinds.length ==
          TerminalCompatibilitySelectorKind.values.length,
      'records must represent every selector kind',
    );
    return TerminalCompatibilityInventory._(
      version: version,
      inventoryRevision: revision,
      scope: scope,
      sourcePins: List<TerminalCompatibilitySourcePin>.unmodifiable(sourcePins),
      records: List<TerminalCompatibilityRecord>.unmodifiable(records),
    );
  }

  static TerminalCompatibilitySourcePin _decodeSourcePin(
    Map<String, Object?> map,
    int index,
  ) {
    final String context = 'sourcePins[$index]';
    _expectKeys(map, const <String>{
      'id',
      'family',
      'title',
      'edition',
      'artifactUrl',
      'artifactBytes',
      'artifactSha256',
      'documentPath',
      'documentSha256',
      'retrievedOn',
    }, context);
    final String id = _boundedText(map['id'], '$context.id', 64);
    _expect(_validSlug(id), '$context.id is invalid');
    final TerminalCompatibilitySourceFamily family = _sourceFamily(
      _boundedText(map['family'], '$context.family', 16),
      context,
    );
    final String title = _boundedText(map['title'], '$context.title', 160);
    final String edition = _boundedText(
      map['edition'],
      '$context.edition',
      160,
    );
    final Uri url = Uri.parse(
      _boundedText(map['artifactUrl'], '$context.artifactUrl', 512),
    );
    _expect(
      url.scheme == 'https' &&
          url.host.isNotEmpty &&
          url.userInfo.isEmpty &&
          url.fragment.isEmpty,
      '$context.artifactUrl must be an HTTPS artifact URL',
    );
    final int artifactBytes = _integer(
      map['artifactBytes'],
      '$context.artifactBytes',
    );
    _expect(
      artifactBytes > 0 && artifactBytes <= maximumArtifactBytes,
      '$context.artifactBytes is outside 1..$maximumArtifactBytes',
    );
    final String artifactSha256 = _boundedText(
      map['artifactSha256'],
      '$context.artifactSha256',
      64,
    );
    _expect(_validSha256(artifactSha256), '$context artifact hash is invalid');
    final String? documentPath = _nullableString(
      map['documentPath'],
      '$context.documentPath',
    );
    final String? documentSha256 = _nullableString(
      map['documentSha256'],
      '$context.documentSha256',
    );
    _expect(
      (documentPath == null) == (documentSha256 == null),
      '$context document path/hash must both be null or present',
    );
    if (documentPath != null) {
      _expect(
        documentPath.length <= 256 && _safeRelativePath(documentPath),
        '$context.documentPath is invalid',
      );
      _expect(
        _validSha256(documentSha256!),
        '$context document hash is invalid',
      );
    }
    final String retrievedOn = _boundedText(
      map['retrievedOn'],
      '$context.retrievedOn',
      10,
    );
    _expect(
      RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(retrievedOn) &&
          DateTime.tryParse(retrievedOn) != null,
      '$context.retrievedOn must be YYYY-MM-DD',
    );
    return TerminalCompatibilitySourcePin(
      id: id,
      family: family,
      title: title,
      edition: edition,
      artifactUrl: url,
      artifactBytes: artifactBytes,
      artifactSha256: artifactSha256,
      documentPath: documentPath,
      documentSha256: documentSha256,
      retrievedOn: retrievedOn,
    );
  }

  static TerminalCompatibilityRecord _decodeRecord(
    Map<String, Object?> map,
    int index,
    Map<String, TerminalCompatibilitySourcePin> pinsById,
    Directory repositoryRoot,
  ) {
    final String context = 'records[$index]';
    _expectKeys(map, const <String>{
      'id',
      'mnemonic',
      'syntax',
      'selector',
      'support',
      'disposition',
      'sourceRefs',
      'implementationEvidence',
      'testEvidence',
      'notes',
    }, context);
    final String id = _boundedText(map['id'], '$context.id', 96);
    _expect(
      RegExp(
        r'^(contour|dec|ecma48|ghostty|iterm2|kitty|mintty|xterm):(c0|c1|esc|csi|osc|dcs|sos|pm|apc|mode):[a-z0-9]+(?:-[a-z0-9]+)*$',
      ).hasMatch(id),
      '$context.id is invalid',
    );
    final String mnemonic = _boundedText(
      map['mnemonic'],
      '$context.mnemonic',
      64,
    );
    _expect(
      RegExp(r'^[A-Z0-9]+(?:-[A-Z0-9]+)*$').hasMatch(mnemonic),
      '$context.mnemonic is invalid',
    );
    final String syntax = _boundedText(map['syntax'], '$context.syntax', 160);
    final TerminalCompatibilitySelector selector = _decodeSelector(
      _object(map['selector'], '$context.selector'),
      context,
    );
    final List<String> idParts = id.split(':');
    _expect(
      idParts[1] == selector.kind.name,
      '$context.id selector kind differs from selector',
    );
    final TerminalCompatibilitySupport support = _support(
      _boundedText(map['support'], '$context.support', 16),
      context,
    );
    final TerminalCompatibilityDisposition disposition = _disposition(
      _boundedText(map['disposition'], '$context.disposition', 16),
      context,
    );
    final List<Object?> sourceValues = _array(
      map['sourceRefs'],
      '$context.sourceRefs',
    );
    _expect(
      sourceValues.isNotEmpty &&
          sourceValues.length <= maximumReferencesPerRecord,
      '$context.sourceRefs count is outside 1..$maximumReferencesPerRecord',
    );
    final List<TerminalCompatibilitySourceReference> references =
        <TerminalCompatibilitySourceReference>[];
    final Set<String> referencedSources = <String>{};
    for (
      int sourceIndex = 0;
      sourceIndex < sourceValues.length;
      sourceIndex++
    ) {
      final Map<String, Object?> reference = _object(
        sourceValues[sourceIndex],
        '$context.sourceRefs[$sourceIndex]',
      );
      _expectKeys(reference, const <String>{
        'source',
        'locator',
      }, '$context.sourceRefs[$sourceIndex]');
      final String source = _boundedText(
        reference['source'],
        '$context.sourceRefs[$sourceIndex].source',
        64,
      );
      _expect(
        pinsById.containsKey(source),
        '$context references unknown source $source',
      );
      _expect(
        referencedSources.add(source),
        '$context repeats source reference $source',
      );
      references.add(
        TerminalCompatibilitySourceReference(
          source: source,
          locator: _boundedText(
            reference['locator'],
            '$context.sourceRefs[$sourceIndex].locator',
            256,
          ),
        ),
      );
    }
    final TerminalCompatibilitySourcePin primarySource =
        pinsById[references.first.source]!;
    _expect(
      idParts.first == primarySource.family.name,
      '$context.id family differs from its primary source',
    );
    final List<String> implementationEvidence = _evidence(
      map['implementationEvidence'],
      '$context.implementationEvidence',
      repositoryRoot,
    );
    final List<String> testEvidence = _evidence(
      map['testEvidence'],
      '$context.testEvidence',
      repositoryRoot,
    );
    final String notes = _text(map['notes'], '$context.notes');
    _expect(notes.length <= 1024, '$context.notes exceeds 1024 characters');
    if (support == TerminalCompatibilitySupport.implemented ||
        support == TerminalCompatibilitySupport.partial ||
        support == TerminalCompatibilitySupport.safeIgnore) {
      _expect(
        implementationEvidence.isNotEmpty && testEvidence.isNotEmpty,
        '$context support requires implementation and test evidence',
      );
    }
    if (support != TerminalCompatibilitySupport.implemented) {
      _expect(notes.isNotEmpty, '$context support requires explanatory notes');
    }
    if (disposition == TerminalCompatibilityDisposition.reply) {
      _expect(
        support == TerminalCompatibilitySupport.implemented ||
            support == TerminalCompatibilitySupport.partial,
        '$context reply disposition requires implementation',
      );
    }
    if (support == TerminalCompatibilitySupport.safeIgnore) {
      _expect(
        disposition == TerminalCompatibilityDisposition.ignore,
        '$context safe-ignore support requires ignore disposition',
      );
    }
    if (support == TerminalCompatibilitySupport.unsupported) {
      _expect(
        disposition == TerminalCompatibilityDisposition.reject &&
            implementationEvidence.isEmpty &&
            testEvidence.isEmpty,
        '$context unsupported support requires reject disposition and no '
        'implementation/test evidence',
      );
    }
    return TerminalCompatibilityRecord(
      id: id,
      mnemonic: mnemonic,
      syntax: syntax,
      selector: selector,
      support: support,
      disposition: disposition,
      sourceReferences: List<TerminalCompatibilitySourceReference>.unmodifiable(
        references,
      ),
      implementationEvidence: implementationEvidence,
      testEvidence: testEvidence,
      notes: notes,
    );
  }

  static TerminalCompatibilitySelector _decodeSelector(
    Map<String, Object?> map,
    String recordContext,
  ) {
    final String context = '$recordContext.selector';
    final TerminalCompatibilitySelectorKind kind = _selectorKind(
      _boundedText(map['kind'], '$context.kind', 8),
      context,
    );
    switch (kind) {
      case TerminalCompatibilitySelectorKind.c0:
      case TerminalCompatibilitySelectorKind.c1:
        _expectKeys(map, const <String>{'kind', 'code'}, context);
        final int code = _integer(map['code'], '$context.code');
        final bool valid = kind == TerminalCompatibilitySelectorKind.c0
            ? code >= 0 && code <= 0x1f
            : code >= 0x80 && code <= 0x9f;
        _expect(valid, '$context.code is outside the ${kind.name} range');
        return TerminalCompatibilitySelector(
          kind: kind,
          code: code,
          canonicalKey: '${kind.name}:$code',
        );
      case TerminalCompatibilitySelectorKind.esc:
        _expectKeys(map, const <String>{
          'kind',
          'intermediates',
          'finalByte',
        }, context);
        final List<int> intermediates = _byteArray(
          map['intermediates'],
          '$context.intermediates',
          minimum: 0x20,
          maximum: 0x2f,
          maximumLength: 2,
        );
        final int finalByte = _integer(map['finalByte'], '$context.finalByte');
        _expect(
          finalByte >= 0x30 && finalByte <= 0x7e,
          '$context.finalByte is outside the ESC range',
        );
        return TerminalCompatibilitySelector(
          kind: kind,
          intermediates: intermediates,
          finalByte: finalByte,
          canonicalKey:
              'esc:${intermediates.length}:'
              '${intermediates.isEmpty ? '0' : intermediates.join('.')}:'
              '$finalByte',
        );
      case TerminalCompatibilitySelectorKind.csi:
      case TerminalCompatibilitySelectorKind.dcs:
        _expectKeys(map, const <String>{
          'kind',
          'privateMarker',
          'intermediates',
          'finalByte',
        }, context);
        final int? privateMarker = _nullableInteger(
          map['privateMarker'],
          '$context.privateMarker',
        );
        _expect(
          privateMarker == null ||
              (privateMarker >= 0x3c && privateMarker <= 0x3f),
          '$context.privateMarker is outside 0x3c..0x3f',
        );
        final List<int> intermediates = _byteArray(
          map['intermediates'],
          '$context.intermediates',
          minimum: 0x20,
          maximum: 0x2f,
          maximumLength: 2,
        );
        final int finalByte = _integer(map['finalByte'], '$context.finalByte');
        _expect(
          finalByte >= 0x40 && finalByte <= 0x7e,
          '$context.finalByte is outside the ${kind.name.toUpperCase()} range',
        );
        return TerminalCompatibilitySelector(
          kind: kind,
          privateMarker: privateMarker,
          intermediates: intermediates,
          finalByte: finalByte,
          canonicalKey:
              '${kind.name}:${privateMarker ?? -1}:${intermediates.length}:'
              '${intermediates.isEmpty ? '0' : intermediates.join('.')}:'
              '$finalByte',
        );
      case TerminalCompatibilitySelectorKind.osc:
        _expectKeys(map, const <String>{'kind', 'command'}, context);
        final int command = _integer(map['command'], '$context.command');
        _expect(
          command >= 0 && command <= maximumOscCommand,
          '$context.command is outside 0..$maximumOscCommand',
        );
        return TerminalCompatibilitySelector(
          kind: kind,
          command: command,
          canonicalKey: 'osc:$command',
        );
      case TerminalCompatibilitySelectorKind.sos:
      case TerminalCompatibilitySelectorKind.pm:
      case TerminalCompatibilitySelectorKind.apc:
        _expectKeys(map, const <String>{'kind'}, context);
        return TerminalCompatibilitySelector(
          kind: kind,
          canonicalKey: kind.name,
        );
      case TerminalCompatibilitySelectorKind.mode:
        _expectKeys(map, const <String>{'kind', 'private', 'number'}, context);
        final bool privateMode = _boolean(map['private'], '$context.private');
        final int modeNumber = _integer(map['number'], '$context.number');
        _expect(
          modeNumber >= 0 && modeNumber <= maximumModeNumber,
          '$context.number is outside 0..$maximumModeNumber',
        );
        return TerminalCompatibilitySelector(
          kind: kind,
          privateMode: privateMode,
          modeNumber: modeNumber,
          canonicalKey: 'mode:${privateMode ? 1 : 0}:$modeNumber',
        );
    }
  }

  static List<String> _evidence(
    Object? value,
    String context,
    Directory repositoryRoot,
  ) {
    final List<Object?> values = _array(value, context);
    _expect(
      values.length <= maximumEvidencePerRecord,
      '$context exceeds $maximumEvidencePerRecord entries',
    );
    final List<String> result = <String>[];
    final Set<String> seen = <String>{};
    for (int index = 0; index < values.length; index++) {
      final String evidence = _boundedText(
        values[index],
        '$context[$index]',
        256,
      );
      final int separator = evidence.indexOf('#');
      _expect(
        separator > 0 && separator == evidence.lastIndexOf('#'),
        '$context[$index] must be path#anchor',
      );
      final String path = evidence.substring(0, separator);
      final String anchor = evidence.substring(separator + 1);
      _expect(_safeRelativePath(path), '$context[$index] has an unsafe path');
      _expect(
        RegExp(r'^[A-Za-z0-9][A-Za-z0-9._-]*$').hasMatch(anchor),
        '$context[$index] has an invalid anchor',
      );
      final File file = File.fromUri(repositoryRoot.absolute.uri.resolve(path));
      _expect(file.existsSync(), '$context[$index] file does not exist: $path');
      _expect(
        FileSystemEntity.typeSync(file.path, followLinks: false) ==
            FileSystemEntityType.file,
        '$context[$index] must reference a regular file',
      );
      _expect(seen.add(evidence), '$context repeats $evidence');
      result.add(evidence);
    }
    return List<String>.unmodifiable(result);
  }

  static List<int> _byteArray(
    Object? value,
    String context, {
    required int minimum,
    required int maximum,
    required int maximumLength,
  }) {
    final List<Object?> values = _array(value, context);
    _expect(
      values.length <= maximumLength,
      '$context exceeds $maximumLength bytes',
    );
    final List<int> result = <int>[];
    for (int index = 0; index < values.length; index++) {
      final int byte = _integer(values[index], '$context[$index]');
      _expect(
        byte >= minimum && byte <= maximum,
        '$context[$index] is outside $minimum..$maximum',
      );
      result.add(byte);
    }
    return List<int>.unmodifiable(result);
  }

  static TerminalCompatibilitySourceFamily _sourceFamily(
    String value,
    String context,
  ) => switch (value) {
    'contour' => TerminalCompatibilitySourceFamily.contour,
    'dec' => TerminalCompatibilitySourceFamily.dec,
    'ecma48' => TerminalCompatibilitySourceFamily.ecma48,
    'ghostty' => TerminalCompatibilitySourceFamily.ghostty,
    'iterm2' => TerminalCompatibilitySourceFamily.iterm2,
    'kitty' => TerminalCompatibilitySourceFamily.kitty,
    'mintty' => TerminalCompatibilitySourceFamily.mintty,
    'xterm' => TerminalCompatibilitySourceFamily.xterm,
    _ => throw TerminalCompatibilityInventoryException(
      '$context has unknown source family $value',
    ),
  };

  static TerminalCompatibilitySelectorKind _selectorKind(
    String value,
    String context,
  ) => switch (value) {
    'c0' => TerminalCompatibilitySelectorKind.c0,
    'c1' => TerminalCompatibilitySelectorKind.c1,
    'esc' => TerminalCompatibilitySelectorKind.esc,
    'csi' => TerminalCompatibilitySelectorKind.csi,
    'osc' => TerminalCompatibilitySelectorKind.osc,
    'dcs' => TerminalCompatibilitySelectorKind.dcs,
    'sos' => TerminalCompatibilitySelectorKind.sos,
    'pm' => TerminalCompatibilitySelectorKind.pm,
    'apc' => TerminalCompatibilitySelectorKind.apc,
    'mode' => TerminalCompatibilitySelectorKind.mode,
    _ => throw TerminalCompatibilityInventoryException(
      '$context has unknown selector kind $value',
    ),
  };

  static TerminalCompatibilitySupport _support(String value, String context) =>
      switch (value) {
        'implemented' => TerminalCompatibilitySupport.implemented,
        'partial' => TerminalCompatibilitySupport.partial,
        'safe-ignore' => TerminalCompatibilitySupport.safeIgnore,
        'unsupported' => TerminalCompatibilitySupport.unsupported,
        _ => throw TerminalCompatibilityInventoryException(
          '$context has unknown support $value',
        ),
      };

  static TerminalCompatibilityDisposition _disposition(
    String value,
    String context,
  ) => switch (value) {
    'execute' => TerminalCompatibilityDisposition.execute,
    'reply' => TerminalCompatibilityDisposition.reply,
    'ignore' => TerminalCompatibilityDisposition.ignore,
    'reject' => TerminalCompatibilityDisposition.reject,
    _ => throw TerminalCompatibilityInventoryException(
      '$context has unknown disposition $value',
    ),
  };

  static Map<String, Object?> _object(Object? value, String context) {
    if (value is! Map<Object?, Object?>) {
      throw TerminalCompatibilityInventoryException(
        '$context must be an object',
      );
    }
    final Map<String, Object?> result = <String, Object?>{};
    for (final MapEntry<Object?, Object?> entry in value.entries) {
      if (entry.key is! String) {
        throw TerminalCompatibilityInventoryException(
          '$context has a non-string key',
        );
      }
      result[entry.key! as String] = entry.value;
    }
    return result;
  }

  static List<Object?> _array(Object? value, String context) {
    if (value is! List<Object?>) {
      throw TerminalCompatibilityInventoryException(
        '$context must be an array',
      );
    }
    return value;
  }

  static String _text(Object? value, String context) {
    if (value is! String) {
      throw TerminalCompatibilityInventoryException(
        '$context must be a string',
      );
    }
    _expect(!_containsControl(value), '$context contains a control character');
    return value;
  }

  static String _boundedText(Object? value, String context, int maximum) {
    final String result = _text(value, context);
    _expect(
      result.isNotEmpty && result.length <= maximum,
      '$context length is outside 1..$maximum',
    );
    return result;
  }

  static String? _nullableString(Object? value, String context) {
    if (value == null) return null;
    return _text(value, context);
  }

  static int _integer(Object? value, String context) {
    if (value is! int) {
      throw TerminalCompatibilityInventoryException(
        '$context must be an integer',
      );
    }
    return value;
  }

  static int? _nullableInteger(Object? value, String context) {
    if (value == null) return null;
    return _integer(value, context);
  }

  static bool _boolean(Object? value, String context) {
    if (value is! bool) {
      throw TerminalCompatibilityInventoryException(
        '$context must be a boolean',
      );
    }
    return value;
  }

  static void _expectKeys(
    Map<String, Object?> map,
    Set<String> expected,
    String context,
  ) {
    final Set<String> actual = map.keys.toSet();
    if (actual.length == expected.length && actual.containsAll(expected)) {
      return;
    }
    final List<String> missing = expected.difference(actual).toList()..sort();
    final List<String> unknown = actual.difference(expected).toList()..sort();
    throw TerminalCompatibilityInventoryException(
      '$context keys differ; missing=${missing.join(',')} '
      'unknown=${unknown.join(',')}',
    );
  }

  static bool _validSlug(String value) =>
      RegExp(r'^[a-z0-9]+(?:-[a-z0-9]+)*$').hasMatch(value);

  static bool _validSha256(String value) =>
      RegExp(r'^[0-9a-f]{64}$').hasMatch(value);

  static bool _safeRelativePath(String value) {
    if (value.isEmpty || value.startsWith('/') || value.contains('\\')) {
      return false;
    }
    return value
        .split('/')
        .every(
          (String segment) =>
              segment.isNotEmpty && segment != '.' && segment != '..',
        );
  }

  static bool _containsControl(String value) {
    for (int index = 0; index < value.length; index++) {
      final int unit = value.codeUnitAt(index);
      if (unit < 0x20 || unit == 0x7f) return true;
    }
    return false;
  }

  static void _expect(bool condition, String message) {
    if (!condition) throw TerminalCompatibilityInventoryException(message);
  }
}

void main(List<String> arguments) {
  if (arguments.length > 1 ||
      (arguments.isNotEmpty && arguments.single != '--check')) {
    stderr.writeln(
      'TERMINAL_COMPATIBILITY_INVENTORY_FAIL usage: '
      'dart run tool/terminal_compatibility_inventory.dart [--check]',
    );
    exitCode = 64;
    return;
  }
  final Directory repositoryRoot = File.fromUri(Platform.script)
      .absolute
      .parent
      .parent;
  try {
    final TerminalCompatibilityInventory inventory =
        TerminalCompatibilityInventory.load(
          File.fromUri(
            repositoryRoot.uri.resolve(
              defaultTerminalCompatibilityInventoryPath,
            ),
          ),
          repositoryRoot: repositoryRoot,
        );
    stdout.writeln(inventory.machineLine());
    if (inventory.scope == 'complete-baseline') {
      stdout.writeln(
        inventory.reconcileImplementationSurface(
          File.fromUri(
            repositoryRoot.uri.resolve(
              defaultTerminalImplementationSurfacePath,
            ),
          ),
        ),
      );
    }
  } on Object catch (error) {
    stderr.writeln('TERMINAL_COMPATIBILITY_INVENTORY_FAIL $error');
    exitCode = 1;
  }
}
