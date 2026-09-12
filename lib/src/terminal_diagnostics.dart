import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'terminal_core/terminal_mouse_modes.dart';
import 'terminal_core/terminal_screen_parser_sink.dart';
import 'terminal_core/terminal_screen_set.dart';
import 'terminal_core/vt_parser_inspector.dart';
import 'terminal_core/vt_parser_trace.dart';
import 'terminal_renderer/terminal_live_metal_surface.dart';

enum TerminalDiagnosticsRuntimeKind { developerJit, releaseAot }

enum TerminalDiagnosticsLanguage { english, japanese }

enum TerminalDiagnosticsDirection { leftToRight, rightToLeft }

enum TerminalDiagnosticsWindowRole { standard, quick }

enum TerminalDiagnosticsPaneLifecycle {
  unavailable,
  created,
  starting,
  running,
  confirmationPending,
  exited,
  failed,
  closing,
  closed,
}

enum TerminalDiagnosticsFeatureState {
  unavailable,
  disabled,
  enabled,
  active,
  denied,
  failed,
}

enum TerminalDiagnosticsExportDisposition { written, failed }

enum TerminalDiagnosticsLimitKind { inspectorText, outputBytes }

final class TerminalDiagnosticsLimitException implements Exception {
  const TerminalDiagnosticsLimitException({
    required this.kind,
    required this.actual,
    required this.maximum,
  });

  final TerminalDiagnosticsLimitKind kind;
  final int actual;
  final int maximum;

  @override
  String toString() =>
      'TerminalDiagnosticsLimitException(${kind.name}: $actual > $maximum)';
}

final class TerminalDiagnosticsApplicationSnapshot {
  TerminalDiagnosticsApplicationSnapshot({
    required this.runtimeKind,
    required this.appKitEventProtocol,
    required this.language,
    required this.direction,
    required this.reduceMotion,
    required this.increaseContrast,
    required this.differentiateWithoutColor,
  }) {
    if (appKitEventProtocol < 1) {
      throw ArgumentError.value(
        appKitEventProtocol,
        'appKitEventProtocol',
        'must be positive',
      );
    }
  }

  final TerminalDiagnosticsRuntimeKind runtimeKind;
  final int appKitEventProtocol;
  final TerminalDiagnosticsLanguage language;
  final TerminalDiagnosticsDirection direction;
  final bool reduceMotion;
  final bool increaseContrast;
  final bool differentiateWithoutColor;

  Map<String, Object?> toJson() => <String, Object?>{
    'runtime': runtimeKind.name,
    'appkit_event_protocol': appKitEventProtocol,
    'language': language.name,
    'direction': direction.name,
    'reduce_motion': reduceMotion,
    'increase_contrast': increaseContrast,
    'differentiate_without_color': differentiateWithoutColor,
  };
}

final class TerminalDiagnosticsHierarchySnapshot {
  TerminalDiagnosticsHierarchySnapshot({
    required this.windowCount,
    required this.tabCount,
    required this.paneCount,
    required this.livePaneCount,
    required this.activeWindowRole,
  }) {
    _nonnegative(windowCount, 'windowCount');
    _nonnegative(tabCount, 'tabCount');
    _nonnegative(paneCount, 'paneCount');
    _nonnegative(livePaneCount, 'livePaneCount');
    if (livePaneCount > paneCount) {
      throw ArgumentError.value(
        livePaneCount,
        'livePaneCount',
        'cannot exceed paneCount',
      );
    }
  }

  final int windowCount;
  final int tabCount;
  final int paneCount;
  final int livePaneCount;
  final TerminalDiagnosticsWindowRole activeWindowRole;

  Map<String, Object?> toJson() => <String, Object?>{
    'windows': windowCount,
    'tabs': tabCount,
    'panes': paneCount,
    'live_panes': livePaneCount,
    'active_window_role': activeWindowRole.name,
  };
}

