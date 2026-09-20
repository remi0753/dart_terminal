import 'dart:convert';

import 'package:dart_terminal/dart_terminal.dart';

Future<void> main() => runTerminalNativeContentTests();

Future<void> runTerminalNativeContentTests() async {
  _testBoundedWordLookup();
  _testWideWrappedAndStaleWordLookup();
  _testNativeContentGeometryAndMousePolicy();
  _testServicesSelectionAndFolderPolicy();
  _testExternalTextAdmission();
  _testShellSafeFilePathAdmission();
  _testExternalContentLimits();
  await _testExternalPasteLifecycle();
}

void _testNativeContentGeometryAndMousePolicy() {
  final TerminalScreenSet screens = TerminalScreenSet(rows: 2, columns: 8);
  _write(screens.primary, 'alpha');
  final TerminalNativeContentCell? cell =
      TerminalNativeContentPolicy.cellAtPoint(
        x: 26,
        y: 31,
        contentOriginX: 10,
        contentOriginY: 7,
        cellWidth: 8,
        cellHeight: 16,
        rows: 2,
        columns: 8,
      );
  _expect(
    cell == const TerminalNativeContentCell(row: 1, column: 2) &&
        TerminalNativeContentPolicy.cellAtPoint(
              x: 9.9,
              y: 7,
              contentOriginX: 10,
              contentOriginY: 7,
              cellWidth: 8,
              cellHeight: 16,
              rows: 2,
              columns: 8,
            ) ==
            null &&
        TerminalNativeContentPolicy.cellAtPoint(
              x: 10,
              y: double.nan,
              contentOriginX: 10,
              contentOriginY: 7,
              cellWidth: 8,
              cellHeight: 16,
              rows: 2,
              columns: 8,
            ) ==
            null,
    'native points resolve only inside finite padding-aware grid geometry',
  );
  final TerminalWordCandidate candidate = TerminalWordLookup.atCell(
    screens.viewport,
    0,
    2,
  ).candidate!;
  final TerminalDefinitionPlacement? placement =
      TerminalNativeContentPolicy.definitionPlacement(
        candidate: candidate,
        contentOriginX: 10,
        contentOriginY: 7,
        cellWidth: 8,
        cellHeight: 16,
        fontBaseline: 12,
      );
  _expect(
    placement?.baselineX == 10 && placement?.baselineY == 19,
    'definition placement uses the word start and current font baseline',
  );
  _expect(
    TerminalNativeContentPolicy.cursorCell(
          viewport: screens.viewport,
          cursorRow: 0,
          cursorColumn: 4,
        ) ==
        const TerminalNativeContentCell(row: 0, column: 4),
    'keyboard Quick Look resolves the visible caret cell',
  );

  _expect(
    TerminalNativeContentPolicy.isContextGesture(
          isButtonDown: true,
          button: 1,
          control: false,
        ) &&
        TerminalNativeContentPolicy.isContextGesture(
          isButtonDown: true,
          button: 0,
          control: true,
        ) &&
        !TerminalNativeContentPolicy.isContextGesture(
          isButtonDown: false,
          button: 1,
          control: false,
        ) &&
        TerminalNativeContentPolicy.contextMenuAvailable(
          isLive: true,
          mouseModes: const TerminalMouseModes(),
        ) &&
        !TerminalNativeContentPolicy.contextMenuAvailable(
          isLive: true,
          mouseModes: const TerminalMouseModes(
            tracking: TerminalMouseTrackingMode.anyEvent,
          ),
        ) &&
        !TerminalNativeContentPolicy.contextMenuAvailable(
          isLive: false,
          mouseModes: const TerminalMouseModes(),
        ),
    'secondary/control gestures are native only outside terminal capture',
  );
  final TerminalNativeContextGestureGate<String> gestureGate =
      TerminalNativeContextGestureGate<String>();
  _expect(
    gestureGate.suppress(
          target: 'tab',
          isButtonDown: true,
          isButtonUp: false,
          startsNativeContextGesture: true,
        ) &&
        gestureGate.suppress(
          target: 'tab',
          isButtonDown: false,
          isButtonUp: false,
          startsNativeContextGesture: false,
        ) &&
        gestureGate.suppress(
          target: 'tab',
          isButtonDown: false,
          isButtonUp: true,
          startsNativeContextGesture: false,
        ) &&
        !gestureGate.suppress(
          target: 'tab',
          isButtonDown: true,
          isButtonUp: false,
          startsNativeContextGesture: false,
        ),
    'a full native context gesture is suppressed exactly through mouse-up',
  );
  gestureGate
    ..suppress(
      target: 'tab',
      isButtonDown: true,
      isButtonUp: false,
      startsNativeContextGesture: true,
    )
    ..clear();
  _expect(
    !gestureGate.suppress(
      target: 'tab',
      isButtonDown: false,
      isButtonUp: true,
      startsNativeContextGesture: false,
    ),
    'gesture teardown cannot suppress a later unrelated terminal event',
  );
}

