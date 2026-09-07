import 'dart:convert';

import 'terminal_application_state.dart';
import 'terminal_pane.dart';
import 'terminal_tab_metadata.dart';
import 'terminal_tab_presentation.dart';

/// Hard admission limits for durable application restoration state.
abstract final class TerminalRestorationLimits {
  static const int maximumSerializedUtf8Bytes = 512 * 1024;
  static const int maximumWindows =
      TerminalApplicationStateLimits.maximumWindows;
  static const int maximumTotalTabs = 128;
  static const int maximumTabsPerWindow =
      TerminalApplicationStateLimits.maximumTabsPerWindow;
  static const int maximumTotalPanes = 64;
  static const int maximumPanesPerTab =
      TerminalApplicationStateLimits.maximumPanesPerTab;
  static const int maximumTreeDepth = maximumPanesPerTab;
  static const double maximumCoordinateMagnitude = 10000000;
  static const double maximumWindowExtent = 1000000;
}

/// A finite positive window rectangle in global logical AppKit points.
final class TerminalWindowFrame {
  factory TerminalWindowFrame({
    required double left,
    required double top,
    required double width,
    required double height,
  }) {
    for (final MapEntry<String, double> coordinate in <String, double>{
      'left': left,
      'top': top,
    }.entries) {
      if (!coordinate.value.isFinite ||
          coordinate.value.abs() >
              TerminalRestorationLimits.maximumCoordinateMagnitude) {
        throw ArgumentError.value(
          coordinate.value,
          coordinate.key,
          'must be finite and within the restoration coordinate bound',
        );
      }
    }
    for (final MapEntry<String, double> extent in <String, double>{
      'width': width,
      'height': height,
    }.entries) {
      if (!extent.value.isFinite ||
          extent.value <= 0 ||
          extent.value > TerminalRestorationLimits.maximumWindowExtent) {
        throw ArgumentError.value(
          extent.value,
          extent.key,
          'must be finite, positive, and within the restoration extent bound',
        );
      }
    }
    return TerminalWindowFrame._(
      left: left,
      top: top,
      width: width,
      height: height,
    );
  }

  const TerminalWindowFrame._({
    required this.left,
    required this.top,
    required this.width,
    required this.height,
  });

  final double left;
  final double top;
  final double width;
  final double height;

  double get right => left + width;
  double get bottom => top + height;

  @override
  bool operator ==(Object other) =>
      other is TerminalWindowFrame &&
      other.left == left &&
      other.top == top &&
      other.width == width &&
      other.height == height;

  @override
  int get hashCode => Object.hash(left, top, width, height);
}

/// One currently observed display and its usable global rectangle.
final class TerminalScreenPlacement {
  factory TerminalScreenPlacement({
    required int displayId,
    required TerminalWindowFrame frame,
    required TerminalWindowFrame visibleFrame,
  }) {
    if (displayId <= 0) {
      throw ArgumentError.value(displayId, 'displayId', 'must be positive');
    }
    return TerminalScreenPlacement._(
      displayId: displayId,
      frame: frame,
      visibleFrame: visibleFrame,
    );
  }

  const TerminalScreenPlacement._({
    required this.displayId,
    required this.frame,
    required this.visibleFrame,
  });

  final int displayId;
  final TerminalWindowFrame frame;
  final TerminalWindowFrame visibleFrame;

  @override
  bool operator ==(Object other) =>
      other is TerminalScreenPlacement &&
      other.displayId == displayId &&
      other.frame == frame &&
      other.visibleFrame == visibleFrame;

  @override
  int get hashCode => Object.hash(displayId, frame, visibleFrame);
}

/// Durable presentation intent for one logical window.
final class TerminalWindowPlacement {
  const TerminalWindowPlacement({
    required this.windowedFrame,
    required this.screen,
    required this.fullscreen,
  });

  final TerminalWindowFrame windowedFrame;
  final TerminalScreenPlacement? screen;
  final bool fullscreen;

  TerminalWindowPlacement copyWith({
    TerminalWindowFrame? windowedFrame,
    TerminalScreenPlacement? screen,
    bool clearScreen = false,
    bool? fullscreen,
  }) => TerminalWindowPlacement(
    windowedFrame: windowedFrame ?? this.windowedFrame,
    screen: clearScreen ? null : screen ?? this.screen,
    fullscreen: fullscreen ?? this.fullscreen,
  );

  @override
  bool operator ==(Object other) =>
      other is TerminalWindowPlacement &&
      other.windowedFrame == windowedFrame &&
      other.screen == screen &&
      other.fullscreen == fullscreen;

