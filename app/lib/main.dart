import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'services/history_service.dart';
import 'services/server_config.dart';
import 'services/session_media.dart';
import 'services/theme_provider.dart';
import 'screens/home/home_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final config = ServerConfig();
  final theme = ThemeProvider();
  final history = HistoryService();
  await config.load();
  await theme.load();
  await history.load();
  runApp(HueHeritageApp(config: config, theme: theme, history: history));
}

class HueHeritageApp extends StatelessWidget {
  final ServerConfig config;
  final ThemeProvider theme;
  final HistoryService history;

  const HueHeritageApp({super.key, required this.config, required this.theme, required this.history});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider<ServerConfig>.value(value: config),
        ChangeNotifierProvider<ThemeProvider>.value(value: theme),
        ChangeNotifierProvider<HistoryService>.value(value: history),
        ChangeNotifierProvider<SessionMedia>(create: (_) => SessionMedia()),
      ],
      child: Consumer<ThemeProvider>(
        builder: (context, theme, _) {
          return MaterialApp(
            title: 'Hue Heritage Music',
            theme: ThemeData(
              colorSchemeSeed: const Color(0xFF5B3B8C),
              useMaterial3: true,
            ),
            darkTheme: ThemeData(
              colorSchemeSeed: const Color(0xFF5B3B8C),
              brightness: Brightness.dark,
              useMaterial3: true,
            ),
            themeMode: theme.mode,
            home: const OfflineBanner(child: HomeScreen()),
          );
        },
      ),
    );
  }
}

class OfflineBanner extends StatelessWidget {
  final Widget child;

  const OfflineBanner({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<ConnectivityResult>>(
      stream: Connectivity().onConnectivityChanged,
      initialData: const [ConnectivityResult.none],
      builder: (context, snapshot) {
        final offline = snapshot.data?.contains(ConnectivityResult.none) ?? false;
        return Directionality(
          textDirection: TextDirection.ltr,
          child: Column(
            children: [
              if (offline)
                const Material(
                  color: Color(0xFF8C3B3B),
                  child: SizedBox(
                    width: double.infinity,
                    child: Padding(
                      padding: EdgeInsets.symmetric(vertical: 6, horizontal: 12),
                      child: Text(
                        'Mất kết nối mạng. Một số chức năng cần internet.',
                        style: TextStyle(color: Colors.white),
                      ),
                    ),
                  ),
                ),
              Expanded(child: child),
            ],
          ),
        );
      },
    );
  }
}
