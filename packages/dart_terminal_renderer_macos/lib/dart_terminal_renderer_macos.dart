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
}