final class TerminalDiagnosticsFocusedPaneSnapshot {
  TerminalDiagnosticsFocusedPaneSnapshot({
    required this.present,
    required this.lifecycle,
    required this.rows,
    required this.columns,
    required this.activeScreen,
    required this.viewportOffset,
    required this.applicationCursorKeys,
    required this.applicationKeypad,
    required this.applicationEscape,
    required this.modifyOtherKeys,
    required this.kittyKeyboardFlags,
    required this.kittyKeyboardStackDepth,
    required this.bracketedPasteMode,
    required this.focusReportingMode,
    required this.synchronizedOutputMode,
    required this.colorSchemeReportingMode,
    required this.inBandSizeReportingMode,
    required this.mouseTracking,
    required this.mouseEncoding,
    required this.transitionGeneration,
    required this.resetGeneration,
    required this.scrollbackRows,
    required this.styleDefinitions,
    required this.graphemeDefinitions,
    required this.graphemeScalars,
    required this.hyperlinkDefinitions,
    required this.hyperlinkRefusals,
    required this.kittyImages,
    required this.kittyPlacements,
    required this.writeBackpressureCount,
    required this.replyBackpressureCount,
    required this.concurrentPasteInputRejections,
  }) {
    for (final MapEntry<String, int> field in <String, int>{
      'rows': rows,
      'columns': columns,
      'viewportOffset': viewportOffset,
      'modifyOtherKeys': modifyOtherKeys,
      'kittyKeyboardFlags': kittyKeyboardFlags,
      'kittyKeyboardStackDepth': kittyKeyboardStackDepth,
      'transitionGeneration': transitionGeneration,
      'resetGeneration': resetGeneration,
      'scrollbackRows': scrollbackRows,
      'styleDefinitions': styleDefinitions,
      'graphemeDefinitions': graphemeDefinitions,
      'graphemeScalars': graphemeScalars,
      'hyperlinkDefinitions': hyperlinkDefinitions,
      'hyperlinkRefusals': hyperlinkRefusals,
      'kittyImages': kittyImages,
      'kittyPlacements': kittyPlacements,
      'writeBackpressureCount': writeBackpressureCount,
      'replyBackpressureCount': replyBackpressureCount,
      'concurrentPasteInputRejections': concurrentPasteInputRejections,
    }.entries) {
      _nonnegative(field.value, field.key);
    }
    if (!present && lifecycle != TerminalDiagnosticsPaneLifecycle.unavailable) {
      throw ArgumentError.value(
        lifecycle,
        'lifecycle',
        'must be unavailable when no focused pane is present',
      );
    }
    if (present && lifecycle == TerminalDiagnosticsPaneLifecycle.unavailable) {
      throw ArgumentError.value(
        lifecycle,
        'lifecycle',
        'must describe the focused pane when present',
      );
    }
    if (present && (rows < 1 || columns < 1)) {
      throw ArgumentError('present focused pane dimensions must be positive');
    }
  }

  factory TerminalDiagnosticsFocusedPaneSnapshot.unavailable() =>
      TerminalDiagnosticsFocusedPaneSnapshot(
        present: false,
        lifecycle: TerminalDiagnosticsPaneLifecycle.unavailable,
        rows: 0,
        columns: 0,
        activeScreen: TerminalScreenKind.primary,
        viewportOffset: 0,
        applicationCursorKeys: false,
        applicationKeypad: false,
        applicationEscape: false,
        modifyOtherKeys: 0,
        kittyKeyboardFlags: 0,
        kittyKeyboardStackDepth: 0,
        bracketedPasteMode: false,
        focusReportingMode: false,
        synchronizedOutputMode: false,
        colorSchemeReportingMode: false,
        inBandSizeReportingMode: false,
        mouseTracking: TerminalMouseTrackingMode.none,
        mouseEncoding: TerminalMouseCoordinateEncoding.legacy,
        transitionGeneration: 0,
        resetGeneration: 0,
        scrollbackRows: 0,
        styleDefinitions: 0,
        graphemeDefinitions: 0,
        graphemeScalars: 0,
        hyperlinkDefinitions: 0,
        hyperlinkRefusals: 0,
        kittyImages: 0,
        kittyPlacements: 0,
        writeBackpressureCount: 0,
        replyBackpressureCount: 0,
        concurrentPasteInputRejections: 0,
      );