  @override
  int get hashCode => Object.hash(windowedFrame, screen, fullscreen);
}

/// Deterministic frame selection for restoration and display migration.
abstract final class TerminalWindowPlacementPolicy {
  static const double preferredMinimumWidth = 320;
  static const double preferredMinimumHeight = 200;

  static TerminalWindowPlacement resolveForAvailableScreens(
    TerminalWindowPlacement saved,
    Iterable<TerminalScreenPlacement> availableScreens, {
    int? fallbackDisplayId,
  }) {
    final List<TerminalScreenPlacement> screens = availableScreens.toList(
      growable: false,
    );
    if (screens.isEmpty) return saved;
    TerminalScreenPlacement? destination;
    final int? preferredId = saved.screen?.displayId;
    for (final TerminalScreenPlacement screen in screens) {
      if (screen.displayId == preferredId) {
        destination = screen;
        break;
      }
    }
    if (destination == null && fallbackDisplayId != null) {
      for (final TerminalScreenPlacement screen in screens) {
        if (screen.displayId == fallbackDisplayId) {
          destination = screen;
          break;
        }
      }
    }
    destination ??= screens.first;
    final TerminalWindowFrame frame =
        saved.screen == null || saved.screen!.displayId == destination.displayId
        ? clampToVisibleFrame(saved.windowedFrame, destination.visibleFrame)
        : migrateBetweenScreens(
            saved.windowedFrame,
            from: saved.screen!,
            to: destination,
          );
    return TerminalWindowPlacement(
      windowedFrame: frame,
      screen: destination,
      fullscreen: saved.fullscreen,
    );
  }

  static TerminalWindowFrame migrateBetweenScreens(
    TerminalWindowFrame frame, {
    required TerminalScreenPlacement from,
    required TerminalScreenPlacement to,
  }) {
    final TerminalWindowFrame source = from.visibleFrame;
    final TerminalWindowFrame destination = to.visibleFrame;
    final double width = _boundedExtent(
      frame.width,
      destination.width,
      preferredMinimumWidth,
    );
    final double height = _boundedExtent(
      frame.height,
      destination.height,
      preferredMinimumHeight,
    );
    final double horizontalRatio = _relativeOffset(
      frame.left,
      source.left,
      source.width - frame.width,
    );
    final double verticalRatio = _relativeOffset(
      frame.top,
      source.top,
      source.height - frame.height,
    );
    return TerminalWindowFrame(
      left: destination.left + horizontalRatio * (destination.width - width),
      top: destination.top + verticalRatio * (destination.height - height),
      width: width,
      height: height,
    );
  }

  static TerminalWindowFrame clampToVisibleFrame(
    TerminalWindowFrame frame,
    TerminalWindowFrame visibleFrame,
  ) {
    final double width = _boundedExtent(
      frame.width,
      visibleFrame.width,
      preferredMinimumWidth,
    );
    final double height = _boundedExtent(
      frame.height,
      visibleFrame.height,
      preferredMinimumHeight,
    );
    return TerminalWindowFrame(
      left: frame.left.clamp(visibleFrame.left, visibleFrame.right - width),
      top: frame.top.clamp(visibleFrame.top, visibleFrame.bottom - height),
      width: width,
      height: height,
    );
  }

  static double _boundedExtent(
    double requested,
    double available,
    double preferredMinimum,
  ) => requested.clamp(
    available < preferredMinimum ? available : preferredMinimum,
    available,
  );

  static double _relativeOffset(double value, double origin, double travel) =>
      travel <= 0 ? 0.5 : ((value - origin) / travel).clamp(0, 1);
}

/// One restored pane starts a fresh session at this optional trusted cwd.
final class TerminalRestorablePane {
  factory TerminalRestorablePane({required String? workingDirectory}) {
    if (workingDirectory != null &&
        !_isSafeLocalWorkingDirectory(workingDirectory)) {
      throw ArgumentError.value(
        workingDirectory,
        'workingDirectory',
        'must be a safe absolute local path',
      );
    }
    return TerminalRestorablePane._(workingDirectory);
  }

  const TerminalRestorablePane._(this.workingDirectory);

  final String? workingDirectory;
}

sealed class TerminalRestorableSplitNode {
  const TerminalRestorableSplitNode();

  int get paneCount;
  int get depth;
  List<TerminalRestorablePane> get panes;
}

final class TerminalRestorableSplitLeaf extends TerminalRestorableSplitNode {
  const TerminalRestorableSplitLeaf(this.pane);

  final TerminalRestorablePane pane;

  @override
  int get paneCount => 1;

  @override
  int get depth => 1;

