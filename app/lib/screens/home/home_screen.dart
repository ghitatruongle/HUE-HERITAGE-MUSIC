import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/constants/app_constants.dart';
import '../../core/theme/app_theme.dart';
import '../../services/locale_provider.dart';
import '../../services/server_config.dart';
import '../../widgets/responsive_layout.dart';
import '../analysis/analysis_screen.dart';
import '../creation/creation_screen.dart';
import '../heritage/heritage_list_screen.dart';
import '../history/history_screen.dart';
import '../learning/learning_screen.dart';
import '../restoration/restoration_screen.dart';
import '../settings/settings_screen.dart';
import '../transcription/transcription_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _navIndex = 0;

  @override
  Widget build(BuildContext context) {
    final destinations = [
      NavigationDestinationItem(
        icon: Icons.home_outlined,
        selectedIcon: Icons.home,
        labelKey: 'home',
        screen: _HomeContent(onSelectTab: (idx) => setState(() => _navIndex = idx)),
      ),
      const NavigationDestinationItem(
        icon: Icons.library_music_outlined,
        selectedIcon: Icons.library_music,
        labelKey: 'heritage',
        screen: HeritageListScreen(),
      ),
      const NavigationDestinationItem(
        icon: Icons.healing_outlined,
        selectedIcon: Icons.healing,
        labelKey: 'restoration',
        screen: RestorationScreen(),
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
    ];

    return ResponsiveScaffold(
      destinations: destinations,
      selectedIndex: _navIndex,
      onDestinationSelected: (idx) => setState(() => _navIndex = idx),
    );
  }
}

class _HomeContent extends StatelessWidget {
  final void Function(int) onSelectTab;

  const _HomeContent({required this.onSelectTab});

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
        tabIndex: 1,
      ),
      _Feature(
        icon: Icons.healing,
        color: const Color(0xFF00695C),
        title: strings.featRestorationTitle,
        subtitle: strings.featRestorationDesc,
        tabIndex: 2,
      ),
      _Feature(
        icon: Icons.mic,
        color: AppTheme.primaryPurple,
        title: strings.featLearningTitle,
        subtitle: strings.featLearningDesc,
        tabIndex: 3,
      ),
      _Feature(
        icon: Icons.query_stats,
        color: const Color(0xFF2A5FA5),
        title: strings.featAnalysisTitle,
        subtitle: strings.featAnalysisDesc,
        tabIndex: 4,
      ),
      _Feature(
        icon: Icons.music_note,
        color: const Color(0xFF8F6C00),
        title: strings.featTranscriptionTitle,
        subtitle: strings.featTranscriptionDesc,
        tabIndex: 5,
      ),
      _Feature(
        icon: Icons.auto_awesome,
        color: const Color(0xFFAD3B6F),
        title: strings.featCreationTitle,
        subtitle: strings.featCreationDesc,
        tabIndex: 6,
      ),
      _Feature(
        icon: Icons.history,
        color: const Color(0xFF5D4037),
        title: strings.featHistoryTitle,
        subtitle: strings.featHistoryDesc,
        tabIndex: 7,
      ),
      _Feature(
        icon: Icons.settings_outlined,
        color: const Color(0xFF546E7A),
        title: strings.settingsTitle,
        subtitle: locale.isVietnamese
            ? 'Cấu hình kết nối máy chủ AI, giao diện và ngôn ngữ'
            : 'Configure AI server connection, UI theme and language',
        tabIndex: 8,
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
            Text(
              strings.featuresHeader,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
            ),
            const SizedBox(height: 14),
            if (crossAxisCount == 1)
              for (final f in features) ...[
                _FeatureCard(feature: f, onSelect: () => onSelectTab(f.tabIndex)),
                const SizedBox(height: 12),
              ]
            else
              GridView.count(
                crossAxisCount: crossAxisCount,
                crossAxisSpacing: 16,
                mainAxisSpacing: 16,
                childAspectRatio: crossAxisCount == 3 ? 1.6 : 1.9,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                children: [
                  for (final f in features)
                    _FeatureCard(feature: f, onSelect: () => onSelectTab(f.tabIndex)),
                ],
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

class _Feature {
  final IconData icon;
  final Color color;
  final String title;
  final String subtitle;
  final int tabIndex;

  const _Feature({
    required this.icon,
    required this.color,
    required this.title,
    required this.subtitle,
    required this.tabIndex,
  });
}

class _FeatureCard extends StatefulWidget {
  final _Feature feature;
  final VoidCallback onSelect;

  const _FeatureCard({required this.feature, required this.onSelect});

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
            onTap: widget.onSelect,
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
                        Row(
                          children: [
                            Flexible(
                              child: Text(
                                widget.feature.title,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                                      fontWeight: FontWeight.w700,
                                      color: scheme.onSurface,
                                    ),
                              ),
                            ),
                            if (widget.feature.title.contains('Beta')) ...[
                              const SizedBox(width: 8),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
                                decoration: BoxDecoration(
                                  color: AppTheme.amberGold.withValues(alpha: 0.2),
                                  borderRadius: BorderRadius.circular(4),
                                  border: Border.all(color: AppTheme.amberGold, width: 0.8),
                                ),
                                child: const Text('BETA', style: TextStyle(color: AppTheme.amberGold, fontSize: 10, fontWeight: FontWeight.bold)),
                              ),
                            ],
                          ],
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
