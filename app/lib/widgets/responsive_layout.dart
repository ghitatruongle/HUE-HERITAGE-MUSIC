import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/theme/app_theme.dart';
import 'hue_icons.dart';
import '../services/locale_provider.dart';
import '../services/server_config.dart';
import 'app_logo.dart';
import 'content_max_width.dart';
import '../core/constants/app_constants.dart';

enum NavGroup { listenLearn, create, system, admin }

class NavigationDestinationItem {
  final IconData icon;
  final IconData selectedIcon;
  final String labelKey;
  final Widget screen;
  final NavGroup group;
  final bool pinnedMobile;
  final bool showBetaBadge;

  const NavigationDestinationItem({
    required this.icon,
    required this.selectedIcon,
    required this.labelKey,
    required this.screen,
    this.group = NavGroup.system,
    this.pinnedMobile = false,
    this.showBetaBadge = false,
  });
}

class ResponsiveScaffold extends StatefulWidget {
  final List<NavigationDestinationItem> destinations;
  final int selectedIndex;
  final ValueChanged<int> onDestinationSelected;
  final Widget? floatingActionButton;
  final int sessionEpoch;

  const ResponsiveScaffold({
    super.key,
    required this.destinations,
    required this.selectedIndex,
    required this.onDestinationSelected,
    this.floatingActionButton,
    this.sessionEpoch = 0,
  });

  @override
  State<ResponsiveScaffold> createState() => _ResponsiveScaffoldState();
}

class _ResponsiveScaffoldState extends State<ResponsiveScaffold> {
  final GlobalKey _contentKey = GlobalKey();
  bool _isSidebarCollapsed = false;
  final Set<int> _visitedTabs = {};

  @override
  void didUpdateWidget(covariant ResponsiveScaffold oldWidget) {
    super.didUpdateWidget(oldWidget);
    final maxLen = widget.destinations.length;
    if (maxLen <= 0) {
      _visitedTabs.clear();
      return;
    }
    final clamped = widget.selectedIndex.clamp(0, maxLen - 1);
    if (oldWidget.sessionEpoch != widget.sessionEpoch) {
      _visitedTabs
        ..clear()
        ..add(clamped);
    } else {
      _visitedTabs.removeWhere((i) => i >= maxLen);
      _visitedTabs.add(clamped);
    }
  }

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    final isDesktop = width >= AppBreakpoints.desktop;
    final locale = context.watch<LocaleProvider>();
    final server = context.watch<ServerConfig>();
    if (widget.destinations.isNotEmpty) {
      _visitedTabs.add(widget.selectedIndex.clamp(0, widget.destinations.length - 1));
    }
    final contentArea = _buildContentArea();

