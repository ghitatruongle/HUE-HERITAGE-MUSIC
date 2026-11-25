import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/constants/app_constants.dart';
import '../../core/theme/app_theme.dart';
import '../../services/auth_service.dart';
import '../../services/history_service.dart';
import '../../services/locale_provider.dart';
import '../../services/practice_resume.dart';
import '../../services/server_config.dart';
import '../../services/session_media.dart';
import '../../widgets/app_logo.dart';
import '../../widgets/avatar_view.dart';
import '../../widgets/empty_state.dart';
import '../../widgets/heritage_motif.dart';
import '../../widgets/hue_icons.dart';
import '../../widgets/server_onboarding_dialog.dart';
import '../../widgets/staggered_entrance.dart';
import '../../widgets/status_colors.dart';
import '../../widgets/responsive_layout.dart';
import '../analysis/analysis_screen.dart';
import '../admin/admin_screen.dart';
import '../auth/login_screen.dart';
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
  int _sessionEpoch = 0;
  bool _onboardingShown = false;
  bool _mcpDialogShown = false;
  String? _trackedUser;
  String? _trackedServer;
  bool _didInitDeps = false;

  void _syncSessionBoundary(BuildContext context, AuthService auth, ServerConfig server) {
    final curUser = auth.isLoggedIn ? (auth.username ?? '') : null;
    final curServer = server.baseUrl;
    if (!_didInitDeps) {
      _didInitDeps = true;
      _trackedUser = curUser;
      _trackedServer = curServer;
      return;
    }
    final loggedOut = _trackedUser != null && curUser == null;
    final userSwitched = _trackedUser != null && curUser != null && curUser != _trackedUser;
    final serverSwitched =
        _trackedServer != null && _trackedServer!.isNotEmpty && curServer.isNotEmpty && curServer != _trackedServer;
    _trackedUser = curUser;
    _trackedServer = curServer;
    if (loggedOut || userSwitched || serverSwitched) {
      _mcpDialogShown = false;
      _sessionEpoch++;
      AvatarView.clearCache();
      final sessionMedia = context.read<SessionMedia>();
      final history = context.read<HistoryService>();
      Future.microtask(() {
        PracticeResume.clear();
        sessionMedia.clearRecording();
        if (mounted) {
          unawaited(history.clear());
        }
      });
    }
  }

  void _maybeShowOnboarding(BuildContext context) {
    final server = context.read<ServerConfig>();
    if (!server.hasServer && !_onboardingShown) {
      _onboardingShown = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        showDialog(
          context: context,
          barrierDismissible: false,
          builder: (_) => const ServerOnboardingDialog(),
        );
      });
    }
  }

  void _maybeShowSessionNotices(BuildContext context) {
    final auth = context.read<AuthService>();
    final strings = context.read<LocaleProvider>().strings;
    if (auth.sessionExpiredNotice) {
      auth.consumeSessionExpiredNotice();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(strings.sessionExpired)),
        );
      });
    }
    if (auth.isLoggedIn && auth.mustChangePassword && !_mcpDialogShown) {
      _mcpDialogShown = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        showDialog<void>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            title: Text(strings.mustChangeTitle),
            content: Text(strings.mustChangeBody),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: Text(strings.mustChangeLater),
              ),
              FilledButton(
                onPressed: () {
                  Navigator.pop(dialogContext);
                  Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const LoginScreen()),
                  );
                },
                child: Text(strings.mustChangeNow),
              ),
            ],
          ),
        );
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthService>();
    final server = context.watch<ServerConfig>();
    _syncSessionBoundary(context, auth, server);
    _maybeShowOnboarding(context);
    _maybeShowSessionNotices(context);
    final destinations = [
      NavigationDestinationItem(
        icon: HueIcons.home,
        selectedIcon: HueIcons.home,
        labelKey: 'home',
        screen: _HomeContent(onSelectTab: (idx) => setState(() => _navIndex = idx)),
        pinnedMobile: true,
      ),
      const NavigationDestinationItem(
        icon: HueIcons.libraryMusic,
        selectedIcon: HueIcons.libraryMusic,
        labelKey: 'heritage',
        screen: HeritageListScreen(),
        group: NavGroup.listenLearn,
        pinnedMobile: true,
      ),
      const NavigationDestinationItem(
        icon: HueIcons.healing,
        selectedIcon: HueIcons.healing,
        labelKey: 'restoration',
        screen: RestorationScreen(),
        group: NavGroup.create,
        showBetaBadge: true,
      ),
      const NavigationDestinationItem(
        icon: HueIcons.mic,
        selectedIcon: HueIcons.mic,
        labelKey: 'learning',
        screen: LearningScreen(),
        group: NavGroup.listenLearn,
        pinnedMobile: true,
      ),
      const NavigationDestinationItem(
        icon: HueIcons.queryStats,
        selectedIcon: HueIcons.queryStats,
        labelKey: 'analysis',
        screen: AnalysisScreen(),
        group: NavGroup.listenLearn,
      ),
      const NavigationDestinationItem(
        icon: HueIcons.musicNote,
        selectedIcon: HueIcons.musicNote,
        labelKey: 'transcription',
        screen: TranscriptionScreen(),
        group: NavGroup.listenLearn,
      ),
      const NavigationDestinationItem(
        icon: HueIcons.autoAwesome,
        selectedIcon: HueIcons.autoAwesome,
        labelKey: 'creation',
        screen: CreationScreen(),
        group: NavGroup.create,
        pinnedMobile: true,
      ),
      const NavigationDestinationItem(
        icon: HueIcons.history,
        selectedIcon: HueIcons.history,
        labelKey: 'history',
        screen: HistoryScreen(),
        group: NavGroup.system,
      ),
      const NavigationDestinationItem(
        icon: HueIcons.settings,
        selectedIcon: HueIcons.settings,
        labelKey: 'settings',
        screen: SettingsScreen(),
        group: NavGroup.system,
      ),
      const NavigationDestinationItem(
        icon: HueIcons.accountCircle,
        selectedIcon: HueIcons.accountCircle,
        labelKey: 'auth',
        screen: LoginScreen(),
        group: NavGroup.system,
      ),
    ];

    if (auth.isStaff) {
      destinations.add(
        NavigationDestinationItem(
          icon: HueIcons.adminPanel,
          selectedIcon: HueIcons.adminPanel,
          labelKey: 'admin',
          screen: AdminScreen(key: ValueKey('admin-${auth.role}-${auth.username ?? ""}')),
          group: NavGroup.admin,
        ),
      );
    }

    if (_navIndex < 0 || _navIndex >= destinations.length) {
      _navIndex = 0;
    }

    return ResponsiveScaffold(
      destinations: destinations,
      selectedIndex: _navIndex,
      sessionEpoch: _sessionEpoch,
      onDestinationSelected: (idx) => setState(() => _navIndex = idx.clamp(0, destinations.length - 1)),
    );
  }
}

