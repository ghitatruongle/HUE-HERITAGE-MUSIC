import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/constants/app_constants.dart';
import '../../core/theme/app_theme.dart';
import '../../services/locale_provider.dart';
import '../../services/server_config.dart';
import '../../services/theme_provider.dart';
import '../../widgets/docked_player_bar.dart';
import '../../widgets/responsive_layout.dart';
import '../analysis/analysis_screen.dart';
import '../creation/creation_screen.dart';
import '../heritage/heritage_list_screen.dart';
import '../history/history_screen.dart';
import '../info/info_screen.dart';
import '../instruments/instruments_screen.dart';
import '../learning/learning_screen.dart';
import '../settings/settings_screen.dart';
import '../transcription/transcription_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _navIndex = 0;

  void _openPage(BuildContext context, String title, Widget page) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => Scaffold(
          appBar: AppBar(title: Text(title)),
          body: SafeArea(child: page),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    final isDesktop = width >= 860;

    final destinations = [
      NavigationDestinationItem(
        icon: Icons.home_outlined,
        selectedIcon: Icons.home,
        labelKey: 'home',
        screen: _HomeContent(onOpen: _openPage),
      ),
      const NavigationDestinationItem(
        icon: Icons.library_music_outlined,
        selectedIcon: Icons.library_music,
        labelKey: 'heritage',
        screen: HeritageListScreen(),
      ),
      const NavigationDestinationItem(
        icon: Icons.mic_outlined,
        selectedIcon: Icons.mic,
        labelKey: 'learning',
        screen: LearningScreen(),
      ),
      const NavigationDestinationItem(
        icon: Icons.query_stats_outlined,
        selectedIcon: Icons.query_stats,
        labelKey: 'analysis',
        screen: AnalysisScreen(),
      ),
      const NavigationDestinationItem(
        icon: Icons.music_note_outlined,
        selectedIcon: Icons.music_note,
        labelKey: 'transcription',
        screen: TranscriptionScreen(),
      ),
      const NavigationDestinationItem(
        icon: Icons.auto_awesome_outlined,
        selectedIcon: Icons.auto_awesome,
        labelKey: 'creation',
        screen: CreationScreen(),
      ),
      const NavigationDestinationItem(
        icon: Icons.shuffle_outlined,
        selectedIcon: Icons.shuffle,
        labelKey: 'cover',
        screen: CreationScreen(coverMode: true),
      ),
      const NavigationDestinationItem(
        icon: Icons.healing_outlined,
        selectedIcon: Icons.healing,
        labelKey: 'restoration',
        screen: HeritageListScreen(restorationMode: true),
      ),
      const NavigationDestinationItem(
        icon: Icons.piano_outlined,
        selectedIcon: Icons.piano,
        labelKey: 'instruments',
        screen: InstrumentsScreen(),
      ),
      const NavigationDestinationItem(
        icon: Icons.history_outlined,
        selectedIcon: Icons.history,
        labelKey: 'history',
        screen: HistoryScreen(),
      ),
      const NavigationDestinationItem(
        icon: Icons.settings_outlined,
        selectedIcon: Icons.settings,
        labelKey: 'settings',
        screen: SettingsScreen(),
      ),
      const NavigationDestinationItem(
        icon: Icons.info_outline,
        selectedIcon: Icons.info,
        labelKey: 'info',
        screen: InfoScreen(),
      ),
    ];

    if (isDesktop) {
      return ResponsiveScaffold(
        destinations: destinations,
        selectedIndex: _navIndex,
        onDestinationSelected: (idx) => setState(() => _navIndex = idx),
      );
    }

    final locale = context.watch<LocaleProvider>();
    final theme = context.watch<ThemeProvider>();

    return Scaffold(
      appBar: AppBar(
        title: Text(locale.strings.appTitle),
        actions: [
          OutlinedButton(
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              minimumSize: Size.zero,
            ),
            onPressed: () => locale.toggleLanguage(),
            child: Text(locale.isVietnamese ? 'VI' : 'EN', style: const TextStyle(fontSize: 12)),
          ),
          const SizedBox(width: 4),
          IconButton(
            icon: Icon(theme.isDark ? Icons.light_mode : Icons.dark_mode),
            tooltip: locale.strings.themeModeTitle,
            onPressed: () => theme.toggleTheme(context),
          ),
          IconButton(
            icon: const Icon(Icons.settings_outlined),
            tooltip: locale.strings.settingsTitle,
            onPressed: () => _openPage(context, locale.strings.settingsTitle, const SettingsScreen()),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: _navIndex == 4
                  ? _MoreContent(onOpen: _openPage)
                  : destinations[_navIndex].screen,
            ),
            const DockedPlayerBar(),
          ],
        ),
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _navIndex < 5 ? _navIndex : 0,
        onDestinationSelected: (idx) => setState(() => _navIndex = idx),
        destinations: [
          NavigationDestination(
            icon: const Icon(Icons.home_outlined),
            selectedIcon: const Icon(Icons.home),
            label: locale.strings.navHome,
          ),
          NavigationDestination(
            icon: const Icon(Icons.library_music_outlined),
            selectedIcon: const Icon(Icons.library_music),
            label: locale.strings.navHeritage,
          ),
          NavigationDestination(
            icon: const Icon(Icons.mic_outlined),
            selectedIcon: const Icon(Icons.mic),
            label: locale.strings.navLearning,
          ),
          NavigationDestination(
            icon: const Icon(Icons.query_stats_outlined),
            selectedIcon: const Icon(Icons.query_stats),
            label: locale.strings.navAnalysis,
          ),
          NavigationDestination(
            icon: const Icon(Icons.more_horiz),
            label: locale.strings.featuresHeader,
          ),
        ],
      ),
    );
  }
}

