import 'dart:async';

import 'package:dart_appkit/dart_appkit.dart';

import 'terminal_action_registry.dart';

typedef TerminalMenuEnabledReader = bool Function();
typedef TerminalMenuEnabledWriter = void Function(bool value);
typedef TerminalMenuDispatchObserver = void Function(
  TerminalActionDispatchResult result,
);

/// Native-neutral binding used to synchronize one projected menu item.
final class TerminalMenuEnablementBinding {
  const TerminalMenuEnablementBinding({
    required this.id,
    required this.read,
    required this.write,
  });

  final TerminalActionId id;
  final TerminalMenuEnabledReader read;
  final TerminalMenuEnabledWriter write;
}

/// Synchronizes menu validation and routes every invocation through one
/// application action dispatcher.
final class TerminalMenuProjectionController {
  factory TerminalMenuProjectionController({
    required TerminalActionDispatcher dispatcher,
    required Iterable<TerminalMenuEnablementBinding> bindings,
    TerminalMenuDispatchObserver? onDispatched,
  }) {
    final Map<TerminalActionId, TerminalMenuEnablementBinding> byId =
        <TerminalActionId, TerminalMenuEnablementBinding>{};
    for (final TerminalMenuEnablementBinding binding in bindings) {
      if (dispatcher.catalog.actionForId(binding.id) == null) {
        throw ArgumentError.value(
          binding.id,
          'bindings',
          'is not present in the action catalog',
        );
      }
      if (byId.containsKey(binding.id)) {
        throw StateError('duplicate menu binding ${binding.id.stableName}');
      }
      byId[binding.id] = binding;
    }
    final Set<TerminalActionId> missing = dispatcher.catalog.actions
        .map((TerminalActionDefinition action) => action.id)
        .where((TerminalActionId id) => !byId.containsKey(id))
        .toSet();
    if (missing.isNotEmpty) {
      throw StateError(
        'menu projection is missing actions: '
        '${missing.map((TerminalActionId id) => id.stableName).join(', ')}',
      );
    }
    return TerminalMenuProjectionController._(
      dispatcher,
      Map<TerminalActionId, TerminalMenuEnablementBinding>.unmodifiable(byId),
      onDispatched,
    );
  }

  TerminalMenuProjectionController._(
    this.dispatcher,
    this._bindings,
    this.onDispatched,
  );

  final TerminalActionDispatcher dispatcher;
  final Map<TerminalActionId, TerminalMenuEnablementBinding> _bindings;
  final TerminalMenuDispatchObserver? onDispatched;
  bool _isDisposed = false;

  bool get isDisposed => _isDisposed;

  void refresh() {
    _ensureAlive();
    for (final MapEntry<TerminalActionId, TerminalMenuEnablementBinding> entry
        in _bindings.entries) {
      final bool enabled = dispatcher.snapshot(entry.key).isEnabled;
      if (entry.value.read() != enabled) {
        entry.value.write(enabled);
      }
    }
  }

  Future<TerminalActionDispatchResult> route(TerminalActionId id) async {
    _ensureAlive();
    if (!_bindings.containsKey(id)) {
      throw StateError('action ${id.stableName} is not projected');
    }
    final TerminalActionDispatchResult result = await dispatcher.dispatch(id);
    if (!_isDisposed) {
      refresh();
      onDispatched?.call(result);
    }
    return result;
  }

  void dispose() {
    if (_isDisposed) {
      return;
    }
    _isDisposed = true;
  }

  void _ensureAlive() {
    if (_isDisposed) {
      throw StateError('menu projection controller is disposed');
    }
  }
}

typedef TerminalNativeMenuInvocationObserver = void Function(
  TerminalActionId id,
  MenuItemInvokedEvent event,
);