class _HomeContent extends StatelessWidget {
  final void Function(int) onSelectTab;

  const _HomeContent({required this.onSelectTab});

  @override
  Widget build(BuildContext context) {
    final strings = context.watch<LocaleProvider>().strings;
    final server = context.watch<ServerConfig>();

    final quickActions = [
      _QuickAction(
        icon: HueIcons.libraryMusic,
        color: AppTheme.featureAccent(context, 0),
        label: strings.featHeritageTitle,
        tabIndex: 1,
      ),
      _QuickAction(
        icon: HueIcons.mic,
        color: AppTheme.featureAccent(context, 2),
        label: strings.featLearningTitle,
        tabIndex: 3,
      ),
      _QuickAction(
        icon: HueIcons.autoAwesome,
        color: AppTheme.featureAccent(context, 5),
        label: strings.featCreationTitle,
        tabIndex: 6,
      ),
      _QuickAction(
        icon: HueIcons.healing,
        color: AppTheme.featureAccent(context, 1),
        label: strings.navRestoration,
        tabIndex: 2,
      ),
    ];

    return CustomScrollView(
      slivers: [
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(AppSpacing.xl, AppSpacing.lg, AppSpacing.xl, 0),
          sliver: SliverToBoxAdapter(
            child: RepaintBoundary(child: _buildHeroHeader(context, strings, server)),
          ),
        ),
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(AppSpacing.xl, AppSpacing.lg, AppSpacing.xl, 0),
          sliver: SliverToBoxAdapter(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  strings.quickAccessTitle,
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                ),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: [
                    for (var i = 0; i < quickActions.length; i++)
                      StaggeredEntrance(
                        index: i,
                        child: _QuickActionChip(
                          action: quickActions[i],
                          onSelect: () => onSelectTab(quickActions[i].tabIndex),
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ),
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(AppSpacing.xl, AppSpacing.xl, AppSpacing.xl, 0),
          sliver: SliverToBoxAdapter(
            child: _buildRecentSection(context, strings),
          ),
        ),
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(AppSpacing.xl, AppSpacing.xl, AppSpacing.xl, AppSpacing.xxl),
          sliver: SliverToBoxAdapter(
            child: Center(
              child: Text(
                'Hue Heritage Music · ${strings.versionLabel} ${AppConstants.appVersion}',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                      fontSize: AppFontSize.xs,
                    ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildRecentSection(BuildContext context, dynamic strings) {
    final entries = context.watch<HistoryService>().entries;
    final recent = entries.take(3).toList();
    final resume = PracticeResume.pickLatest(entries);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              strings.recentActivityTitle,
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
            ),
            if (entries.isNotEmpty)
              TextButton.icon(
                onPressed: () => onSelectTab(7),
                icon: const HueIcon(HueIcons.arrowForward, size: 15),
                label: Text(strings.taskHistoryTitle),
                style: TextButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
                  textStyle: Theme.of(context).textTheme.labelMedium,
                ),
              ),
          ],
        ),
        const SizedBox(height: 10),
        if (resume != null)
          Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.sm),
            child: _ResumeTile(
              title: resume.title,
              onTap: () {
                PracticeResume.lessonId.value = resume.detail;
                onSelectTab(3);
              },
            ),
          ),
        if (recent.isEmpty)
          EmptyState(icon: HueIcons.historyToggleOff, title: strings.recentActivityEmpty)
        else
          Column(
            children: [
              for (var i = 0; i < recent.length; i++)
                StaggeredEntrance(
                  index: i,
                  child: _RecentTile(
                    entry: recent[i],
                    onTap: () => onSelectTab(7),
                  ),
                ),
            ],
          ),
      ],
    );
  }

  Widget _buildHeroHeader(BuildContext context, dynamic strings, ServerConfig server) {
    final logoBox = Container(
      width: 44,
      height: 44,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(AppRadius.md),
        color: Colors.white.withValues(alpha: 0.15),
        border: Border.all(color: Colors.white.withValues(alpha: 0.25)),
      ),
      child: const AppLogo(size: 44, iconSize: 24, iconColor: Colors.white),
    );
    final titleText = Text(
      strings.appTitle,
      style: const TextStyle(
        color: Colors.white,
        fontSize: AppFontSize.title,
        fontWeight: FontWeight.w700,
        letterSpacing: 0.2,
        fontFamily: AppTheme.displayFontFamily,
      ),
    );
    final subtitleText = Text(
      strings.appSubtitle,
      maxLines: 3,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(
        color: Colors.white.withValues(alpha: 0.88),
        fontSize: AppFontSize.sm,
        height: 1.35,
      ),
    );
    final statusPill = Container(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.xs),
      decoration: BoxDecoration(
        color: AppTheme.darkBg.withValues(alpha: 0.82),
        borderRadius: BorderRadius.circular(AppRadius.xl),
        border: Border.all(
          color: (server.hasServer ? AppTheme.emeraldBright : AppTheme.statusDangerDark).withValues(alpha: 0.75),
          width: 0.9,
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
              color: server.hasServer ? AppTheme.emeraldBright : AppTheme.statusDangerDark,
            ),
          ),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              server.hasServer ? strings.serverOnline : strings.serverOffline,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: server.hasServer ? AppTheme.emeraldBright : AppTheme.statusDangerDark,
                fontSize: AppFontSize.xs,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
    final accountButton = Consumer<AuthService?>(
      builder: (context, auth, _) {
        final loggedIn = auth?.isLoggedIn ?? false;
        return IconButton(
          tooltip: loggedIn ? (auth?.username ?? strings.authTooltipLoggedIn) : strings.authTooltipGuest,
          icon: const HueIcon(
            HueIcons.accountCircle,
            color: Colors.white,
            size: 26,
          ),
          onPressed: () {
            Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const LoginScreen()),
            );
          },
        );
      },
    );

    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(AppRadius.lg),
        gradient: AppTheme.brandGradientOf(context),
        boxShadow: AppElevation.card(Theme.of(context).brightness),
      ),
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xl, vertical: AppSpacing.lg),
      child: HeritageMotif(
        color: Colors.white,
        opacity: 0.09,
        child: LayoutBuilder(
          builder: (context, constraints) {
            if (constraints.maxWidth < AppBreakpoints.compact) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      logoBox,
                      const SizedBox(width: 12),
                      Expanded(child: titleText),
                      accountButton,
                    ],
                  ),
                  const SizedBox(height: 8),
                  subtitleText,
                  const SizedBox(height: 10),
                  statusPill,
                ],
              );
            }
            return Row(
              children: [
                logoBox,
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      titleText,
                      const SizedBox(height: 2),
                      subtitleText,
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                Flexible(child: statusPill),
                const SizedBox(width: 8),
                accountButton,
              ],
            );
          },
        ),
      ),
    );
  }
}

