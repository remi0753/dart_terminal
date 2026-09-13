import 'dart:async';

import 'package:dart_appkit/dart_appkit.dart';
import 'package:dart_terminal/dart_terminal.dart';
import 'package:dart_terminal_app_intents_macos/dart_terminal_app_intents_macos.dart';
import 'package:dart_terminal_app_intents_macos/testing.dart';

Future<void> main() => runTerminalSystemAutomationProductTests();

Future<void> runTerminalSystemAutomationProductTests() async {
  _testAutomationPollingBudget();
  await _testAppIntentsUseSharedActionsExactlyOnce();
  await _testAppIntentsRejectAndDisposeDeterministically();
  await _testNotificationLifecycleAndOpaqueFocus();
  await _testNotificationFailureDisableAndStaleResponse();
  _testNotificationCapacityBound();
}

void _testAutomationPollingBudget() {
  _expect(
    TerminalAppIntentsProductController.productPollInterval ==
            const Duration(milliseconds: 250) &&
        TerminalAppleScriptProductSession.defaultPollInterval ==
            const Duration(milliseconds: 250),
    'product automation polling keeps its fixed idle-work budget',
  );
}

Future<void> _testAppIntentsUseSharedActionsExactlyOnce() async {
  final _FakeAppIntentsBindings bindings = _FakeAppIntentsBindings();
  final TerminalAppIntentsMacosSession session =
      TerminalAppIntentsMacosSession.withBindings(bindings);
  final List<TerminalActionId> invoked = <TerminalActionId>[];
  var statusChangeCount = 0;
  final TerminalActionCatalog catalog = TerminalActionCatalog.standard();
  final TerminalActionDispatcher dispatcher = TerminalActionDispatcher(
    catalog: catalog,
    registrations: <TerminalActionRegistration>[
      for (final TerminalActionId id in const <TerminalActionId>[
        TerminalActionId.newWindow,
        TerminalActionId.newTab,
        TerminalActionId.toggleQuickTerminal,
      ])
        TerminalActionRegistration(id: id, handler: () => invoked.add(id)),
    ],
  );
  final TerminalAppIntentsProductController controller =
      TerminalAppIntentsProductController(
        session: session,
        dispatch: dispatcher.dispatch,
        onStatusChanged: () => statusChangeCount++,
      );
  controller.applyEnabled(true);
  final int enabledStatusChangeCount = statusChangeCount;
  await controller.poll();
  _expect(
    statusChangeCount == enabledStatusChangeCount,
    'an empty App Intents poll did not publish transient UI status work',
  );
  final TerminalAppIntentsMacosSelfAutomation automation =
      TerminalAppIntentsMacosSelfAutomation.withBindings(bindings);
  for (final TerminalAppIntentAction action in TerminalAppIntentAction.values) {
    automation.enqueue(action);
  }
  await controller.poll();
  _expect(
    invoked.join(',') ==
            '${TerminalActionId.newWindow},${TerminalActionId.newTab},'
                '${TerminalActionId.toggleQuickTerminal}' &&
        bindings.completions.join(',') == '0,0,0' &&
        controller.status.completedCommandCount == 3 &&
        controller.status.rejectedCommandCount == 0 &&
        controller.status.failedCommandCount == 0 &&
        controller.status.settingsLine.contains('availability=ready'),
    'App Intent enums did not use the three shared actions exactly once',
  );
  await controller.dispose();
  _expect(
    bindings.shutdownCount == 1 &&
        controller.isDisposed &&
        controller.status.settingsLine.contains('availability=stopped'),
    'App Intents controller did not release the native queue exactly once',
  );
}