    return PopScope(
      canPop: widget.selectedIndex == 0,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && widget.selectedIndex != 0) {
          widget.onDestinationSelected(0);
        }
      },
      child: Scaffold(
      floatingActionButton: widget.floatingActionButton,
      body: Column(
        children: [
          Expanded(
            child: isDesktop
                ? _buildDesktopLayout(context, locale, server, contentArea)
                : _buildMobileLayout(contentArea),
          ),
        ],
      ),
      bottomNavigationBar: isDesktop ? null : _buildMobileBottomBar(context, locale),
      ),
    );
  }

  Widget _buildContentArea() {
    if (widget.destinations.isEmpty) {
      return SizedBox.shrink(key: _contentKey);
    }
    final clamped = widget.selectedIndex.clamp(0, widget.destinations.length - 1);
    return KeyedSubtree(
      key: _contentKey,
      child: ContentMaxWidth(
        maxWidth: 1360,
        child: _TabMotion(
          index: clamped,
          child: _LazyIndexedStack(
            key: ValueKey<int>(widget.sessionEpoch),
            index: clamped,
            visited: _visitedTabs,
            children: [for (final d in widget.destinations) d.screen],
          ),
        ),
      ),
    );
  }

  Widget _buildDesktopLayout(
    BuildContext context,
    LocaleProvider locale,
    ServerConfig server,
    Widget contentArea,
  ) {
    final sidebarBg = Theme.of(context).colorScheme.surfaceContainerHighest;
    final borderColor = Theme.of(context).colorScheme.outline;

    return Row(
      children: [
        AnimatedContainer(
          duration: MediaQuery.disableAnimationsOf(context) ? Duration.zero : AppMotion.base,
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
                  vertical: AppSpacing.sm,
                ),
                child: _isSidebarCollapsed
                    ? Column(
                        children: [
                          IconButton(
                            icon: const HueIcon(HueIcons.menu, size: 22),
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
                              borderRadius: BorderRadius.circular(AppRadius.md),
                              border: Border.all(color: AppTheme.imperialGold.withValues(alpha: 0.85), width: 1.2),
                            ),
                            child: const AppLogo(size: 36, borderRadius: 10, iconSize: 20, iconColor: Colors.white),
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
                              borderRadius: BorderRadius.circular(AppRadius.md),
                              border: Border.all(color: AppTheme.imperialGold.withValues(alpha: 0.85), width: 1.3),
                              boxShadow: [
                                BoxShadow(
                                  color: AppTheme.primaryPurple.withValues(alpha: 0.3),
                                  blurRadius: 8,
                                  offset: const Offset(0, 3),
                                ),
                              ],
                            ),
                            child: const AppLogo(size: 40, iconSize: 22, iconColor: Colors.white),
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
                                  style: TextStyle(
                                    fontWeight: FontWeight.w700,
                                    fontSize: AppFontSize.lg,
                                    fontFamily: AppTheme.displayFontFamily,
                                    color: Theme.of(context).colorScheme.onSurface,
                                  ),
                                ),
                                Text(
                                  locale.strings.sidebarTagline,
                                  style: TextStyle(
                                    fontSize: AppFontSize.xs,
                                    color: AppTheme.goldReadable(context),
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          IconButton(
                            icon: const HueIcon(HueIcons.menuOpen, size: 20),
                            tooltip: locale.strings.collapseSidebar,
                            onPressed: () => setState(() => _isSidebarCollapsed = true),
                          ),
                        ],
                      ),
              ),
              const Divider(height: 1),
              Expanded(
                child: _isSidebarCollapsed
                    ? ListView.builder(
                        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm, vertical: AppSpacing.md),
                        itemCount: widget.destinations.length,
                        itemBuilder: (context, index) => _collapsedNavTile(context, index),
                      )
                    : ListView(
                        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.xs),
                        children: _groupedNavRows(context, locale, collapsed: false),
                      ),
              ),
              const Divider(height: 1),
              Container(
                padding: EdgeInsets.symmetric(
                  horizontal: _isSidebarCollapsed ? 8 : 14,
                  vertical: AppSpacing.xs,
                ),
                child: _isSidebarCollapsed
                    ? Tooltip(
                        message: server.hasServer ? locale.strings.serverOnline : locale.strings.serverOffline,
                        child: Container(
                          width: 8,
                          height: 8,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: server.hasServer ? AppTheme.emeraldReadable(context) : AppTheme.statusReadable(context, AppStatusKind.danger),
                          ),
                        ),
                      )
                    : Container(
                        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.xs),
                        decoration: BoxDecoration(
                          color: Theme.of(context).colorScheme.surface,
                          borderRadius: BorderRadius.circular(AppRadius.sm),
                          border: Border.all(color: Theme.of(context).colorScheme.outline.withValues(alpha: 0.6)),
                        ),
                        child: Row(
                          children: [
                            Container(
                              width: 8,
                              height: 8,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: server.hasServer ? AppTheme.emeraldReadable(context) : AppTheme.statusReadable(context, AppStatusKind.danger),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                server.hasServer ? locale.strings.serverOnline : locale.strings.serverOffline,
                                style: TextStyle(fontSize: AppFontSize.xs, fontWeight: FontWeight.w600, color: Theme.of(context).colorScheme.onSurfaceVariant),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                      ),
              ),
            ],
          ),
        ),
        Expanded(
          child: contentArea,
        ),
      ],
    );
  }

  List<Widget> _groupedNavRows(BuildContext context, LocaleProvider locale, {required bool collapsed}) {
    final rows = <Widget>[];
    final homeIndex = widget.destinations.indexWhere((d) => d.labelKey == 'home');
    if (homeIndex != -1) {
      rows.add(_expandedNavTile(context, homeIndex));
    }
    final groups = <(NavGroup, String)>[
      (NavGroup.listenLearn, locale.strings.navGroupListen),
      (NavGroup.create, locale.strings.navGroupCreate),
      (NavGroup.system, locale.strings.navGroupSystem),
      (NavGroup.admin, locale.strings.navGroupAdmin),
    ];
    for (final (group, groupLabel) in groups) {
      final indices = <int>[
        for (var i = 0; i < widget.destinations.length; i++)
          if (widget.destinations[i].group == group && widget.destinations[i].labelKey != 'home') i,
      ];
      if (indices.isEmpty) continue;
      rows.add(
        Padding(
          padding: const EdgeInsets.fromLTRB(AppSpacing.lg, AppSpacing.xs, AppSpacing.sm, AppSpacing.xs),
          child: Text(
            groupLabel.toUpperCase(),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.8,
                ),
          ),
        ),
      );
      for (final i in indices) {
        rows.add(_expandedNavTile(context, i));
      }
    }
    return rows;
  }

  Widget _collapsedNavTile(BuildContext context, int index) {
    final item = widget.destinations[index];
    final isSelected = widget.selectedIndex == index;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final label = _resolveNavLabel(item.labelKey, context.read<LocaleProvider>());
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: Semantics(
        button: true,
        selected: isSelected,
        label: label,
        child: Tooltip(
          message: label,
          preferBelow: false,
          child: Material(
            color: isSelected
                ? AppTheme.primaryPurple.withValues(alpha: isDark ? 0.3 : 0.15)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(AppRadius.md),
            child: InkWell(
              borderRadius: BorderRadius.circular(AppRadius.md),
              onTap: () => widget.onDestinationSelected(index),
              child: Container(
                width: 48,
                height: 48,
                alignment: Alignment.center,
                child: HueIcon(
                  isSelected ? item.selectedIcon : item.icon,
                  size: 22,
                  color: isSelected
                      ? (isDark ? AppTheme.primaryPurpleGlow : AppTheme.primaryPurple)
                      : Theme.of(context).colorScheme.onSurfaceVariant,
                  decorative: true,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _expandedNavTile(BuildContext context, int index) {
    final item = widget.destinations[index];
    final isSelected = widget.selectedIndex == index;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final locale = context.read<LocaleProvider>();
    final label = _resolveNavLabel(item.labelKey, locale);
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.xs),
      child: Semantics(
        button: true,
        selected: isSelected,
        child: Material(
          color: isSelected
              ? AppTheme.primaryPurple.withValues(alpha: isDark ? 0.25 : 0.15)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(AppRadius.md),
          child: InkWell(
            borderRadius: BorderRadius.circular(AppRadius.md),
            onTap: () => widget.onDestinationSelected(index),
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 48),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.sm),
                child: Row(
                children: [
                  HueIcon(
                    isSelected ? item.selectedIcon : item.icon,
                    size: 20,
                    color: isSelected
                        ? (isDark ? AppTheme.primaryPurpleGlow : AppTheme.primaryPurple)
                        : Theme.of(context).colorScheme.onSurfaceVariant,
                    decorative: true,
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
                            fontSize: AppFontSize.md,
                            color: isSelected
                                ? (isDark ? AppTheme.primaryPurpleGlow : AppTheme.primaryPurple)
                                : Theme.of(context).colorScheme.onSurface,
                          ),
                        ),
                      ),
                      if (item.showBetaBadge) ...[
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xs, vertical: 0),
                          decoration: BoxDecoration(
                            color: AppTheme.goldReadable(context).withValues(alpha: 0.2),
                            borderRadius: BorderRadius.circular(AppRadius.xs),
                            border: Border.all(color: AppTheme.goldReadable(context), width: 0.8),
                          ),
                          child: Text('BETA', style: TextStyle(color: AppTheme.goldReadable(context), fontSize: AppFontSize.xs, fontWeight: FontWeight.bold)),
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
                      borderRadius: BorderRadius.circular(AppRadius.xs),
                    ),
                  ),
              ],
              ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildMobileLayout(Widget contentArea) => contentArea;

  void _showAllDestinationsSheet(BuildContext context, LocaleProvider locale) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.xl)),
      ),
      builder: (ctx) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: AppSpacing.lg, horizontal: AppSpacing.md),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.sm),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        locale.strings.navMore,
                        style: Theme.of(ctx).textTheme.titleLarge,
                      ),
                      IconButton(
                        tooltip: locale.strings.closeBtn,
                        icon: const HueIcon(HueIcons.close),
                        onPressed: () => Navigator.pop(ctx),
                      ),
                    ],
                  ),
                ),
                const Divider(),
                Flexible(
                  child: ListView(
                    shrinkWrap: true,
                    children: [
                      for (final row in _groupedSheetRows(ctx, locale)) row,
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  List<Widget> _groupedSheetRows(BuildContext context, LocaleProvider locale) {
    final rows = <Widget>[];
    final homeIndex = widget.destinations.indexWhere((d) => d.labelKey == 'home');
    if (homeIndex != -1) {
      rows.add(_sheetTile(context, homeIndex, locale));
    }
    final groups = <(NavGroup, String)>[
      (NavGroup.listenLearn, locale.strings.navGroupListen),
      (NavGroup.create, locale.strings.navGroupCreate),
      (NavGroup.system, locale.strings.navGroupSystem),
      (NavGroup.admin, locale.strings.navGroupAdmin),
    ];
    for (final (group, groupLabel) in groups) {
      final indices = <int>[
        for (var i = 0; i < widget.destinations.length; i++)
          if (widget.destinations[i].group == group && widget.destinations[i].labelKey != 'home') i,
      ];
      if (indices.isEmpty) continue;
      rows.add(
        Padding(
          padding: const EdgeInsets.fromLTRB(AppSpacing.lg, AppSpacing.md, AppSpacing.md, AppSpacing.xs),
          child: Text(
            groupLabel.toUpperCase(),
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.8,
                ),
          ),
        ),
      );
      for (final i in indices) {
        rows.add(_sheetTile(context, i, locale));
      }
    }
    return rows;
  }

  Widget _sheetTile(BuildContext context, int i, LocaleProvider locale) {
    final item = widget.destinations[i];
    final isSelected = widget.selectedIndex == i;
    final primary = Theme.of(context).colorScheme.primary;
    return ListTile(
      leading: HueIcon(
        isSelected ? item.selectedIcon : item.icon,
        color: isSelected ? primary : null,
        decorative: true,
      ),
      title: Row(
        children: [
          Flexible(
            child: Text(
              _resolveNavLabel(item.labelKey, locale),
              style: TextStyle(
                fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                color: isSelected ? primary : null,
              ),
            ),
          ),
          if (item.showBetaBadge) ...[
            const SizedBox(width: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xs, vertical: 0),
              decoration: BoxDecoration(
                color: AppTheme.goldReadable(context).withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(AppRadius.xs),
                border: Border.all(color: AppTheme.goldReadable(context), width: 0.8),
              ),
              child: Text('BETA', style: TextStyle(color: AppTheme.goldReadable(context), fontSize: AppFontSize.xs, fontWeight: FontWeight.bold)),
            ),
          ],
        ],
      ),
      trailing: isSelected
          ? HueIcon(HueIcons.check, color: primary, size: 20)
          : null,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.md)),
      onTap: () {
        Navigator.pop(context);
        widget.onDestinationSelected(i);
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
              icon: HueIcon(item.icon, decorative: true),
              selectedIcon: HueIcon(item.selectedIcon, decorative: true),
              label: _resolveNavLabel(item.labelKey, locale),
            ),
        ],
      );
    }

    final topIndices = <int>[
      for (var i = 0; i < widget.destinations.length; i++)
        if (widget.destinations[i].pinnedMobile) i,
    ];
    final fallback = [
      for (var i = 0; i < widget.destinations.length; i++)
        if (!topIndices.contains(i)) i,
    ];
    while (topIndices.length < 4 && fallback.isNotEmpty) {
      topIndices.add(fallback.removeAt(0));
    }
    final moreIndex = topIndices.length;
    final activeInTop = topIndices.indexOf(widget.selectedIndex);
    final currentIndex = activeInTop != -1 ? activeInTop : moreIndex;

    return NavigationBar(
      selectedIndex: currentIndex.clamp(0, moreIndex),
      onDestinationSelected: (index) {
        if (index >= moreIndex) {
          _showAllDestinationsSheet(context, locale);
        } else {
          widget.onDestinationSelected(topIndices[index]);
        }
      },
      destinations: [
        for (final i in topIndices)
          NavigationDestination(
            icon: HueIcon(widget.destinations[i].icon, decorative: true),
            selectedIcon: HueIcon(widget.destinations[i].selectedIcon, decorative: true),
            label: _resolveNavLabel(widget.destinations[i].labelKey, locale),
          ),
        NavigationDestination(
          icon: const HueIcon(HueIcons.gridView),
          selectedIcon: const HueIcon(HueIcons.gridView),
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
      'restoration' => s.navRestoration,
      'history' => s.taskHistoryTitle,
      'settings' => s.settingsTitle,
      'auth' => s.authTitle,
      'admin' => s.navAdmin,
      _ => key,
    };
  }
}

