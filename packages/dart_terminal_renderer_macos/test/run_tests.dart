import 'dart:io';

import 'accessibility_test.dart';
import 'font_catalog_test.dart';
import 'metal_renderer_test.dart';
import 'native_asset_test.dart';
import 'raster_test.dart';
import 'shaping_test.dart';
import 'text_input_test.dart';

void main() {
  runAccessibilityTests();
  runNativeAssetTests();
  runFontCatalogTests();
  runMetalRendererTests();
  runRasterTests();
  runShapingTests();
  runTextInputTests();
  if (exitCode != 0) {
    throw StateError('terminal renderer native asset smoke failed');
  }
  stdout.writeln('terminal renderer Dart tests passed');
}
