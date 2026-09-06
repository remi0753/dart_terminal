import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dart_terminal/dart_terminal.dart';

Future<void> main() => runTerminalPasteTests();

Future<void> runTerminalPasteTests() async {
  _testModeAwareNewlinesAndSingleFrame();
  _testControlsAndTerminatorAreSafe();
  _testUnicodeAndEverySmallChunkBoundary();
  _testAnalysisAndLimits();
  await _testExpiringContentFreeConfirmation();
}

Future<void> _testExpiringContentFreeConfirmation() async {
  const String boundarySource = 'A\r\n🙂\x1b[201~Z';
  final TerminalPastePlan boundarySync = TerminalPasteCodec.plan(
    boundarySource,
    bracketed: true,
  );
  final TerminalPastePlan boundaryAsync = await TerminalPasteCodec.planAsync(
    boundarySource,
    bracketed: true,
    yieldAfterCodeUnits: 1,
  );
  _expect(
    boundarySync.analysis.fingerprint == boundaryAsync.analysis.fingerprint &&
        boundarySync.analysis.encodedBytes ==
            boundaryAsync.analysis.encodedBytes &&
        boundarySync.analysis.logicalNewlineCount ==
            boundaryAsync.analysis.logicalNewlineCount &&
        boundarySync.analysis.controlCharacterCount ==
            boundaryAsync.analysis.controlCharacterCount &&
        _bytesEqual(
          _collect(boundarySync, chunkBytes: 3),
          _collect(boundaryAsync, chunkBytes: 3),
        ),
    'async planning matches sync analysis across CRLF/surrogate boundaries',
  );
  final TerminalPasteConfirmationGate gate = TerminalPasteConfirmationGate(
    confirmationWindow: const Duration(seconds: 10),
  );
  final TerminalPastePlan safe = TerminalPasteCodec.plan(
    'single line',
    bracketed: false,
  );
  _expect(
    gate
            .evaluate(pasteboardChangeCount: 1, plan: safe, invocationMicros: 0)
            .isApproved &&
        !gate.hasPendingConfirmation,
    'safe content is approved without retaining a confirmation',
  );

  final TerminalPastePlan risky = TerminalPasteCodec.plan(
    'first\nsecond',
    bracketed: true,
  );
  final TerminalPasteApprovalResult first = gate.evaluate(
    pasteboardChangeCount: 2,
    plan: risky,
    invocationMicros: 100,
    confirmationIssuedMicros: 5 * Duration.microsecondsPerSecond,
  );
  _expect(
    first.disposition ==
            TerminalPasteApprovalDisposition.confirmationRequired &&
        gate.hasPendingConfirmation,
    'first risky invocation requires confirmation',
  );
  _expect(
    gate
            .evaluate(
              pasteboardChangeCount: 2,
              plan: TerminalPasteCodec.plan('first\nsecond', bracketed: true),
              invocationMicros: 10 * Duration.microsecondsPerSecond,
              confirmationIssuedMicros: 15 * Duration.microsecondsPerSecond,
            )
            .isApproved &&
        !gate.hasPendingConfirmation,
    'a matching re-read is approved inside the bounded window',
  );

  gate.evaluate(
    pasteboardChangeCount: 3,
    plan: risky,
    invocationMicros: 20 * Duration.microsecondsPerSecond,
  );
  final TerminalPasteApprovalResult changed = gate.evaluate(
    pasteboardChangeCount: 4,
    plan: risky,
    invocationMicros: 21 * Duration.microsecondsPerSecond,
  );
  final TerminalPasteApprovalResult modeChanged = gate.evaluate(
    pasteboardChangeCount: 4,
    plan: TerminalPasteCodec.plan('first\nsecond', bracketed: false),
    invocationMicros: 22 * Duration.microsecondsPerSecond,
  );
  final TerminalPasteApprovalResult expired = gate.evaluate(
    pasteboardChangeCount: 4,
    plan: TerminalPasteCodec.plan('first\nsecond', bracketed: false),
    invocationMicros: 33 * Duration.microsecondsPerSecond,
  );
  _expect(
    changed.disposition ==
            TerminalPasteApprovalDisposition.confirmationRequired &&
        modeChanged.disposition ==
            TerminalPasteApprovalDisposition.confirmationRequired &&
        expired.disposition ==
            TerminalPasteApprovalDisposition.confirmationRequired,
    'change count, terminal mode, and expiry each invalidate confirmation',
  );
  gate.clear();
  _expect(!gate.hasPendingConfirmation, 'confirmation can be cleared');
  final String largeSource = String.fromCharCodes(
    Uint8List(10 * 1024 * 1024)..fillRange(0, 10 * 1024 * 1024, 0x61),
  );
  final TerminalPastePlan firstLarge = TerminalPasteCodec.plan(
    '$largeSource\n',
    bracketed: true,
  );
  var eventLoopAdvanced = false;
  Timer.run(() => eventLoopAdvanced = true);
  final TerminalPastePlan secondLarge = await TerminalPasteCodec.planAsync(
    '$largeSource\n',
    bracketed: true,
  );
  _expect(
    eventLoopAdvanced &&
        firstLarge.analysis.fingerprint == secondLarge.analysis.fingerprint &&
        firstLarge.analysis.encodedBytes == secondLarge.analysis.encodedBytes,
    'async planning yields and retains synchronous analysis parity',
  );
  _expect(
    !gate
        .evaluate(
          pasteboardChangeCount: 9,
          plan: firstLarge,
          invocationMicros: 929569,
          confirmationIssuedMicros: 1083965,
        )
        .isApproved,
    'first 10 MiB invocation requests confirmation',
  );
  _expect(
    gate
        .evaluate(
          pasteboardChangeCount: 9,
          plan: secondLarge,
          invocationMicros: 1190473,
          confirmationIssuedMicros: 1342583,
        )
        .isApproved,
    'matching 10 MiB re-read is approved with product timing',
  );
  _expectThrows<ArgumentError>(
    () => TerminalPasteConfirmationGate(confirmationWindow: Duration.zero),
    'non-positive confirmation window',
  );
  await _expectAsyncThrows<RangeError>(
    () => TerminalPasteCodec.planAsync(
      'x',
      bracketed: false,
      yieldAfterCodeUnits: 0,
    ),
    'zero async planning batch',
  );
}

