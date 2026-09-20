import 'dart:collection';
import 'dart:convert';
import 'dart:typed_data';

import 'terminal_note_model.dart';
import 'terminal_sha256.dart';

abstract final class TerminalNoteStoreCodecLimits {
  static const int maximumFileBytes = 16 * 1024 * 1024;
  static const int maximumRestorationPaneContexts = 64;
  static const int maximumDeletionJournalEntries = 8192;
  static const int maximumJsonDepth = 16;
  static const int maximumJsonNodes = 262144;
}

enum TerminalNoteCodecFailure {
  emptyInput,
  fileTooLarge,
  invalidByte,
  invalidUtf8,
  malformedJson,
  duplicateKey,
  nonCanonical,
  unknownFormat,
  unsupportedVersion,
  upgradeRequired,
  checksumMismatch,
  schemaViolation,
  limitExceeded,
  invariantViolation,
  migrationUnavailable,
}

/// Fixed, content-free codec failure suitable for logs and worker messages.
final class TerminalNoteCodecException implements Exception {
  const TerminalNoteCodecException(this.failure);

  final TerminalNoteCodecFailure failure;

  bool get requiresUpgrade =>
      failure == TerminalNoteCodecFailure.upgradeRequired;

  @override
  String toString() => 'Terminal note codec failed: ${failure.name}';
}

final class TerminalNoteRestorationBinding {
  TerminalNoteRestorationBinding({
    required this.restorationSha256,
    required Iterable<TerminalNoteContextId> paneContextIds,
  }) : paneContextIds = List<TerminalNoteContextId>.unmodifiable(
         paneContextIds,
       ) {
    if (!_isLowerHex(restorationSha256, 64) ||
        this.paneContextIds.length >
            TerminalNoteStoreCodecLimits.maximumRestorationPaneContexts ||
        this.paneContextIds.toSet().length != this.paneContextIds.length) {
      throw const TerminalNoteCodecException(
        TerminalNoteCodecFailure.schemaViolation,
      );
    }
  }

  static const int restorationFormat = 1;

  final String restorationSha256;
  final List<TerminalNoteContextId> paneContextIds;
}

final class TerminalNoteStoreDocument {
  TerminalNoteStoreDocument({required this.snapshot, this.restorationBinding}) {
    try {
      snapshot.validate();
    } on TerminalNoteValidationException {
      throw const TerminalNoteCodecException(
        TerminalNoteCodecFailure.invariantViolation,
      );
    }
    final TerminalNoteRestorationBinding? binding = restorationBinding;
    if (binding != null) {
      for (final TerminalNoteContextId id in binding.paneContextIds) {
        final NoteContextRecord? context = snapshot.contextFor(id);
        if (context == null ||
            context.kind != TerminalNoteContextKind.standard) {
          throw const TerminalNoteCodecException(
            TerminalNoteCodecFailure.invariantViolation,
          );
        }
      }
    }
  }

  final TerminalNoteSnapshot snapshot;
  final TerminalNoteRestorationBinding? restorationBinding;
}

final class TerminalNoteDeletionTombstone {
  TerminalNoteDeletionTombstone({
    required this.noteId,
    required this.deletionRevision,
  }) {
    _validateCounter(deletionRevision);
  }

  final NoteId noteId;
  final BigInt deletionRevision;
}

final class TerminalNoteDeletionJournal {
  TerminalNoteDeletionJournal({
    required Iterable<TerminalNoteDeletionTombstone> entries,
  }) : entries = List<TerminalNoteDeletionTombstone>.unmodifiable(entries) {
    if (this.entries.length >
        TerminalNoteStoreCodecLimits.maximumDeletionJournalEntries) {
      throw const TerminalNoteCodecException(
        TerminalNoteCodecFailure.limitExceeded,
      );
    }
    if (this.entries
            .map((TerminalNoteDeletionTombstone entry) => entry.noteId)
            .toSet()
            .length !=
        this.entries.length) {
      throw const TerminalNoteCodecException(
        TerminalNoteCodecFailure.invariantViolation,
      );
    }
  }

  final List<TerminalNoteDeletionTombstone> entries;
}

/// Pure canonical codec for Note store and deletion journal version 1.
final class TerminalNoteStoreCodec {
  const TerminalNoteStoreCodec();

  static const String storeFormat = 'dart-terminal-notes';
  static const String deletionJournalFormat = 'dart-terminal-note-deletions';
  static const int currentVersion = 1;

  Uint8List encode(TerminalNoteStoreDocument document) {
    final _JsonObject payload = _encodeStorePayload(document);
    final String payloadSource = _canonicalJson(payload);
    final String checksum = terminalSha256(utf8.encode(payloadSource));
    return _encodeEnvelope(
      format: storeFormat,
      checksum: checksum,
      payload: payload,
    );
  }

  TerminalNoteStoreDocument decode(List<int> bytes) {
    final _DecodedEnvelope envelope = _decodeEnvelope(
      bytes,
      expectedFormat: storeFormat,
    );
    return _decodeStorePayload(envelope.payload);
  }