class _HomeContent extends StatelessWidget {
  final void Function(BuildContext, String, Widget) onOpen;

  const _HomeContent({required this.onOpen});

  @override
  Widget build(BuildContext context) {
    final locale = context.watch<LocaleProvider>();
    final strings = locale.strings;
    final server = context.watch<ServerConfig>();

    final features = [
      _Feature(
        icon: Icons.library_music,
        color: const Color(0xFF00796B),
        title: strings.featHeritageTitle,
        subtitle: strings.featHeritageDesc,
        page: const HeritageListScreen(),
        screenTitle: strings.featHeritageTitle,
      ),
      _Feature(
        icon: Icons.mic,
        color: AppTheme.primaryPurple,
        title: strings.featLearningTitle,
        subtitle: strings.featLearningDesc,
        page: const LearningScreen(),
        screenTitle: strings.featLearningTitle,
      ),
      _Feature(
        icon: Icons.query_stats,
        color: const Color(0xFF2A5FA5),
        title: strings.featAnalysisTitle,
        subtitle: strings.featAnalysisDesc,
        page: const AnalysisScreen(),
        screenTitle: strings.featAnalysisTitle,
      ),
      _Feature(
        icon: Icons.music_note,
        color: const Color(0xFF8F6C00),
        title: strings.featTranscriptionTitle,
        subtitle: strings.featTranscriptionDesc,
        page: const TranscriptionScreen(),
        screenTitle: strings.featTranscriptionTitle,
      ),
      _Feature(
        icon: Icons.auto_awesome,
        color: const Color(0xFFAD3B6F),
        title: strings.featCreationTitle,
        subtitle: strings.featCreationDesc,
        page: const CreationScreen(),
        screenTitle: strings.featCreationTitle,
      ),
      _Feature(
        icon: Icons.shuffle,
        color: const Color(0xFFB34700),
        title: strings.featCoverTitle,
        subtitle: strings.featCoverDesc,
        page: const CreationScreen(coverMode: true),
        screenTitle: strings.featCoverTitle,
      ),
      _Feature(
        icon: Icons.healing,
        color: const Color(0xFF00695C),
        title: strings.featRestorationTitle,
        subtitle: strings.featRestorationDesc,
        page: const HeritageListScreen(restorationMode: true),
        screenTitle: strings.featRestorationTitle,
      ),
      _Feature(
        icon: Icons.piano,
        color: const Color(0xFF4A5F2A),
        title: strings.featInstrumentsTitle,
        subtitle: strings.featInstrumentsDesc,
        page: const InstrumentsScreen(),
        screenTitle: strings.featInstrumentsTitle,
      ),
      _Feature(
        icon: Icons.history,
        color: const Color(0xFF5D4037),
        title: strings.featHistoryTitle,
        subtitle: strings.featHistoryDesc,
        page: const HistoryScreen(),
        screenTitle: strings.featHistoryTitle,
      ),
      _Feature(
        icon: Icons.info_outline,
        color: const Color(0xFF455A64),
        title: strings.featInfoTitle,
        subtitle: strings.featInfoDesc,
        page: const InfoScreen(),
        screenTitle: strings.featInfoTitle,
      ),
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        int crossAxisCount = 1;
        if (width >= 1100) {
          crossAxisCount = 3;
        } else if (width >= 620) {
          crossAxisCount = 2;
        }

        return ListView(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
          children: [
            _buildHeroBanner(context, strings, server),
            const SizedBox(height: 24),
            Row(
              children: [
                Text(
                  strings.featuresHeader,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                ),
                const Spacer(),
                Text(
                  strings.modulesCount(features.length),
                  style: TextStyle(
                    fontSize: 12,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            if (crossAxisCount == 1)
              for (final f in features) ...[
                _FeatureCard(feature: f, onOpen: onOpen),
                const SizedBox(height: 12),
              ]
            else
              GridView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: features.length,
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: crossAxisCount,
                  mainAxisExtent: 108,
                  crossAxisSpacing: 14,
                  mainAxisSpacing: 14,
                ),
                itemBuilder: (context, idx) => _FeatureCard(
                  feature: features[idx],
                  onOpen: onOpen,
                ),
              ),
            const SizedBox(height: 24),
            Text(
              'Hue Heritage Music · ${strings.versionLabel} ${AppConstants.appVersion}',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildHeroBanner(BuildContext context, dynamic strings, ServerConfig server) {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        gradient: const LinearGradient(
          colors: [Color(0xFF3B1D66), Color(0xFF5B3B8C), Color(0xFF8B5CF6)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF5B3B8C).withValues(alpha: 0.35),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      padding: const EdgeInsets.all(28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 60,
                height: 60,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(16),
                  color: Colors.white.withValues(alpha: 0.15),
                  border: Border.all(color: Colors.white.withValues(alpha: 0.3)),
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(16),
                  child: Image.asset(
                    'assets/images/app_logo.png',
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => const Icon(Icons.music_note, color: Colors.white, size: 32),
                  ),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      strings.appTitle,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 22,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.3,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                      decoration: BoxDecoration(
                        color: AppTheme.amberGold.withValues(alpha: 0.25),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: AppTheme.amberGold.withValues(alpha: 0.5)),
                      ),
                      child: Text(
                        server.hasServer ? strings.serverOnline : strings.serverOffline,
                        style: const TextStyle(
                          color: AppTheme.amberGold,
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          Text(
            strings.appSubtitle,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.92),
              fontSize: 14,
              height: 1.55,
            ),
          ),
        ],
      ),
    );
  }
}

class _MoreContent extends StatelessWidget {
  final void Function(BuildContext, String, Widget) onOpen;

  const _MoreContent({required this.onOpen});

  @override
  Widget build(BuildContext context) {
    final strings = context.watch<LocaleProvider>().strings;
    final features = [
      _Feature(
        icon: Icons.auto_awesome,
        color: const Color(0xFFAD3B6F),
        title: strings.featCreationTitle,
        subtitle: strings.featCreationDesc,
        page: const CreationScreen(),
        screenTitle: strings.featCreationTitle,
      ),
      _Feature(
        icon: Icons.shuffle,
        color: const Color(0xFFB34700),
        title: strings.featCoverTitle,
        subtitle: strings.featCoverDesc,
        page: const CreationScreen(coverMode: true),
        screenTitle: strings.featCoverTitle,
      ),
      _Feature(
        icon: Icons.healing,
        color: const Color(0xFF00695C),
        title: strings.featRestorationTitle,
        subtitle: strings.featRestorationDesc,
        page: const HeritageListScreen(restorationMode: true),
        screenTitle: strings.featRestorationTitle,
      ),
      _Feature(
        icon: Icons.piano,
        color: const Color(0xFF4A5F2A),
        title: strings.featInstrumentsTitle,
        subtitle: strings.featInstrumentsDesc,
        page: const InstrumentsScreen(),
        screenTitle: strings.featInstrumentsTitle,
      ),
      _Feature(
        icon: Icons.history,
        color: const Color(0xFF5D4037),
        title: strings.featHistoryTitle,
        subtitle: strings.featHistoryDesc,
        page: const HistoryScreen(),
        screenTitle: strings.featHistoryTitle,
      ),
      _Feature(
        icon: Icons.info_outline,
        color: const Color(0xFF455A64),
        title: strings.featInfoTitle,
        subtitle: strings.featInfoDesc,
        page: const InfoScreen(),
        screenTitle: strings.featInfoTitle,
      ),
    ];

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
      children: [
        Text(
          strings.featuresHeader,
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w800,
              ),
        ),
        const SizedBox(height: 14),
        for (final f in features) ...[
          _FeatureCard(feature: f, onOpen: onOpen),
          const SizedBox(height: 12),
        ],
      ],
    );
  }
}

class _Feature {
  final IconData icon;
  final Color color;
  final String title;
  final String subtitle;
  final Widget page;
  final String screenTitle;

  const _Feature({
    required this.icon,
    required this.color,
    required this.title,
    required this.subtitle,
    required this.page,
    required this.screenTitle,
  });
}

class _FeatureCard extends StatefulWidget {
  final _Feature feature;
  final void Function(BuildContext, String, Widget) onOpen;

  const _FeatureCard({required this.feature, required this.onOpen});

  @override
  State<_FeatureCard> createState() => _FeatureCardState();
}

class _FeatureCardState extends State<_FeatureCard> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final baseBorder = isDark ? const Color(0xFF2E2B48) : const Color(0xFFE4DFEE);
    const hoverBorder = AppTheme.primaryPurpleGlow;

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        decoration: BoxDecoration(
          color: _isHovered
              ? scheme.surfaceContainerHighest
              : scheme.surfaceContainerHighest.withValues(alpha: 0.5),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: _isHovered ? hoverBorder : baseBorder,
            width: _isHovered ? 1.5 : 1.0,
          ),
          boxShadow: _isHovered
              ? [
                  BoxShadow(
                    color: AppTheme.primaryPurple.withValues(alpha: isDark ? 0.25 : 0.12),
                    blurRadius: 14,
                    offset: const Offset(0, 6),
                  ),
                ]
              : null,
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(20),
            onTap: () => widget.onOpen(context, widget.feature.screenTitle, widget.feature.page),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Container(
                    width: 52,
                    height: 52,
                    decoration: BoxDecoration(
                      color: widget.feature.color.withValues(alpha: 0.16),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Icon(widget.feature.icon, color: widget.feature.color, size: 28),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          widget.feature.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.titleSmall?.copyWith(
                                fontWeight: FontWeight.w700,
                                color: scheme.onSurface,
                              ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          widget.feature.subtitle,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                color: scheme.onSurfaceVariant,
                                height: 1.35,
                              ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Icon(Icons.chevron_right, color: scheme.onSurfaceVariant, size: 20),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
