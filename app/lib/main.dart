import 'dart:async';
import 'dart:ui' show PlatformDispatcher;

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:provider/provider.dart';

import 'core/constants/app_constants.dart';
import 'core/theme/app_theme.dart';
import 'screens/home/home_screen.dart';
import 'services/auth_service.dart';
import 'services/crash_log.dart';
import 'services/history_service.dart';
import 'services/locale_provider.dart';
import 'services/server_config.dart';
import 'services/session_media.dart';
import 'services/theme_provider.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  FlutterError.onError = (details) {
    FlutterError.presentError(details);
    unawaited(CrashLog.write(details.exceptionAsString()));
  };
  PlatformDispatcher.instance.onError = (error, stack) {
    unawaited(CrashLog.write('$error\n$stack'));
    return true;
  };
  final config = ServerConfig();
  final theme = ThemeProvider();
  final history = HistoryService();
  final locale = LocaleProvider();
  final auth = AuthService();
  await config.load();
  await theme.load();
  await history.load();
  await locale.load();
  await auth.load();
  try {
    final info = await PackageInfo.fromPlatform();
    if (info.version.isNotEmpty) {
      AppConstants.appVersion = info.version;
    }
  } catch (_) {}
  runApp(HueHeritageApp(
    config: config,
    theme: theme,
    history: history,
    locale: locale,
    auth: auth,
  ));
  if (auth.isLoggedIn && config.hasServer) {
    unawaited(auth.validateSession(config.baseUrl));
  }
}

class HueHeritageApp extends StatelessWidget {
  final ServerConfig config;
  final ThemeProvider theme;
  final HistoryService history;
  final LocaleProvider locale;
  final AuthService auth;

  const HueHeritageApp({
    super.key,
    required this.config,
    required this.theme,
    required this.history,
    required this.locale,
    required this.auth,
  });

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider<ServerConfig>.value(value: config),
        ChangeNotifierProvider<ThemeProvider>.value(value: theme),
        ChangeNotifierProvider<HistoryService>.value(value: history),
        ChangeNotifierProvider<LocaleProvider>.value(value: locale),
        ChangeNotifierProvider<AuthService>.value(value: auth),
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
  final Connectivity _connectivity = Connectivity();
  bool _offline = false;

  @override
  void initState() {
    super.initState();
    _check();
  }

  Future<void> _check() async {
    try {
      final result = await _connectivity.checkConnectivity();
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
      stream: _connectivity.onConnectivityChanged,
      builder: (context, snapshot) {
        final data = snapshot.data;
        final offline = data != null
            ? (data.contains(ConnectivityResult.none) || data.isEmpty)
            : _offline;
        return Column(
          children: [
            if (offline)
              Material(
                color: Theme.of(context).colorScheme.errorContainer,
                child: SizedBox(
                  width: double.infinity,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 12),
                    child: Text(
                      locale.strings.offlineMessage,
                      style: TextStyle(color: Theme.of(context).colorScheme.onErrorContainer, fontSize: 13),
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