  Uint8List encodeDeletionJournal(TerminalNoteDeletionJournal journal) {
    final List<TerminalNoteDeletionTombstone> entries =
        List<TerminalNoteDeletionTombstone>.of(journal.entries)
          ..sort(_compareTombstones);
    final _JsonObject payload = _object(<MapEntry<String, Object?>>[
      MapEntry<String, Object?>('entries', <Object?>[
        for (final TerminalNoteDeletionTombstone entry in entries)
          _object(<MapEntry<String, Object?>>[
            MapEntry<String, Object?>('noteId', entry.noteId.canonicalValue),
            MapEntry<String, Object?>(
              'deletionRevision',
              entry.deletionRevision,
            ),
          ]),
      ]),
    ]);
    return _encodeEnvelope(
      format: deletionJournalFormat,
      checksum: terminalSha256(utf8.encode(_canonicalJson(payload))),
      payload: payload,
    );
  }

  TerminalNoteDeletionJournal decodeDeletionJournal(List<int> bytes) {
    final _DecodedEnvelope envelope = _decodeEnvelope(
      bytes,
      expectedFormat: deletionJournalFormat,
    );
    final _ObjectReader payload = _ObjectReader(
      envelope.payload,
      const <String>['entries'],
    );
    final List<Object?> values = _array(payload.value('entries'));
    if (values.length >
        TerminalNoteStoreCodecLimits.maximumDeletionJournalEntries) {
      _fail(TerminalNoteCodecFailure.limitExceeded);
    }
    final List<TerminalNoteDeletionTombstone> entries =
        <TerminalNoteDeletionTombstone>[];
    TerminalNoteDeletionTombstone? previous;
    final Set<NoteId> noteIds = <NoteId>{};
    for (final Object? value in values) {
      final _ObjectReader record = _ObjectReader(
        _jsonObject(value),
        const <String>['noteId', 'deletionRevision'],
      );
      final TerminalNoteDeletionTombstone entry = TerminalNoteDeletionTombstone(
        noteId: _noteId(record.value('noteId')),
        deletionRevision: _counter(record.value('deletionRevision')),
      );
      if (!noteIds.add(entry.noteId) ||
          (previous != null && _compareTombstones(previous, entry) >= 0)) {
        _fail(TerminalNoteCodecFailure.nonCanonical);
      }
      entries.add(entry);
      previous = entry;
    }
    return TerminalNoteDeletionJournal(entries: entries);
  }

  Uint8List _encodeEnvelope({
    required String format,
    required String checksum,
    required _JsonObject payload,
  }) {
    final _JsonObject envelope = _object(<MapEntry<String, Object?>>[
      MapEntry<String, Object?>('format', format),
      const MapEntry<String, Object?>('version', currentVersion),
      MapEntry<String, Object?>('payloadSha256', checksum),
      MapEntry<String, Object?>('payload', payload),
    ]);
    final Uint8List result = Uint8List.fromList(
      utf8.encode('${_canonicalJson(envelope)}\n'),
    );
    if (result.length > TerminalNoteStoreCodecLimits.maximumFileBytes) {
      _fail(TerminalNoteCodecFailure.fileTooLarge);
    }
    return result;
  }

  _DecodedEnvelope _decodeEnvelope(
    List<int> bytes, {
    required String expectedFormat,
  }) {
    if (bytes.isEmpty) _fail(TerminalNoteCodecFailure.emptyInput);
    if (bytes.length > TerminalNoteStoreCodecLimits.maximumFileBytes) {
      _fail(TerminalNoteCodecFailure.fileTooLarge);
    }
    for (final int byte in bytes) {
      if (byte < 0 || byte > 0xff) {
        _fail(TerminalNoteCodecFailure.invalidByte);
      }
    }
    if (bytes.last != 0x0a) {
      _fail(TerminalNoteCodecFailure.nonCanonical);
    }
    final String source;
    try {
      source = utf8.decode(bytes, allowMalformed: false);
    } on FormatException {
      _fail(TerminalNoteCodecFailure.invalidUtf8);
    }
    final String jsonSource = source.substring(0, source.length - 1);
    final Object? parsed = _StrictJsonParser(jsonSource).parse();
    if (_canonicalJson(parsed) != jsonSource) {
      _fail(TerminalNoteCodecFailure.nonCanonical);
    }
    final _ObjectReader root = _ObjectReader(
      _jsonObject(parsed),
      const <String>['format', 'version', 'payloadSha256', 'payload'],
    );
    if (_string(root.value('format')) != expectedFormat) {
      _fail(TerminalNoteCodecFailure.unknownFormat);
    }
    final BigInt version = _integer(root.value('version'));
    if (version > BigInt.from(currentVersion)) {
      _fail(TerminalNoteCodecFailure.upgradeRequired);
    }
    if (version < BigInt.from(currentVersion)) {
      _fail(TerminalNoteCodecFailure.migrationUnavailable);
    }
    final String checksum = _string(root.value('payloadSha256'));
    if (!_isLowerHex(checksum, 64)) {
      _fail(TerminalNoteCodecFailure.schemaViolation);
    }
    final _JsonObject payload = _jsonObject(root.value('payload'));
    final String actual = terminalSha256(utf8.encode(_canonicalJson(payload)));
    if (actual != checksum) {
      _fail(TerminalNoteCodecFailure.checksumMismatch);
    }
    return _DecodedEnvelope(payload);
  }