Future<void> _testAppIntentsRejectAndDisposeDeterministically() async {
  final _FakeAppIntentsBindings bindings = _FakeAppIntentsBindings();
  final TerminalAppIntentsMacosSession session =
      TerminalAppIntentsMacosSession.withBindings(bindings);
  var dispatchCount = 0;
  final TerminalAppIntentsProductController controller =
      TerminalAppIntentsProductController(
        session: session,
        dispatch: (TerminalActionId id) async {
          dispatchCount++;
          return TerminalActionDispatchResult(
            id: id,
            disposition: dispatchCount == 1
                ? TerminalActionDispatchDisposition.unavailable
                : dispatchCount == 2
                ? TerminalActionDispatchDisposition.busy
                : TerminalActionDispatchDisposition.failed,
            error: dispatchCount < 3 ? null : StateError('bounded failure'),
            stackTrace: dispatchCount < 3 ? null : StackTrace.current,
          );
        },
      );
  controller.applyEnabled(true);
  TerminalAppIntentsMacosSelfAutomation.withBindings(bindings)
    ..enqueue(TerminalAppIntentAction.newWindow)
    ..enqueue(TerminalAppIntentAction.newTab)
    ..enqueue(TerminalAppIntentAction.toggleQuickTerminal);
  await controller.poll();
  _expect(
    bindings.completions.join(',') == '1,1,2' &&
        controller.status.rejectedCommandCount == 2 &&
        controller.status.failedCommandCount == 1 &&
        controller.status.lastFailure ==
            TerminalAppIntentsProductFailure.actionFailed &&
        !controller.status.settingsLine.contains('bounded failure'),
    'unavailable and failed shared actions did not remain bounded/content-free',
  );
  controller.applyEnabled(false);
  _expect(
    !controller.status.enabled && bindings.queuedActions.isEmpty,
    'live disable did not close App Intent admission',
  );
  await controller.dispose();
}

Future<void> _testNotificationLifecycleAndOpaqueFocus() async {
  final _FakeNotificationPlatform platform = _FakeNotificationPlatform();
  final List<TerminalSessionId> focused = <TerminalSessionId>[];
  final TerminalNotificationProductController controller =
      TerminalNotificationProductController(
        platform: platform,
        focusSession: (TerminalSessionId id) {
          focused.add(id);
          return true;
        },
      );
  controller.applyEnabled(true);
  _expect(
    platform.settingsTokens.length == 1 &&
        controller.status.pendingRequestCount == 1,
    'notification enable did not begin an asynchronous settings refresh',
  );
  await controller.handleEvent(
    _event(
      kind: AppKitUserNotificationEventKind.settings,
      token: platform.settingsTokens.single,
      authorization: AppKitUserNotificationAuthorizationStatus.authorized,
    ),
  );
  const TerminalSessionId sessionId = TerminalSessionId(
    paneId: PaneId(7),
    generation: 3,
  );
  _expect(
    controller.postNotification(
      sessionId: sessionId,
      identifier: 'dt.p7.s3.n1',
      title: 'private-title',
      body: 'private-body',
    ),
    'tracked notification was not admitted',
  );
  final _PostedNotification posted = platform.posts.single;
  await controller.handleEvent(
    _event(
      kind: AppKitUserNotificationEventKind.delivery,
      token: posted.deliveryToken,
      authorization: AppKitUserNotificationAuthorizationStatus.authorized,
    ),
  );
  await controller.handleEvent(
    _event(
      kind: AppKitUserNotificationEventKind.defaultResponse,
      token: posted.responseToken,
    ),
  );
  _expect(
    focused.length == 1 &&
        focused.single == sessionId &&
        controller.status.liveResponseCount == 0 &&
        controller.status.authorizationStatus ==
            AppKitUserNotificationAuthorizationStatus.authorized &&
        !controller.status.settingsLine.contains('private-title') &&
        !controller.status.settingsLine.contains('private-body') &&
        !controller.status.settingsLine.contains('dt.p7'),
    'notification response did not focus only its opaque live-session record',
  );
  controller.dispose();
}

