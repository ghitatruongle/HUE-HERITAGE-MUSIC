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
  Future<void> pumpMobile(WidgetTester tester, ValueNotifier<int> index) async {
    tester.view.devicePixelRatio = 1.0;
    tester.view.physicalSize = const Size(320, 640);
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ValueListenableBuilder<int>(
        valueListenable: index,
        builder: (context, i, _) => _shell(index: i, onSelect: (next) => index.value = next),
      ),
    );
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump(const Duration(milliseconds: 100));
  }

  testWidgets('C5 mobile: back ở tab trong → về Home, không thoát app', (tester) async {
    final index = ValueNotifier<int>(1);
    await pumpMobile(tester, index);
    expect(find.byKey(const Key('screen-b')), findsOneWidget);

    await tester.binding.handlePopRoute();
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump(const Duration(milliseconds: 100));
    expect(index.value, 0, reason: 'back mobile ở tab trong phải điều hướng về Home');
    expect(find.byKey(const Key('counter-value')), findsOneWidget);
    expect(find.byKey(const Key('screen-b')), findsNothing);
  });

  testWidgets('C5 mobile: back ở Home → cho phép bubble thoát app chủ đích', (tester) async {
    final index = ValueNotifier<int>(0);
    await pumpMobile(tester, index);
    expect(find.byKey(const Key('counter-value')), findsOneWidget);

    expect(tester.state<NavigatorState>(find.byType(Navigator)).canPop(), isFalse,
        reason: 'Home là root route — không có route dưới để pop');
    final popScope = tester.widget<PopScope>(
      find.byWidgetPredicate((w) => w is PopScope),
    );
    expect(popScope.canPop, isTrue,
        reason: 'PopScope phải cho phép bubble → SystemNavigator.pop (thoát app chủ đích)');
    await tester.binding.handlePopRoute();
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.byKey(const Key('counter-value')), findsOneWidget,
        reason: 'test binding mock SystemNavigator — route không bị remove, không crash');
    expect(tester.takeException(), isNull);
  });

  testWidgets('C5 mobile: tab giữ nguyên trạng thái khi chuyển đi rồi về', (tester) async {
    final index = ValueNotifier<int>(0);
    await pumpMobile(tester, index);

    await tester.tap(find.byKey(const Key('counter-inc')));
    await tester.pump();
    expect(find.text('1'), findsOneWidget);

    index.value = 1;
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.byKey(const Key('screen-b')), findsOneWidget);

    index.value = 0;
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('1'), findsOneWidget, reason: 'state tab phải giữ ở mobile shell');
  });
}