  _JsonObject _encodeStorePayload(TerminalNoteStoreDocument document) {
    final TerminalNoteSnapshot snapshot = document.snapshot;
    try {
      snapshot.validate();
    } on TerminalNoteValidationException {
      _fail(TerminalNoteCodecFailure.invariantViolation);
    }
    final List<NoteContextRecord> contexts = snapshot.contexts.values.toList()
      ..sort(
        (NoteContextRecord left, NoteContextRecord right) =>
            left.id.compareTo(right.id),
      );
    final List<NoteRecord> notes = snapshot.notes.values.toList()
      ..sort(
        (NoteRecord left, NoteRecord right) => left.id.compareTo(right.id),
      );
    final List<NoteTriggerRecord> triggers = snapshot.triggers.values.toList()
      ..sort(
        (NoteTriggerRecord left, NoteTriggerRecord right) =>
            left.noteId.compareTo(right.noteId),
      );
    final List<NoteDeliveryRecord> deliveries =
        snapshot.deliveries.values.toList()..sort(_compareDeliveries);
    return _object(<MapEntry<String, Object?>>[
      MapEntry<String, Object?>('storeRevision', snapshot.storeRevision),
      MapEntry<String, Object?>(
        'nextDeliverySequence',
        snapshot.nextDeliverySequence,
      ),
      MapEntry<String, Object?>('contexts', <Object?>[
        for (final NoteContextRecord context in contexts)
          _object(<MapEntry<String, Object?>>[
            MapEntry<String, Object?>('id', context.id.canonicalValue),
            MapEntry<String, Object?>('kind', _contextKind(context.kind)),
            MapEntry<String, Object?>('state', _contextState(context.state)),
            MapEntry<String, Object?>('revision', context.revision),
          ]),
      ]),
      MapEntry<String, Object?>('notes', <Object?>[
        for (final NoteRecord note in notes) _encodeNote(note),
      ]),
      MapEntry<String, Object?>('triggers', <Object?>[
        for (final NoteTriggerRecord trigger in triggers)
          _object(<MapEntry<String, Object?>>[
            MapEntry<String, Object?>('noteId', trigger.noteId.canonicalValue),
            MapEntry<String, Object?>('generation', trigger.generation),
            MapEntry<String, Object?>('kind', _triggerKind(trigger.kind)),
            MapEntry<String, Object?>('phase', _triggerPhase(trigger.phase)),
            MapEntry<String, Object?>(
              'suspendReason',
              trigger.suspendReason == null
                  ? null
                  : _suspendReason(trigger.suspendReason!),
            ),
            MapEntry<String, Object?>(
              'armedAtRevision',
              trigger.armedAtRevision,
            ),
          ]),
      ]),
      MapEntry<String, Object?>('deliveries', <Object?>[
        for (final NoteDeliveryRecord delivery in deliveries)
          _object(<MapEntry<String, Object?>>[
            MapEntry<String, Object?>('noteId', delivery.noteId.canonicalValue),
            MapEntry<String, Object?>(
              'triggerGeneration',
              delivery.triggerGeneration,
            ),
            MapEntry<String, Object?>('sequence', delivery.sequence.value),
          ]),
      ]),
      MapEntry<String, Object?>(
        'restorationBinding',
        _encodeRestorationBinding(document.restorationBinding),
      ),
    ]);
  }

  TerminalNoteStoreDocument _decodeStorePayload(_JsonObject value) {
    try {
      final _ObjectReader payload = _ObjectReader(value, const <String>[
        'storeRevision',
        'nextDeliverySequence',
        'contexts',
        'notes',
        'triggers',
        'deliveries',
        'restorationBinding',
      ]);
      final BigInt storeRevision = _counter(
        payload.value('storeRevision'),
        allowZero: true,
      );
      final BigInt nextDeliverySequence = _counter(
        payload.value('nextDeliverySequence'),
      );
      final Map<TerminalNoteContextId, NoteContextRecord> contexts =
          _decodeContexts(payload.value('contexts'));
      final Map<NoteId, NoteRecord> notes = _decodeNotes(
        payload.value('notes'),
      );
      final Map<NoteId, NoteTriggerRecord> triggers = _decodeTriggers(
        payload.value('triggers'),
      );
      final Map<NoteId, NoteDeliveryRecord> deliveries = _decodeDeliveries(
        payload.value('deliveries'),
      );
      final TerminalNoteSnapshot snapshot = TerminalNoteSnapshot.fromRecords(
        storeRevision: storeRevision,
        nextDeliverySequence: nextDeliverySequence,
        contexts: contexts,
        notes: notes,
        triggers: triggers,
        deliveries: deliveries,
      );
      final TerminalNoteRestorationBinding? binding = _decodeRestorationBinding(
        payload.value('restorationBinding'),
      );
      return TerminalNoteStoreDocument(
        snapshot: snapshot,
        restorationBinding: binding,
      );
    } on TerminalNoteCodecException {
      rethrow;
    } on TerminalNoteValidationException {
      _fail(TerminalNoteCodecFailure.invariantViolation);
    } on Object {
      _fail(TerminalNoteCodecFailure.schemaViolation);
    }
  }

  Map<TerminalNoteContextId, NoteContextRecord> _decodeContexts(Object? value) {
    final List<Object?> values = _array(value);
    if (values.length > TerminalNoteLimits.maximumContexts) {
      _fail(TerminalNoteCodecFailure.limitExceeded);
    }
    final Map<TerminalNoteContextId, NoteContextRecord> result =
        <TerminalNoteContextId, NoteContextRecord>{};
    TerminalNoteContextId? previous;
    for (final Object? value in values) {
      final _ObjectReader record = _ObjectReader(
        _jsonObject(value),
        const <String>['id', 'kind', 'state', 'revision'],
      );
      final TerminalNoteContextId id = _contextId(record.value('id'));
      if (previous != null && previous.compareTo(id) >= 0) {
        _fail(TerminalNoteCodecFailure.nonCanonical);
      }
      result[id] = NoteContextRecord(
        id: id,
        kind: _decodeContextKind(record.value('kind')),
        state: _decodeContextState(record.value('state')),
        revision: _counter(record.value('revision')),
      );
      previous = id;
    }
    return result;
  }