void _testServicesSelectionAndFolderPolicy() {
  final TerminalScreenSet screens = TerminalScreenSet(rows: 1, columns: 8);
  _write(screens.primary, 'selected');
  final TerminalSelectionRange range = screens.viewport.selectionRange(
    screens.viewport.anchorAt(0, 0),
    screens.viewport.anchorAfter(0, 7),
    unit: TerminalSelectionUnit.cell,
  )!;
  final TerminalSelectionText selected = screens.viewport.extractSelection(
    range,
  )!;
  _expect(
    TerminalNativeContentPolicy.servicesSelection(selected) == 'selected' &&
        TerminalNativeContentPolicy.servicesSelection(null) == null,
    'Services caches only one complete non-empty terminal selection',
  );
  _expect(
    TerminalNativeContentPolicy.folderWorkingDirectory(
              Uri.parse('file:///private/tmp/Folder%20Name'),
            ) ==
            '/private/tmp/Folder Name' &&
        TerminalNativeContentPolicy.folderWorkingDirectory(
              Uri.parse('file://localhost/private/tmp'),
            ) ==
            '/private/tmp' &&
        TerminalNativeContentPolicy.folderWorkingDirectory(
              Uri.parse('https://example.com/private/tmp'),
            ) ==
            null &&
        TerminalNativeContentPolicy.folderWorkingDirectory(
              Uri.parse('file://remote/private/tmp'),
            ) ==
            null,
    'Finder directories become bounded local cwd authority only',
  );
}

void _testBoundedWordLookup() {
  final TerminalScreenSet screens = TerminalScreenSet(rows: 2, columns: 16);
  _write(screens.primary, 'alpha_beta +  ');

  final TerminalWordLookupResult word = TerminalWordLookup.atCell(
    screens.viewport,
    0,
    3,
  );
  _expect(
    word.isAvailable &&
        word.candidate!.text == 'alpha_beta' &&
        word.candidate!.pointerRow == 0 &&
        word.candidate!.pointerColumn == 3 &&
        word.candidate!.baselineRow == 0 &&
        word.candidate!.baselineColumn == 0,
    'ASCII word lookup returns exact stable text and baseline geometry',
  );
  _expect(
    TerminalWordLookup.atCell(screens.viewport, 0, 11).candidate?.text == '+' &&
        TerminalWordLookup.atCell(screens.viewport, 0, 12).disposition ==
            TerminalWordLookupDisposition.whitespace &&
        TerminalWordLookup.atCell(screens.viewport, -1, 0).disposition ==
            TerminalWordLookupDisposition.outsideViewport &&
        TerminalWordLookup.atCell(screens.viewport, 2, 0).disposition ==
            TerminalWordLookupDisposition.outsideViewport,
    'separator, whitespace, and off-grid cells have explicit outcomes',
  );

  final TerminalScreenSet limited = TerminalScreenSet(rows: 1, columns: 8);
  _write(limited.primary, 'abcdefgh');
  _expect(
    TerminalWordLookup.atCell(
          limited.viewport,
          0,
          3,
          maxWordScanCells: 1,
        ).disposition ==
        TerminalWordLookupDisposition.boundaryLimited,
    'a partially scanned word is never exposed to native Quick Look',
  );
  _expect(
    TerminalWordLookup.atCell(
          limited.viewport,
          0,
          3,
          maxScalars: 3,
        ).disposition ==
        TerminalWordLookupDisposition.tooLarge,
    'a scalar-limited word is rejected instead of truncated',
  );
}

