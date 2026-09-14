import 'terminal_application_state.dart';
import 'terminal_context_dock.dart';
import 'terminal_directory_snapshot.dart';
import 'terminal_native_content.dart';
import 'terminal_pane.dart';
import 'terminal_secure_keyboard_entry.dart';

/// Distinguishes ordinary shell line editing from protected process input.
///
/// Interactive zsh and sh may disable terminal echo while they own an idle
/// prompt. Treating ECHO-off alone as protected would disable the Navigator at
/// exactly the point where a path is useful. Explicit manual secure input is
/// always private; automatic ECHO-off becomes private once a command or a
/// different foreground process owns the terminal.
abstract final class TerminalContextDockPrivacyPolicy {
  static bool canObserve({
    required PaneId paneId,
    required TerminalPaneProcessSnapshot process,
    TerminalSecureKeyboardEntryStatus? secureInput,
  }) {
    if (process.disposition == TerminalPaneProcessDisposition.nonLive ||
        process.disposition == TerminalPaneProcessDisposition.unavailable) {
      return false;
    }
    final bool targetedSecureInput = secureInput?.targetIdentity == paneId;
    if (targetedSecureInput &&
        (secureInput!.manualRequested ||
            secureInput.mode == TerminalSecureKeyboardEntryMode.manual)) {
      return false;
    }
    return process.terminalEchoEnabled != false ||
        process.disposition == TerminalPaneProcessDisposition.idleShell;
  }
}

enum TerminalContextDockPathInsertionBlock {
  none,
  navigatorInactive,
  noSelection,
  staleTarget,
  remote,
  secureInput,
  alternateScreen,
  foregroundProcess,
  busy,
  disposed,
}

final class TerminalContextDockPathSelection {
  const TerminalContextDockPathSelection({
    required this.windowId,
    required this.paneId,
    required this.generation,
    required this.entry,
  });

  final TerminalWindowId windowId;
  final PaneId paneId;
  final int generation;
  final TerminalDirectoryEntrySnapshot entry;
}

final class TerminalContextDockPathTarget {
  const TerminalContextDockPathTarget({
    required this.paneId,
    required this.identity,
    required this.isLocal,
    required this.secureInputActive,
    required this.usingAlternateScreen,
    required this.processDisposition,
  });

  final PaneId paneId;
  final Object identity;
  final bool isLocal;
  final bool secureInputActive;
  final bool usingAlternateScreen;
  final TerminalPaneProcessDisposition processDisposition;

  TerminalContextDockPathInsertionBlock get insertionBlock {
    if (!isLocal) return TerminalContextDockPathInsertionBlock.remote;
    if (secureInputActive) {
      return TerminalContextDockPathInsertionBlock.secureInput;
    }
    if (usingAlternateScreen) {
      return TerminalContextDockPathInsertionBlock.alternateScreen;
    }
    if (processDisposition != TerminalPaneProcessDisposition.idleShell) {
      return TerminalContextDockPathInsertionBlock.foregroundProcess;
    }
    return TerminalContextDockPathInsertionBlock.none;
  }
}

final class TerminalContextDockPathHandoffSnapshot {
  const TerminalContextDockPathHandoffSnapshot({
    required this.block,
    required this.canCopy,
    required this.canInsert,
    this.path,
  });

  final TerminalContextDockPathInsertionBlock block;
  final bool canCopy;
  final bool canInsert;
  final String? path;
}

enum TerminalContextDockPathHandoffDisposition {
  copied,
  inserted,
  unavailable,
  confirmationRequired,
  busy,
  transferIncomplete,
  focusFailed,
  disposed,
}

final class TerminalContextDockPathHandoffResult {
  const TerminalContextDockPathHandoffResult(
    this.disposition, {
    this.block = TerminalContextDockPathInsertionBlock.none,
    this.pasteResult,
  });

  final TerminalContextDockPathHandoffDisposition disposition;
  final TerminalContextDockPathInsertionBlock block;
  final TerminalExternalPasteResult? pasteResult;
}

typedef TerminalContextDockPathSelectionResolver =
    TerminalContextDockPathSelection? Function(TerminalWindowId windowId);
typedef TerminalContextDockPathTargetResolver =
    TerminalContextDockPathTarget? Function(
      TerminalWindowId windowId,
      PaneId paneId,
    );
typedef TerminalContextDockClipboardWriter = int Function(String text);
typedef TerminalContextDockTerminalFocus = Future<bool> Function(
  TerminalWindowId windowId,
  PaneId paneId,
);

