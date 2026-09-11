import 'vt_parser.dart';

/// Machine-readable declaration of the semantic sequence surface.
///
/// The screen parser sink gates dispatch through these sorted declarations.
/// Changing an accepted selector or mode therefore requires changing this
/// product-code contract, which in turn makes the checked-in implementation
/// manifest stale until it is regenerated and reviewed.
abstract final class TerminalCompatibilitySurface {
  static const int formatVersion = 1;

  static const List<int> controlBytes = <int>[
    0x07,
    0x08,
    0x09,
    0x0a,
    0x0b,
    0x0c,
    0x0d,
    0x0e,
    0x0f,
    0x84,
    0x85,
    0x88,
    0x8d,
  ];

  static const List<int> escapeSelectors = <int>[
    0x37,
    0x38,
    0x3d,
    0x3e,
    0x44,
    0x45,
    0x48,
    0x4d,
    0x63,
    0x012830,
    0x012842,
    0x012930,
    0x012942,
  ];

  static const List<int> csiSelectors = <int>[
    0x40,
    0x41,
    0x42,
    0x43,
    0x44,
    0x45,
    0x46,
    0x47,
    0x48,
    0x49,
    0x4a,
    0x4b,
    0x4c,
    0x4d,
    0x50,
    0x53,
    0x54,
    0x58,
    0x5a,
    0x60,
    0x63,
    0x64,
    0x66,
    0x67,
    0x68,
    0x6c,
    0x6d,
    0x6e,
    0x72,
    0x73,
    0x74,
    0x75,
    0x012071,
    0x012470,
    0x3c000075,
    0x3d000075,
    0x3e000063,
    0x3e00006d,
    0x3e000071,
    0x3e000075,
    0x3f000068,
    0x3f00006c,
    0x3f00006d,
    0x3f00006e,
    0x3f000075,
    0x3f012470,
  ];

  static const List<int> oscCommands = <int>[
    0,
    1,
    2,
    4,
    7,
    8,
    9,
    10,
    11,
    12,
    52,
    99,
    104,
    110,
    111,
    112,
    133,
  ];

  static const List<int> dcsSelectors = <int>[0x012471, 0x012b71];

  static const List<int> ansiModes = <int>[4];

  static const List<int> decPrivateModes = <int>[
    1,
    5,
    6,
    7,
    9,
    12,
    25,
    47,
    69,
    1000,
    1002,
    1003,
    1004,
    1005,
    1006,
    1015,
    1016,
    1047,
    1048,
    1049,
    2004,
    2026,
    2027,
    2031,
    2048,
    7727,
  ];

  static const bool dcsIsBoundedUnsupported = true;

  static const List<VtStringKind> supportedStringKinds = <VtStringKind>[
    VtStringKind.applicationProgramCommand,
  ];

  static const List<VtStringKind> boundedUnsupportedStringKinds =
      <VtStringKind>[
        VtStringKind.startOfString,
        VtStringKind.privacyMessage,
        VtStringKind.applicationProgramCommand,
      ];

  static int escapeSelectorKey({
    required int finalByte,
    required int intermediateCount,
    int firstIntermediate = 0,
  }) {
    if (intermediateCount < 0 || intermediateCount > 1) return -1;
    return (intermediateCount << 16) | (firstIntermediate << 8) | finalByte;
  }

  static int csiSelectorKey({
    required int? privateMarker,
    required int finalByte,
    required int intermediateCount,
    int firstIntermediate = 0,
  }) {
    if (intermediateCount < 0 || intermediateCount > 1) return -1;
    return ((privateMarker ?? 0) << 24) |
        (intermediateCount << 16) |
        (firstIntermediate << 8) |
        finalByte;
  }

  static bool supportsControl(int controlByte) =>
      _containsSorted(controlBytes, controlByte);

  static bool supportsEscape({
    required int finalByte,
    required int intermediateCount,
    int firstIntermediate = 0,
  }) => _containsSorted(
    escapeSelectors,
    escapeSelectorKey(
      finalByte: finalByte,
      intermediateCount: intermediateCount,
      firstIntermediate: firstIntermediate,
    ),
  );

  static bool supportsCsi({
    required int? privateMarker,
    required int finalByte,
    required int intermediateCount,
    int firstIntermediate = 0,
  }) => _containsSorted(
    csiSelectors,
    csiSelectorKey(
      privateMarker: privateMarker,
      finalByte: finalByte,
      intermediateCount: intermediateCount,
      firstIntermediate: firstIntermediate,
    ),
  );

  static bool supportsDcs({
    required int? privateMarker,
    required int finalByte,
    required int intermediateCount,
    int firstIntermediate = 0,
  }) =>
      privateMarker == null &&
      _containsSorted(
        dcsSelectors,
        escapeSelectorKey(
          finalByte: finalByte,
          intermediateCount: intermediateCount,
          firstIntermediate: firstIntermediate,
        ),
      );

  static bool supportsOsc(int command) => _containsSorted(oscCommands, command);

  static bool supportsMode(int mode, {required bool decPrivate}) =>
      _containsSorted(decPrivate ? decPrivateModes : ansiModes, mode);

  static bool _containsSorted(List<int> values, int target) {
    int low = 0;
    int high = values.length - 1;
    while (low <= high) {
      final int middle = low + ((high - low) >> 1);
      final int value = values[middle];
      if (value == target) return true;
      if (value < target) {
        low = middle + 1;
      } else {
        high = middle - 1;
      }
    }
    return false;
  }
}
