import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'services/server_config.dart';
import 'services/session_media.dart';
import 'services/theme_provider.dart';
import 'screens/home/home_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final config = ServerConfig();
  final theme = ThemeProvider();
  await config.load();
  await theme.load();
  runApp(HueHeritageApp(config: config, theme: theme));
}

class HueHeritageApp extends StatelessWidget {
  final ServerConfig config;
  final ThemeProvider theme;

  const HueHeritageApp({super.key, required this.config, required this.theme});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider<ServerConfig>.value(value: config),
        ChangeNotifierProvider<ThemeProvider>.value(value: theme),
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
            home: const HomeScreen(),
          );
        },
      ),
    );
  }
}
