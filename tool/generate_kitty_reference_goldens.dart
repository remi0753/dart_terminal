import 'dart:io';

import 'package:dart_terminal/dart_terminal.dart';

import '../test/support/kitty_reference_golden_fixture.dart';

void main() {
  final Directory directory = Directory('test/goldens/kitty')..createSync();
  for (final int scale in <int>[1, 2]) {
    final File output = File(
      '${directory.path}/static-placement-${scale}x.dtgi',
    );
    output.writeAsBytesSync(
      TerminalGoldenImageCodec.encode(
        createKittyReferenceGoldenFixture(scale: scale),
      ),
      flush: true,
    );
    stdout.writeln('KITTY_REFERENCE_GOLDEN_GENERATED path=${output.path}');
  }
}