  final bool present;
  final TerminalDiagnosticsPaneLifecycle lifecycle;
  final int rows;
  final int columns;
  final TerminalScreenKind activeScreen;
  final int viewportOffset;
  final bool applicationCursorKeys;
  final bool applicationKeypad;
  final bool applicationEscape;
  final int modifyOtherKeys;
  final int kittyKeyboardFlags;
  final int kittyKeyboardStackDepth;
  final bool bracketedPasteMode;
  final bool focusReportingMode;
  final bool synchronizedOutputMode;
  final bool colorSchemeReportingMode;
  final bool inBandSizeReportingMode;
  final TerminalMouseTrackingMode mouseTracking;
  final TerminalMouseCoordinateEncoding mouseEncoding;
  final int transitionGeneration;
  final int resetGeneration;
  final int scrollbackRows;
  final int styleDefinitions;
  final int graphemeDefinitions;
  final int graphemeScalars;
  final int hyperlinkDefinitions;
  final int hyperlinkRefusals;
  final int kittyImages;
  final int kittyPlacements;
  final int writeBackpressureCount;
  final int replyBackpressureCount;
  final int concurrentPasteInputRejections;

  Map<String, Object?> toJson() => <String, Object?>{
    'present': present,
    'lifecycle': lifecycle.name,
    'rows': rows,
    'columns': columns,
    'active_screen': activeScreen.name,
    'viewport_offset': viewportOffset,
    'keyboard_modes': <String, Object?>{
      'application_cursor_keys': applicationCursorKeys,
      'application_keypad': applicationKeypad,
      'application_escape': applicationEscape,
      'modify_other_keys': modifyOtherKeys,
      'kitty_flags': kittyKeyboardFlags,
      'kitty_stack_depth': kittyKeyboardStackDepth,
    },
    'modes': <String, Object?>{
      'bracketed_paste': bracketedPasteMode,
      'focus_reporting': focusReportingMode,
      'synchronized_output': synchronizedOutputMode,
      'color_scheme_reporting': colorSchemeReportingMode,
      'in_band_size_reporting': inBandSizeReportingMode,
      'mouse_tracking': mouseTracking.name,
      'mouse_encoding': mouseEncoding.name,
    },
    'generations': <String, Object?>{
      'transition': transitionGeneration,
      'reset': resetGeneration,
    },
    'resources': <String, Object?>{
      'scrollback_rows': scrollbackRows,
      'style_definitions': styleDefinitions,
      'grapheme_definitions': graphemeDefinitions,
      'grapheme_scalars': graphemeScalars,
      'hyperlink_definitions': hyperlinkDefinitions,
      'hyperlink_refusals': hyperlinkRefusals,
      'kitty_images': kittyImages,
      'kitty_placements': kittyPlacements,
    },
    'transport': <String, Object?>{
      'write_backpressure': writeBackpressureCount,
      'reply_backpressure': replyBackpressureCount,
      'concurrent_paste_input_rejections': concurrentPasteInputRejections,
    },
  };
}