/// Applies explicit Navigator path actions without creating another PTY path.
///
/// Copy writes only the selected absolute path. Insertion reuses the bounded
/// external-content admission, confirmation, and paste transport, and is
/// available only for one still-live idle local shell.
final class TerminalContextDockPathHandoffController {
  TerminalContextDockPathHandoffController({
    required this.dockState,
    required TerminalContextDockPathSelectionResolver resolveSelection,
    required TerminalContextDockPathTargetResolver resolveTarget,
    required TerminalContextDockClipboardWriter writeClipboard,
    required TerminalExternalPasteController<PaneId> pasteController,
    required TerminalContextDockTerminalFocus focusTerminal,
    void Function()? onClipboardWritten,
  }) : _resolveSelection = resolveSelection,
       _resolveTarget = resolveTarget,
       _writeClipboard = writeClipboard,
       _pasteController = pasteController,
       _focusTerminal = focusTerminal,
       _onClipboardWritten = onClipboardWritten;

  final TerminalContextDockState dockState;
  final TerminalContextDockPathSelectionResolver _resolveSelection;
  final TerminalContextDockPathTargetResolver _resolveTarget;
  final TerminalContextDockClipboardWriter _writeClipboard;
  final TerminalExternalPasteController<PaneId> _pasteController;
  final TerminalContextDockTerminalFocus _focusTerminal;
  final void Function()? _onClipboardWritten;

  static const int maximumPathUtf8Bytes = 1024 * 1024;

  bool _operationInProgress = false;
  bool _disposed = false;

  bool get isDisposed => _disposed;
  bool get operationInProgress => _operationInProgress;

  TerminalContextDockPathHandoffSnapshot snapshotForWindow(
    TerminalWindowId windowId,
  ) {
    if (isDisposed || dockState.isDisposed) {
      return const TerminalContextDockPathHandoffSnapshot(
        block: TerminalContextDockPathInsertionBlock.disposed,
        canCopy: false,
        canInsert: false,
      );
    }
    final TerminalContextDockWindowSnapshot? dock = dockState.snapshotForWindow(
      windowId,
    );
    if (dock == null || !dock.navigatorOwnsInput) {
      return const TerminalContextDockPathHandoffSnapshot(
        block: TerminalContextDockPathInsertionBlock.navigatorInactive,
        canCopy: false,
        canInsert: false,
      );
    }
    final TerminalContextDockPathSelection? selection = _safeSelection(
      windowId,
      dock,
    );
    if (selection == null) {
      return const TerminalContextDockPathHandoffSnapshot(
        block: TerminalContextDockPathInsertionBlock.noSelection,
        canCopy: false,
        canInsert: false,
      );
    }
    final TerminalContextDockPathTarget? target = _safeTarget(
      windowId,
      dock.targetPaneId,
    );
    if (target == null || target.paneId != dock.targetPaneId) {
      return TerminalContextDockPathHandoffSnapshot(
        block: TerminalContextDockPathInsertionBlock.staleTarget,
        canCopy: false,
        canInsert: false,
        path: selection.entry.path,
      );
    }
    if (!target.isLocal) {
      return TerminalContextDockPathHandoffSnapshot(
        block: TerminalContextDockPathInsertionBlock.remote,
        canCopy: false,
        canInsert: false,
        path: selection.entry.path,
      );
    }
    final TerminalContextDockPathInsertionBlock block = operationInProgress
        ? TerminalContextDockPathInsertionBlock.busy
        : target.insertionBlock;
    return TerminalContextDockPathHandoffSnapshot(
      block: block,
      canCopy: block != TerminalContextDockPathInsertionBlock.secureInput,
      canInsert: block == TerminalContextDockPathInsertionBlock.none,
      path: selection.entry.path,
    );
  }

  TerminalContextDockPathHandoffResult copyPath(TerminalWindowId windowId) {
    final TerminalContextDockPathHandoffSnapshot snapshot = snapshotForWindow(
      windowId,
    );
    final String? path = snapshot.path;
    if (!snapshot.canCopy || path == null) {
      return TerminalContextDockPathHandoffResult(
        isDisposed
            ? TerminalContextDockPathHandoffDisposition.disposed
            : TerminalContextDockPathHandoffDisposition.unavailable,
        block: snapshot.block,
      );
    }
    try {
      _writeClipboard(path);
      _onClipboardWritten?.call();
      return const TerminalContextDockPathHandoffResult(
        TerminalContextDockPathHandoffDisposition.copied,
      );
    } on Object {
      return const TerminalContextDockPathHandoffResult(
        TerminalContextDockPathHandoffDisposition.unavailable,
      );
    }
  }

