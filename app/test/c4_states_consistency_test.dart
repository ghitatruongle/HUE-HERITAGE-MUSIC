import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:hue_heritage_music/models/music_task.dart';
import 'package:hue_heritage_music/screens/auth/account_manager_section.dart';
import 'package:hue_heritage_music/screens/auth/invite_manager_section.dart';
import 'package:hue_heritage_music/screens/creation/task_result_card.dart';
import 'package:hue_heritage_music/screens/home/home_screen.dart';
import 'package:hue_heritage_music/services/auth_service.dart';
import 'package:hue_heritage_music/services/history_service.dart';
import 'package:hue_heritage_music/services/locale_provider.dart';
import 'package:hue_heritage_music/services/server_config.dart';
import 'package:hue_heritage_music/services/session_media.dart';
import 'package:hue_heritage_music/services/theme_provider.dart';
import 'package:hue_heritage_music/widgets/empty_state.dart';
import 'package:hue_heritage_music/widgets/error_panel.dart';
import 'package:hue_heritage_music/widgets/skeleton_loader.dart';

class _EmptyPageAdapter implements HttpClientAdapter {
  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    return ResponseBody.fromString(
      jsonEncode({'total': 0, 'items': []}),
      200,
      headers: {Headers.contentTypeHeader: [Headers.jsonContentType]},
    );
  }

  @override
  void close({bool force = false}) {}
}

LocaleProvider _viLocale() => LocaleProvider()..setLocale('vi');

ServerConfig _mockServer() {
  final server = ServerConfig();
  server.api.dio.httpClientAdapter = _EmptyPageAdapter();
  return server;
}

Future<void> _pumpSection(WidgetTester tester, ServerConfig server, Widget child) async {
  await tester.pumpWidget(
    MultiProvider(
      providers: [
        ChangeNotifierProvider<ServerConfig>.value(value: server),
        ChangeNotifierProvider<LocaleProvider>.value(value: _viLocale()),
        ChangeNotifierProvider<AuthService>.value(value: AuthService()),
      ],
      child: MaterialApp(home: Scaffold(body: SingleChildScrollView(child: child))),
    ),
  );
}

void main() {
  testWidgets('TaskResultCard failed → ErrorPanel + thông báo thân thiện', (tester) async {
    await _pumpSection(
      tester,
      _mockServer(),
      TaskResultCard(
        task: MusicTask(id: 't1', kind: 'gen', status: 'failed', reason: ''),
        polling: false,
        onCancel: (_) {},
      ),
    );
    await tester.pump();
    expect(find.byType(ErrorPanel), findsOneWidget);
    expect(find.textContaining('Tác vụ thất bại'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('TaskResultCard failed có reason → ErrorPanel kèm reason', (tester) async {
    await _pumpSection(
      tester,
      _mockServer(),
      TaskResultCard(
        task: MusicTask(id: 't2', kind: 'gen', status: 'failed', reason: 'hết quota'),
        polling: false,
        onCancel: (_) {},
      ),
    );
    await tester.pump();
    expect(find.byType(ErrorPanel), findsOneWidget);
    expect(find.textContaining('hết quota'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('TaskResultCard done → không ErrorPanel', (tester) async {
    await _pumpSection(
      tester,
      _mockServer(),
      TaskResultCard(
        task: MusicTask(id: 't3', kind: 'gen', status: 'done', reason: '', audioUrl: ''),
        polling: false,
        onCancel: (_) {},
      ),
    );
    await tester.pump();
    expect(find.byType(ErrorPanel), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('AccountManagerSection loading → SkeletonLoader, rỗng → EmptyState', (tester) async {
    final server = _mockServer();
    await _pumpSection(tester, server, const AccountManagerSection());
    await tester.pump();
    expect(find.byType(SkeletonLoader), findsWidgets);
    await tester.pump(const Duration(milliseconds: 50));
    await tester.pump(const Duration(milliseconds: 200));
    expect(find.byType(EmptyState), findsOneWidget);
    expect(find.textContaining('Chưa có tài khoản nào'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('InviteManagerSection loading → SkeletonLoader, rỗng → EmptyState', (tester) async {
    final server = _mockServer();
    await _pumpSection(tester, server, const InviteManagerSection());
    await tester.pump();
    expect(find.byType(SkeletonLoader), findsWidgets);
    await tester.pump(const Duration(milliseconds: 50));
    await tester.pump(const Duration(milliseconds: 200));
    expect(find.byType(EmptyState), findsOneWidget);
    expect(find.textContaining('Chưa có mã mời nào'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Home recent rỗng → EmptyState dùng chung', (tester) async {
    final server = _mockServer();
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<ServerConfig>.value(value: server),
          ChangeNotifierProvider<ThemeProvider>.value(value: ThemeProvider()),
          ChangeNotifierProvider<HistoryService>.value(value: HistoryService()),
          ChangeNotifierProvider<LocaleProvider>.value(value: _viLocale()),
          ChangeNotifierProvider<AuthService>.value(value: AuthService()),
          ChangeNotifierProvider<SessionMedia>.value(value: SessionMedia()),
        ],
        child: const MaterialApp(home: Scaffold(body: HomeScreen())),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 60));
    expect(find.textContaining('Chưa có hoạt động nào'), findsOneWidget);
    expect(find.byType(EmptyState), findsWidgets);
    expect(tester.takeException(), isNull);
  });
}
