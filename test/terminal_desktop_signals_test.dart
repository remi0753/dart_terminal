import 'dart:convert';
import 'dart:typed_data';

import 'package:dart_terminal/dart_terminal.dart';

void main() => runTerminalDesktopSignalsTests();

void runTerminalDesktopSignalsTests() {
  _testLegacyNotificationAndProgressGrammar();
  _testKittyPlainTextChunking();
  _testNotificationBoundsAndQueuePolicy();
  _testSessionResetAndScreenIsolation();
}

void _testLegacyNotificationAndProgressGrammar() {
  final _Harness harness = _Harness();
  harness.parse(_osc(9, 'Hello world'));
  final TerminalDesktopNotificationRequest request =
      harness.screens.desktopNotifications.nextRequest!;
  _expect(
    request.protocol == TerminalDesktopNotificationProtocol.legacyOsc9 &&
        request.title.isEmpty &&
        request.body == 'Hello world' &&
        request.identifier == null &&
        harness.sink.acceptedDesktopNotificationCount == 1,
    'legacy OSC 9 creates one bounded plain-text body request',
  );

  harness.parse(_osc(9, '4;1;42'));
  _expect(
    harness.screens.progress.value.state == TerminalProgressState.set &&
        harness.screens.progress.value.percent == 42,
    'OSC 9;4 set publishes an exact percentage',
  );
  harness.parse(_osc(9, '4;2'));
  _expect(
    harness.screens.progress.value.state == TerminalProgressState.error &&
        harness.screens.progress.value.percent == null,
    'OSC 9;4 error permits an absent percentage',
  );
  harness.parse(_osc(9, '4;4;999'));
  _expect(
    harness.screens.progress.value.state == TerminalProgressState.paused &&
        harness.screens.progress.value.percent == 100,
    'the pinned overflow case clamps a bounded percentage to 100',
  );
  harness.parse(_osc(9, '4;3'));
  harness.parse(_osc(9, '4;0'));
  _expect(
    harness.screens.progress.value.state == TerminalProgressState.removed &&
        harness.screens.progress.value.percent == null &&
        harness.sink.acceptedProgressUpdateCount == 5,
    'indeterminate and remove follow the pinned state mapping',
  );

  final int queued = harness.screens.desktopNotifications.queuedRequestCount;
  final int generation = harness.screens.progress.generation;
  for (final String malformed in <String>[
    '4;',
    '4;5',
    '4;1;1;2',
    '4;3;10',
    '4;1;-1',
  ]) {
    harness.parse(_osc(9, malformed));
  }
  _expect(
    harness.sink.unsupportedSequenceCount == 5 &&
        harness.screens.desktopNotifications.queuedRequestCount == queued &&
        harness.screens.progress.generation == generation,
    'malformed reserved progress forms cannot fall back to notifications',
  );
}

void _testKittyPlainTextChunking() {
  final _Harness harness = _Harness();
  harness.parse(_osc(99, 'i=build:d=0;Build '));
  harness.parse(_osc(99, 'i=build:p=body:d=0;half complete'));
  _expect(
    harness.screens.desktopNotifications.pendingRequestCount == 1 &&
        harness.screens.desktopNotifications.queuedRequestCount == 0,
    'unfinished title/body chunks remain bounded and undisplayed',
  );
  harness.parse(_osc(99, 'i=build:p=title;finished'));
  final TerminalDesktopNotificationRequest completed =
      harness.screens.desktopNotifications.nextRequest!;
  _expect(
    completed.protocol == TerminalDesktopNotificationProtocol.kittyOsc99 &&
        completed.identifier == 'build' &&
        completed.title == 'Build finished' &&
        completed.body == 'half complete' &&
        harness.screens.desktopNotifications.pendingRequestCount == 0,
    'final chunk concatenates the selected title/body subset exactly',
  );

  harness.parse(_osc(99, 'future=value:p=body;single'));
  _expect(
    harness.screens.desktopNotifications.queuedRequests.last.body == 'single',
    'syntactically valid unknown metadata is ignored for extensibility',
  );
  final List<TerminalDesktopNotificationRequest> snapshot =
      harness.screens.desktopNotifications.queuedRequests;
  _expectThrows<UnsupportedError>(
    () => snapshot.add(completed),
    'queued notification snapshots are immutable',
  );

  final int queued = harness.screens.desktopNotifications.queuedRequestCount;
  for (final String excluded in <String>[
    'e=1;SGVsbG8=',
    'p=icon;bytes',
    'p=buttons;yes',
    'p=close:i=build;',
    'a=report;click',
    'o=unfocused;hidden',
  ]) {
    harness.parse(_osc(99, excluded));
  }
  _expect(
    harness.sink.unsupportedSequenceCount == 6 &&
        harness.screens.desktopNotifications.queuedRequestCount == queued,
    'encoded and native-authority OSC 99 features remain fail-closed',
  );
}

