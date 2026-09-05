/// Building blocks for the Dart Terminal starter application.
library;

export 'src/runtime_lifecycle.dart' show RuntimeLifecycleScenario;
export 'src/terminal_application.dart'
    show
        TerminalApplication,
        TerminalKeyEventRouter,
        TerminalOptions,
        RuntimeShellExitTestScenario,
        terminalUsage;
export 'src/terminal_buffer.dart' show TerminalBuffer;
export 'src/terminal_core/streaming_utf8_decoder.dart'
    show StreamingUtf8Decoder, Utf8ScalarSink;
export 'src/terminal_core/terminal_reply.dart'
    show TerminalModeReportStatus, TerminalReplyEncoder, TerminalReplyHandler;
export 'src/terminal_core/terminal_screen.dart'
    show
        TerminalCellFlags,
        TerminalCursorShape,
        TerminalPalette,
        TerminalRowFlags,
        TerminalScreen,
        TerminalScreenMode,
        TerminalScrollback;
export 'src/terminal_core/terminal_screen_parser_sink.dart'
    show TerminalScreenParserSink;
export 'src/terminal_core/terminal_screen_set.dart'
    show
        TerminalLogicalAnchor,
        TerminalSearchDirection,
        TerminalSearchMatch,
        TerminalSearchResult,
        TerminalScreenKind,
        TerminalScreenSet,
        TerminalSelectionRange,
        TerminalSelectionText,
        TerminalSelectionUnit,
        TerminalViewport,
        TerminalViewportPosition;
export 'src/terminal_core/terminal_snapshot.dart'
    show
        TerminalSnapshotFormatLimits,
        TerminalSnapshotFormatter,
        TerminalSnapshotLimitException;
export 'src/terminal_core/terminal_snapshot_comparison.dart'
    show
        TerminalSnapshotComparator,
        TerminalSnapshotComparison,
        TerminalSnapshotComparisonLimits,
        TerminalSnapshotMismatchException;
export 'src/terminal_core/terminal_style.dart'
    show TerminalStyleAttributes, TerminalStyleTable, TerminalUnderlineStyle;
export 'src/terminal_core/terminal_unicode.dart'
    show TerminalGraphemeBreaker, TerminalGraphemeTable, TerminalUnicode;
export 'src/terminal_core/vt_parser.dart'
    show
        VtDcsSequence,
        VtEscapeSequence,
        VtParameters,
        VtParser,
        VtParserAsciiSink,
        VtParserLimitKind,
        VtParserLimits,
        VtParserSink,
        VtParserUncapturedSequenceSink,
        VtSequenceHeader,
        VtStringKind,
        VtStringSequence,
        VtStringTerminator,
        VtUncapturedSequenceKind;
export 'src/terminal_core/vt_parser_table.dart' show VtParserState;
export 'src/terminal_pane.dart'
    show
        PaneId,
        TerminalPane,
        TerminalPaneCloseDecision,
        TerminalPaneExitAction,
        TerminalPaneExitObservation,
        TerminalPaneExitObserver,
        TerminalPaneLifecycleObservation,
        TerminalPaneLifecycleObserver,
        TerminalPaneOwner,
        TerminalPaneOwnerShutdownResult,
        TerminalPaneSession,
        TerminalPaneSessionExitDisposition,
        TerminalPaneSessionFactory,
        TerminalPaneSessionShutdownResult,
        TerminalPaneState,
        TerminalSessionShutdownDisposition,
        TerminalSessionId;
export 'src/terminal_renderer/frame_scheduler.dart';
export 'src/terminal_renderer/glyph_atlas.dart';
export 'src/terminal_renderer/golden_image.dart'
    show
        TerminalGoldenImageCodec,
        TerminalGoldenImageComparator,
        TerminalGoldenImageComparison,
        TerminalGoldenImageComparisonLimits,
        TerminalGoldenImageFormatException,
        TerminalGoldenImageLimits,
        TerminalGoldenImageMismatchException;
export 'src/terminal_renderer/metal_atlas_bridge.dart';
export 'src/terminal_renderer/metal_failure_recovery.dart';
export 'src/terminal_renderer/reference_renderer.dart'
    show
        TerminalReferenceBitmap,
        TerminalReferenceColor,
        TerminalReferenceImage,
        TerminalReferenceLayer,
        TerminalReferenceMask,
        TerminalReferencePrimitive,
        TerminalReferenceRenderLimits,
        TerminalReferenceRenderer,
        TerminalReferenceSolid;
export 'src/terminal_renderer/render_rebuild_coordinator.dart';
export 'src/terminal_renderer/render_resource_rebuilder.dart';
export 'src/terminal_renderer/terminal_damage.dart';
export 'src/terminal_renderer/terminal_damage_transfer.dart';
export 'src/terminal_session.dart'
    show
        TerminalSessionNativeObservation,
        TerminalSessionNativeObserver,
        TerminalSessionShutdownResult;