  @override
  List<TerminalRestorablePane> get panes => <TerminalRestorablePane>[pane];
}

final class TerminalRestorableSplitBranch extends TerminalRestorableSplitNode {
  factory TerminalRestorableSplitBranch({
    required TerminalSplitAxis axis,
    required double fraction,
    required TerminalRestorableSplitNode first,
    required TerminalRestorableSplitNode second,
  }) {
    if (!fraction.isFinite || fraction <= 0 || fraction >= 1) {
      throw ArgumentError.value(
        fraction,
        'fraction',
        'must be finite and strictly between zero and one',
      );
    }
    final int paneCount = first.paneCount + second.paneCount;
    final int depth =
        1 + (first.depth > second.depth ? first.depth : second.depth);
    if (paneCount > TerminalRestorationLimits.maximumPanesPerTab) {
      throw const TerminalRestorationLimitException(
        'restored tab exceeds its pane limit',
      );
    }
    if (depth > TerminalRestorationLimits.maximumTreeDepth) {
      throw const TerminalRestorationLimitException(
        'restored split tree exceeds its depth limit',
      );
    }
    return TerminalRestorableSplitBranch._(
      axis: axis,
      fraction: fraction,
      first: first,
      second: second,
      paneCount: paneCount,
      depth: depth,
    );
  }

  const TerminalRestorableSplitBranch._({
    required this.axis,
    required this.fraction,
    required this.first,
    required this.second,
    required this.paneCount,
    required this.depth,
  });

  final TerminalSplitAxis axis;
  final double fraction;
  final TerminalRestorableSplitNode first;
  final TerminalRestorableSplitNode second;

  @override
  final int paneCount;

  @override
  final int depth;

  @override
  List<TerminalRestorablePane> get panes => <TerminalRestorablePane>[
    ...first.panes,
    ...second.panes,
  ];
}

final class TerminalRestorableTab {
  factory TerminalRestorableTab({
    required TerminalRestorableSplitNode splitTree,
    required int focusedPaneIndex,
    required int? zoomedPaneIndex,
    required String? customTitle,
    required TerminalTabColor? color,
  }) {
    if (splitTree.paneCount <= 0 ||
        splitTree.paneCount > TerminalRestorationLimits.maximumPanesPerTab) {
      throw const TerminalRestorationLimitException(
        'restored tab has an invalid pane count',
      );
    }
    if (focusedPaneIndex < 0 || focusedPaneIndex >= splitTree.paneCount) {
      throw ArgumentError.value(
        focusedPaneIndex,
        'focusedPaneIndex',
        'must select a restored pane',
      );
    }
    if (zoomedPaneIndex != null && zoomedPaneIndex != focusedPaneIndex) {
      throw ArgumentError.value(
        zoomedPaneIndex,
        'zoomedPaneIndex',
        'must be null or the focused pane index',
      );
    }
    if (customTitle != null &&
        !TerminalTabMetadataPolicy.isSafeCustomTitle(customTitle)) {
      throw ArgumentError.value(
        customTitle,
        'customTitle',
        'must be safe bounded tab text',
      );
    }
    return TerminalRestorableTab._(
      splitTree: splitTree,
      focusedPaneIndex: focusedPaneIndex,
      zoomedPaneIndex: zoomedPaneIndex,
      customTitle: customTitle,
      color: color,
    );
  }

  const TerminalRestorableTab._({
    required this.splitTree,
    required this.focusedPaneIndex,
    required this.zoomedPaneIndex,
    required this.customTitle,
    required this.color,
  });

  final TerminalRestorableSplitNode splitTree;
  final int focusedPaneIndex;
  final int? zoomedPaneIndex;
  final String? customTitle;
  final TerminalTabColor? color;
  List<TerminalRestorablePane> get panes => splitTree.panes;
}

final class TerminalRestorableWindow {
  factory TerminalRestorableWindow({
    required TerminalWindowPlacement placement,
    required Iterable<TerminalRestorableTab> tabs,
    required int selectedTabIndex,
  }) {
    final List<TerminalRestorableTab> collected = tabs.toList(growable: false);
    if (collected.isEmpty ||
        collected.length > TerminalRestorationLimits.maximumTabsPerWindow) {
      throw const TerminalRestorationLimitException(
        'restored window has an invalid tab count',
      );
    }
    if (selectedTabIndex < 0 || selectedTabIndex >= collected.length) {
      throw ArgumentError.value(
        selectedTabIndex,
        'selectedTabIndex',
        'must select a restored tab',
      );
    }
    return TerminalRestorableWindow._(
      placement: placement,
      tabs: List<TerminalRestorableTab>.unmodifiable(collected),
      selectedTabIndex: selectedTabIndex,
    );
  }