final class TerminalDiagnosticsParserSnapshot {
  TerminalDiagnosticsParserSnapshot({
    required this.inspection,
    required this.unsupportedControls,
    required this.unsupportedSequences,
    required this.cancelCount,
    required this.limitCount,
    required this.malformedCount,
    required this.incompleteCount,
    required this.acceptedReplies,
    required this.rejectedReplies,
    required this.acceptedHyperlinks,
    required this.rejectedHyperlinks,
    required this.deniedClipboardReads,
    required this.deniedClipboardWrites,
    required this.deniedClipboardClears,
    required this.rejectedClipboardRequests,
    required this.acceptedClipboardReads,
    required this.acceptedClipboardWrites,
    required this.acceptedClipboardClears,
    required this.acceptedGraphicsCommands,
    required this.rejectedGraphicsCommands,
    required this.acceptedNotifications,
    required this.acceptedProgressUpdates,
  }) {
    for (final MapEntry<String, int> field in <String, int>{
      'unsupportedControls': unsupportedControls,
      'unsupportedSequences': unsupportedSequences,
      'cancelCount': cancelCount,
      'limitCount': limitCount,
      'malformedCount': malformedCount,
      'incompleteCount': incompleteCount,
      'acceptedReplies': acceptedReplies,
      'rejectedReplies': rejectedReplies,
      'acceptedHyperlinks': acceptedHyperlinks,
      'rejectedHyperlinks': rejectedHyperlinks,
      'deniedClipboardReads': deniedClipboardReads,
      'deniedClipboardWrites': deniedClipboardWrites,
      'deniedClipboardClears': deniedClipboardClears,
      'rejectedClipboardRequests': rejectedClipboardRequests,
      'acceptedClipboardReads': acceptedClipboardReads,
      'acceptedClipboardWrites': acceptedClipboardWrites,
      'acceptedClipboardClears': acceptedClipboardClears,
      'acceptedGraphicsCommands': acceptedGraphicsCommands,
      'rejectedGraphicsCommands': rejectedGraphicsCommands,
      'acceptedNotifications': acceptedNotifications,
      'acceptedProgressUpdates': acceptedProgressUpdates,
    }.entries) {
      _nonnegative(field.value, field.key);
    }
  }

  factory TerminalDiagnosticsParserSnapshot.capture({
    required VtParserInspector inspector,
    required TerminalScreenParserSink sink,
  }) => TerminalDiagnosticsParserSnapshot(
    inspection: inspector.snapshot(),
    unsupportedControls: sink.unsupportedControlCount,
    unsupportedSequences: sink.unsupportedSequenceCount,
    cancelCount: sink.cancelCount,
    limitCount: sink.limitCount,
    malformedCount: sink.malformedCount,
    incompleteCount: sink.incompleteCount,
    acceptedReplies: sink.acceptedReplyCount,
    rejectedReplies: sink.rejectedReplyCount,
    acceptedHyperlinks: sink.acceptedHyperlinkCount,
    rejectedHyperlinks: sink.rejectedHyperlinkCount,
    deniedClipboardReads: sink.deniedClipboardReadCount,
    deniedClipboardWrites: sink.deniedClipboardWriteCount,
    deniedClipboardClears: sink.deniedClipboardClearCount,
    rejectedClipboardRequests: sink.rejectedClipboardRequestCount,
    acceptedClipboardReads: sink.acceptedClipboardReadCount,
    acceptedClipboardWrites: sink.acceptedClipboardWriteCount,
    acceptedClipboardClears: sink.acceptedClipboardClearCount,
    acceptedGraphicsCommands: sink.acceptedKittyGraphicsCommandCount,
    rejectedGraphicsCommands: sink.rejectedKittyGraphicsCommandCount,
    acceptedNotifications: sink.acceptedDesktopNotificationCount,
    acceptedProgressUpdates: sink.acceptedProgressUpdateCount,
  );

  final VtParserInspectionSnapshot inspection;
  final int unsupportedControls;
  final int unsupportedSequences;
  final int cancelCount;
  final int limitCount;
  final int malformedCount;
  final int incompleteCount;
  final int acceptedReplies;
  final int rejectedReplies;
  final int acceptedHyperlinks;
  final int rejectedHyperlinks;
  final int deniedClipboardReads;
  final int deniedClipboardWrites;
  final int deniedClipboardClears;
  final int rejectedClipboardRequests;
  final int acceptedClipboardReads;
  final int acceptedClipboardWrites;
  final int acceptedClipboardClears;
  final int acceptedGraphicsCommands;
  final int rejectedGraphicsCommands;
  final int acceptedNotifications;
  final int acceptedProgressUpdates;

