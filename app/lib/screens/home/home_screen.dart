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
        double childAspectRatio = 3.2;

        if (width >= 960) {
          crossAxisCount = 4;
          childAspectRatio = 2.1;
        } else if (width >= 620) {
          crossAxisCount = 2;
          childAspectRatio = 2.3;
        } else {
          crossAxisCount = 1;
          childAspectRatio = 3.6;
        }

        return SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildHeroHeader(context, strings, server),
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    strings.featuresHeader,
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w800,
                          fontSize: 15,
                        ),
                  ),
                  Text(
                    strings.modulesCount(features.length),
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: AppTheme.amberGold,
                          fontWeight: FontWeight.w600,
                        ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              GridView.count(
                crossAxisCount: crossAxisCount,
                crossAxisSpacing: 12,
                mainAxisSpacing: 12,
                childAspectRatio: childAspectRatio,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                children: [
                  for (final f in features)
                    _FeatureCard(feature: f, onSelect: () => onSelectTab(f.tabIndex)),
                ],
              ),
              const SizedBox(height: 20),
              Center(
                child: Text(
                  'Hue Heritage Music · ${strings.versionLabel} ${AppConstants.appVersion}',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                        fontSize: 11,
                      ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildHeroHeader(BuildContext context, dynamic strings, ServerConfig server) {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        gradient: const LinearGradient(
          colors: [Color(0xFF2A1545), Color(0xFF4A2B78), Color(0xFF6B3FA0)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF5B3B8C).withValues(alpha: 0.25),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              color: Colors.white.withValues(alpha: 0.15),
              border: Border.all(color: Colors.white.withValues(alpha: 0.25)),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: Image.asset(
                'assets/images/app_logo.png',
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => const Icon(Icons.music_note, color: Colors.white, size: 24),
              ),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  strings.appTitle,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 17,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.2,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  strings.appSubtitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.88),
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: (server.hasServer ? AppTheme.emeraldGreen : Colors.redAccent).withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: (server.hasServer ? AppTheme.emeraldGreen : Colors.redAccent).withValues(alpha: 0.6),
                width: 0.8,
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 7,
                  height: 7,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: server.hasServer ? AppTheme.emeraldGreen : Colors.redAccent,
                  ),
                ),
                const SizedBox(width: 6),
                Text(
                  server.hasServer ? strings.serverOnline : strings.serverOffline,
                  style: TextStyle(
                    color: server.hasServer ? AppTheme.emeraldGreen : Colors.redAccent,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
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
        duration: const Duration(milliseconds: 160),
        decoration: BoxDecoration(
          color: _isHovered
              ? scheme.surfaceContainerHighest
              : scheme.surfaceContainerHighest.withValues(alpha: 0.45),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: _isHovered ? hoverBorder : baseBorder,
            width: _isHovered ? 1.4 : 1.0,
          ),
          boxShadow: _isHovered
              ? [
                  BoxShadow(
                    color: AppTheme.primaryPurple.withValues(alpha: isDark ? 0.2 : 0.08),
                    blurRadius: 10,
                    offset: const Offset(0, 4),
                  ),
                ]
              : null,
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(14),
            onTap: widget.onSelect,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              child: Row(
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: widget.feature.color.withValues(alpha: 0.14),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(widget.feature.icon, color: widget.feature.color, size: 22),
                  ),
                  const SizedBox(width: 12),
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
                                      fontSize: 13,
                                      color: scheme.onSurface,
                                    ),
                              ),
                            ),
                            if (widget.feature.title.contains('Beta')) ...[
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
                        const SizedBox(height: 2),
                        Text(
                          widget.feature.subtitle,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 11,
                            color: scheme.onSurfaceVariant.withValues(alpha: 0.85),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 6),
                  Icon(
                    Icons.arrow_forward_ios_rounded,
                    size: 13,
                    color: _isHovered ? AppTheme.primaryPurple : scheme.onSurfaceVariant.withValues(alpha: 0.4),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
