/// Building blocks for the Dart Terminal starter application.
library;

export 'src/runtime_lifecycle.dart' show RuntimeLifecycleScenario;
export 'src/terminal_action_menu.dart';
export 'src/terminal_action_registry.dart';
export 'src/terminal_application.dart'
    show
        TerminalApplication,
        TerminalKeyRouteDisposition,
        TerminalKeyRouteResult,
        TerminalKeyEventRouter,
        TerminalOptions,
        RuntimeShellExitTestScenario,
        terminalUsage;
export 'src/terminal_application_quit_coordinator.dart';
export 'src/terminal_application_state.dart';
export 'src/terminal_buffer.dart' show TerminalBuffer;
export 'src/terminal_command_line.dart';
export 'src/terminal_command_palette.dart';
export 'src/terminal_config.dart';
export 'src/terminal_config_reload.dart';
export 'src/terminal_configuration_reference.dart';
export 'src/terminal_core/streaming_utf8_decoder.dart'
    show StreamingUtf8Decoder, Utf8ScalarSink;
export 'src/terminal_core/terminal_hyperlink.dart'
    show
        TerminalHyperlinkDefinition,
        TerminalHyperlinkHit,
        TerminalHyperlinkTable;
export 'src/terminal_core/terminal_keyboard_modes.dart'
    show TerminalKeyboardModes;
export 'src/terminal_core/terminal_mouse_modes.dart';
export 'src/terminal_core/terminal_reply.dart'
    show TerminalModeReportStatus, TerminalReplyEncoder, TerminalReplyHandler;
export 'src/terminal_core/terminal_screen.dart'
    show
        TerminalCellFlags,
        TerminalCharacterSet,
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
        TerminalAccessibilityLimitException,
        TerminalAccessibilityLimitKind,
        TerminalAccessibilityLine,
        TerminalAccessibilitySnapshot,
        TerminalAccessibilityTextRange,
        TerminalLogicalAnchor,
        TerminalSearchDirection,
        TerminalSearchMatch,
        TerminalSearchResult,
        TerminalScreenKind,
        TerminalScreenSet,
        TerminalSelectionProjection,
        TerminalSelectionRange,
        TerminalSelectionSpan,
        TerminalSelectionText,
        TerminalSelectionUnit,
        TerminalViewport,
        TerminalViewportPosition;
export 'src/terminal_core/terminal_semantic_prompt.dart'
    show
        TerminalSemanticPromptAction,
        TerminalSemanticPromptModel,
        TerminalSemanticShellState;
export 'src/terminal_core/terminal_session_metadata.dart'
    show TerminalSessionMetadata;
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
export 'src/terminal_core/vt_parser_inspector.dart'
    show
        VtParserInspectionEvent,
        VtParserInspectionKind,
        VtParserInspectionObserver,
        VtParserInspector,
        VtParserInspectorLimits;
export 'src/terminal_core/vt_parser_table.dart' show VtParserState;
export 'src/terminal_core/vt_parser_trace.dart'
    show
        VtParserTraceExporter,
        VtParserTraceExportLimits,
        VtParserTraceLimitException,
        VtParserTraceLimitKind;
export 'src/terminal_effective_config.dart';
export 'src/terminal_input/terminal_appkit_key_adapter.dart'
    show TerminalAppKitKeyAdapter;
export 'src/terminal_input/terminal_focus_reporter.dart';
export 'src/terminal_input/terminal_hyperlink_interaction.dart';
export 'src/terminal_input/terminal_input_matrix.dart';
export 'src/terminal_input/terminal_key_binding.dart';
export 'src/terminal_input/terminal_key_encoder.dart'
    show
        TerminalKeyEncoder,
        TerminalKeyEncodingLimitException,
        TerminalOptionKeyBehavior;
export 'src/terminal_input/terminal_key_event.dart'
    show
        TerminalInputLimits,
        TerminalKeyEvent,
        TerminalKeyModifiers,
        TerminalPhysicalKey;
export 'src/terminal_input/terminal_mouse_encoder.dart';
export 'src/terminal_input/terminal_mouse_event.dart';
export 'src/terminal_input/terminal_mouse_router.dart';
export 'src/terminal_input/terminal_paste.dart';
export 'src/terminal_input/terminal_preedit.dart';
export 'src/terminal_input/terminal_scroll_router.dart';
export 'src/terminal_input/terminal_selection_autoscroll.dart';
export 'src/terminal_input/terminal_selection_gesture.dart';
export 'src/terminal_input/terminal_text_input_event_router.dart';
export 'src/terminal_native_hierarchy.dart';
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
        TerminalPaneProcessDisposition,
        TerminalPaneProcessSnapshot,
        TerminalPaneSession,
        TerminalPaneSessionExitDisposition,
        TerminalPaneSessionFactory,
        TerminalPaneSessionShutdownResult,
        TerminalPaneState,
        TerminalSessionShutdownDisposition,
        TerminalSessionId;
export 'src/terminal_pane_close_coordinator.dart';
export 'src/terminal_product_configuration.dart';
export 'src/terminal_product_hierarchy_actions.dart';
export 'src/terminal_prompt_navigation.dart';
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
export 'src/terminal_renderer/pane_work_scheduler.dart';
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
export 'src/terminal_renderer/renderer_metrics.dart';
export 'src/terminal_renderer/terminal_damage.dart';
export 'src/terminal_renderer/terminal_damage_transfer.dart';
export 'src/terminal_renderer/terminal_live_metal_surface.dart';
export 'src/terminal_renderer/terminal_render_model.dart';
export 'src/terminal_renderer/terminal_screen_metal_compositor.dart';
export 'src/terminal_renderer/terminal_viewport_render_model.dart';
export 'src/terminal_restoration.dart';
export 'src/terminal_restoration_lifecycle.dart';
export 'src/terminal_session.dart'
    show
        TerminalSessionNativeObservation,
        TerminalSessionNativeObserver,
        TerminalSessionShutdownResult;
export 'src/terminal_shell_integration.dart';
export 'src/terminal_tab_metadata.dart';
export 'src/terminal_tab_presentation.dart';