  Map<NoteId, NoteRecord> _decodeNotes(Object? value) {
    final List<Object?> values = _array(value);
    if (values.length > TerminalNoteLimits.maximumNotes) {
      _fail(TerminalNoteCodecFailure.limitExceeded);
    }
    final Map<NoteId, NoteRecord> result = <NoteId, NoteRecord>{};
    NoteId? previous;
    for (final Object? value in values) {
      final _ObjectReader record = _ObjectReader(
        _jsonObject(value),
        const <String>[
          'id',
          'attachment',
          'body',
          'color',
          'status',
          'order',
          'createdAtUtcMicros',
          'updatedAtUtcMicros',
          'revision',
        ],
      );
      final NoteId id = _noteId(record.value('id'));
      if (previous != null && previous.compareTo(id) >= 0) {
        _fail(TerminalNoteCodecFailure.nonCanonical);
      }
      final String bodySource = _string(record.value('body'));
      final NoteBody body = NoteBody.fromText(bodySource);
      if (body.value != bodySource) {
        _fail(TerminalNoteCodecFailure.nonCanonical);
      }
      result[id] = NoteRecord(
        id: id,
        attachment: _decodeAttachment(record.value('attachment')),
        body: body,
        color: _decodeColor(record.value('color')),
        status: _decodeStatus(record.value('status')),
        order: _boundedInt(record.value('order'), allowZero: true),
        createdAtUtcMicros: _boundedInt(
          record.value('createdAtUtcMicros'),
          allowZero: true,
        ),
        updatedAtUtcMicros: _boundedInt(
          record.value('updatedAtUtcMicros'),
          allowZero: true,
        ),
        revision: _counter(record.value('revision')),
      );
      previous = id;
    }
    return result;
  }

  Map<NoteId, NoteTriggerRecord> _decodeTriggers(Object? value) {
    final List<Object?> values = _array(value);
    if (values.length > TerminalNoteLimits.maximumTriggers) {
      _fail(TerminalNoteCodecFailure.limitExceeded);
    }
    final Map<NoteId, NoteTriggerRecord> result = <NoteId, NoteTriggerRecord>{};
    NoteId? previous;
    for (final Object? value in values) {
      final _ObjectReader record = _ObjectReader(
        _jsonObject(value),
        const <String>[
          'noteId',
          'generation',
          'kind',
          'phase',
          'suspendReason',
          'armedAtRevision',
        ],
      );
      final NoteId noteId = _noteId(record.value('noteId'));
      if (previous != null && previous.compareTo(noteId) >= 0) {
        _fail(TerminalNoteCodecFailure.nonCanonical);
      }
      final NoteTriggerKind kind = _decodeTriggerKind(record.value('kind'));
      NoteTriggerPhase phase = _decodeTriggerPhase(record.value('phase'));
      NoteTriggerSuspendReason? reason = _nullableSuspendReason(
        record.value('suspendReason'),
      );
      if (kind == NoteTriggerKind.atNextPrompt &&
          phase != NoteTriggerPhase.due &&
          phase != NoteTriggerPhase.suspended) {
        phase = NoteTriggerPhase.suspended;
        reason = NoteTriggerSuspendReason.sessionEnded;
      }
      result[noteId] = NoteTriggerRecord(
        noteId: noteId,
        generation: _counter(record.value('generation')),
        kind: kind,
        phase: phase,
        suspendReason: reason,
        armedAtRevision: _counter(record.value('armedAtRevision')),
      );
      previous = noteId;
    }
    return result;
  }

  Map<NoteId, NoteDeliveryRecord> _decodeDeliveries(Object? value) {
    final List<Object?> values = _array(value);
    if (values.length > TerminalNoteLimits.maximumDeliveries) {
      _fail(TerminalNoteCodecFailure.limitExceeded);
    }
    final Map<NoteId, NoteDeliveryRecord> result =
        <NoteId, NoteDeliveryRecord>{};
    NoteDeliveryRecord? previous;
    for (final Object? value in values) {
      final _ObjectReader record = _ObjectReader(
        _jsonObject(value),
        const <String>['noteId', 'triggerGeneration', 'sequence'],
      );
      final NoteDeliveryRecord delivery = NoteDeliveryRecord(
        noteId: _noteId(record.value('noteId')),
        triggerGeneration: _counter(record.value('triggerGeneration')),
        sequence: DeliverySequence(_counter(record.value('sequence'))),
      );
      if (previous != null && _compareDeliveries(previous, delivery) >= 0) {
        _fail(TerminalNoteCodecFailure.nonCanonical);
      }
      if (result.containsKey(delivery.noteId)) {
        _fail(TerminalNoteCodecFailure.invariantViolation);
      }
      result[delivery.noteId] = delivery;
      previous = delivery;
    }
    return result;
  }

  TerminalNoteRestorationBinding? _decodeRestorationBinding(Object? value) {
    if (value == null) return null;
    final _ObjectReader binding = _ObjectReader(
      _jsonObject(value),
      const <String>[
        'restorationFormat',
        'restorationSha256',
        'paneContextIds',
      ],
    );
    if (_integer(binding.value('restorationFormat')) != BigInt.one) {
      _fail(TerminalNoteCodecFailure.schemaViolation);
    }
    final List<Object?> ids = _array(binding.value('paneContextIds'));
    if (ids.length >
        TerminalNoteStoreCodecLimits.maximumRestorationPaneContexts) {
      _fail(TerminalNoteCodecFailure.limitExceeded);
    }
    return TerminalNoteRestorationBinding(
      restorationSha256: _string(binding.value('restorationSha256')),
      paneContextIds: <TerminalNoteContextId>[
        for (final Object? id in ids) _contextId(id),
      ],
    );
  }
}