void _testWideWrappedAndStaleWordLookup() {
  final TerminalScreenSet screens = TerminalScreenSet(rows: 3, columns: 4);
  for (final int scalar in '界字alpha'.runes) {
    screens.primary.printScalar(scalar);
  }
  final TerminalWordLookupResult wide = TerminalWordLookup.atCell(
    screens.viewport,
    0,
    1,
  );
  final TerminalWordLookupResult wrapped = TerminalWordLookup.atCell(
    screens.viewport,
    1,
    2,
  );
  _expect(
    wide.candidate?.text == '界字alpha' &&
        wide.candidate?.pointerColumn == 1 &&
        wide.candidate?.baselineColumn == 0 &&
        wrapped.candidate?.text == '界字alpha' &&
        wrapped.candidate?.baselineRow == 0,
    'wide continuation and soft wrapping preserve one canonical word',
  );
  final TerminalWordCandidate candidate = wrapped.candidate!;
  screens.primary.setNarrowCell(0, 0, 0x58);
  _expect(
    TerminalWordLookup.revalidate(screens.viewport, candidate).disposition ==
        TerminalWordLookupDisposition.stale,
    'a viewport mutation invalidates a retained native lookup candidate',
  );
}

void _testExternalTextAdmission() {
  final TerminalExternalContentResult service =
      TerminalExternalContentAdmission.text(
        'translated text',
        source: TerminalExternalTextSource.service,
      );
  final TerminalExternalContentResult drop =
      TerminalExternalContentAdmission.text(
        'first\nsecond',
        source: TerminalExternalTextSource.drop,
      );
  _expect(
    service.isAdmitted &&
        service.content!.kind == TerminalExternalContentKind.text &&
        service.content!.textSource == TerminalExternalTextSource.service &&
        service.content!.utf8Bytes == 15 &&
        service.content!.itemCount == 1 &&
        drop.content!.text == 'first\nsecond' &&
        drop.content!.utf8Bytes == 12,
    'service and dropped text retain typed source and exact UTF-8 bounds',
  );
  _expect(
    TerminalExternalContentAdmission.text(
          '',
          source: TerminalExternalTextSource.drop,
        ).disposition ==
        TerminalExternalContentDisposition.empty,
    'empty external text produces no paste candidate',
  );
}

void _testShellSafeFilePathAdmission() {
  final TerminalExternalContentResult result =
      TerminalExternalContentAdmission.filePaths(const <String>[
        '/private/tmp/plain',
        '/private/tmp/two words',
        "/private/tmp/it's-safe",
        r'/private/tmp/$(touch nope)',
        '/private/tmp/*',
      ]);
  _expect(
    result.isAdmitted &&
        result.content!.kind == TerminalExternalContentKind.filePaths &&
        result.content!.textSource == TerminalExternalTextSource.drop &&
        result.content!.itemCount == 5 &&
        result.content!.text ==
            "'/private/tmp/plain' '/private/tmp/two words' "
                "'/private/tmp/it'\\''s-safe' '/private/tmp/\$(touch nope)' "
                "'/private/tmp/*' " &&
        result.content!.utf8Bytes == result.content!.text.codeUnits.length,
    'every file path is one literal shell word with a trailing separator',
  );
  final TerminalExternalContentResult single =
      TerminalExternalContentAdmission.filePaths(
        const <String>["/private/tmp/it's-safe"],
        maxFilePaths: 1,
        appendTrailingSeparator: false,
      );
  _expect(
    single.content?.text == "'/private/tmp/it'\\''s-safe'" &&
        single.content?.utf8Bytes == single.content?.text.codeUnits.length,
    'single-path handoff is one quoted word without trailing whitespace',
  );
  for (final String path in <String>[
    'relative/path',
    '/private/tmp/line\nbreak',
    '/private/tmp/tab\tname',
    '/private/tmp/${String.fromCharCode(0xd800)}',
  ]) {
    _expect(
      TerminalExternalContentAdmission.filePaths(<String>[path]).disposition ==
          TerminalExternalContentDisposition.invalidPath,
      'hostile or ambiguous path is rejected: ${path.codeUnits}',
    );
  }
}

