import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_theme.dart';
import '../../services/history_service.dart';
import '../../services/locale_provider.dart';

class HistoryScreen extends StatefulWidget {
  const HistoryScreen({super.key});

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  String _selectedFilter = 'all';

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final locale = context.watch<LocaleProvider>();
    final strings = locale.strings;
    final allEntries = context.watch<HistoryService>().entries;

    final entries = _selectedFilter == 'all'
        ? allEntries
        : allEntries.where((e) => e.kind == _selectedFilter).toList();

    return Scaffold(
      body: CustomScrollView(
        slivers: [
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: Text(
                          strings.taskHistoryTitle,
                          style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                                fontWeight: FontWeight.w800,
                              ),
                        ),
                      ),
                      if (allEntries.isNotEmpty)
                        OutlinedButton.icon(
                          onPressed: () => _confirmClear(context, strings),
                          icon: const Icon(Icons.delete_sweep_outlined, size: 18),
                          label: Text(strings.clearHistory),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: scheme.error,
                            side: BorderSide(color: scheme.error.withValues(alpha: 0.5)),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    decoration: BoxDecoration(
                      color: AppTheme.emeraldGreen.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: AppTheme.emeraldGreen.withValues(alpha: 0.3),
                      ),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.verified_user_outlined,
                            color: AppTheme.emeraldGreen, size: 20),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            strings.historyPrivacyNote,
                            style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w500,
                              color: AppTheme.emeraldGreen,
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
                        _filterChip('all', locale.isVietnamese ? 'Tất cả' : 'All', allEntries.length),
                        const SizedBox(width: 8),
                        _filterChip('compare', strings.navLearning, allEntries.where((e) => e.kind == 'compare').length),
                        const SizedBox(width: 8),
                        _filterChip('transcribe', strings.featTranscriptionTitle, allEntries.where((e) => e.kind == 'transcribe').length),
                        const SizedBox(width: 8),
                        _filterChip('restore', strings.navRestoration, allEntries.where((e) => e.kind == 'restore').length),
                        const SizedBox(width: 8),
                        _filterChip('generate', strings.navCreation, allEntries.where((e) => e.kind == 'generate').length),
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
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.all(32),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.history_toggle_off, size: 64, color: scheme.onSurfaceVariant.withValues(alpha: 0.4)),
                      const SizedBox(height: 16),
                      Text(
                        strings.emptyHistory,
                        textAlign: TextAlign.center,
                        style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 14),
                      ),
                    ],
                  ),
                ),
              ),
            )
          else
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 32),
              sliver: SliverList(
                delegate: SliverChildBuilderDelegate(
                  (context, index) => _localTile(context, entries[index], locale),
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
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(
          color: isDark ? const Color(0xFF2E2B48) : const Color(0xFFE4DFEE),
        ),
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        leading: Container(
          width: 42,
          height: 42,
          decoration: BoxDecoration(
            color: AppTheme.primaryPurple.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(_kindIcon(e.kind), color: AppTheme.primaryPurple, size: 22),
        ),
        title: Text(
          e.title.isEmpty ? _kindLabel(e.kind, locale) : e.title,
          style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Row(
            children: [
              Text(_kindLabel(e.kind, locale), style: const TextStyle(fontSize: 11, color: AppTheme.amberGold, fontWeight: FontWeight.w600)),
              const Text(' • ', style: TextStyle(fontSize: 11)),
              Text(_formatDate(e.at), style: TextStyle(fontSize: 11, color: Theme.of(context).colorScheme.onSurfaceVariant)),
            ],
          ),
        ),
        trailing: _statusChip(e.status, locale),
      ),
    );
  }

  Widget _statusChip(String status, LocaleProvider locale) {
    final color = switch (status) {
      'done' => AppTheme.emeraldGreen,
      'error' => Colors.redAccent,
      'running' => Colors.blueAccent,
      _ => Colors.grey,
    };
    final label = switch (status) {
      'done' => locale.isVietnamese ? 'Hoàn thành' : 'Done',
      'error' => locale.isVietnamese ? 'Lỗi' : 'Error',
      'running' => locale.isVietnamese ? 'Đang chạy' : 'Running',
      _ => status,
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(8),
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
        'transcribe' => Icons.music_note,
        'restore' => Icons.healing,
        'instruments' => Icons.piano,
        'generate' => Icons.auto_awesome,
        'cover' => Icons.shuffle,
        'compare' => Icons.mic,
        'analyze-pitch' => Icons.query_stats,
        _ => Icons.task_outlined,
      };

  String _kindLabel(String kind, LocaleProvider locale) {
    final s = locale.strings;
    return switch (kind) {
      'transcribe' => s.featTranscriptionTitle,
      'restore' => s.navRestoration,
      'instruments' => s.navInstruments,
      'generate' => s.navCreation,
      'cover' => s.navCover,
      'compare' => s.navLearning,
      'analyze-pitch' => s.featAnalysisTitle,
      _ => kind.isEmpty ? s.taskHistoryTitle : kind,
    };
  }

  String _formatDate(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year} '
      '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
}