/// Version-gated pure migration entrypoint. Version 1 currently has no step.
final class TerminalNoteStoreMigrator {
  const TerminalNoteStoreMigrator({
    this.codec = const TerminalNoteStoreCodec(),
  });

  final TerminalNoteStoreCodec codec;

  TerminalNoteStoreDocument migrate(
    List<int> source, {
    int targetVersion = TerminalNoteStoreCodec.currentVersion,
  }) {
    if (targetVersion != TerminalNoteStoreCodec.currentVersion) {
      throw const TerminalNoteCodecException(
        TerminalNoteCodecFailure.migrationUnavailable,
      );
    }
    return codec.decode(source);
  }
}

_JsonObject _encodeNote(NoteRecord note) => _object(<MapEntry<String, Object?>>[
  MapEntry<String, Object?>('id', note.id.canonicalValue),
  MapEntry<String, Object?>('attachment', _encodeAttachment(note.attachment)),
  MapEntry<String, Object?>('body', note.body.value),
  MapEntry<String, Object?>('color', _color(note.color)),
  MapEntry<String, Object?>('status', _status(note.status)),
  MapEntry<String, Object?>('order', BigInt.from(note.order)),
  MapEntry<String, Object?>(
    'createdAtUtcMicros',
    BigInt.from(note.createdAtUtcMicros),
  ),
  MapEntry<String, Object?>(
    'updatedAtUtcMicros',
    BigInt.from(note.updatedAtUtcMicros),
  ),
  MapEntry<String, Object?>('revision', note.revision),
]);

_JsonObject _encodeAttachment(TerminalNoteAttachment attachment) =>
    attachment.isAttached
    ? _object(<MapEntry<String, Object?>>[
        const MapEntry<String, Object?>('kind', 'attached'),
        MapEntry<String, Object?>(
          'contextId',
          attachment.contextId!.canonicalValue,
        ),
      ])
    : _object(<MapEntry<String, Object?>>[
        const MapEntry<String, Object?>('kind', 'detached'),
        MapEntry<String, Object?>(
          'previousContextId',
          attachment.previousContextId!.canonicalValue,
        ),
        MapEntry<String, Object?>(
          'reason',
          _detachReason(attachment.detachReason!),
        ),
      ]);

TerminalNoteAttachment _decodeAttachment(Object? value) {
  final _JsonObject object = _jsonObject(value);
  if (object.entries.isEmpty) _fail(TerminalNoteCodecFailure.schemaViolation);
  final String kind = _string(object.entries.first.value);
  if (object.entries.first.key != 'kind') {
    _fail(TerminalNoteCodecFailure.nonCanonical);
  }
  return switch (kind) {
    'attached' => () {
      final _ObjectReader reader = _ObjectReader(object, const <String>[
        'kind',
        'contextId',
      ]);
      return TerminalNoteAttachment.attached(
        _contextId(reader.value('contextId')),
      );
    }(),
    'detached' => () {
      final _ObjectReader reader = _ObjectReader(object, const <String>[
        'kind',
        'previousContextId',
        'reason',
      ]);
      return TerminalNoteAttachment.detached(
        previousContextId: _contextId(reader.value('previousContextId')),
        reason: _decodeDetachReason(reader.value('reason')),
      );
    }(),
    _ => throw const TerminalNoteCodecException(
      TerminalNoteCodecFailure.schemaViolation,
    ),
  };
}

Object? _encodeRestorationBinding(TerminalNoteRestorationBinding? binding) =>
    binding == null
    ? null
    : _object(<MapEntry<String, Object?>>[
        const MapEntry<String, Object?>(
          'restorationFormat',
          TerminalNoteRestorationBinding.restorationFormat,
        ),
        MapEntry<String, Object?>(
          'restorationSha256',
          binding.restorationSha256,
        ),
        MapEntry<String, Object?>('paneContextIds', <Object?>[
          for (final TerminalNoteContextId id in binding.paneContextIds)
            id.canonicalValue,
        ]),
      ]);

String _contextKind(TerminalNoteContextKind value) => switch (value) {
  TerminalNoteContextKind.standard => 'standard',
  TerminalNoteContextKind.quickTerminal => 'quickTerminal',
};

TerminalNoteContextKind _decodeContextKind(Object? value) =>
    switch (_string(value)) {
      'standard' => TerminalNoteContextKind.standard,
      'quickTerminal' => TerminalNoteContextKind.quickTerminal,
      _ => throw const TerminalNoteCodecException(
        TerminalNoteCodecFailure.schemaViolation,
      ),
    };

String _contextState(TerminalNoteContextState value) => switch (value) {
  TerminalNoteContextState.active => 'active',
  TerminalNoteContextState.restorable => 'restorable',
  TerminalNoteContextState.detached => 'detached',
};

TerminalNoteContextState _decodeContextState(Object? value) =>
    switch (_string(value)) {
      'active' => TerminalNoteContextState.active,
      'restorable' => TerminalNoteContextState.restorable,
      'detached' => TerminalNoteContextState.detached,
      _ => throw const TerminalNoteCodecException(
        TerminalNoteCodecFailure.schemaViolation,
      ),
    };

