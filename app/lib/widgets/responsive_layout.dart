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
  bool _isSidebarCollapsed = false;

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
        AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          width: _isSidebarCollapsed ? 72 : 250,
          decoration: BoxDecoration(
            color: sidebarBg,
            border: Border(right: BorderSide(color: borderColor, width: 1.5)),
          ),
          child: Column(
            children: [
              Container(
                padding: EdgeInsets.symmetric(
                  horizontal: _isSidebarCollapsed ? 12 : 16,
                  vertical: 18,
                ),
                child: _isSidebarCollapsed
                    ? Column(
                        children: [
                          IconButton(
                            icon: const Icon(Icons.menu, size: 22),
                            tooltip: locale.strings.expandSidebar,
                            onPressed: () => setState(() => _isSidebarCollapsed = false),
                          ),
                          const SizedBox(height: 8),
                          Container(
                            width: 36,
                            height: 36,
                            decoration: BoxDecoration(
                              gradient: const LinearGradient(
                                colors: [AppTheme.primaryPurple, AppTheme.primaryPurpleLight],
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                              ),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(10),
                              child: Image.asset(
                                'assets/images/app_logo.png',
                                fit: BoxFit.cover,
                                errorBuilder: (_, __, ___) => const Icon(Icons.music_note, color: Colors.white, size: 20),
                              ),
                            ),
                          ),
                        ],
                      )
                    : Row(
                        children: [
                          Container(
                            width: 40,
                            height: 40,
                            decoration: BoxDecoration(
                              gradient: const LinearGradient(
                                colors: [AppTheme.primaryPurple, AppTheme.primaryPurpleLight],
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                              ),
                              borderRadius: BorderRadius.circular(12),
                              boxShadow: [
                                BoxShadow(
                                  color: AppTheme.primaryPurple.withValues(alpha: 0.3),
                                  blurRadius: 8,
                                  offset: const Offset(0, 3),
                                ),
                              ],
                            ),
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(12),
                              child: Image.asset(
                                'assets/images/app_logo.png',
                                fit: BoxFit.cover,
                                errorBuilder: (_, __, ___) => const Icon(Icons.music_note, color: Colors.white, size: 22),
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  locale.strings.appTitle,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14),
                                ),
                                Text(
                                  locale.strings.sidebarTagline,
                                  style: const TextStyle(
                                    fontSize: 10.5,
                                    color: AppTheme.amberGold,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          IconButton(
                            icon: const Icon(Icons.menu_open, size: 20),
                            tooltip: locale.strings.collapseSidebar,
                            onPressed: () => setState(() => _isSidebarCollapsed = true),
                          ),
                        ],
                      ),
              ),
              const Divider(height: 1),
              Expanded(
                child: ListView.builder(
                  padding: EdgeInsets.symmetric(
                    horizontal: _isSidebarCollapsed ? 8 : 10,
                    vertical: 10,
                  ),
                  itemCount: widget.destinations.length,
                  itemBuilder: (context, index) {
                    final item = widget.destinations[index];
                    final isSelected = widget.selectedIndex == index;
                    final label = _resolveNavLabel(item.labelKey, locale);

                    if (_isSidebarCollapsed) {
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 6),
                        child: Tooltip(
                          message: label,
                          preferBelow: false,
                          child: Material(
                            color: isSelected
                                ? AppTheme.primaryPurple.withValues(alpha: isDark ? 0.3 : 0.15)
                                : Colors.transparent,
                            borderRadius: BorderRadius.circular(10),
                            child: InkWell(
                              borderRadius: BorderRadius.circular(10),
                              onTap: () => widget.onDestinationSelected(index),
                              child: Container(
                                width: 44,
                                height: 44,
                                alignment: Alignment.center,
                                child: Icon(
                                  isSelected ? item.selectedIcon : item.icon,
                                  size: 22,
                                  color: isSelected
                                      ? (isDark ? AppTheme.primaryPurpleGlow : AppTheme.primaryPurple)
                                      : Theme.of(context).colorScheme.onSurfaceVariant,
                                ),
                              ),
                            ),
                          ),
                        ),
                      );
                    }

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
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
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
                                  child: Row(
                                    children: [
                                      Flexible(
                                        child: Text(
                                          label,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: TextStyle(
                                            fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                                            fontSize: 13,
                                            color: isSelected
                                                ? (isDark ? AppTheme.primaryPurpleGlow : AppTheme.primaryPurple)
                                                : Theme.of(context).colorScheme.onSurface,
                                          ),
                                        ),
                                      ),
                                      if (item.labelKey == 'restoration') ...[
                                        const SizedBox(width: 6),
                                        Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                                          decoration: BoxDecoration(
                                            color: AppTheme.amberGold.withValues(alpha: 0.2),
                                            borderRadius: BorderRadius.circular(4),
                                            border: Border.all(color: AppTheme.amberGold, width: 0.8),
                                          ),
                                          child: const Text('BETA', style: TextStyle(color: AppTheme.amberGold, fontSize: 9, fontWeight: FontWeight.bold)),
                                        ),
                                      ],
                                    ],
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
                padding: EdgeInsets.symmetric(
                  horizontal: _isSidebarCollapsed ? 8 : 14,
                  vertical: 10,
                ),
                child: _isSidebarCollapsed
                    ? Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            iconSize: 18,
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
                            icon: Text(locale.isVietnamese ? 'VI' : 'EN', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 11)),
                            tooltip: locale.strings.languageTitle,
                            onPressed: () => locale.toggleLanguage(),
                          ),
                          const SizedBox(height: 4),
                          IconButton(
                            iconSize: 18,
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
                            icon: Icon(isDark ? Icons.light_mode : Icons.dark_mode),
                            tooltip: locale.strings.themeModeTitle,
                            onPressed: () => theme.toggleTheme(context),
                          ),
                          const SizedBox(height: 6),
                          Tooltip(
                            message: server.hasServer ? locale.strings.serverOnline : locale.strings.serverOffline,
                            child: Container(
                              width: 8,
                              height: 8,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: server.hasServer ? AppTheme.emeraldGreen : Colors.red,
                              ),
                            ),
                          ),
                        ],
                      )
                    : Column(
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

  void _showAllDestinationsSheet(BuildContext context, LocaleProvider locale) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 12),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        locale.strings.navMore,
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close),
                        onPressed: () => Navigator.pop(ctx),
                      ),
                    ],
                  ),
                ),
                const Divider(),
                Flexible(
                  child: ListView.builder(
                    shrinkWrap: true,
                    itemCount: widget.destinations.length,
                    itemBuilder: (context, i) {
                      final item = widget.destinations[i];
                      final isSelected = widget.selectedIndex == i;
                      return ListTile(
                        leading: Icon(
                          isSelected ? item.selectedIcon : item.icon,
                          color: isSelected ? AppTheme.primaryPurple : null,
                        ),
                        title: Text(
                          _resolveNavLabel(item.labelKey, locale),
                          style: TextStyle(
                            fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                            color: isSelected ? AppTheme.primaryPurple : null,
                          ),
                        ),
                        trailing: isSelected
                            ? const Icon(Icons.check, color: AppTheme.primaryPurple, size: 20)
                            : null,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        onTap: () {
                          Navigator.pop(ctx);
                          widget.onDestinationSelected(i);
                        },
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildMobileBottomBar(BuildContext context, LocaleProvider locale) {
    if (widget.destinations.length <= 5) {
      return NavigationBar(
        selectedIndex: widget.selectedIndex < widget.destinations.length ? widget.selectedIndex : 0,
        onDestinationSelected: widget.onDestinationSelected,
        destinations: [
          for (final item in widget.destinations)
            NavigationDestination(
              icon: Icon(item.icon),
              selectedIcon: Icon(item.selectedIcon),
              label: _resolveNavLabel(item.labelKey, locale),
            ),
        ],
      );
    }

    final topIndices = [0, 1, 3, 6];
    final activeInTop = topIndices.indexOf(widget.selectedIndex);
    final currentIndex = activeInTop != -1 ? activeInTop : 4;

    return NavigationBar(
      selectedIndex: currentIndex,
      onDestinationSelected: (index) {
        if (index == 4) {
          _showAllDestinationsSheet(context, locale);
        } else {
          widget.onDestinationSelected(topIndices[index]);
        }
      },
      destinations: [
        NavigationDestination(
          icon: Icon(widget.destinations[0].icon),
          selectedIcon: Icon(widget.destinations[0].selectedIcon),
          label: _resolveNavLabel(widget.destinations[0].labelKey, locale),
        ),
        NavigationDestination(
          icon: Icon(widget.destinations[1].icon),
          selectedIcon: Icon(widget.destinations[1].selectedIcon),
          label: _resolveNavLabel(widget.destinations[1].labelKey, locale),
        ),
        NavigationDestination(
          icon: Icon(widget.destinations[3].icon),
          selectedIcon: Icon(widget.destinations[3].selectedIcon),
          label: _resolveNavLabel(widget.destinations[3].labelKey, locale),
        ),
        NavigationDestination(
          icon: Icon(widget.destinations[6].icon),
          selectedIcon: Icon(widget.destinations[6].selectedIcon),
          label: _resolveNavLabel(widget.destinations[6].labelKey, locale),
        ),
        NavigationDestination(
          icon: const Icon(Icons.grid_view_outlined),
          selectedIcon: const Icon(Icons.grid_view_rounded),
          label: locale.strings.navMore,
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
