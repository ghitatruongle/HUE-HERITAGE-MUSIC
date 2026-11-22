import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hue_heritage_music/services/auth_service.dart';
import 'package:hue_heritage_music/services/history_service.dart';
import 'package:hue_heritage_music/services/locale_provider.dart';
import 'package:hue_heritage_music/services/server_config.dart';
import 'package:hue_heritage_music/services/theme_provider.dart';

Future<int> _timed(Future<void> Function() body) async {
  final sw = Stopwatch()..start();
  await body();
  sw.stop();
  return sw.elapsedMilliseconds;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    const secureChannel = MethodChannel('plugins.it_nomads.com/flutter_secure_storage');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      secureChannel,
      (call) async {
        await Future<void>.delayed(const Duration(milliseconds: 25));
        return null;
      },
    );
    const prefsChannel = MethodChannel('plugins.flutter.io/shared_preferences');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      prefsChannel,
      (call) async {
        await Future<void>.delayed(const Duration(milliseconds: 25));
        return <String, Object>{};
      },
    );
    const pathProviderChannel = MethodChannel('plugins.flutter.io/path_provider');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      pathProviderChannel,
      (call) async => '/tmp/hue-startup-test-support',
    );
  });

  test('Khởi động: 5 hàm load() chạy song song nhanh hơn chạy tuần tự rõ rệt', () async {
    Future<List<Future<void> Function()>> makeLoads() async {
      final config = ServerConfig();
      final theme = ThemeProvider();
      final history = HistoryService();
      final locale = LocaleProvider();
      final auth = AuthService();
      return [
        () => config.load(),
        () => theme.load(),
        () => history.load(),
        () => locale.load(),
        () => auth.load(),
      ];
    }

    final seqLoads = await makeLoads();
    final seqMs = await _timed(() async {
      for (final load in seqLoads) {
        await load();
      }
    });

    final parLoads = await makeLoads();
    final parMs = await _timed(() async {
      await Future.wait([for (final load in parLoads) load()]);
    });

    expect(parMs, lessThan(seqMs));
  });
}