String _color(NoteColorKey value) => switch (value) {
  NoteColorKey.neutral => 'neutral',
  NoteColorKey.yellow => 'yellow',
  NoteColorKey.blue => 'blue',
  NoteColorKey.green => 'green',
  NoteColorKey.pink => 'pink',
  NoteColorKey.purple => 'purple',
};

NoteColorKey _decodeColor(Object? value) => switch (_string(value)) {
  'neutral' => NoteColorKey.neutral,
  'yellow' => NoteColorKey.yellow,
  'blue' => NoteColorKey.blue,
  'green' => NoteColorKey.green,
  'pink' => NoteColorKey.pink,
  'purple' => NoteColorKey.purple,
  _ => throw const TerminalNoteCodecException(
    TerminalNoteCodecFailure.schemaViolation,
  ),
};

String _status(NoteStatus value) => switch (value) {
  NoteStatus.active => 'active',
  NoteStatus.resolved => 'resolved',
};

NoteStatus _decodeStatus(Object? value) => switch (_string(value)) {
  'active' => NoteStatus.active,
  'resolved' => NoteStatus.resolved,
  _ => throw const TerminalNoteCodecException(
    TerminalNoteCodecFailure.schemaViolation,
  ),
};

String _detachReason(TerminalNoteDetachReason value) => switch (value) {
  TerminalNoteDetachReason.paneClosed => 'paneClosed',
  TerminalNoteDetachReason.restorationMismatch => 'restorationMismatch',
  TerminalNoteDetachReason.contextUnavailable => 'contextUnavailable',
  TerminalNoteDetachReason.explicitDetach => 'explicitDetach',
};

TerminalNoteDetachReason _decodeDetachReason(Object? value) =>
    switch (_string(value)) {
      'paneClosed' => TerminalNoteDetachReason.paneClosed,
      'restorationMismatch' => TerminalNoteDetachReason.restorationMismatch,
      'contextUnavailable' => TerminalNoteDetachReason.contextUnavailable,
      'explicitDetach' => TerminalNoteDetachReason.explicitDetach,
      _ => throw const TerminalNoteCodecException(
        TerminalNoteCodecFailure.schemaViolation,
      ),
    };

String _triggerKind(NoteTriggerKind value) => switch (value) {
  NoteTriggerKind.onReturn => 'onReturn',
  NoteTriggerKind.atNextPrompt => 'atNextPrompt',
};

NoteTriggerKind _decodeTriggerKind(Object? value) => switch (_string(value)) {
  'onReturn' => NoteTriggerKind.onReturn,
  'atNextPrompt' => NoteTriggerKind.atNextPrompt,
  _ => throw const TerminalNoteCodecException(
    TerminalNoteCodecFailure.schemaViolation,
  ),
};

String _triggerPhase(NoteTriggerPhase value) => switch (value) {
  NoteTriggerPhase.onReturnArmedHere => 'onReturnArmedHere',
  NoteTriggerPhase.onReturnArmedAway => 'onReturnArmedAway',
  NoteTriggerPhase.atNextPromptWaitingCommand => 'atNextPromptWaitingCommand',
  NoteTriggerPhase.atNextPromptWaitingEnd => 'atNextPromptWaitingEnd',
  NoteTriggerPhase.atNextPromptWaitingPromptStart =>
    'atNextPromptWaitingPromptStart',
  NoteTriggerPhase.atNextPromptWaitingInput => 'atNextPromptWaitingInput',
  NoteTriggerPhase.due => 'due',
  NoteTriggerPhase.suspended => 'suspended',
};

NoteTriggerPhase _decodeTriggerPhase(Object? value) => switch (_string(value)) {
  'onReturnArmedHere' => NoteTriggerPhase.onReturnArmedHere,
  'onReturnArmedAway' => NoteTriggerPhase.onReturnArmedAway,
  'atNextPromptWaitingCommand' => NoteTriggerPhase.atNextPromptWaitingCommand,
  'atNextPromptWaitingEnd' => NoteTriggerPhase.atNextPromptWaitingEnd,
  'atNextPromptWaitingPromptStart' =>
    NoteTriggerPhase.atNextPromptWaitingPromptStart,
  'atNextPromptWaitingInput' => NoteTriggerPhase.atNextPromptWaitingInput,
  'due' => NoteTriggerPhase.due,
  'suspended' => NoteTriggerPhase.suspended,
  _ => throw const TerminalNoteCodecException(
    TerminalNoteCodecFailure.schemaViolation,
  ),
};

String _suspendReason(NoteTriggerSuspendReason value) => switch (value) {
  NoteTriggerSuspendReason.sessionEnded => 'sessionEnded',
  NoteTriggerSuspendReason.instanceChanged => 'instanceChanged',
  NoteTriggerSuspendReason.semanticReset => 'semanticReset',
  NoteTriggerSuspendReason.adapterDisabled => 'adapterDisabled',
  NoteTriggerSuspendReason.versionMismatch => 'versionMismatch',
  NoteTriggerSuspendReason.eventOverflow => 'eventOverflow',
};

NoteTriggerSuspendReason? _nullableSuspendReason(Object? value) => value == null
    ? null
    : switch (_string(value)) {
        'sessionEnded' => NoteTriggerSuspendReason.sessionEnded,
        'instanceChanged' => NoteTriggerSuspendReason.instanceChanged,
        'semanticReset' => NoteTriggerSuspendReason.semanticReset,
        'adapterDisabled' => NoteTriggerSuspendReason.adapterDisabled,
        'versionMismatch' => NoteTriggerSuspendReason.versionMismatch,
        'eventOverflow' => NoteTriggerSuspendReason.eventOverflow,
        _ => throw const TerminalNoteCodecException(
          TerminalNoteCodecFailure.schemaViolation,
        ),
      };

