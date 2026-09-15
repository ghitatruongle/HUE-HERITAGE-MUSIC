import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/theme/app_theme.dart';
import '../services/locale_provider.dart';
import '../services/server_config.dart';
import '../services/theme_provider.dart';
import 'docked_player_bar.dart';

class NavigationDestinationItem {
  final IconData icon;
  final IconData selectedIcon;
  final String labelKey;
  final Widget screen;

  const NavigationDestinationItem({
    required this.icon,
    required this.selectedIcon,
    required this.labelKey,
    required this.screen,
  });
}

class ResponsiveScaffold extends StatefulWidget {
  final List<NavigationDestinationItem> destinations;
  final int selectedIndex;
  final ValueChanged<int> onDestinationSelected;
  final Widget? floatingActionButton;

  const ResponsiveScaffold({
    super.key,
    required this.destinations,
    required this.selectedIndex,
    required this.onDestinationSelected,
    this.floatingActionButton,
  });

  @override
  State<ResponsiveScaffold> createState() => _ResponsiveScaffoldState();
}

class _ResponsiveScaffoldState extends State<ResponsiveScaffold> {
  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    final isDesktop = width >= 860;
    final locale = context.watch<LocaleProvider>();
    final theme = context.watch<ThemeProvider>();
    final server = context.watch<ServerConfig>();

    return Scaffold(
      floatingActionButton: widget.floatingActionButton,
      body: Column(
        children: [
          Expanded(
            child: isDesktop
                ? _buildDesktopLayout(context, locale, theme, server)
                : _buildMobileLayout(context, locale, theme, server),
          ),
          const DockedPlayerBar(),
        ],
      ),
      bottomNavigationBar: isDesktop ? null : _buildMobileBottomBar(context, locale),
    );
  }

  Widget _buildDesktopLayout(
    BuildContext context,
    LocaleProvider locale,
    ThemeProvider theme,
    ServerConfig server,
  ) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final sidebarBg = isDark ? const Color(0xFF131120) : const Color(0xFFF0ECF7);
    final borderColor = isDark ? const Color(0xFF2E2B48) : const Color(0xFFE4DFEE);

    return Row(
      children: [
        Container(
          width: 256,
          decoration: BoxDecoration(
            color: sidebarBg,
            border: Border(right: BorderSide(color: borderColor, width: 1.5)),
          ),
          child: Column(
            children: [
              Container(
                padding: const EdgeInsets.fromLTRB(20, 24, 20, 20),
                child: Row(
                  children: [
                    Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [AppTheme.primaryPurple, AppTheme.primaryPurpleLight],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        borderRadius: BorderRadius.circular(12),
                        boxShadow: [
                          BoxShadow(
                            color: AppTheme.primaryPurple.withValues(alpha: 0.35),
                            blurRadius: 10,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: Image.asset(
                          'assets/images/app_logo.png',
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => const Icon(Icons.music_note, color: Colors.white),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            locale.strings.appTitle,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15),
                          ),
                          Text(
                            locale.strings.sidebarTagline,
                            style: const TextStyle(
                              fontSize: 11,
                              color: AppTheme.amberGold,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1),
              Expanded(
                child: ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                  itemCount: widget.destinations.length,
                  itemBuilder: (context, index) {
                    final item = widget.destinations[index];
                    final isSelected = widget.selectedIndex == index;
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 4),
                      child: Material(
                        color: isSelected
                            ? AppTheme.primaryPurple.withValues(alpha: isDark ? 0.25 : 0.15)
                            : Colors.transparent,
                        borderRadius: BorderRadius.circular(12),
                        child: InkWell(
                          borderRadius: BorderRadius.circular(12),
                          onTap: () => widget.onDestinationSelected(index),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                            child: Row(
                              children: [
                                Icon(
                                  isSelected ? item.selectedIcon : item.icon,
                                  size: 20,
                                  color: isSelected
                                      ? (isDark ? AppTheme.primaryPurpleGlow : AppTheme.primaryPurple)
                                      : Theme.of(context).colorScheme.onSurfaceVariant,
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Text(
                                    _resolveNavLabel(item.labelKey, locale),
                                    style: TextStyle(
                                      fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                                      fontSize: 13,
                                      color: isSelected
                                          ? (isDark ? AppTheme.primaryPurpleGlow : AppTheme.primaryPurple)
                                          : Theme.of(context).colorScheme.onSurface,
                                    ),
                                  ),
                                ),
                                if (isSelected)
                                  Container(
                                    width: 4,
                                    height: 16,
                                    decoration: BoxDecoration(
                                      color: isDark ? AppTheme.primaryPurpleGlow : AppTheme.primaryPurple,
                                      borderRadius: BorderRadius.circular(2),
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
              const Divider(height: 1),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        OutlinedButton(
                          style: OutlinedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                            minimumSize: Size.zero,
                          ),
                          onPressed: () => locale.toggleLanguage(),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.language, size: 16),
                              const SizedBox(width: 6),
                              Text(locale.isVietnamese ? 'VI' : 'EN', style: const TextStyle(fontSize: 12)),
                            ],
                          ),
                        ),
                        IconButton(
                          iconSize: 20,
                          icon: Icon(isDark ? Icons.light_mode : Icons.dark_mode),
                          tooltip: locale.strings.themeModeTitle,
                          onPressed: () => theme.toggleTheme(context),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                        color: isDark ? const Color(0xFF1B192C) : const Color(0xFFE6E1F0),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        children: [
                          Container(
                            width: 8,
                            height: 8,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: server.hasServer ? AppTheme.emeraldGreen : Colors.red,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              server.hasServer ? locale.strings.serverOnline : locale.strings.serverOffline,
                              style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w600),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: widget.destinations[widget.selectedIndex].screen,
        ),
      ],
    );
  }

  Widget _buildMobileLayout(
    BuildContext context,
    LocaleProvider locale,
    ThemeProvider theme,
    ServerConfig server,
  ) {
    return widget.destinations[widget.selectedIndex].screen;
  }

  Widget _buildMobileBottomBar(BuildContext context, LocaleProvider locale) {
    final bottomDestinations = widget.destinations.take(5).toList();
    final currentIndex = widget.selectedIndex < 5 ? widget.selectedIndex : 0;

    return NavigationBar(
      selectedIndex: currentIndex,
      onDestinationSelected: (index) => widget.onDestinationSelected(index),
      destinations: [
        for (final item in bottomDestinations)
          NavigationDestination(
            icon: Icon(item.icon),
            selectedIcon: Icon(item.selectedIcon),
            label: _resolveNavLabel(item.labelKey, locale),
          ),
      ],
    );
  }

  String _resolveNavLabel(String key, LocaleProvider locale) {
    final s = locale.strings;
    return switch (key) {
      'home' => s.navHome,
      'heritage' => s.navHeritage,
      'learning' => s.navLearning,
      'analysis' => s.navAnalysis,
      'transcription' => s.navTranscription,
      'creation' => s.navCreation,
      'cover' => s.navCover,
      'restoration' => s.navRestoration,
      'instruments' => s.navInstruments,
      'history' => s.taskHistoryTitle,
      'settings' => s.settingsTitle,
      'info' => s.projectInfoTitle,
      _ => key,
    };
  }
}