void _testModeAwareNewlinesAndSingleFrame() {
  const String source = 'one\r\ntwo\rthree\nfour';
  final TerminalPastePlan bracketed = TerminalPasteCodec.plan(
    source,
    bracketed: true,
  );
  _expect(
    bracketed.analysis.logicalNewlineCount == 3 &&
        bracketed.analysis.controlCharacterCount == 0 &&
        bracketed.analysis.requiresConfirmation,
    'logical newlines are normalized and conservatively require confirmation',
  );
  _expectBytes(
    _collect(bracketed, chunkBytes: 3),
    '\x1b[200~one\ntwo\nthree\nfour\x1b[201~',
    'one bracket frame spans every transport chunk',
  );

  final TerminalPastePlan plain = TerminalPasteCodec.plan(
    source,
    bracketed: false,
  );
  _expectBytes(
    _collect(plain, chunkBytes: 2),
    'one\rtwo\rthree\rfour',
    'all logical newlines become one carriage return outside bracket mode',
  );
  _expect(
    bracketed.analysis.encodedBodyBytes == plain.analysis.encodedBodyBytes &&
        bracketed.analysis.encodedBytes == plain.analysis.encodedBytes + 12,
    'analysis counts the frozen frame without a whole encoded allocation',
  );
}

void _testControlsAndTerminatorAreSafe() {
  final String controls = String.fromCharCodes(const <int>[
    0x00,
    0x03,
    0x04,
    0x05,
    0x08,
    0x0f,
    0x11,
    0x12,
    0x13,
    0x15,
    0x16,
    0x17,
    0x1a,
    0x1b,
    0x1c,
    0x7f,
  ]);
  final TerminalPastePlan controlPlan = TerminalPasteCodec.plan(
    'a${controls}z\t',
    bracketed: true,
  );
  _expect(
    controlPlan.analysis.controlCharacterCount == controls.length + 1 &&
        controlPlan.analysis.replacedControlCount == controls.length &&
        controlPlan.analysis.risks.contains(TerminalPasteRisk.controlCharacter),
    'all hidden controls are classified and terminal-driver controls replace',
  );
  _expectBytes(
    _collect(controlPlan, chunkBytes: 1),
    '\x1b[200~a                z\t\x1b[201~',
    'dangerous input bytes become spaces while an intentional tab survives',
  );

  final TerminalPastePlan terminator = TerminalPasteCodec.plan(
    'before\x1b[201~echo injected\nafter',
    bracketed: true,
  );
  final Uint8List encoded = _collect(terminator, chunkBytes: 5);
  _expect(
    terminator.analysis.hasBracketTerminator &&
        terminator.analysis.risks.contains(
          TerminalPasteRisk.bracketTerminator,
        ) &&
        _countSubsequence(encoded, utf8.encode('\x1b[201~')) == 1,
    'embedded terminator is detected and only the encoder suffix survives',
  );
  _expectBytes(
    encoded,
    '\x1b[200~before [201~echo injected\nafter\x1b[201~',
    'ESC replacement prevents bracket escape after confirmation',
  );
}