void _testExternalContentLimits() {
  _expect(
    TerminalExternalContentAdmission.text(
          'éé',
          source: TerminalExternalTextSource.drop,
          maxUtf8Bytes: 3,
        ).disposition ==
        TerminalExternalContentDisposition.tooLarge,
    'external text uses UTF-8 bytes rather than UTF-16 units',
  );
  _expect(
    TerminalExternalContentAdmission.filePaths(const <String>[
          '/a',
          '/b',
        ], maxFilePaths: 1).disposition ==
        TerminalExternalContentDisposition.tooManyItems,
    'file count is bounded before serialization',
  );
  _expect(
    TerminalExternalContentAdmission.filePaths(const <String>[
              '/abcd',
            ], maxFilePathUtf8Bytes: 4).disposition ==
            TerminalExternalContentDisposition.tooLarge &&
        TerminalExternalContentAdmission.filePaths(const <String>[
              '/a',
              '/b',
            ], maxUtf8Bytes: 9).disposition ==
            TerminalExternalContentDisposition.tooLarge &&
        TerminalExternalContentAdmission.filePaths(const <String>[])
                .disposition ==
            TerminalExternalContentDisposition.empty,
    'per-path, aggregate, and empty file inputs fail without partial output',
  );
  _expectThrows<RangeError>(
    () => TerminalExternalContentAdmission.text(
      'x',
      source: TerminalExternalTextSource.drop,
      maxUtf8Bytes: 0,
    ),
    'zero text limit',
  );
  _expectThrows<RangeError>(
    () => TerminalExternalContentAdmission.filePaths(const <String>[
      '/x',
    ], maxFilePaths: TerminalExternalContentAdmission.maximumFilePaths + 1),
    'file count above the hard maximum',
  );
}