  const TerminalRestorableWindow._({
    required this.placement,
    required this.tabs,
    required this.selectedTabIndex,
  });

  final TerminalWindowPlacement placement;
  final List<TerminalRestorableTab> tabs;
  final int selectedTabIndex;
}

final class TerminalRestorationSnapshot {
  factory TerminalRestorationSnapshot({
    required Iterable<TerminalRestorableWindow> windows,
    required int activeWindowIndex,
  }) {
    final List<TerminalRestorableWindow> collected = windows.toList(
      growable: false,
    );
    if (collected.isEmpty ||
        collected.length > TerminalRestorationLimits.maximumWindows) {
      throw const TerminalRestorationLimitException(
        'restoration snapshot has an invalid window count',
      );
    }
    if (activeWindowIndex < 0 || activeWindowIndex >= collected.length) {
      throw ArgumentError.value(
        activeWindowIndex,
        'activeWindowIndex',
        'must select a restored window',
      );
    }
    final int tabCount = collected.fold<int>(
      0,
      (int count, TerminalRestorableWindow window) =>
          count + window.tabs.length,
    );
    final int paneCount = collected.fold<int>(
      0,
      (int count, TerminalRestorableWindow window) =>
          count +
          window.tabs.fold<int>(
            0,
            (int nested, TerminalRestorableTab tab) =>
                nested + tab.splitTree.paneCount,
          ),
    );
    if (tabCount > TerminalRestorationLimits.maximumTotalTabs) {
      throw const TerminalRestorationLimitException(
        'restoration snapshot exceeds its total tab limit',
      );
    }
    if (paneCount > TerminalRestorationLimits.maximumTotalPanes) {
      throw const TerminalRestorationLimitException(
        'restoration snapshot exceeds its total pane limit',
      );
    }
    return TerminalRestorationSnapshot._(
      windows: List<TerminalRestorableWindow>.unmodifiable(collected),
      activeWindowIndex: activeWindowIndex,
      tabCount: tabCount,
      paneCount: paneCount,
    );
  }

  const TerminalRestorationSnapshot._({
    required this.windows,
    required this.activeWindowIndex,
    required this.tabCount,
    required this.paneCount,
  });

  static const int formatVersion = 1;

  final List<TerminalRestorableWindow> windows;
  final int activeWindowIndex;
  final int tabCount;
  final int paneCount;
}

final class TerminalRestorationLimitException implements Exception {
  const TerminalRestorationLimitException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Strict deterministic JSON codec for untrusted restoration data.
abstract final class TerminalRestorationCodec {
  static String encode(TerminalRestorationSnapshot snapshot) {
    final String encoded = jsonEncode(<String, Object?>{
      'version': TerminalRestorationSnapshot.formatVersion,
      'activeWindow': snapshot.activeWindowIndex,
      'windows': snapshot.windows.map(_encodeWindow).toList(growable: false),
    });
    _checkSerializedSize(encoded);
    return encoded;
  }

  static TerminalRestorationSnapshot decode(String encoded) {
    _checkSerializedSize(encoded);
    final Object? decoded;
    try {
      decoded = jsonDecode(encoded);
    } on FormatException catch (error) {
      throw FormatException('invalid restoration JSON: ${error.message}');
    }
    final Map<String, Object?> root = _map(decoded, 'root');
    _expectKeys(root, const <String>{'version', 'activeWindow', 'windows'});
    final int version = _integer(root['version'], 'version');
    if (version != TerminalRestorationSnapshot.formatVersion) {
      throw FormatException('unsupported restoration version $version');
    }
    final List<Object?> windows = _list(root['windows'], 'windows');
    if (windows.length > TerminalRestorationLimits.maximumWindows) {
      throw const TerminalRestorationLimitException(
        'restoration snapshot exceeds its window limit',
      );
    }
    final _TerminalRestorationDecodeBudget budget =
        _TerminalRestorationDecodeBudget();
    return TerminalRestorationSnapshot(
      windows: <TerminalRestorableWindow>[
        for (var index = 0; index < windows.length; index++)
          _decodeWindow(windows[index], 'windows[$index]', budget),
      ],
      activeWindowIndex: _integer(root['activeWindow'], 'activeWindow'),
    );
  }

  static Map<String, Object?> _encodeWindow(TerminalRestorableWindow window) =>
      <String, Object?>{
        'placement': _encodePlacement(window.placement),
        'selectedTab': window.selectedTabIndex,
        'tabs': window.tabs.map(_encodeTab).toList(growable: false),
      };

