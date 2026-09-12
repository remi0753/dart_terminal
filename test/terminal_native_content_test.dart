import 'package:dart_terminal/dart_terminal.dart';

void main() => runTerminalNativeContentTests();

void runTerminalNativeContentTests() {
  _testBoundedWordLookup();
  _testWideWrappedAndStaleWordLookup();
  _testExternalTextAdmission();
  _testShellSafeFilePathAdmission();
  _testExternalContentLimits();
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
