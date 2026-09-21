import 'package:dart_system_entropy_macos/dart_system_entropy_macos.dart';

/// Application-owned cryptographically secure entropy supplied by macOS.
///
/// The embedded Dart runtime intentionally does not assume that
/// `Random.secure()` is available. The generic package owns the platform
/// boundary while this facade exposes only an injectable byte source to
/// product code.
abstract final class TerminalSystemEntropy {
  static const int maximumRequestBytes = MacosSystemEntropy.maximumRequestBytes;

  static List<int> bytes(int length) => MacosSystemEntropy.bytes(length);
}