  static Map<String, Object?> _encodePlacement(
    TerminalWindowPlacement placement,
  ) => <String, Object?>{
    'windowedFrame': _encodeFrame(placement.windowedFrame),
    'screen': placement.screen == null
        ? null
        : <String, Object?>{
            'display': placement.screen!.displayId,
            'frame': _encodeFrame(placement.screen!.frame),
            'visibleFrame': _encodeFrame(placement.screen!.visibleFrame),
          },
    'fullscreen': placement.fullscreen,
  };

  static List<double> _encodeFrame(TerminalWindowFrame frame) => <double>[
    frame.left,
    frame.top,
    frame.width,
    frame.height,
  ];

  static Map<String, Object?> _encodeTab(TerminalRestorableTab tab) =>
      <String, Object?>{
        'focusedPane': tab.focusedPaneIndex,
        'zoomedPane': tab.zoomedPaneIndex,
        'title': tab.customTitle,
        'color': tab.color == null
            ? null
            : <int>[
                tab.color!.red,
                tab.color!.green,
                tab.color!.blue,
                tab.color!.alpha,
              ],
        'tree': _encodeNode(tab.splitTree),
      };

  static Map<String, Object?> _encodeNode(TerminalRestorableSplitNode node) =>
      switch (node) {
        TerminalRestorableSplitLeaf(:final pane) => <String, Object?>{
          'kind': 'pane',
          'cwd': pane.workingDirectory,
        },
        TerminalRestorableSplitBranch(
          :final axis,
          :final fraction,
          :final first,
          :final second,
        ) =>
          <String, Object?>{
            'kind': 'branch',
            'axis': axis.name,
            'fraction': fraction,
            'first': _encodeNode(first),
            'second': _encodeNode(second),
          },
      };

  static TerminalRestorableWindow _decodeWindow(
    Object? value,
    String path,
    _TerminalRestorationDecodeBudget budget,
  ) {
    final Map<String, Object?> map = _map(value, path);
    _expectKeys(map, const <String>{'placement', 'selectedTab', 'tabs'});
    final List<Object?> tabs = _list(map['tabs'], '$path.tabs');
    if (tabs.length > TerminalRestorationLimits.maximumTabsPerWindow) {
      throw const TerminalRestorationLimitException(
        'restored window exceeds its tab limit',
      );
    }
    budget.admitTabs(tabs.length);
    return TerminalRestorableWindow(
      placement: _decodePlacement(map['placement'], '$path.placement'),
      tabs: <TerminalRestorableTab>[
        for (var index = 0; index < tabs.length; index++)
          _decodeTab(tabs[index], '$path.tabs[$index]', budget),
      ],
      selectedTabIndex: _integer(map['selectedTab'], '$path.selectedTab'),
    );
  }

  static TerminalWindowPlacement _decodePlacement(Object? value, String path) {
    final Map<String, Object?> map = _map(value, path);
    _expectKeys(map, const <String>{'windowedFrame', 'screen', 'fullscreen'});
    final Object? screenValue = map['screen'];
    TerminalScreenPlacement? screen;
    if (screenValue != null) {
      final Map<String, Object?> screenMap = _map(screenValue, '$path.screen');
      _expectKeys(screenMap, const <String>{
        'display',
        'frame',
        'visibleFrame',
      });
      screen = TerminalScreenPlacement(
        displayId: _integer(screenMap['display'], '$path.screen.display'),
        frame: _decodeFrame(screenMap['frame'], '$path.screen.frame'),
        visibleFrame: _decodeFrame(
          screenMap['visibleFrame'],
          '$path.screen.visibleFrame',
        ),
      );
    }
    return TerminalWindowPlacement(
      windowedFrame: _decodeFrame(map['windowedFrame'], '$path.windowedFrame'),
      screen: screen,
      fullscreen: _boolean(map['fullscreen'], '$path.fullscreen'),
    );
  }

  static TerminalWindowFrame _decodeFrame(Object? value, String path) {
    final List<Object?> components = _list(value, path);
    if (components.length != 4) {
      throw FormatException('$path must contain exactly four numbers');
    }
    return TerminalWindowFrame(
      left: _number(components[0], '$path[0]'),
      top: _number(components[1], '$path[1]'),
      width: _number(components[2], '$path[2]'),
      height: _number(components[3], '$path[3]'),
    );
  }

