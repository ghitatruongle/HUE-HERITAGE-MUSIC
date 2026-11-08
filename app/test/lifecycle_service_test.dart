import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hue_heritage_music/services/app_lifecycle_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('registered hooks fire on paused and resumed', () {
    int pauses = 0;
    int resumes = 0;
    final hooks = AppLifecycleHooks(
      onPause: () => pauses++,
      onResume: () => resumes++,
    );
    AppLifecycleService.instance.register(hooks);
    AppLifecycleService.instance.simulate(AppLifecycleState.paused);
    AppLifecycleService.instance.simulate(AppLifecycleState.inactive);
    AppLifecycleService.instance.simulate(AppLifecycleState.hidden);
    AppLifecycleService.instance.simulate(AppLifecycleState.resumed);
    AppLifecycleService.instance.unregister(hooks);
    expect(pauses, 2);
    expect(resumes, 1);
  });

  test('hook exception does not break other hooks', () {
    final fired = <String>[];
    final bad = AppLifecycleHooks(
      onPause: () => throw StateError('boom'),
      onResume: () => fired.add('bad-resume'),
    );
    final good = AppLifecycleHooks(onPause: () => fired.add('good-pause'));
    AppLifecycleService.instance.register(bad);
    AppLifecycleService.instance.register(good);
    AppLifecycleService.instance.simulate(AppLifecycleState.paused);
    AppLifecycleService.instance.unregister(bad);
    AppLifecycleService.instance.unregister(good);
    expect(fired, contains('good-pause'));
    expect(fired, isNot(contains('bad-resume')));
  });

  test('unregistered hooks no longer fire', () {
    int pauses = 0;
    final hooks = AppLifecycleHooks(onPause: () => pauses++);
    AppLifecycleService.instance.register(hooks);
    AppLifecycleService.instance.unregister(hooks);
    AppLifecycleService.instance.simulate(AppLifecycleState.paused);
    expect(pauses, 0);
  });
}
