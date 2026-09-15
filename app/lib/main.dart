import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'core/theme/app_theme.dart';
import 'screens/home/home_screen.dart';
import 'services/history_service.dart';
import 'services/locale_provider.dart';
import 'services/server_config.dart';
import 'services/session_media.dart';
import 'services/theme_provider.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final config = ServerConfig();
  final theme = ThemeProvider();
  final history = HistoryService();
  final locale = LocaleProvider();
  await config.load();
  await theme.load();
  await history.load();
  await locale.load();
  runApp(HueHeritageApp(
    config: config,
    theme: theme,
    history: history,
    locale: locale,
  ));
}

class HueHeritageApp extends StatelessWidget {
  final ServerConfig config;
  final ThemeProvider theme;
  final HistoryService history;
  final LocaleProvider locale;

  const HueHeritageApp({
    super.key,
    required this.config,
    required this.theme,
    required this.history,
    required this.locale,
  });

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider<ServerConfig>.value(value: config),
        ChangeNotifierProvider<ThemeProvider>.value(value: theme),
        ChangeNotifierProvider<HistoryService>.value(value: history),
        ChangeNotifierProvider<LocaleProvider>.value(value: locale),
        ChangeNotifierProvider<SessionMedia>(create: (_) => SessionMedia()),
      ],
      child: Consumer2<ThemeProvider, LocaleProvider>(
        builder: (context, themeProvider, localeProvider, _) {
          return MaterialApp(
            title: localeProvider.strings.appTitle,
            theme: AppTheme.lightTheme,
            darkTheme: AppTheme.darkTheme,
            themeMode: themeProvider.mode,
            locale: localeProvider.currentLocale,
            home: const OfflineBanner(child: HomeScreen()),
          );
        },
      ),
    );
  }
}

class OfflineBanner extends StatefulWidget {
  final Widget child;

  const OfflineBanner({super.key, required this.child});

  @override
  State<OfflineBanner> createState() => _OfflineBannerState();
}

class _OfflineBannerState extends State<OfflineBanner> {
  bool _offline = false;

  @override
  void initState() {
    super.initState();
    _check();
  }

  Future<void> _check() async {
    try {
      final result = await Connectivity().checkConnectivity();
      if (!mounted) return;
      setState(() {
        _offline = result.contains(ConnectivityResult.none) || result.isEmpty;
      });
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final locale = context.watch<LocaleProvider>();
    return StreamBuilder<List<ConnectivityResult>>(
      stream: Connectivity().onConnectivityChanged,
      builder: (context, snapshot) {
        final data = snapshot.data;
        final offline = data != null
            ? (data.contains(ConnectivityResult.none) || data.isEmpty)
            : _offline;
        return Column(
          children: [
            if (offline)
              Material(
                color: const Color(0xFF8C3B3B),
                child: SizedBox(
                  width: double.infinity,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 12),
                    child: Text(
                      locale.strings.offlineMessage,
                      style: const TextStyle(color: Colors.white, fontSize: 13),
                      textAlign: TextAlign.center,
                    ),
                  ),
                ),
              ),
            Expanded(child: widget.child),
          ],
        );
      },
    );
  }
}