int _compareDeliveries(NoteDeliveryRecord left, NoteDeliveryRecord right) {
  final int sequence = left.sequence.compareTo(right.sequence);
  return sequence == 0 ? left.noteId.compareTo(right.noteId) : sequence;
}

int _compareTombstones(
  TerminalNoteDeletionTombstone left,
  TerminalNoteDeletionTombstone right,
) {
  final int revision = left.deletionRevision.compareTo(right.deletionRevision);
  return revision == 0 ? left.noteId.compareTo(right.noteId) : revision;
}

NoteId _noteId(Object? value) {
  try {
    return NoteId.fromHex(_string(value));
  } on TerminalNoteValidationException {
    _fail(TerminalNoteCodecFailure.schemaViolation);
  }
}

TerminalNoteContextId _contextId(Object? value) {
  try {
    return TerminalNoteContextId.fromHex(_string(value));
  } on TerminalNoteValidationException {
    _fail(TerminalNoteCodecFailure.schemaViolation);
  }
}

BigInt _counter(Object? value, {bool allowZero = false}) {
  final BigInt result = _integer(value);
  if (result < (allowZero ? BigInt.zero : BigInt.one) ||
      result > TerminalNoteLimits.maximumUnsigned64) {
    _fail(TerminalNoteCodecFailure.limitExceeded);
  }
  return result;
}

void _validateCounter(BigInt value) {
  if (value < BigInt.one || value > TerminalNoteLimits.maximumUnsigned64) {
    throw const TerminalNoteCodecException(
      TerminalNoteCodecFailure.limitExceeded,
    );
  }
}

int _boundedInt(Object? value, {bool allowZero = false}) {
  final BigInt integer = _integer(value);
  final BigInt minimum = allowZero ? BigInt.zero : BigInt.one;
  if (integer < minimum || integer > BigInt.from(0x7fffffffffffffff)) {
    _fail(TerminalNoteCodecFailure.schemaViolation);
  }
  return integer.toInt();
}

String _string(Object? value) {
  if (value is! String) _fail(TerminalNoteCodecFailure.schemaViolation);
  return value;
}

BigInt _integer(Object? value) {
  if (value is! BigInt) _fail(TerminalNoteCodecFailure.schemaViolation);
  return value;
}

List<Object?> _array(Object? value) {
  if (value is! List<Object?>) {
    _fail(TerminalNoteCodecFailure.schemaViolation);
  }
  return value;
}

_JsonObject _jsonObject(Object? value) {
  if (value is! _JsonObject) {
    _fail(TerminalNoteCodecFailure.schemaViolation);
  }
  return value;
}

bool _isLowerHex(String value, int length) {
  if (value.length != length) return false;
  for (final int unit in value.codeUnits) {
    final bool digit = unit >= 0x30 && unit <= 0x39;
    final bool lower = unit >= 0x61 && unit <= 0x66;
    if (!digit && !lower) return false;
  }
  return true;
}

Never _fail(TerminalNoteCodecFailure failure) =>
    throw TerminalNoteCodecException(failure);

final class _DecodedEnvelope {
  const _DecodedEnvelope(this.payload);

  final _JsonObject payload;
}

final class _ObjectReader {
  _ObjectReader(this.object, List<String> expectedKeys) {
    if (object.entries.length != expectedKeys.length) {
      _fail(TerminalNoteCodecFailure.schemaViolation);
    }
    for (var index = 0; index < expectedKeys.length; index++) {
      if (object.entries[index].key != expectedKeys[index]) {
        _fail(TerminalNoteCodecFailure.schemaViolation);
      }
    }
  }

  final _JsonObject object;

  Object? value(String key) => object.values[key];
}

final class _JsonObject {
  factory _JsonObject(Iterable<MapEntry<String, Object?>> entries) {
    final List<MapEntry<String, Object?>> materialized =
        List<MapEntry<String, Object?>>.unmodifiable(entries);
    return _JsonObject._(
      materialized,
      UnmodifiableMapView<String, Object?>(<String, Object?>{
        for (final MapEntry<String, Object?> entry in materialized)
          entry.key: entry.value,
      }),
    );
  }

  const _JsonObject._(this.entries, this.values);

  final List<MapEntry<String, Object?>> entries;
  final Map<String, Object?> values;
}

_JsonObject _object(List<MapEntry<String, Object?>> entries) =>
    _JsonObject(entries);

String _canonicalJson(Object? value) {
  final StringBuffer output = StringBuffer();
  _writeCanonicalJson(output, value);
  return output.toString();
}

void _writeCanonicalJson(StringBuffer output, Object? value) {
  if (value == null) {
    output.write('null');
  } else if (value is String) {
    output.write(jsonEncode(value));
  } else if (value is BigInt) {
    output.write(value.toString());
  } else if (value is int) {
    output.write(value.toString());
  } else if (value is bool) {
    output.write(value ? 'true' : 'false');
  } else if (value is List<Object?>) {
    output.write('[');
    for (var index = 0; index < value.length; index++) {
      if (index != 0) output.write(',');
      _writeCanonicalJson(output, value[index]);
    }
    output.write(']');
  } else if (value is _JsonObject) {
    output.write('{');
    for (var index = 0; index < value.entries.length; index++) {
      if (index != 0) output.write(',');
      final MapEntry<String, Object?> entry = value.entries[index];
      output
        ..write(jsonEncode(entry.key))
        ..write(':');
      _writeCanonicalJson(output, entry.value);
    }
    output.write('}');
  } else {
    _fail(TerminalNoteCodecFailure.schemaViolation);
  }
}

