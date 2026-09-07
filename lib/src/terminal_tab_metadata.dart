import 'dart:convert';

import 'terminal_core/terminal_session_metadata.dart';

/// Hard limits for application-owned tab presentation metadata.
abstract final class TerminalTabMetadataLimits {
  static const int maximumCustomTitleUtf8Bytes = 256;
}

/// An immutable sRGB color selected for one native terminal tab marker.
final class TerminalTabColor {
  factory TerminalTabColor({
    required int red,
    required int green,
    required int blue,
    int alpha = 255,
  }) {
    for (final MapEntry<String, int> component in <String, int>{
      'red': red,
      'green': green,
      'blue': blue,
      'alpha': alpha,
    }.entries) {
      if (component.value < 0 || component.value > 255) {
        throw RangeError.range(component.value, 0, 255, component.key);
      }
    }
    if (alpha == 0) {
      throw ArgumentError.value(alpha, 'alpha', 'must be visible');
    }
    return TerminalTabColor._(red: red, green: green, blue: blue, alpha: alpha);
  }

  const TerminalTabColor._({
    required this.red,
    required this.green,
    required this.blue,
    required this.alpha,
  });

  static const TerminalTabColor redMarker = TerminalTabColor._(
    red: 214,
    green: 58,
    blue: 73,
    alpha: 255,
  );
  static const TerminalTabColor orangeMarker = TerminalTabColor._(
    red: 224,
    green: 124,
    blue: 57,
    alpha: 255,
  );
  static const TerminalTabColor yellowMarker = TerminalTabColor._(
    red: 207,
    green: 166,
    blue: 47,
    alpha: 255,
  );
  static const TerminalTabColor greenMarker = TerminalTabColor._(
    red: 66,
    green: 168,
    blue: 89,
    alpha: 255,
  );
  static const TerminalTabColor blueMarker = TerminalTabColor._(
    red: 55,
    green: 126,
    blue: 209,
    alpha: 255,
  );
  static const TerminalTabColor purpleMarker = TerminalTabColor._(
    red: 146,
    green: 89,
    blue: 196,
    alpha: 255,
  );

  final int red;
  final int green;
  final int blue;
  final int alpha;

  @override
  bool operator ==(Object other) =>
      other is TerminalTabColor &&
      other.red == red &&
      other.green == green &&
      other.blue == blue &&
      other.alpha == alpha;

  @override
  int get hashCode => Object.hash(red, green, blue, alpha);
}

/// Product validation shared by tab state and its presentation resolver.
abstract final class TerminalTabMetadataPolicy {
  static bool isSafeCustomTitle(String value) =>
      value.isNotEmpty &&
      TerminalSessionMetadata.isSafeTitle(value) &&
      utf8.encode(value).length <=
          TerminalTabMetadataLimits.maximumCustomTitleUtf8Bytes;
}