Future<void> _testNotificationFailureDisableAndStaleResponse() async {
  final _FakeNotificationPlatform platform = _FakeNotificationPlatform();
  var focusResult = false;
  final List<String> deliveryFailures = <String>[];
  final TerminalNotificationProductController controller =
      TerminalNotificationProductController(
        platform: platform,
        focusSession: (_) => focusResult,
        onDeliveryFailure: deliveryFailures.add,
      );
  controller.applyEnabled(true);
  controller.requestAuthorization();
  await controller.handleEvent(
    _event(
      kind: AppKitUserNotificationEventKind.authorization,
      token: platform.authorizationTokens.single,
      authorization: AppKitUserNotificationAuthorizationStatus.denied,
      failure: AppKitUserNotificationFailure.denied,
    ),
  );
  const TerminalSessionId sessionId = TerminalSessionId(
    paneId: PaneId(8),
    generation: 4,
  );
  controller.postNotification(
    sessionId: sessionId,
    identifier: 'dt.p8.s4.n1',
    title: 'failure',
    body: '',
  );
  final _PostedNotification failed = platform.posts.last;
  await controller.handleEvent(
    _event(
      kind: AppKitUserNotificationEventKind.delivery,
      token: failed.deliveryToken,
      authorization: AppKitUserNotificationAuthorizationStatus.denied,
      failure: AppKitUserNotificationFailure.denied,
    ),
  );
  _expect(
    controller.status.lastFailure ==
            TerminalNotificationProductFailure.denied &&
        controller.status.liveResponseCount == 0 &&
        deliveryFailures.single == 'dt.p8.s4.n1',
    'denied delivery retained response ownership',
  );

  controller.postNotification(
    sessionId: sessionId,
    identifier: 'dt.p8.s4.n2',
    title: 'stale',
    body: '',
  );
  final _PostedNotification stale = platform.posts.last;
  await controller.handleEvent(
    _event(
      kind: AppKitUserNotificationEventKind.defaultResponse,
      token: stale.responseToken,
    ),
  );
  _expect(
    controller.status.lastFailure ==
        TerminalNotificationProductFailure.staleResponse,
    'stale live-session re-resolution was not rejected',
  );
  focusResult = true;
  controller.postNotification(
    sessionId: sessionId,
    identifier: 'dt.p8.s4.n3',
    title: 'disabled',
    body: '',
  );
  controller.applyEnabled(false);
  _expect(
    platform.removed.contains('dt.p8.s4.n3') &&
        controller.status.liveResponseCount == 0 &&
        !controller.postNotification(
          sessionId: sessionId,
          identifier: 'dt.p8.s4.n4',
          title: 'rejected',
          body: '',
        ),
    'notification live disable did not cancel and reject projection',
  );
  await controller.handleEvent(
    _event(
      kind: AppKitUserNotificationEventKind.defaultResponse,
      token: platform.posts.last.responseToken,
    ),
  );
  controller.dispose();
  _expect(
    controller.isDisposed && controller.status.settingsLine.endsWith('stopped'),
    'notification disposal status is incomplete',
  );
}

void _testNotificationCapacityBound() {
  final _FakeNotificationPlatform platform = _FakeNotificationPlatform();
  final TerminalNotificationProductController controller =
      TerminalNotificationProductController(
        platform: platform,
        focusSession: (_) => true,
      )..applyEnabled(true);
  const TerminalSessionId sessionId = TerminalSessionId(
    paneId: PaneId(9),
    generation: 1,
  );
  for (
    var index = 0;
    index < TerminalNotificationProductController.maximumTrackedNotifications;
    index++
  ) {
    _expect(
      controller.postNotification(
        sessionId: sessionId,
        identifier: 'dt.p9.s1.n${index + 1}',
        title: 'bounded',
        body: '',
      ),
      'notification capacity rejected an in-bound record',
    );
  }
  _expect(
    !controller.postNotification(
          sessionId: sessionId,
          identifier: 'dt.p9.s1.overflow',
          title: 'overflow',
          body: '',
        ) &&
        controller.status.liveResponseCount ==
            TerminalNotificationProductController.maximumTrackedNotifications &&
        controller.status.lastFailure ==
            TerminalNotificationProductFailure.capacity,
    'notification response ownership exceeded its hard capacity',
  );
  controller.dispose();
  _expect(
    platform.removed.length ==
            TerminalNotificationProductController.maximumTrackedNotifications &&
        controller.status.liveResponseCount == 0,
    'bounded notification disposal did not release every response owner',
  );
}