void _testUnicodeAndEverySmallChunkBoundary() {
  final String source = 'Aé日本🙂e\u0301${String.fromCharCode(0xd800)}Z';
  final TerminalPastePlan plan = TerminalPasteCodec.plan(
    source,
    bracketed: true,
  );
  final Uint8List expected = Uint8List.fromList(
    utf8.encode('\x1b[200~Aé日本🙂e\u0301�Z\x1b[201~'),
  );
  for (int chunkBytes = 1; chunkBytes <= 17; chunkBytes++) {
    _expect(
      _bytesEqual(_collect(plan, chunkBytes: chunkBytes), expected),
      'UTF-8 survives chunk size $chunkBytes',
    );
  }
  final TerminalPasteChunkEncoder encoder = plan.encoder(maximumChunkBytes: 7);
  while (encoder.nextChunk() != null) {}
  _expect(
    encoder.isDone &&
        encoder.nextChunk() == null &&
        encoder.emittedBytes == plan.analysis.encodedBytes,
    'encoder completion and byte count are stable',
  );
  final TerminalPastePlan empty = TerminalPasteCodec.plan('', bracketed: true);
  _expect(
    empty.analysis.isEmpty &&
        empty.analysis.encodedBytes == 0 &&
        empty.encoder().nextChunk() == null,
    'empty paste emits no frame or PTY bytes',
  );
}

void _testAnalysisAndLimits() {
  final TerminalPastePlan first = TerminalPasteCodec.plan(
    'same',
    bracketed: false,
    maximumBodyBytes: 8,
    largeThresholdBytes: 4,
  );
  final TerminalPastePlan second = TerminalPasteCodec.plan(
    'same',
    bracketed: false,
    maximumBodyBytes: 8,
    largeThresholdBytes: 4,
  );
  final TerminalPastePlan different = TerminalPasteCodec.plan(
    'Same',
    bracketed: false,
    maximumBodyBytes: 8,
    largeThresholdBytes: 4,
  );
  _expect(
    first.analysis.isLarge &&
        first.analysis.risks.length == 1 &&
        first.analysis.risks.single == TerminalPasteRisk.large &&
        first.analysis.fingerprint == second.analysis.fingerprint &&
        first.analysis.fingerprint != different.analysis.fingerprint,
    'large threshold and content fingerprint are deterministic',
  );
  _expectThrows<TerminalPasteLimitException>(
    () => TerminalPasteCodec.plan(
      '12345',
      bracketed: false,
      maximumBodyBytes: 4,
      largeThresholdBytes: 4,
    ),
    'encoded body limit is enforced while scanning',
  );
  _expectThrows<RangeError>(
    () => first.encoder(maximumChunkBytes: 0),
    'zero chunk bound',
  );
  _expectThrows<RangeError>(
    () => TerminalPasteCodec.plan(
      'x',
      bracketed: false,
      maximumBodyBytes: 4,
      largeThresholdBytes: 5,
    ),
    'large threshold beyond body bound',
  );
}

Uint8List _collect(TerminalPastePlan plan, {required int chunkBytes}) {
  final TerminalPasteChunkEncoder encoder = plan.encoder(
    maximumChunkBytes: chunkBytes,
  );
  final BytesBuilder bytes = BytesBuilder(copy: false);
  while (true) {
    final Uint8List? chunk = encoder.nextChunk();
    if (chunk == null) break;
    _expect(chunk.isNotEmpty && chunk.length <= chunkBytes, 'chunk bound');
    bytes.add(chunk);
  }
  return bytes.takeBytes();
}

int _countSubsequence(Uint8List bytes, List<int> pattern) {
  var count = 0;
  for (int offset = 0; offset <= bytes.length - pattern.length; offset++) {
    var matches = true;
    for (int index = 0; index < pattern.length; index++) {
      if (bytes[offset + index] != pattern[index]) {
        matches = false;
        break;
      }
    }
    if (matches) count++;
  }
  return count;
}

bool _bytesEqual(List<int> first, List<int> second) {
  if (first.length != second.length) return false;
  for (int index = 0; index < first.length; index++) {
    if (first[index] != second[index]) return false;
  }
  return true;
}

void _expectBytes(Uint8List actual, String expected, String description) {
  _expect(
    _bytesEqual(actual, utf8.encode(expected)),
    '$description: ${utf8.decode(actual, allowMalformed: true)}',
  );
}

void _expectThrows<T extends Object>(void Function() body, String description) {
  try {
    body();
  } on T {
    return;
  }
  throw StateError('paste test failed: expected $T for $description');
}

Future<void> _expectAsyncThrows<T extends Object>(
  Future<void> Function() body,
  String description,
) async {
  try {
    await body();
  } on T {
    return;
  }
  throw StateError('paste test failed: expected $T for $description');
}

void _expect(bool condition, String description) {
  if (!condition) throw StateError('paste test failed: $description');
}