Future<void> _testExternalPasteLifecycle() async {
  final _ExternalPasteHarness harness = _ExternalPasteHarness();
  final TerminalExternalPasteController<int> controller =
      TerminalExternalPasteController<int>(
        resolveTarget: harness.resolve,
        monotonicMicros: () => harness.clockMicros++,
      );
  final TerminalExternalContent safe = TerminalExternalContentAdmission.text(
    'safe',
    source: TerminalExternalTextSource.drop,
  ).content!;
  final TerminalExternalPasteResult completed = await controller.submit(
    7,
    safe,
  );
  _expect(
    completed.disposition == TerminalExternalPasteDisposition.completed &&
        harness.writes.single == '\x1b[200~safe\x1b[201~' &&
        harness.notices.isEmpty,
    'safe external text uses exact bracketed ordinary paste transport bytes',
  );

  harness.writes.clear();
  final TerminalExternalContent risky = TerminalExternalContentAdmission.text(
    'first\nsecond',
    source: TerminalExternalTextSource.service,
  ).content!;
  final TerminalExternalPasteResult confirmation = await controller.submit(
    7,
    risky,
  );
  _expect(
    confirmation.disposition ==
            TerminalExternalPasteDisposition.confirmationRequired &&
        harness.writes.isEmpty &&
        harness.notices.single.kind ==
            TerminalClipboardNoticeKind.pasteConfirmationRequired,
    'first risky Service delivery confirms without any PTY write',
  );
  final TerminalExternalPasteResult approved = await controller.submit(
    7,
    risky,
  );
  _expect(
    approved.disposition == TerminalExternalPasteDisposition.completed &&
        harness.writes.single == '\x1b[200~first\nsecond\x1b[201~',
    'repeating the same risky Service delivery approves the same paste path',
  );

  harness
    ..writes.clear()
    ..notices.clear();
  final TerminalExternalContent scripted =
      TerminalExternalContentAdmission.text(
        risky.text,
        source: TerminalExternalTextSource.appleScript,
      ).content!;
  final TerminalExternalPasteResult serviceConfirmation = await controller
      .submit(7, risky);
  final TerminalExternalPasteResult scriptConfirmation = await controller
      .submit(7, scripted);
  _expect(
    serviceConfirmation.disposition ==
            TerminalExternalPasteDisposition.confirmationRequired &&
        scriptConfirmation.disposition ==
            TerminalExternalPasteDisposition.confirmationRequired &&
        harness.writes.isEmpty &&
        harness.notices.length == 2,
    'scripted text reused confirmation authority from a Service delivery',
  );

  harness
    ..writes.clear()
    .._resolutionCount = 0
    ..replaceAfterFirstResolution = true;
  final TerminalExternalPasteResult stale = await controller.submit(7, safe);
  _expect(
    stale.disposition == TerminalExternalPasteDisposition.staleTarget &&
        harness.writes.isEmpty,
    'target replacement during asynchronous planning produces zero writes',
  );
  harness
    ..replaceAfterFirstResolution = false
    ..busy = true;
  _expect(
    (await controller.submit(7, safe)).disposition ==
            TerminalExternalPasteDisposition.busy &&
        harness.writes.isEmpty,
    'a target with an active paste fails closed',
  );
  harness
    ..busy = false
    ..writes.clear();
  var admissionCount = 0;
  final TerminalExternalPasteController<int> admissionController =
      TerminalExternalPasteController<int>(
        canSubmit: (_, _) => ++admissionCount == 1,
        resolveTarget: harness.resolve,
        monotonicMicros: () => harness.clockMicros++,
      );
  _expect(
    (await admissionController.submit(7, safe)).disposition ==
            TerminalExternalPasteDisposition.staleTarget &&
        admissionCount == 2 &&
        harness.writes.isEmpty,
    'external paste admission is revalidated after asynchronous planning',
  );
  admissionController.dispose();
  controller.dispose();
  controller.dispose();
  _expect(
    (await controller.submit(7, safe)).disposition ==
        TerminalExternalPasteDisposition.disposed,
    'disposed native paste lifecycle rejects late events',
  );
}

final class _ExternalPasteHarness {
  final Object originalIdentity = Object();
  final Object replacementIdentity = Object();
  final List<String> writes = <String>[];
  final List<TerminalClipboardNotice> notices = <TerminalClipboardNotice>[];
  int clockMicros = 1;
  int _resolutionCount = 0;
  bool replaceAfterFirstResolution = false;
  bool busy = false;

  TerminalExternalPasteTarget? resolve(int identity) {
    if (identity != 7) return null;
    _resolutionCount++;
    final Object token = replaceAfterFirstResolution && _resolutionCount > 1
        ? replacementIdentity
        : originalIdentity;
    return TerminalExternalPasteTarget(
      identity: token,
      bracketedPasteMode: true,
      pasteInProgress: busy,
      showNotice: notices.add,
      paste: (TerminalPastePlan plan) async {
        final List<int> bytes = <int>[];
        final TerminalPasteChunkEncoder encoder = plan.encoder();
        for (
          var chunk = encoder.nextChunk();
          chunk != null;
          chunk = encoder.nextChunk()
        ) {
          bytes.addAll(chunk);
        }
        writes.add(utf8.decode(bytes));
        return TerminalPasteTransferResult(
          disposition: TerminalPasteTransferDisposition.completed,
          encodedBytes: bytes.length,
          completedChunks: writes.length,
          backpressureCount: 0,
          maximumQueuedBytes: bytes.length,
          concurrentInputRejections: 0,
        );
      },
    );
  }
}

void _write(TerminalScreen screen, String value) {
  for (final int scalar in value.runes) {
    screen.printScalar(scalar);
  }
}

void _expectThrows<T extends Object>(
  void Function() operation,
  String description,
) {
  try {
    operation();
  } on T {
    return;
  }
  throw StateError('expected $T for $description');
}

void _expect(bool condition, String description) {
  if (!condition) throw StateError('native content test failed: $description');
}