  Map<String, Object?> toJson() => <String, Object?>{
    'capture_enabled': inspection.captureEnabled,
    'inspection': VtParserTraceExporter().observationSnapshot(inspection),
    'semantics': <String, Object?>{
      'unsupported_controls': unsupportedControls,
      'unsupported_sequences': unsupportedSequences,
      'cancel': cancelCount,
      'limit': limitCount,
      'malformed': malformedCount,
      'incomplete': incompleteCount,
      'accepted_replies': acceptedReplies,
      'rejected_replies': rejectedReplies,
      'accepted_hyperlinks': acceptedHyperlinks,
      'rejected_hyperlinks': rejectedHyperlinks,
      'denied_clipboard_reads': deniedClipboardReads,
      'denied_clipboard_writes': deniedClipboardWrites,
      'denied_clipboard_clears': deniedClipboardClears,
      'rejected_clipboard_requests': rejectedClipboardRequests,
      'accepted_clipboard_reads': acceptedClipboardReads,
      'accepted_clipboard_writes': acceptedClipboardWrites,
      'accepted_clipboard_clears': acceptedClipboardClears,
      'accepted_graphics_commands': acceptedGraphicsCommands,
      'rejected_graphics_commands': rejectedGraphicsCommands,
      'accepted_notifications': acceptedNotifications,
      'accepted_progress_updates': acceptedProgressUpdates,
    },
  };
}

final class TerminalDiagnosticsRendererSnapshot {
  const TerminalDiagnosticsRendererSnapshot._(this._fields);

  factory TerminalDiagnosticsRendererSnapshot.unavailable() =>
      const TerminalDiagnosticsRendererSnapshot._(<String, Object?>{
        'available': false,
      });

  factory TerminalDiagnosticsRendererSnapshot.fromLiveSurface(
    TerminalLiveMetalSurfaceSnapshot snapshot,
  ) => TerminalDiagnosticsRendererSnapshot._(<String, Object?>{
    'available': true,
    'disposed': snapshot.isDisposed,
    'rows': snapshot.rows,
    'columns': snapshot.columns,
    'viewport_width': snapshot.viewportWidth,
    'viewport_height': snapshot.viewportHeight,
    'content_offset_x': snapshot.contentOffsetX,
    'content_offset_y': snapshot.contentOffsetY,
    'content_viewport_width': snapshot.contentViewportWidth,
    'content_viewport_height': snapshot.contentViewportHeight,
    'scale_16_16': snapshot.scale16_16,
    'last_damage_generation': snapshot.lastAppliedDamageGeneration,
    'last_model_revision': snapshot.lastAcceptedModelRevision,
    'last_frame_generation': snapshot.lastAcceptedFrameGeneration,
    'renderer_generation': snapshot.rendererGeneration,
    'atlas_generation': snapshot.atlasResourceGeneration,
    'frame_builds': snapshot.frameBuildCount,
    'accepted_frames': snapshot.acceptedFrameCount,
    'pending_frames': snapshot.pendingFrameCount,
    'live_atlas_pins': snapshot.liveAtlasPinCount,
    'kitty_atlas_entries': snapshot.kittyAtlasEntryCount,
    'kitty_images': snapshot.kittyImageCount,
    'kitty_placements': snapshot.kittyPlacementCount,
    'kitty_tiles': snapshot.kittyTileCount,
    'kitty_resource_evictions': snapshot.kittyResourceEvictionCount,
    'kitty_evicted_bytes': snapshot.kittyEvictedBytes,
    'kitty_evicted_placements': snapshot.kittyEvictedPlacementCount,
    'kitty_atlas_evictions': snapshot.kittyAtlasEvictionCount,
    'scheduled_work': snapshot.hasScheduledWork,
    'synchronized_output_mode': snapshot.synchronizedOutputMode,
    'synchronized_output_held': snapshot.synchronizedOutputHeld,
    'synchronized_output_releases': snapshot.synchronizedOutputReleaseCount,
    'synchronized_output_timeouts': snapshot.synchronizedOutputTimeoutCount,
    'accessibility_generation': snapshot.accessibilityGeneration,
    'reduce_motion': snapshot.reduceMotion,
    'increase_contrast': snapshot.increaseContrast,
    'differentiate_without_color': snapshot.differentiateWithoutColor,
  });