  static TerminalRestorableTab _decodeTab(
    Object? value,
    String path,
    _TerminalRestorationDecodeBudget budget,
  ) {
    final Map<String, Object?> map = _map(value, path);
    _expectKeys(map, const <String>{
      'focusedPane',
      'zoomedPane',
      'title',
      'color',
      'tree',
    });
    final Object? colorValue = map['color'];
    TerminalTabColor? color;
    if (colorValue != null) {
      final List<Object?> components = _list(colorValue, '$path.color');
      if (components.length != 4) {
        throw FormatException('$path.color must contain exactly four bytes');
      }
      color = TerminalTabColor(
        red: _integer(components[0], '$path.color[0]'),
        green: _integer(components[1], '$path.color[1]'),
        blue: _integer(components[2], '$path.color[2]'),
        alpha: _integer(components[3], '$path.color[3]'),
      );
    }
    return TerminalRestorableTab(
      splitTree: _decodeNode(
        map['tree'],
        '$path.tree',
        depth: 1,
        budget: budget,
      ),
      focusedPaneIndex: _integer(map['focusedPane'], '$path.focusedPane'),
      zoomedPaneIndex: map['zoomedPane'] == null
          ? null
          : _integer(map['zoomedPane'], '$path.zoomedPane'),
      customTitle: map['title'] == null
          ? null
          : _string(map['title'], '$path.title'),
      color: color,
    );
  }

  static TerminalRestorableSplitNode _decodeNode(
    Object? value,
    String path, {
    required int depth,
    required _TerminalRestorationDecodeBudget budget,
  }) {
    if (depth > TerminalRestorationLimits.maximumTreeDepth) {
      throw const TerminalRestorationLimitException(
        'restored split tree exceeds its depth limit',
      );
    }
    final Map<String, Object?> map = _map(value, path);
    final String kind = _string(map['kind'], '$path.kind');
    switch (kind) {
      case 'pane':
        _expectKeys(map, const <String>{'kind', 'cwd'});
        budget.admitPane();
        return TerminalRestorableSplitLeaf(
          TerminalRestorablePane(
            workingDirectory: map['cwd'] == null
                ? null
                : _string(map['cwd'], '$path.cwd'),
          ),
        );
      case 'branch':
        _expectKeys(map, const <String>{
          'kind',
          'axis',
          'fraction',
          'first',
          'second',
        });
        final String axisName = _string(map['axis'], '$path.axis');
        final TerminalSplitAxis? axis = TerminalSplitAxis.values
            .where((TerminalSplitAxis candidate) => candidate.name == axisName)
            .firstOrNull;
        if (axis == null) throw FormatException('$path.axis is unsupported');
        return TerminalRestorableSplitBranch(
          axis: axis,
          fraction: _number(map['fraction'], '$path.fraction'),
          first: _decodeNode(
            map['first'],
            '$path.first',
            depth: depth + 1,
            budget: budget,
          ),
          second: _decodeNode(
            map['second'],
            '$path.second',
            depth: depth + 1,
            budget: budget,
          ),
        );
      default:
        throw FormatException('$path.kind is unsupported');
    }
  }

  static void _checkSerializedSize(String encoded) {
    if (utf8.encode(encoded).length >
        TerminalRestorationLimits.maximumSerializedUtf8Bytes) {
      throw const TerminalRestorationLimitException(
        'restoration JSON exceeds its UTF-8 byte limit',
      );
    }
  }

  static Map<String, Object?> _map(Object? value, String path) {
    if (value is! Map<String, Object?>) {
      throw FormatException('$path must be an object');
    }
    return value;
  }

  static List<Object?> _list(Object? value, String path) {
    if (value is! List<Object?>) throw FormatException('$path must be a list');
    return value;
  }

  static String _string(Object? value, String path) {
    if (value is! String) throw FormatException('$path must be a string');
    return value;
  }

  static int _integer(Object? value, String path) {
    if (value is! int) throw FormatException('$path must be an integer');
    return value;
  }

  static double _number(Object? value, String path) {
    if (value is! num || !value.toDouble().isFinite) {
      throw FormatException('$path must be a finite number');
    }
    return value.toDouble();
  }

  static bool _boolean(Object? value, String path) {
    if (value is! bool) throw FormatException('$path must be a boolean');
    return value;
  }

  static void _expectKeys(Map<String, Object?> map, Set<String> expected) {
    if (map.length != expected.length ||
        !map.keys.toSet().containsAll(expected)) {
      throw const FormatException('restoration object has unexpected keys');
    }
  }
}

final class _TerminalRestorationDecodeBudget {
  var _tabs = 0;
  var _panes = 0;

  void admitTabs(int count) {
    _tabs += count;
    if (_tabs > TerminalRestorationLimits.maximumTotalTabs) {
      throw const TerminalRestorationLimitException(
        'restoration JSON exceeds its total tab limit',
      );
    }
  }