ApplicationUserNotificationChangedEvent _event({
  required AppKitUserNotificationEventKind kind,
  required int token,
  AppKitUserNotificationAuthorizationStatus authorization =
      AppKitUserNotificationAuthorizationStatus.unknown,
  AppKitUserNotificationFailure failure = AppKitUserNotificationFailure.none,
}) => ApplicationUserNotificationChangedEvent(
  monotonicMicros: token,
  kind: kind,
  token: token,
  authorizationStatus: authorization,
  failure: failure,
);

final class _FakeAppIntentsBindings implements TerminalAppIntentsMacosBindings {
  final List<int> queuedActions = <int>[];
  final List<int> completions = <int>[];
  var _nextOperation = 1;
  var _generation = 0;
  var _started = false;
  var _enabled = false;
  var shutdownCount = 0;

  @override
  int sessionStart(int maximumPendingCommands, int timeoutMicros) {
    _started = true;
    _generation++;
    return nativeStatusOk;
  }

  @override
  int setEnabled(bool enabled) {
    _enabled = enabled;
    return nativeStatusOk;
  }

  @override
  int debugEnqueueAction(int action) {
    if (!_started || !_enabled) return 9;
    queuedActions.add(action);
    return nativeStatusOk;
  }

  @override
  TerminalAppIntentsMacosTakeResult takeCommand() {
    if (queuedActions.isEmpty) {
      return const TerminalAppIntentsMacosTakeResult(nativeStatusNotFound);
    }
    return TerminalAppIntentsMacosTakeResult(
      nativeStatusOk,
      operationId: _nextOperation++,
      generation: _generation,
      action: queuedActions.removeAt(0),
    );
  }

  @override
  int completeCommand(int operationId, int generation, int disposition) {
    completions.add(disposition);
    return nativeStatusOk;
  }

  @override
  int sessionShutdown() {
    _started = false;
    _enabled = false;
    queuedActions.clear();
    shutdownCount++;
    return nativeStatusOk;
  }

  @override
  TerminalAppIntentsMacosSummary summary() => TerminalAppIntentsMacosSummary(
    generation: _generation,
    queuedCommandCount: queuedActions.length,
    pendingCommandCount: queuedActions.length,
    acceptedCommandCount: _nextOperation - 1 + queuedActions.length,
    resolvedCommandCount: completions.length,
    rejectedCommandCount: 0,
    timedOutCommandCount: 0,
    started: _started,
    enabled: _enabled,
  );
}

final class _PostedNotification {
  const _PostedNotification({
    required this.notification,
    required this.deliveryToken,
    required this.responseToken,
  });

  final AppKitUserNotification notification;
  final int deliveryToken;
  final int responseToken;
}

final class _FakeNotificationPlatform
    implements TerminalUserNotificationPlatformPort {
  final List<int> settingsTokens = <int>[];
  final List<int> authorizationTokens = <int>[];
  final List<_PostedNotification> posts = <_PostedNotification>[];
  final List<String> removed = <String>[];
  final List<String?> badgeLabels = <String?>[];
  var _nextToken = 1;

  @override
  AppKitUserNotificationAuthorizationStatus? get cachedAuthorizationStatus =>
      null;

  @override
  int refreshSettings() {
    final int token = _nextToken++;
    settingsTokens.add(token);
    return token;
  }

  @override
  int requestAuthorization() {
    final int token = _nextToken++;
    authorizationTokens.add(token);
    return token;
  }

  @override
  int postTrackedNotification(
    AppKitUserNotification notification, {
    required int responseToken,
  }) {
    final int deliveryToken = _nextToken++;
    posts.add(
      _PostedNotification(
        notification: notification,
        deliveryToken: deliveryToken,
        responseToken: responseToken,
      ),
    );
    return deliveryToken;
  }

  @override
  void removeNotification(String identifier) => removed.add(identifier);

  @override
  void setDockBadgeLabel(String? label) => badgeLabels.add(label);
}

void _expect(bool condition, String message) {
  if (!condition) throw StateError(message);
}