  final Map<String, Object?> _fields;

  Map<String, Object?> toJson() => Map<String, Object?>.of(_fields);
}

final class TerminalDiagnosticsConfigurationSnapshot {
  TerminalDiagnosticsConfigurationSnapshot({
    required this.schemaOptionCount,
    required this.effectiveGeneration,
    required this.attemptGeneration,
    required this.warningCount,
    required this.errorCount,
    required this.liveOptionCount,
    required this.newSessionOptionCount,
  }) {
    for (final MapEntry<String, int> field in <String, int>{
      'schemaOptionCount': schemaOptionCount,
      'effectiveGeneration': effectiveGeneration,
      'attemptGeneration': attemptGeneration,
      'warningCount': warningCount,
      'errorCount': errorCount,
      'liveOptionCount': liveOptionCount,
      'newSessionOptionCount': newSessionOptionCount,
    }.entries) {
      _nonnegative(field.value, field.key);
    }
  }

  final int schemaOptionCount;
  final int effectiveGeneration;
  final int attemptGeneration;
  final int warningCount;
  final int errorCount;
  final int liveOptionCount;
  final int newSessionOptionCount;

  Map<String, Object?> toJson() => <String, Object?>{
    'schema_options': schemaOptionCount,
    'effective_generation': effectiveGeneration,
    'attempt_generation': attemptGeneration,
    'diagnostic_warnings': warningCount,
    'diagnostic_errors': errorCount,
    'live_options': liveOptionCount,
    'new_session_options': newSessionOptionCount,
  };
}

final class TerminalDiagnosticsFeaturesSnapshot {
  TerminalDiagnosticsFeaturesSnapshot({
    required this.secureInput,
    required this.quickWindowShortcut,
    required this.notifications,
    required this.appIntents,
    required this.appleScript,
    required this.osc52,
    required this.pendingOsc52Requests,
    required this.pendingNotificationRequests,
  }) {
    _nonnegative(pendingOsc52Requests, 'pendingOsc52Requests');
    _nonnegative(pendingNotificationRequests, 'pendingNotificationRequests');
  }

  final TerminalDiagnosticsFeatureState secureInput;
  final TerminalDiagnosticsFeatureState quickWindowShortcut;
  final TerminalDiagnosticsFeatureState notifications;
  final TerminalDiagnosticsFeatureState appIntents;
  final TerminalDiagnosticsFeatureState appleScript;
  final TerminalDiagnosticsFeatureState osc52;
  final int pendingOsc52Requests;
  final int pendingNotificationRequests;

  Map<String, Object?> toJson() => <String, Object?>{
    'secure_input': secureInput.name,
    'quick_window_shortcut': quickWindowShortcut.name,
    'notifications': notifications.name,
    'app_intents': appIntents.name,
    'apple_script': appleScript.name,
    'osc52': osc52.name,
    'pending_osc52_requests': pendingOsc52Requests,
    'pending_notification_requests': pendingNotificationRequests,
  };
}

final class TerminalDiagnosticsSnapshot {
  const TerminalDiagnosticsSnapshot({
    required this.application,
    required this.hierarchy,
    required this.focusedPane,
    required this.parser,
    required this.renderer,
    required this.configuration,
    required this.features,
  });

  final TerminalDiagnosticsApplicationSnapshot application;
  final TerminalDiagnosticsHierarchySnapshot hierarchy;
  final TerminalDiagnosticsFocusedPaneSnapshot focusedPane;
  final TerminalDiagnosticsParserSnapshot parser;
  final TerminalDiagnosticsRendererSnapshot renderer;
  final TerminalDiagnosticsConfigurationSnapshot configuration;
  final TerminalDiagnosticsFeaturesSnapshot features;
}

final class TerminalDiagnosticsFormatter {
  const TerminalDiagnosticsFormatter();

  static const String formatName = 'dart-terminal-diagnostics';
  static const int formatVersion = 1;
  static const int maximumInspectorTextUtf8Bytes = 256 * 1024;
  static const int maximumOutputUtf8Bytes = 1024 * 1024;