  void admitPane() {
    _panes++;
    if (_panes > TerminalRestorationLimits.maximumTotalPanes) {
      throw const TerminalRestorationLimitException(
        'restoration JSON exceeds its total pane limit',
      );
    }
  }
}

typedef TerminalRestorationPlacementProvider = TerminalWindowPlacement Function(
  TerminalWindowId windowId,
);
typedef TerminalRestorationWorkingDirectoryProvider = String? Function(
  PaneId paneId,
);
typedef TerminalRestoredPaneConfigurationFactory =
    TerminalPaneConfiguration Function(TerminalRestorablePane pane);

/// Captures only bounded presentation and fresh-session launch state.
abstract final class TerminalApplicationRestorationCapture {
  static TerminalRestorationSnapshot capture(
    TerminalApplicationState state, {
    required TerminalRestorationPlacementProvider placementForWindow,
    required TerminalRestorationWorkingDirectoryProvider
    workingDirectoryForPane,
  }) {
    state.validate();
    if (state.windows.isEmpty || state.activeWindowId == null) {
      throw StateError('cannot capture an empty terminal application');
    }
    final List<TerminalRestorableWindow> windows = <TerminalRestorableWindow>[];
    for (final TerminalWindowState window in state.windows) {
      final List<TerminalRestorableTab> tabs = <TerminalRestorableTab>[];
      for (final TerminalTabState tab in window.tabs) {
        final List<PaneId> paneIds = tab.paneIds;
        tabs.add(
          TerminalRestorableTab(
            splitTree: _captureNode(
              tab.splitTree.root,
              workingDirectoryForPane,
            ),
            focusedPaneIndex: paneIds.indexOf(tab.focusedPaneId),
            zoomedPaneIndex: tab.zoomedPaneId == null
                ? null
                : paneIds.indexOf(tab.zoomedPaneId!),
            customTitle: tab.customTitle,
            color: tab.color,
          ),
        );
      }
      windows.add(
        TerminalRestorableWindow(
          placement: placementForWindow(window.id),
          tabs: tabs,
          selectedTabIndex: window.tabIds.indexOf(window.selectedTabId),
        ),
      );
    }
    return TerminalRestorationSnapshot(
      windows: windows,
      activeWindowIndex: state.windowIds.indexOf(state.activeWindowId!),
    );
  }

  static TerminalRestorableSplitNode _captureNode(
    TerminalSplitNode node,
    TerminalRestorationWorkingDirectoryProvider workingDirectoryForPane,
  ) => switch (node) {
    TerminalSplitLeaf(:final paneId) => TerminalRestorableSplitLeaf(
      TerminalRestorablePane(workingDirectory: workingDirectoryForPane(paneId)),
    ),
    TerminalSplitBranch(
      :final axis,
      :final fraction,
      :final first,
      :final second,
    ) =>
      TerminalRestorableSplitBranch(
        axis: axis,
        fraction: fraction,
        first: _captureNode(first, workingDirectoryForPane),
        second: _captureNode(second, workingDirectoryForPane),
      ),
  };
}

final class TerminalRestorationResult {
  TerminalRestorationResult({
    required this.applicationState,
    required Map<TerminalWindowId, TerminalWindowPlacement> placements,
    required Map<PaneId, String?> launchWorkingDirectories,
  }) : placements = Map<TerminalWindowId, TerminalWindowPlacement>.unmodifiable(
         placements,
       ),
       launchWorkingDirectories = Map<PaneId, String?>.unmodifiable(
         launchWorkingDirectories,
       );