final class _StrictJsonParser {
  _StrictJsonParser(this.source);

  final String source;
  var _index = 0;
  var _nodes = 0;

  Object? parse() {
    _skipWhitespace();
    final Object? result = _parseValue(0);
    _skipWhitespace();
    if (_index != source.length) {
      _fail(TerminalNoteCodecFailure.malformedJson);
    }
    return result;
  }

  Object? _parseValue(int depth) {
    if (depth > TerminalNoteStoreCodecLimits.maximumJsonDepth ||
        ++_nodes > TerminalNoteStoreCodecLimits.maximumJsonNodes) {
      _fail(TerminalNoteCodecFailure.limitExceeded);
    }
    if (_index >= source.length) {
      _fail(TerminalNoteCodecFailure.malformedJson);
    }
    return switch (source.codeUnitAt(_index)) {
      0x7b => _parseObject(depth + 1),
      0x5b => _parseArray(depth + 1),
      0x22 => _parseString(),
      0x74 => _parseLiteral('true', true),
      0x66 => _parseLiteral('false', false),
      0x6e => _parseLiteral('null', null),
      0x2d => _parseInteger(),
      >= 0x30 && <= 0x39 => _parseInteger(),
      _ => throw const TerminalNoteCodecException(
        TerminalNoteCodecFailure.malformedJson,
      ),
    };
  }

  _JsonObject _parseObject(int depth) {
    ++_index;
    _skipWhitespace();
    final List<MapEntry<String, Object?>> entries =
        <MapEntry<String, Object?>>[];
    final Set<String> keys = <String>{};
    if (_take(0x7d)) return _JsonObject(entries);
    while (true) {
      if (_index >= source.length || source.codeUnitAt(_index) != 0x22) {
        _fail(TerminalNoteCodecFailure.malformedJson);
      }
      final String key = _parseString();
      if (!keys.add(key)) _fail(TerminalNoteCodecFailure.duplicateKey);
      _skipWhitespace();
      if (!_take(0x3a)) _fail(TerminalNoteCodecFailure.malformedJson);
      _skipWhitespace();
      entries.add(MapEntry<String, Object?>(key, _parseValue(depth)));
      _skipWhitespace();
      if (_take(0x7d)) break;
      if (!_take(0x2c)) _fail(TerminalNoteCodecFailure.malformedJson);
      _skipWhitespace();
    }
    return _JsonObject(entries);
  }

  List<Object?> _parseArray(int depth) {
    ++_index;
    _skipWhitespace();
    final List<Object?> result = <Object?>[];
    if (_take(0x5d)) return result;
    while (true) {
      result.add(_parseValue(depth));
      _skipWhitespace();
      if (_take(0x5d)) break;
      if (!_take(0x2c)) _fail(TerminalNoteCodecFailure.malformedJson);
      _skipWhitespace();
    }
    return result;
  }

  String _parseString() {
    final int start = _index++;
    var escaped = false;
    while (_index < source.length) {
      final int unit = source.codeUnitAt(_index++);
      if (unit < 0x20) _fail(TerminalNoteCodecFailure.malformedJson);
      if (escaped) {
        escaped = false;
        continue;
      }
      if (unit == 0x5c) {
        escaped = true;
        continue;
      }
      if (unit == 0x22) {
        final String token = source.substring(start, _index);
        try {
          final Object? decoded = jsonDecode(token);
          if (decoded is String) return decoded;
        } on FormatException {
          _fail(TerminalNoteCodecFailure.malformedJson);
        }
        _fail(TerminalNoteCodecFailure.malformedJson);
      }
    }
    _fail(TerminalNoteCodecFailure.malformedJson);
  }

  BigInt _parseInteger() {
    final int start = _index;
    _take(0x2d);
    if (_index >= source.length) {
      _fail(TerminalNoteCodecFailure.malformedJson);
    }
    if (source.codeUnitAt(_index) == 0x30) {
      ++_index;
    } else {
      final int first = source.codeUnitAt(_index);
      if (first < 0x31 || first > 0x39) {
        _fail(TerminalNoteCodecFailure.malformedJson);
      }
      while (_index < source.length) {
        final int unit = source.codeUnitAt(_index);
        if (unit < 0x30 || unit > 0x39) break;
        ++_index;
      }
    }
    final String token = source.substring(start, _index);
    try {
      return BigInt.parse(token);
    } on FormatException {
      _fail(TerminalNoteCodecFailure.malformedJson);
    }
  }

  T _parseLiteral<T>(String literal, T value) {
    if (!source.startsWith(literal, _index)) {
      _fail(TerminalNoteCodecFailure.malformedJson);
    }
    _index += literal.length;
    return value;
  }

  bool _take(int unit) {
    if (_index < source.length && source.codeUnitAt(_index) == unit) {
      ++_index;
      return true;
    }
    return false;
  }

  void _skipWhitespace() {
    while (_index < source.length) {
      final int unit = source.codeUnitAt(_index);
      if (unit != 0x20 && unit != 0x09 && unit != 0x0a && unit != 0x0d) {
        return;
      }
      ++_index;
    }
  }
}