  Uint8List encode(TerminalDiagnosticsSnapshot snapshot) {
    final _TerminalDiagnosticsByteSink output = _TerminalDiagnosticsByteSink(
      maximumOutputUtf8Bytes,
      TerminalDiagnosticsLimitKind.outputBytes,
    );
    final Sink<Object?> encoder = JsonUtf8Encoder('  ')
        .startChunkedConversion(output);
    encoder.add(_report(snapshot));
    encoder.close();
    output.add(const <int>[0x0a]);
    return output.takeBytes();
  }

  String formatInspector(TerminalDiagnosticsSnapshot snapshot) {
    Uint8List? full;
    var fullLength = maximumOutputUtf8Bytes + 1;
    try {
      full = encode(snapshot);
      fullLength = full.length;
    } on TerminalDiagnosticsLimitException catch (error) {
      if (error.kind != TerminalDiagnosticsLimitKind.outputBytes) rethrow;
      fullLength = error.actual;
    }
    if (full != null && full.length <= maximumInspectorTextUtf8Bytes) {
      return utf8.decode(full);
    }
    final VtParserInspectionSnapshot parser = snapshot.parser.inspection;
    final Map<String, Object?> summary = <String, Object?>{
      'format': formatName,
      'version': formatVersion,
      'truncated': true,
      'full_utf8_bytes': fullLength,
      'events_total': parser.totalEventCount,
      'events_retained': parser.events.length,
      'events_evicted': parser.evictedEventCount,
      'events_oversized': parser.oversizedEventCount,
    };
    final String rendered =
        '${const JsonEncoder.withIndent('  ').convert(summary)}\n';
    if (utf8.encode(rendered).length > maximumInspectorTextUtf8Bytes) {
      throw TerminalDiagnosticsLimitException(
        kind: TerminalDiagnosticsLimitKind.inspectorText,
        actual: utf8.encode(rendered).length,
        maximum: maximumInspectorTextUtf8Bytes,
      );
    }
    return rendered;
  }

  Map<String, Object?> _report(TerminalDiagnosticsSnapshot snapshot) =>
      <String, Object?>{
        'format': formatName,
        'version': formatVersion,
        'privacy': <String, Object?>{
          'printable_text': 'count_only',
          'string_payloads': 'length_only',
          'paths': 'omitted',
          'arguments': 'omitted',
          'environment': 'omitted',
          'clipboard': 'omitted',
          'timestamps': 'omitted',
          'stable_identifiers': 'omitted',
          'raw_errors': 'omitted',
        },
        'limits': <String, Object?>{
          'parser_records': snapshot.parser.inspection.limits.maxRecords,
          'parser_metadata_bytes':
              snapshot.parser.inspection.limits.maxMetadataBytes,
          'inspector_text_bytes': maximumInspectorTextUtf8Bytes,
          'output_bytes': maximumOutputUtf8Bytes,
        },
        'application': snapshot.application.toJson(),
        'hierarchy': snapshot.hierarchy.toJson(),
        'focused_pane': snapshot.focusedPane.toJson(),
        'parser': snapshot.parser.toJson(),
        'renderer': snapshot.renderer.toJson(),
        'configuration': snapshot.configuration.toJson(),
        'features': snapshot.features.toJson(),
      };
}

final class TerminalDiagnosticsExportResult {
  const TerminalDiagnosticsExportResult._(this.disposition, this.byteCount);

  const TerminalDiagnosticsExportResult.written(int byteCount)
    : this._(TerminalDiagnosticsExportDisposition.written, byteCount);

  const TerminalDiagnosticsExportResult.failed()
    : this._(TerminalDiagnosticsExportDisposition.failed, 0);

  final TerminalDiagnosticsExportDisposition disposition;
  final int byteCount;
}

abstract interface class TerminalDiagnosticsFileOperations {
  Future<void> writeExclusive(String path, Uint8List bytes);
  Future<void> replace(String sourcePath, String destinationPath);
  Future<void> remove(String path);
}

