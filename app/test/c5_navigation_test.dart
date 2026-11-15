import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

// ignore_for_file: prefer_const_constructors, prefer_const_literals_to_create_immutables

import 'package:hue_heritage_music/core/theme/app_theme.dart';
import 'package:hue_heritage_music/services/locale_provider.dart';
import 'package:hue_heritage_music/services/server_config.dart';
import 'package:hue_heritage_music/services/theme_provider.dart';
import 'package:hue_heritage_music/widgets/responsive_layout.dart';

class _CounterScreen extends StatefulWidget {
  const _CounterScreen();

  @override
  State<_CounterScreen> createState() => _CounterScreenState();
}

class _CounterScreenState extends State<_CounterScreen> {
  int _n = 0;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('$_n', key: const Key('counter-value')),
          FilledButton(
            key: const Key('counter-inc'),
            onPressed: () => setState(() => _n++),
            child: const Text('+1'),
          ),
        ],
      ),
    );
  }
}

class _PlainScreen extends StatelessWidget {
  const _PlainScreen();

  @override
  Widget build(BuildContext context) => Center(child: Text('B', key: const Key('screen-b')));
}

Widget _shell({required int index, required ValueChanged<int> onSelect}) {
  return MultiProvider(
    providers: [
      ChangeNotifierProvider<ServerConfig>.value(value: ServerConfig()),
      ChangeNotifierProvider<ThemeProvider>.value(value: ThemeProvider()),
      ChangeNotifierProvider<LocaleProvider>.value(value: LocaleProvider()..setLocale('vi')),
    ],
    child: MaterialApp(
      theme: AppTheme.lightTheme,
      home: ResponsiveScaffold(
        selectedIndex: index,
        onDestinationSelected: onSelect,
        destinations: [
          NavigationDestinationItem(
            icon: Icons.home_outlined,
            selectedIcon: Icons.home,
            labelKey: 'home',
            screen: const _CounterScreen(),
          ),
          const NavigationDestinationItem(
            icon: Icons.music_note,
            selectedIcon: Icons.music_note,
            labelKey: 'heritage',
            screen: _PlainScreen(),
          ),
        ],
      ),
    ),
  );
}

void main() {
  testWidgets('C5: tab giữ nguyên trạng thái khi chuyển đi rồi quay lại (LazyIndexedStack)', (tester) async {
    tester.view.devicePixelRatio = 1.0;
    tester.view.physicalSize = const Size(1024, 768);
    addTearDown(tester.view.reset);
    final index = ValueNotifier<int>(0);
    await tester.pumpWidget(
      ValueListenableBuilder<int>(
        valueListenable: index,
        builder: (context, i, _) => _shell(index: i, onSelect: (next) => index.value = next),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('counter-inc')));
    await tester.pump();
    expect(find.text('1'), findsOneWidget);

    index.value = 1;
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('screen-b')), findsOneWidget);

    index.value = 0;
    await tester.pumpAndSettle();
    expect(find.text('1'), findsOneWidget, reason: 'counter phải giữ nguyên sau khi chuyển tab đi và về');
  });

  testWidgets('C5: back ở tab trong → về Home, không thoát app', (tester) async {
    tester.view.devicePixelRatio = 1.0;
    tester.view.physicalSize = const Size(1024, 768);
    addTearDown(tester.view.reset);
    final index = ValueNotifier<int>(1);
    await tester.pumpWidget(
      ValueListenableBuilder<int>(
        valueListenable: index,
        builder: (context, i, _) => _shell(index: i, onSelect: (next) => index.value = next),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('screen-b')), findsOneWidget);

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(index.value, 0, reason: 'back ở tab trong phải điều hướng về Home tab');
    expect(find.byKey(const Key('counter-value')), findsOneWidget);
    expect(find.byKey(const Key('screen-b')), findsNothing);
  });
}