  Future<TerminalContextDockPathHandoffResult> insertPath(
    TerminalWindowId windowId,
  ) async {
    final TerminalContextDockPathHandoffSnapshot snapshot = snapshotForWindow(
      windowId,
    );
    final String? path = snapshot.path;
    if (!snapshot.canInsert || path == null) {
      return TerminalContextDockPathHandoffResult(
        isDisposed
            ? TerminalContextDockPathHandoffDisposition.disposed
            : snapshot.block == TerminalContextDockPathInsertionBlock.busy
            ? TerminalContextDockPathHandoffDisposition.busy
            : TerminalContextDockPathHandoffDisposition.unavailable,
        block: snapshot.block,
      );
    }
    _operationInProgress = true;
    try {
      final TerminalExternalContentResult admitted =
          TerminalExternalContentAdmission.filePaths(
            <String>[path],
            maxFilePaths: 1,
            maxFilePathUtf8Bytes: maximumPathUtf8Bytes,
            appendTrailingSeparator: false,
          );
      final TerminalExternalContent? content = admitted.content;
      if (content == null) {
        return const TerminalContextDockPathHandoffResult(
          TerminalContextDockPathHandoffDisposition.unavailable,
        );
      }
      final TerminalContextDockWindowSnapshot? dock = dockState
          .snapshotForWindow(windowId);
      if (dock == null || !dock.navigatorOwnsInput) {
        return const TerminalContextDockPathHandoffResult(
          TerminalContextDockPathHandoffDisposition.unavailable,
          block: TerminalContextDockPathInsertionBlock.staleTarget,
        );
      }
      final TerminalExternalPasteResult paste = await _pasteController.submit(
        dock.targetPaneId,
        content,
      );
      switch (paste.disposition) {
        case TerminalExternalPasteDisposition.completed:
          if (!await _focusTerminal(windowId, dock.targetPaneId)) {
            return TerminalContextDockPathHandoffResult(
              TerminalContextDockPathHandoffDisposition.focusFailed,
              pasteResult: paste,
            );
          }
          return TerminalContextDockPathHandoffResult(
            TerminalContextDockPathHandoffDisposition.inserted,
            pasteResult: paste,
          );
        case TerminalExternalPasteDisposition.confirmationRequired:
          return TerminalContextDockPathHandoffResult(
            TerminalContextDockPathHandoffDisposition.confirmationRequired,
            pasteResult: paste,
          );
        case TerminalExternalPasteDisposition.busy:
          return TerminalContextDockPathHandoffResult(
            TerminalContextDockPathHandoffDisposition.busy,
            block: TerminalContextDockPathInsertionBlock.busy,
            pasteResult: paste,
          );
        case TerminalExternalPasteDisposition.disposed:
          return TerminalContextDockPathHandoffResult(
            TerminalContextDockPathHandoffDisposition.disposed,
            pasteResult: paste,
          );
        case TerminalExternalPasteDisposition.staleTarget ||
            TerminalExternalPasteDisposition.tooLarge:
          return TerminalContextDockPathHandoffResult(
            TerminalContextDockPathHandoffDisposition.unavailable,
            block: TerminalContextDockPathInsertionBlock.staleTarget,
            pasteResult: paste,
          );
        case TerminalExternalPasteDisposition.transferIncomplete:
          return TerminalContextDockPathHandoffResult(
            TerminalContextDockPathHandoffDisposition.transferIncomplete,
            pasteResult: paste,
          );
      }
    } finally {
      _operationInProgress = false;
    }
  }

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _pasteController.dispose();
  }

  TerminalContextDockPathSelection? _safeSelection(
    TerminalWindowId windowId,
    TerminalContextDockWindowSnapshot dock,
  ) {
    try {
      final TerminalContextDockPathSelection? selection = _resolveSelection(
        windowId,
      );
      if (selection == null ||
          selection.windowId != windowId ||
          selection.paneId != dock.targetPaneId ||
          TerminalLocalPathPolicy.normalizeAbsolute(selection.entry.path) !=
              selection.entry.path) {
        return null;
      }
      return selection;
    } on Object {
      return null;
    }
  }

  TerminalContextDockPathTarget? _safeTarget(
    TerminalWindowId windowId,
    PaneId paneId,
  ) {
    try {
      return _resolveTarget(windowId, paneId);
    } on Object {
      return null;
    }
  }
}