final class TerminalDiagnosticsAtomicWriter {
  TerminalDiagnosticsAtomicWriter({TerminalDiagnosticsFileOperations? files})
    : _files = files ?? const _LocalTerminalDiagnosticsFileOperations();

  static const int _maximumTemporaryFileAttempts = 16;
  final TerminalDiagnosticsFileOperations _files;
  int _nextTemporaryOrdinal = 1;

  Future<TerminalDiagnosticsExportResult> write({
    required String destinationPath,
    required Uint8List bytes,
  }) async {
    if (!destinationPath.startsWith('/') ||
        destinationPath.contains('\u0000')) {
      return const TerminalDiagnosticsExportResult.failed();
    }
    if (bytes.isEmpty ||
        bytes.length > TerminalDiagnosticsFormatter.maximumOutputUtf8Bytes) {
      return const TerminalDiagnosticsExportResult.failed();
    }
    String? temporaryPath;
    try {
      for (
        var attempt = 0;
        attempt < _maximumTemporaryFileAttempts;
        attempt++
      ) {
        final int ordinal = _nextTemporaryOrdinal++;
        if (_nextTemporaryOrdinal > 0x7fffffff) _nextTemporaryOrdinal = 1;
        final String candidate = '$destinationPath.dart-terminal-$ordinal.tmp';
        try {
          await _files.writeExclusive(candidate, bytes);
          temporaryPath = candidate;
          break;
        } on FileSystemException catch (error) {
          if (error.osError?.errorCode != 17) rethrow;
        }
      }
      final String? writtenPath = temporaryPath;
      if (writtenPath == null) {
        return const TerminalDiagnosticsExportResult.failed();
      }
      await _files.replace(writtenPath, destinationPath);
      temporaryPath = null;
      return TerminalDiagnosticsExportResult.written(bytes.length);
    } on Object {
      return const TerminalDiagnosticsExportResult.failed();
    } finally {
      final String? abandoned = temporaryPath;
      if (abandoned != null) {
        try {
          await _files.remove(abandoned);
        } on Object {
          // Cleanup failure must not disclose the selected local path.
        }
      }
    }
  }
}

final class _LocalTerminalDiagnosticsFileOperations
    implements TerminalDiagnosticsFileOperations {
  const _LocalTerminalDiagnosticsFileOperations();

  @override
  Future<void> writeExclusive(String path, Uint8List bytes) async {
    final File destination = File(path);
    RandomAccessFile? file;
    try {
      await destination.create(exclusive: true);
      file = await destination.open(mode: FileMode.write);
      await file.writeFrom(bytes);
      await file.flush();
      await file.close();
      file = null;
    } on Object {
      try {
        await file?.close();
      } on Object {
        // Preserve the original write failure.
      }
      try {
        await destination.delete();
      } on Object {
        // The outer writer still reports only a classified failure.
      }
      rethrow;
    }
  }

  @override
  Future<void> replace(String sourcePath, String destinationPath) async {
    await File(sourcePath).rename(destinationPath);
  }

  @override
  Future<void> remove(String path) async {
    await File(path).delete();
  }
}

final class _TerminalDiagnosticsByteSink implements Sink<List<int>> {
  _TerminalDiagnosticsByteSink(this.maximum, this.kind);

  final int maximum;
  final TerminalDiagnosticsLimitKind kind;
  final BytesBuilder _bytes = BytesBuilder(copy: false);
  int _length = 0;

  @override
  void add(List<int> data) {
    final int next = _length + data.length;
    if (next > maximum) {
      throw TerminalDiagnosticsLimitException(
        kind: kind,
        actual: next,
        maximum: maximum,
      );
    }
    _bytes.add(data);
    _length = next;
  }

  @override
  void close() {}

  Uint8List takeBytes() => _bytes.takeBytes();
}

void _nonnegative(int value, String name) {
  if (value < 0) {
    throw ArgumentError.value(value, name, 'must be nonnegative');
  }
}