  final TerminalApplicationState applicationState;
  final Map<TerminalWindowId, TerminalWindowPlacement> placements;
  final Map<PaneId, String?> launchWorkingDirectories;
}

/// Reconstructs snapshot topology with fresh pane/session/native-independent IDs.
abstract final class TerminalApplicationRestorer {
  static Future<TerminalRestorationResult> restore(
    TerminalRestorationSnapshot snapshot, {
    required TerminalRestoredPaneConfigurationFactory configurationForPane,
    TerminalApplicationState? into,
  }) async {
    final TerminalApplicationState state = into ?? TerminalApplicationState();
    if (state.isDisposed || state.windowCount != 0 || state.paneCount != 0) {
      throw StateError('restoration requires an empty live application state');
    }
    final Map<TerminalWindowId, TerminalWindowPlacement> placements =
        <TerminalWindowId, TerminalWindowPlacement>{};
    final Map<PaneId, String?> workingDirectories = <PaneId, String?>{};
    final List<TerminalWindowId> windowIds = <TerminalWindowId>[];
    try {
      for (final TerminalRestorableWindow savedWindow in snapshot.windows) {
        final TerminalRestorableTab firstSavedTab = savedWindow.tabs.first;
        final TerminalRestorablePane firstSavedPane = firstSavedTab.panes.first;
        final TerminalWindowState window = await state.createWindow(
          configurationForPane(firstSavedPane),
        );
        windowIds.add(window.id);
        placements[window.id] = savedWindow.placement;
        final List<TerminalTabId> tabIds = <TerminalTabId>[];
        await _restoreTab(
          state,
          window.selectedTab,
          firstSavedTab,
          configurationForPane,
          workingDirectories,
        );
        tabIds.add(window.selectedTab.id);
        for (final TerminalRestorableTab savedTab in savedWindow.tabs.skip(1)) {
          final TerminalRestorablePane firstPane = savedTab.panes.first;
          final TerminalTabState tab = await state.createTab(
            window.id,
            configurationForPane(firstPane),
          );
          await _restoreTab(
            state,
            tab,
            savedTab,
            configurationForPane,
            workingDirectories,
          );
          tabIds.add(tab.id);
        }
        state.selectTab(window.id, tabIds[savedWindow.selectedTabIndex]);
      }
      state.activateWindow(windowIds[snapshot.activeWindowIndex]);
      state.validate();
      return TerminalRestorationResult(
        applicationState: state,
        placements: placements,
        launchWorkingDirectories: workingDirectories,
      );
    } on Object catch (error, stackTrace) {
      if (!state.isDisposed) await state.shutdown();
      Error.throwWithStackTrace(error, stackTrace);
    }
  }

  static Future<void> _restoreTab(
    TerminalApplicationState state,
    TerminalTabState tab,
    TerminalRestorableTab saved,
    TerminalRestoredPaneConfigurationFactory configurationForPane,
    Map<PaneId, String?> workingDirectories,
  ) async {
    final Map<TerminalRestorablePane, PaneId> paneIds =
        <TerminalRestorablePane, PaneId>{};
    final TerminalRestorablePane initial = saved.panes.first;
    paneIds[initial] = tab.focusedPaneId;
    workingDirectories[tab.focusedPaneId] = initial.workingDirectory;
    await _restoreNode(
      state,
      tab.focusedPaneId,
      saved.splitTree,
      configurationForPane,
      paneIds,
      workingDirectories,
    );
    final List<TerminalRestorablePane> savedPanes = saved.panes;
    final PaneId focused = paneIds[savedPanes[saved.focusedPaneIndex]]!;
    state.focusPane(tab.id, focused);
    if (saved.zoomedPaneIndex != null) {
      state.setPaneZoom(tab.id, focused);
    }
    if (saved.customTitle != null) state.renameTab(tab.id, saved.customTitle);
    if (saved.color != null) state.setTabColor(tab.id, saved.color);
  }

  static Future<void> _restoreNode(
    TerminalApplicationState state,
    PaneId existingPaneId,
    TerminalRestorableSplitNode node,
    TerminalRestoredPaneConfigurationFactory configurationForPane,
    Map<TerminalRestorablePane, PaneId> paneIds,
    Map<PaneId, String?> workingDirectories,
  ) async {
    switch (node) {
      case TerminalRestorableSplitLeaf(:final pane):
        paneIds[pane] = existingPaneId;
        workingDirectories[existingPaneId] = pane.workingDirectory;
      case TerminalRestorableSplitBranch(
        :final axis,
        :final fraction,
        :final first,
        :final second,
      ):
        final TerminalRestorablePane secondInitial = second.panes.first;
        final TerminalPane secondPane = await state.splitPane(
          existingPaneId,
          configurationForPane(secondInitial),
          axis: axis,
          fraction: fraction,
        );
        paneIds[secondInitial] = secondPane.id;
        workingDirectories[secondPane.id] = secondInitial.workingDirectory;
        await _restoreNode(
          state,
          existingPaneId,
          first,
          configurationForPane,
          paneIds,
          workingDirectories,
        );
        await _restoreNode(
          state,
          secondPane.id,
          second,
          configurationForPane,
          paneIds,
          workingDirectories,
        );
    }
  }
}

bool _isSafeLocalWorkingDirectory(String value) {
  if (!value.startsWith('/')) return false;
  try {
    return TerminalTabPresentationResolver.localFilePath(
          Uri.file(value, windows: false),
        ) ==
        value;
  } on ArgumentError {
    return false;
  }
}