class _TabMotion extends StatefulWidget {
  final int index;
  final Widget child;

  const _TabMotion({required this.index, required this.child});

  @override
  State<_TabMotion> createState() => _TabMotionState();
}

class _TabMotionState extends State<_TabMotion> with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this, duration: AppMotion.fast, value: 1.0);
  }

  @override
  void didUpdateWidget(covariant _TabMotion oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.index != widget.index) {
      if (MediaQuery.disableAnimationsOf(context)) {
        _ctrl.stop();
        _ctrl.value = 1.0;
      } else {
        _ctrl.forward(from: 0);
      }
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (context, child) {
        final t = AppMotion.emphasized.transform(_ctrl.value);
        return Opacity(
          opacity: t.clamp(0.0, 1.0),
          child: FractionalTranslation(
            translation: Offset(0.02 * (1 - t), 0),
            child: child,
          ),
        );
      },
      child: widget.child,
    );
  }
}

class _LazyIndexedStack extends StatelessWidget {
  final int index;
  final Set<int> visited;
  final List<Widget> children;

  const _LazyIndexedStack({
    super.key,
    required this.index,
    required this.visited,
    required this.children,
  });

  @override
  Widget build(BuildContext context) {
    return IndexedStack(
      index: index,
      children: [
        for (var i = 0; i < children.length; i++)
          (i == index || visited.contains(i)) ? children[i] : const SizedBox.shrink(),
      ],
    );
  }
}
