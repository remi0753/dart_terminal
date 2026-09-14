import 'dart:typed_data';

import 'package:dart_appkit/dart_appkit.dart';
import 'package:dart_macos_runtime/dart_macos_runtime.dart';

export 'src/accessibility.dart';
export 'src/font_catalog.dart';
export 'src/metal_renderer.dart';
export 'src/text_input.dart';

const String terminalRendererMacosCapabilityId = 'dart_terminal_renderer_macos';
const String terminalMetalViewProviderIdentifier =
    'dart_terminal.TerminalMetalView';

abstract final class TerminalRendererMacos {
  static MacosNativeCapability? _capability;

  static bool get isInitialized => _capability != null;

  static void initialize() {
    _capability ??= MacosNativeCapability.load(
      terminalRendererMacosCapabilityId,
    );
  }

  static View createView() {
    if (_capability == null) {
      throw StateError('TerminalRendererMacos.initialize() must be called');
    }
    return View.custom(terminalMetalViewProviderIdentifier);
  }

  /// Applies one application-wide opacity value to a terminal Metal view.
  ///
  /// The operation is terminal-specific: ordinary AppKit views such as
  /// Settings and Command Palette never receive this presentation policy.
  static void setBackgroundOpacity(View view, double opacity) {
    view.performCustomOperation(encodeBackgroundOpacityOperation(opacity));
  }

  /// Encodes the versioned custom-view operation for deterministic tests.
  static Uint8List encodeBackgroundOpacityOperation(double opacity) {
    if (!opacity.isFinite || opacity < 0 || opacity > 1) {
      throw RangeError.range(opacity, 0, 1, 'opacity');
    }
    final Uint8List payload = Uint8List(24);
    final ByteData data = ByteData.sublistView(payload);
    data.setUint32(0, payload.length, Endian.little);
    data.setUint32(4, 1, Endian.little);
    data.setUint32(8, 9, Endian.little);
    data.setFloat64(16, opacity, Endian.little);
    return payload;
  }
}
