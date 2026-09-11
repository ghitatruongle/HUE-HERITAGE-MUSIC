import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hue_heritage_music/core/constants/app_constants.dart';
import 'package:hue_heritage_music/models/compare_result.dart';
import 'package:hue_heritage_music/models/pitch_data.dart';
import 'package:hue_heritage_music/screens/settings/settings_screen.dart';
import 'package:hue_heritage_music/services/server_config.dart';
import 'package:hue_heritage_music/services/theme_provider.dart';
import 'package:hue_heritage_music/widgets/common_button.dart';
import 'package:hue_heritage_music/widgets/compare_chart.dart';
import 'package:hue_heritage_music/widgets/pitch_contour_chart.dart';
import 'package:provider/provider.dart';

void main() {
  test('ServerConfig keeps default URL when config file is absent', () async {
    final cfg = ServerConfig();
    expect(cfg.baseUrl, AppConstants.defaultServerUrl);
    await cfg.load();
    expect(cfg.baseUrl, AppConstants.defaultServerUrl);
  });

  test('ServerConfig normalizes base URL', () {
    expect(ServerConfig.normalize('http://192.0.2.10:8000/api'), 'http://192.0.2.10:8000');
    expect(ServerConfig.normalize('http://192.0.2.10:8000/'), 'http://192.0.2.10:8000');
    expect(ServerConfig.normalize('192.0.2.10:8000'), 'http://192.0.2.10:8000');
    expect(ServerConfig.normalize(''), AppConstants.defaultServerUrl);
  });

  testWidgets('Settings screen never shows server connection UI', (tester) async {
    await tester.pumpWidget(
      ChangeNotifierProvider<ThemeProvider>.value(
        value: ThemeProvider(),
        child: const MaterialApp(
          home: Scaffold(body: SettingsScreen()),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('Kết nối máy chủ AI'), findsNothing);
    expect(find.text('Địa chỉ máy chủ'), findsNothing);
    expect(find.text('URL máy chủ'), findsNothing);
    expect(find.text('Kiểm tra'), findsNothing);
    expect(find.byType(TextField), findsNothing);
    expect(find.byType(FilledButton), findsNothing);
  });

  testWidgets('CommonButton renders and responds to tap', (tester) async {
    bool tapped = false;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CommonButton(
            label: 'Test Button',
            onPressed: () => tapped = true,
          ),
        ),
      ),
    );

    expect(find.text('Test Button'), findsOneWidget);
    await tester.tap(find.text('Test Button'));
    await tester.pump();
    expect(tapped, isTrue);
  });

  testWidgets('PitchContourChart renders properly', (tester) async {
    final pitch = PitchData(
      meanF0: 220.0,
      frames: 3,
      times: [0.0, 0.5, 1.0],
      f0: [210.0, 220.0, 230.0],
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 400,
            height: 300,
            child: PitchContourChart(data: pitch),
          ),
        ),
      ),
    );

    expect(find.byType(PitchContourChart), findsOneWidget);
  });

  testWidgets('CompareChart renders properly', (tester) async {
    final comp = CompareResult(
      metrics: CompareMetrics(
        score: 85.0,
        pitchScore: 88.0,
        timeScore: 80.0,
        meanAbsCents: 15.0,
        medianCents: 12.0,
        meanOffsetMs: 50.0,
        startOffsetMs: 20.0,
        pairs: 10,
      ),
      times: [0.0, 0.5],
      sampleF0: [220.0, 220.0],
      warpedF0: [225.0, 225.0],
      notes: [
        CompareNote(
          midi: 60,
          name: 'C4',
          start: 0.0,
          end: 0.5,
          errCents: 5.0,
          verdict: 'Chuan',
        ),
      ],
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 400,
            height: 300,
            child: CompareChart(
              times: comp.times,
              sampleF0: comp.sampleF0,
              warpedF0: comp.warpedF0,
            ),
          ),
        ),
      ),
    );

    expect(find.byType(CompareChart), findsOneWidget);
  });
}
