import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_theme.dart';
import '../../services/history_service.dart';
import '../../services/locale_provider.dart';
import '../../widgets/feature_header.dart';
import '../../widgets/empty_state.dart';
import '../../widgets/status_colors.dart';
import '../../widgets/hue_icons.dart';
import '../../widgets/staggered_entrance.dart';

class HistoryScreen extends StatefulWidget {
  const HistoryScreen({super.key});

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  String _selectedFilter = 'all';

  static const Map<String, List<String>> _chipKinds = {
    'all': [],
    'analyze-pitch': ['analyze-pitch'],
    'practice': ['practice'],
    'compare-tune': ['compare-tune'],
    'transcribe': ['transcribe'],
    'restore': ['restore', 'restore-upload'],
    'sing': ['sing_original', 'sing_new_lyrics'],
  };

  @override
  Widget build(BuildContext context) {
    final locale = context.watch<LocaleProvider>();
    final strings = locale.strings;
    final allEntries = context.watch<HistoryService>().entries;

    final selectedKinds = _chipKinds[_selectedFilter] ?? const <String>[];
    final entries = _selectedFilter == 'all'
        ? allEntries
        : allEntries.where((e) => selectedKinds.contains(e.kind)).toList();

    return Scaffold(
      body: CustomScrollView(
        slivers: [
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(AppSpacing.xl, AppSpacing.xl, AppSpacing.xl, AppSpacing.md),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  FeatureHeader(
                    title: strings.taskHistoryTitle,
                    icon: HueIcons.historyToggleOff,
                    actions: [
                      if (allEntries.isNotEmpty)
                        OutlinedButton.icon(
                          onPressed: () => _confirmClear(context, strings),
                          icon: const HueIcon(HueIcons.deleteSweep, size: 18),
                          label: Text(strings.clearHistory),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: Colors.white,
                            side: BorderSide(color: Colors.white.withValues(alpha: 0.5)),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.md),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg, vertical: AppSpacing.md),
                    decoration: BoxDecoration(
                      color: AppTheme.emeraldReadable(context).withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(AppRadius.md),
                      border: Border.all(
                        color: AppTheme.emeraldReadable(context).withValues(alpha: 0.3),
                      ),
                    ),
                    child: Row(
                      children: [
                        HueIcon(HueIcons.verified,
                            color: AppTheme.emeraldReadable(context), size: 20),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            strings.historyPrivacyNote,
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w500,
                              color: AppTheme.emeraldReadable(context),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: [
                        _filterChip('all', strings.historyFilterAll, allEntries.length),
                        const SizedBox(width: 8),
                        _filterChip('analyze-pitch', strings.featAnalysisTitle, allEntries.where((e) => _chipKinds['analyze-pitch']!.contains(e.kind)).length),
                        const SizedBox(width: 8),
                        _filterChip('practice', strings.historyFilterPractice, allEntries.where((e) => _chipKinds['practice']!.contains(e.kind)).length),
                        const SizedBox(width: 8),
                        _filterChip('compare-tune', strings.restorationTabCompare, allEntries.where((e) => _chipKinds['compare-tune']!.contains(e.kind)).length),
                        const SizedBox(width: 8),
                        _filterChip('transcribe', strings.featTranscriptionTitle, allEntries.where((e) => _chipKinds['transcribe']!.contains(e.kind)).length),
                        const SizedBox(width: 8),
                        _filterChip('restore', strings.navRestoration, allEntries.where((e) => _chipKinds['restore']!.contains(e.kind)).length),
                        const SizedBox(width: 8),
                        _filterChip('sing', strings.navCreation, allEntries.where((e) => _chipKinds['sing']!.contains(e.kind)).length),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (entries.isEmpty)
            SliverFillRemaining(
              hasScrollBody: false,
              child: EmptyState(icon: HueIcons.historyToggleOff, title: strings.emptyHistory),
            )
          else
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(AppSpacing.xl, 0, AppSpacing.xl, AppSpacing.xxxl),
              sliver: SliverList(
                delegate: SliverChildBuilderDelegate(
                  (context, index) => StaggeredEntrance(
                    index: index,
                    maxAnimatedIndex: 11,
                    child: _localTile(context, entries[index], locale),
                  ),
                  childCount: entries.length,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _filterChip(String key, String label, int count) {
    final isSelected = _selectedFilter == key;
    return FilterChip(
      selected: isSelected,
      label: Text('$label ($count)'),
      onSelected: (_) => setState(() => _selectedFilter = key),
      selectedColor: AppTheme.primaryPurple.withValues(alpha: 0.2),
      checkmarkColor: AppTheme.primaryPurple,
      labelStyle: TextStyle(
        fontSize: 12,
        fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
        color: isSelected ? AppTheme.primaryPurple : null,
      ),
    );
  }

  Widget _localTile(BuildContext context, HistoryEntry e, LocaleProvider locale) {
    return Card(
      margin: const EdgeInsets.only(bottom: AppSpacing.md),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.lg),
        side: BorderSide(
          color: Theme.of(context).colorScheme.outline,
        ),
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg, vertical: AppSpacing.sm),
        leading: Container(
          width: 42,
          height: 42,
          decoration: BoxDecoration(
            color: AppTheme.primaryPurple.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(AppRadius.md),
          ),
          child: Icon(_kindIcon(e.kind), color: AppTheme.primaryPurple, size: 22),
        ),
        title: Text(
          e.title.isEmpty ? _kindLabel(e.kind, locale) : e.title,
          style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: AppSpacing.xs),
          child: Row(
            children: [
              Text(_kindLabel(e.kind, locale), style: TextStyle(fontSize: 11, color: AppTheme.goldReadable(context), fontWeight: FontWeight.w600)),
              const Text(' • ', style: TextStyle(fontSize: 11)),
              Text(_formatDate(e.at), style: TextStyle(fontSize: 11, color: Theme.of(context).colorScheme.onSurfaceVariant)),
              if (e.score != null) ...[
                const Text(' • ', style: TextStyle(fontSize: 11)),
                Text(
                  locale.strings.historyScore(e.score!.toStringAsFixed(1)),
                  style: const TextStyle(fontSize: 11, color: AppTheme.statusSuccess, fontWeight: FontWeight.w600),
                ),
              ],
            ],
          ),
        ),
        trailing: _statusChip(e.status, locale),
      ),
    );
  }

  Widget _statusChip(String status, LocaleProvider locale) {
    final color = statusColor(context, status);
    final label = switch (status) {
      'done' => locale.strings.historyStatusDone,
      'error' => locale.strings.historyStatusError,
      'running' => locale.strings.historyStatusRunning,
      _ => status,
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.xs),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(AppRadius.sm),
        border: Border.all(color: color.withValues(alpha: 0.3), width: 0.8),
      ),
      child: Text(label, style: TextStyle(color: color, fontWeight: FontWeight.w700, fontSize: 11)),
    );
  }

  void _confirmClear(BuildContext context, dynamic strings) {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(strings.clearHistory),
        content: Text(strings.confirmClearHistory),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(strings.cancelBtn),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Theme.of(context).colorScheme.error),
            onPressed: () {
              context.read<HistoryService>().clear();
              Navigator.pop(ctx);
            },
            child: Text(strings.deleteBtn),
          ),
        ],
      ),
    );
  }

  IconData _kindIcon(String kind) => switch (kind) {
        'transcribe' => HueIcons.musicNote,
        'restore' => HueIcons.healing,
        'restore-upload' => HueIcons.uploadFile,
        'instruments' => HueIcons.piano,
        'generate' => HueIcons.autoAwesome,
        'cover' => HueIcons.shuffle,
        'compare' => HueIcons.mic,
        'compare-tune' => HueIcons.compareArrows,
        'analyze-pitch' => HueIcons.queryStats,
        'practice' => HueIcons.school,
        'sing_original' || 'sing_new_lyrics' => HueIcons.autoAwesome,
        _ => HueIcons.task,
      };

  String _kindLabel(String kind, LocaleProvider locale) {
    final s = locale.strings;
    return switch (kind) {
      'transcribe' => s.featTranscriptionTitle,
      'restore' || 'restore-upload' => s.navRestoration,
      'instruments' => s.navInstruments,
      'generate' => s.navCreation,
      'cover' => s.navCover,
      'compare' => s.navLearning,
      'compare-tune' => s.restorationTabCompare,
      'analyze-pitch' => s.featAnalysisTitle,
      'practice' => s.historyFilterPractice,
      'sing_original' || 'sing_new_lyrics' => s.navCreation,
      _ => kind.isEmpty ? s.taskHistoryTitle : kind,
    };
  }

  String _formatDate(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year} '
      '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
}