void _testNotificationBoundsAndQueuePolicy() {
  final _Harness aggregate = _Harness();
  final String half = List<String>.filled(1024, 'a').join();
  aggregate.parse(_osc(99, 'i=max:d=0;$half'));
  aggregate.parse(_osc(99, 'i=max;$half'));
  _expect(
    aggregate.screens.desktopNotifications.nextRequest!.title.length == 2048,
    'an exact maximum aggregate title is admitted',
  );
  aggregate.parse(_osc(99, 'i=overflow:d=0;$half'));
  aggregate.parse(_osc(99, 'i=overflow;${half}b'));
  _expect(
    aggregate.sink.unsupportedSequenceCount == 1 &&
        aggregate.screens.desktopNotifications.pendingRequestCount == 0,
    'aggregate overflow removes the partial request and emits nothing',
  );

  final _Harness pending = _Harness();
  for (
    int index = 0;
    index < TerminalDesktopNotificationModel.maximumPendingRequests;
    index++
  ) {
    pending.parse(_osc(99, 'i=p$index:d=0;x'));
  }
  pending.parse(_osc(99, 'i=overflow:d=0;x'));
  _expect(
    pending.screens.desktopNotifications.pendingRequestCount == 8 &&
        pending.sink.unsupportedSequenceCount == 1,
    'pending identifier count has an exact deterministic cap',
  );

  final _Harness queue = _Harness();
  for (int index = 0; index < 9; index++) {
    queue.parse(_osc(9, 'message-$index'));
  }
  _expect(
    queue.screens.desktopNotifications.queuedRequestCount == 8 &&
        queue.screens.desktopNotifications.droppedRequestCount == 1 &&
        queue.screens.desktopNotifications.queuedRequests.last.body ==
            'message-7',
    'a full completion queue drops newest requests without growing',
  );
  for (int index = 0; index < 8; index++) {
    _expect(
      queue.screens.desktopNotifications.takeNextRequest()!.body ==
          'message-$index',
      'queue drain preserves admitted order at $index',
    );
  }
  _expect(
    queue.screens.desktopNotifications.takeNextRequest() == null,
    'empty queue drain is a no-op',
  );

  final _Harness unsafe = _Harness();
  unsafe.parse(
    _osc(99, 'i=${List<String>.filled(65, 'x').join()};identifier overflow'),
  );
  unsafe.parse(_osc(9, 'unsafe\u202evalue'));
  unsafe.parse(_osc(9, List<String>.filled(2049, 'x').join()));
  _expect(
    unsafe.sink.unsupportedSequenceCount == 3 &&
        unsafe.screens.desktopNotifications.queuedRequestCount == 0,
    'identifier, display-safety, and per-payload limits fail closed',
  );
}

void _testSessionResetAndScreenIsolation() {
  final _Harness harness = _Harness();
  harness.parse(_osc(99, 'i=pending:d=0;title'));
  harness.parse(_osc(9, 'queued'));
  harness.parse(_osc(9, '4;1;73'));
  harness.parse('\x1b[?47h');
  _expect(
    harness.screens.usingAlternate &&
        harness.screens.desktopNotifications.pendingRequestCount == 1 &&
        harness.screens.progress.value.percent == 73,
    'desktop signals belong to the PTY session rather than either grid',
  );
  harness.parse('\x1bc');
  _expect(
    !harness.screens.usingAlternate &&
        harness.screens.desktopNotifications.pendingRequestCount == 0 &&
        harness.screens.desktopNotifications.queuedRequestCount == 0 &&
        harness.screens.progress.value.state == TerminalProgressState.removed &&
        harness.screens.progress.value.percent == null,
    'RIS clears pending/completed notification and progress session state',
  );
}

String _osc(int command, String payload) => '\x1b]$command;$payload\x07';

final class _Harness {
  _Harness() : screens = TerminalScreenSet(rows: 4, columns: 12) {
    sink = TerminalScreenParserSink.forScreenSet(screens);
    parser = VtParser(sink: sink);
  }

  final TerminalScreenSet screens;
  late final TerminalScreenParserSink sink;
  late final VtParser parser;

  void parse(String value) =>
      parser.parse(Uint8List.fromList(utf8.encode(value)));
}

void _expect(bool condition, String message) {
  if (!condition) throw StateError(message);
}

void _expectThrows<T extends Object>(void Function() action, String message) {
  try {
    action();
  } on T {
    return;
  }
  throw StateError(message);
}