/// Owns the standard native menu graph projected from one action catalog.
final class TerminalAppKitMenuProjection {
  factory TerminalAppKitMenuProjection.install({
    required AppKitApplication application,
    required TerminalActionDispatcher dispatcher,
    TerminalNativeMenuInvocationObserver? onNativeInvocation,
    TerminalMenuDispatchObserver? onDispatched,
  }) {
    final List<Menu> menus = <Menu>[];
    final List<MenuItem> items = <MenuItem>[];
    final List<StreamSubscription<MenuItemInvokedEvent>> subscriptions =
        <StreamSubscription<MenuItemInvokedEvent>>[];
    final Map<TerminalActionId, MenuItem> actionItems =
        <TerminalActionId, MenuItem>{};
    TerminalMenuProjectionController? controller;
    var attached = false;
    try {
      Menu ownMenu(Menu menu) {
        menus.add(menu);
        return menu;
      }

      MenuItem ownItem(MenuItem item) {
        items.add(item);
        return item;
      }

      final Menu mainMenu = ownMenu(Menu());
      final Map<TerminalActionMenu, Menu> actionMenus =
          <TerminalActionMenu, Menu>{};
      for (final TerminalActionMenu section in TerminalActionMenu.values) {
        final String title = _menuTitle(section);
        final Menu menu = ownMenu(Menu(title: title));
        actionMenus[section] = menu;
        mainMenu.addItem(ownItem(MenuItem(title: title)..submenu = menu));
      }
      for (final TerminalActionDefinition definition
          in dispatcher.catalog.actions) {
        final Menu targetMenu = actionMenus[definition.menu]!;
        if (definition.separatorBefore) {
          targetMenu.addItem(ownItem(MenuItem.separator()));
        }
        final TerminalActionShortcut? shortcut = definition.shortcut;
        final MenuItem item = ownItem(
          MenuItem(
            title: definition.title,
            keyEquivalent: shortcut?.keyEquivalent ?? '',
            modifiers: _nativeModifiers(shortcut),
          ),
        );
        targetMenu.addItem(item);
        actionItems[definition.id] = item;
      }
      controller = TerminalMenuProjectionController(
        dispatcher: dispatcher,
        bindings: <TerminalMenuEnablementBinding>[
          for (final MapEntry<TerminalActionId, MenuItem> entry
              in actionItems.entries)
            TerminalMenuEnablementBinding(
              id: entry.key,
              read: () => entry.value.isEnabled,
              write: (bool value) => entry.value.isEnabled = value,
            ),
        ],
        onDispatched: onDispatched,
      );
      final TerminalMenuProjectionController installedController = controller;
      for (final MapEntry<TerminalActionId, MenuItem> entry
          in actionItems.entries) {
        subscriptions.add(
          entry.value.onInvoked.listen((MenuItemInvokedEvent event) {
            onNativeInvocation?.call(entry.key, event);
            unawaited(installedController.route(entry.key));
          }),
        );
      }
      controller.refresh();
      application.mainMenu = mainMenu;
      attached = true;
      return TerminalAppKitMenuProjection._(
        application: application,
        mainMenu: mainMenu,
        menus: List<Menu>.unmodifiable(menus),
        items: List<MenuItem>.unmodifiable(items),
        actionItems: Map<TerminalActionId, MenuItem>.unmodifiable(actionItems),
        subscriptions: subscriptions,
        controller: controller,
      );
    } on Object {
      if (attached) {
        application.mainMenu = null;
      }
      for (final StreamSubscription<MenuItemInvokedEvent> subscription
          in subscriptions) {
        unawaited(subscription.cancel());
      }
      controller?.dispose();
      for (final MenuItem item in items.reversed) {
        if (!item.isDisposed) {
          item.dispose();
        }
      }
      for (final Menu menu in menus.reversed) {
        if (!menu.isDisposed) {
          menu.dispose();
        }
      }
      rethrow;
    }
  }

  TerminalAppKitMenuProjection._({
    required this.application,
    required this.mainMenu,
    required this.menus,
    required this.items,
    required Map<TerminalActionId, MenuItem> actionItems,
    required List<StreamSubscription<MenuItemInvokedEvent>> subscriptions,
    required TerminalMenuProjectionController controller,
  }) : _actionItems = actionItems,
       _subscriptions = subscriptions,
       _controller = controller;

  final AppKitApplication application;
  final Menu mainMenu;
  final List<Menu> menus;
  final List<MenuItem> items;
  final Map<TerminalActionId, MenuItem> _actionItems;
  final List<StreamSubscription<MenuItemInvokedEvent>> _subscriptions;
  final TerminalMenuProjectionController _controller;
  bool _isDisposed = false;

  bool get isDisposed => _isDisposed;

  MenuItem itemForAction(TerminalActionId id) {
    if (_isDisposed) {
      throw StateError('native menu projection is disposed');
    }
    final MenuItem? item = _actionItems[id];
    if (item == null) {
      throw StateError('action ${id.stableName} is not projected');
    }
    return item;
  }

  void refresh() {
    if (_isDisposed) {
      throw StateError('native menu projection is disposed');
    }
    _controller.refresh();
  }

  Future<void> dispose() async {
    if (_isDisposed) {
      return;
    }
    _isDisposed = true;
    for (final StreamSubscription<MenuItemInvokedEvent> subscription
        in _subscriptions) {
      await subscription.cancel();
    }
    _subscriptions.clear();
    _controller.dispose();
    if (!application.isTerminated &&
        identical(application.mainMenu, mainMenu)) {
      application.mainMenu = null;
    }
    for (final MenuItem item in items.reversed) {
      if (!item.isDisposed) {
        item.dispose();
      }
    }
    for (final Menu menu in menus.reversed) {
      if (!menu.isDisposed) {
        menu.dispose();
      }
    }
  }
}

String _menuTitle(TerminalActionMenu menu) => switch (menu) {
  TerminalActionMenu.application => 'Dart Terminal',
  TerminalActionMenu.file => 'File',
  TerminalActionMenu.edit => 'Edit',
  TerminalActionMenu.shell => 'Shell',
  TerminalActionMenu.view => 'View',
  TerminalActionMenu.window => 'Window',
};

ModifierKeys _nativeModifiers(TerminalActionShortcut? shortcut) {
  if (shortcut == null) {
    return const ModifierKeys(0);
  }
  var bits = 0;
  if (shortcut.shift) {
    bits |= ModifierKeys.shiftBit;
  }
  if (shortcut.control) {
    bits |= ModifierKeys.controlBit;
  }
  if (shortcut.option) {
    bits |= ModifierKeys.optionBit;
  }
  if (shortcut.command) {
    bits |= ModifierKeys.commandBit;
  }
  return ModifierKeys(bits);
}