class _QuickAction {
  final IconData icon;
  final Color color;
  final String label;
  final int tabIndex;

  const _QuickAction({
    required this.icon,
    required this.color,
    required this.label,
    required this.tabIndex,
  });
}

class _QuickActionChip extends StatelessWidget {
  final _QuickAction action;
  final VoidCallback onSelect;

  const _QuickActionChip({required this.action, required this.onSelect});

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: action.label,
      child: Material(
        color: action.color.withValues(alpha: AppAlpha.selected),
        borderRadius: BorderRadius.circular(AppRadius.lg),
        child: InkWell(
          borderRadius: BorderRadius.circular(AppRadius.lg),
          onTap: onSelect,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg, vertical: AppSpacing.md),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                HueIcon(action.icon, size: 18, color: action.color, decorative: true),
                const SizedBox(width: 8),
                Flexible(
                  child: Text(
                    action.label,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.labelLarge?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                  ),
                ),
                const SizedBox(width: 4),
                HueIcon(
                  HueIcons.arrowForwardIos,
                  size: 11,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                  decorative: true,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _RecentTile extends StatelessWidget {
  final HistoryEntry entry;
  final VoidCallback onTap;

  const _RecentTile({required this.entry, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final locale = context.read<LocaleProvider>();
    final strings = locale.strings;
    final tileTitle = entry.title.isEmpty ? _kindLabel(entry.kind, strings) : entry.title;
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: Semantics(
        button: true,
        label: tileTitle,
        child: Material(
          color: Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.45),
          borderRadius: BorderRadius.circular(AppRadius.lg),
          child: InkWell(
            borderRadius: BorderRadius.circular(AppRadius.lg),
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg, vertical: AppSpacing.md),
              child: Row(
                children: [
                  Container(
                    width: 38,
                    height: 38,
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.primary.withValues(alpha: AppAlpha.hover + 0.04),
                      borderRadius: BorderRadius.circular(AppRadius.md),
                    ),
                    child: HueIcon(_kindIcon(entry.kind), color: Theme.of(context).colorScheme.primary, size: 19, decorative: true),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          tileTitle,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                fontWeight: FontWeight.w600,
                              ),
                        ),
                        const SizedBox(height: 2),
                        Row(
                          children: [
                            Flexible(
                              child: Text(
                                '${_kindLabel(entry.kind, strings)} · ${_formatDate(entry.at)}',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: Theme.of(context).textTheme.labelSmall,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  _statusChip(context, entry.status, strings),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _statusChip(BuildContext context, String status, dynamic strings) {
    final color = statusColor(context, status);
    final label = switch (status) {
      'done' => strings.historyStatusDone,
      'error' => strings.historyStatusError,
      'running' => strings.historyStatusRunning,
      _ => status,
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm, vertical: AppSpacing.xs),
      decoration: BoxDecoration(
        color: color.withValues(alpha: AppAlpha.hover + 0.06),
        borderRadius: BorderRadius.circular(AppRadius.sm),
        border: Border.all(color: color.withValues(alpha: 0.3), width: 0.8),
      ),
      child: Text(label, style: TextStyle(color: color, fontWeight: FontWeight.w700, fontSize: AppFontSize.xs)),
    );
  }

  IconData _kindIcon(String kind) => switch (kind) {
        'transcribe' => HueIcons.musicNote,
        'restore' || 'restore-upload' => HueIcons.healing,
        'instruments' => HueIcons.piano,
        'generate' => HueIcons.autoAwesome,
        'cover' => HueIcons.shuffle,
        'compare' || 'compare-tune' => HueIcons.compareArrows,
        'analyze-pitch' => HueIcons.queryStats,
        'practice' => HueIcons.school,
        'sing_original' || 'sing_new_lyrics' => HueIcons.autoAwesome,
        _ => HueIcons.task,
      };

  String _kindLabel(String kind, dynamic strings) => switch (kind) {
        'transcribe' => strings.featTranscriptionTitle,
        'restore' || 'restore-upload' => strings.navRestoration,
        'instruments' => strings.navInstruments,
        'generate' => strings.navCreation,
        'cover' => strings.navCover,
        'compare' => strings.navLearning,
        'compare-tune' => strings.restorationTabCompare,
        'analyze-pitch' => strings.featAnalysisTitle,
        'practice' => strings.historyFilterPractice,
        'sing_original' || 'sing_new_lyrics' => strings.navCreation,
        _ => kind.isEmpty ? strings.taskHistoryTitle : kind,
      };

  String _formatDate(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year} '
      '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
}

class _ResumeTile extends StatelessWidget {
  final String title;
  final VoidCallback onTap;

  const _ResumeTile({required this.title, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final strings = context.read<LocaleProvider>().strings;
    return Semantics(
      button: true,
      label: '${strings.homeResumeCta}: $title',
      child: Material(
        color: AppTheme.primaryPurple.withValues(alpha: AppAlpha.selected),
        borderRadius: BorderRadius.circular(AppRadius.lg),
        child: InkWell(
          borderRadius: BorderRadius.circular(AppRadius.lg),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg, vertical: AppSpacing.md),
            child: Row(
              children: [
                Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(color: AppTheme.goldReadable(context), width: 1.2),
                    color: AppTheme.goldReadable(context).withValues(alpha: AppAlpha.hover + 0.06),
                  ),
                  child: HueIcon(HueIcons.playArrow, size: 18, color: AppTheme.goldReadable(context), decorative: true),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        strings.homeResumeCta,
                        style: Theme.of(context).textTheme.labelSmall?.copyWith(
                              color: AppTheme.goldReadable(context),
                              fontWeight: FontWeight.w700,
                              letterSpacing: 0.5,
                            ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                              fontWeight: FontWeight.w600,
                            ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                HueIcon(
                  HueIcons.arrowForward,
                  size: 16,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                  decorative: true,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
