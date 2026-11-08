import 'package:flutter/widgets.dart';

class AppLifecycleHooks {
  final VoidCallback? onPause;
  final VoidCallback? onResume;

  const AppLifecycleHooks({this.onPause, this.onResume});
}

class AppLifecycleService with WidgetsBindingObserver {
  AppLifecycleService._();

  static final AppLifecycleService instance = AppLifecycleService._();

  final List<AppLifecycleHooks> _hooks = [];
  bool _attached = false;

  void _ensureObserver() {
    if (_attached) {
      return;
    }
    WidgetsBinding.instance.addObserver(this);
    _attached = true;
  }

  void register(AppLifecycleHooks hooks) {
    _ensureObserver();
    _hooks.add(hooks);
  }

  void unregister(AppLifecycleHooks hooks) {
    _hooks.remove(hooks);
  }

  @visibleForTesting
  void simulate(AppLifecycleState state) {
    didChangeAppLifecycleState(state);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final pause = state == AppLifecycleState.paused || state == AppLifecycleState.hidden;
    for (final hooks in List<AppLifecycleHooks>.of(_hooks)) {
      try {
        if (pause) {
          hooks.onPause?.call();
        } else if (state == AppLifecycleState.resumed) {
          hooks.onResume?.call();
        }
      } catch (_) {}
    }
  }
}
