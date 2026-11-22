import 'dart:async';
import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hue_heritage_music/screens/settings/settings_screen.dart';
import 'package:hue_heritage_music/services/auth_service.dart';
import 'package:hue_heritage_music/services/locale_provider.dart';
import 'package:hue_heritage_music/services/server_config.dart';
import 'package:hue_heritage_music/services/theme_provider.dart';
import 'package:hue_heritage_music/widgets/hue_button.dart';
import 'package:provider/provider.dart';

const _realPng = '''
iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==''';

class _FakePicker extends FilePicker {
  @override
  Future<FilePickerResult?> pickFiles({
    String? dialogTitle,
    String? initialDirectory,
    FileType type = FileType.any,
    List<String>? allowedExtensions,
    Function(FilePickerStatus)? onFileLoading,
    bool allowCompression = false,
    int compressionQuality = 0,
    bool allowMultiple = false,
    bool withData = false,
    bool withReadStream = false,
    bool lockParentWindow = false,
    bool readSequential = false,
  }) async {
    return FilePickerResult([
      PlatformFile(
        name: 'a.png',
        size: 8,
        bytes: Uint8List.fromList([137, 80, 78, 71, 1, 2, 3, 4]),
      ),
    ]);
  }
}

class _DelayAdapter implements HttpClientAdapter {
  final List<String> posts = [];
  Completer<void> gate = Completer<void>();

  @override
  Future<ResponseBody> fetch(RequestOptions options, Stream<Uint8List>? requestStream, Future<void>? cancelFuture) async {
    if (options.path.contains('/api/auth/me/avatar')) {
      posts.add(options.path);
      await gate.future;
      return ResponseBody.fromString(
        jsonEncode({'avatar': '/api/avatars/x', 'name': 'x.png'}),
        200,
        headers: {Headers.contentTypeHeader: [Headers.jsonContentType]},
      );
    }
    if (options.path.contains('/api/avatars/')) {
      return ResponseBody.fromBytes(
        base64Decode(_realPng.replaceAll('\n', '')),
        200,
        headers: {Headers.contentTypeHeader: ['image/png']},
      );
    }
    return ResponseBody.fromString(
      jsonEncode({'total': 0, 'items': []}),
      200,
      headers: {Headers.contentTypeHeader: [Headers.jsonContentType]},
    );
  }

  @override
  void close({bool force = false}) {}
}

Widget _host(AuthService auth, ServerConfig server) {
  return MultiProvider(
    providers: [
      ChangeNotifierProvider<ServerConfig>.value(value: server),
      ChangeNotifierProvider<LocaleProvider>.value(value: LocaleProvider()..setLocale('vi')),
      ChangeNotifierProvider<ThemeProvider>.value(value: ThemeProvider()),
      ChangeNotifierProvider<AuthService>.value(value: auth),
    ],
    child: const MaterialApp(home: Scaffold(body: SettingsScreen())),
  );
}

void main() {
  setUpAll(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    const secureChannel = MethodChannel('plugins.it_nomads.com/flutter_secure_storage');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      secureChannel,
      (call) async => null,
    );
    FilePicker.platform = _FakePicker();
  });

  testWidgets('Đổi ảnh đại diện: busy-gate chặn nhấn đúp — đúng 1 upload', (tester) async {
    final auth = AuthService();
    await auth.save(token: 'tok-avatar-busy', username: 'busy_admin', email: 'busy@gmail.com', role: 'admin');
    final server = ServerConfig();
    final adapter = _DelayAdapter();
    server.api.dio.httpClientAdapter = adapter;

    await tester.pumpWidget(_host(auth, server));
    await tester.pumpAndSettle();
    expect(find.text('Đổi ảnh đại diện'), findsOneWidget);

    final avatarBtn = find.widgetWithText(HueButton, 'Đổi ảnh đại diện');
    await tester.tap(avatarBtn);
    var guard = 0;
    while (adapter.posts.isEmpty && guard < 20) {
      await tester.pump(const Duration(milliseconds: 50));
      guard++;
    }
    expect(adapter.posts.length, 1, reason: 'lần tap đầu phải bắt đầu upload');
    final busyBtns = tester.widgetList<HueButton>(find.byType(HueButton)).where((b) => b.loading).toList();
    expect(busyBtns.length, 1, reason: 'trong lúc upload nút đổi ảnh phải loading (disabled)');
    expect(find.widgetWithText(HueButton, 'Đổi ảnh đại diện'), findsNothing,
        reason: 'loading thay label — nhấn đúp không có đích');

    final busyFinder = find.byWidgetPredicate((w) => w is HueButton && w.loading);
    await tester.tap(busyFinder, warnIfMissed: false);
    await tester.pump();
    expect(adapter.posts.length, 1, reason: 'tap trên nút disabled không sinh request');
    adapter.gate.complete();
    await tester.pumpAndSettle();
  });
}
