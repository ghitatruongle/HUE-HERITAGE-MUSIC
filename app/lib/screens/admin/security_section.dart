import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../api/api_client.dart';
import '../../api/endpoints/admin_endpoints.dart';
import '../../core/theme/app_theme.dart';
import '../../services/locale_provider.dart';
import '../../core/query_epoch.dart';
import '../../services/server_config.dart';
import '../../widgets/empty_state.dart';
import '../../widgets/error_panel.dart';
import '../../widgets/skeleton_loader.dart';
import '../../widgets/hue_icons.dart';

class SecuritySection extends StatefulWidget {
  const SecuritySection({super.key});

  @override
  State<SecuritySection> createState() => _SecuritySectionState();
}

class _SecuritySectionState extends State<SecuritySection> with AutomaticKeepAliveClientMixin {
  final _searchCtrl = TextEditingController();
  final List<SecurityEvent> _events = [];
  SecuritySummary? _summary;
  int _total = 0;
  bool _truncated = false;
  bool _loading = false;
  bool _loadingMore = false;
  bool _hasError = false;
  String _eventFilter = '';

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  final QueryEpoch _queryEpoch = QueryEpoch();

  Future<void> _reload() async {
    final epoch = _queryEpoch.next();
    setState(() {
      _loading = true;
      _hasError = false;
    });
    try {
      final dio = context.read<ServerConfig>().api.dio;
      final api = AdminEndpoints(dio);
      final results = await Future.wait([
        api.securityEvents(limit: 60, event: _eventFilter, q: _searchCtrl.text.trim()),
        api.securitySummary(),
      ]);
      if (!mounted || !_queryEpoch.isCurrent(epoch)) return;
      final page = results[0] as SecurityEventsPage;
      final summary = results[1] as SecuritySummary;
      setState(() {
        _events
          ..clear()
          ..addAll(page.events);
        _total = page.total;
        _truncated = page.truncated;
        _summary = summary;
      });
    } catch (_) {
      if (mounted && _queryEpoch.isCurrent(epoch)) setState(() => _hasError = true);
    } finally {
      if (mounted && _queryEpoch.isCurrent(epoch)) setState(() => _loading = false);
    }
  }

  Future<void> _loadMore() async {
    if (_loadingMore || _events.length >= _total) return;
    setState(() => _loadingMore = true);
    final epoch = _queryEpoch.value;
    try {
      final dio = context.read<ServerConfig>().api.dio;
      final page = await AdminEndpoints(dio).securityEvents(
        limit: 60,
        offset: _events.length,
        event: _eventFilter,
        q: _searchCtrl.text.trim(),
      );
      if (!mounted || !_queryEpoch.isCurrent(epoch)) return;
      setState(() {
        _events.addAll(page.events);
        _total = page.total;
        _truncated = page.truncated;
      });
    } catch (e) {
      if (mounted && _queryEpoch.isCurrent(epoch)) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(ApiClient.describe(e))),
        );
      }
    } finally {
      if (mounted && _queryEpoch.isCurrent(epoch)) setState(() => _loadingMore = false);
    }
  }

  IconData _eventIcon(String event) {
    if (event.contains('flood') || event.contains('rate_limited')) return HueIcons.block;
    if (event.contains('failed')) return HueIcons.error;
    if (event.startsWith('admin_')) return HueIcons.adminPanel;
    if (event.contains('deleted') || event.contains('cleanup')) return HueIcons.delete;
    if (event.contains('password')) return HueIcons.vpnKey;
    return HueIcons.security;
  }

  Color _eventColor(String event, BuildContext context) {
    if (event.contains('flood') || event.contains('rate_limited')) return AppTheme.statusReadable(context, AppStatusKind.danger);
    if (event.contains('failed')) return AppTheme.statusReadable(context, AppStatusKind.warning);
    if (event.startsWith('admin_')) return AppTheme.goldReadable(context);
    if (event.contains('success') || event.contains('changed')) return AppTheme.emeraldReadable(context);
    return AppTheme.statusReadable(context, AppStatusKind.info);
  }

  String _eventSubtitle(SecurityEvent e) {
    final parts = <String>[];
    for (final entry in e.fields.entries) {
      parts.add('${entry.key}: ${entry.value}');
    }
    return parts.isEmpty ? e.level : parts.join(' · ');
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final strings = context.watch<LocaleProvider>().strings;
    final scheme = Theme.of(context).colorScheme;
    final summary = _summary;

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(AppSpacing.lg, AppSpacing.md, AppSpacing.lg, 0),
          child: Row(
            children: [
              HueIcon(HueIcons.security, size: 18, color: AppTheme.goldReadable(context)),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  strings.securityTitle,
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: AppFontSize.lg),
                ),
              ),
              IconButton(
                tooltip: strings.adminRefresh,
                onPressed: _loading ? null : _reload,
                icon: const HueIcon(HueIcons.refresh, size: 18),
              ),
            ],
          ),
        ),
        if (summary != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(AppSpacing.lg, AppSpacing.sm, AppSpacing.lg, 0),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final entry in summary.counts.entries)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.xs),
                      decoration: BoxDecoration(
                        color: scheme.surfaceContainerHighest.withValues(alpha: 0.6),
                        borderRadius: BorderRadius.circular(AppRadius.lg),
                      ),
                      child: Text(
                        '${strings.securityEventLabel(entry.key)}: ${entry.value}',
                        style: const TextStyle(fontSize: AppFontSize.sm, fontWeight: FontWeight.w600),
                      ),
                    ),
                  if (summary.counts.isEmpty)
                    Text(
                      strings.securityQuietWindow,
                      style: TextStyle(fontSize: AppFontSize.sm, color: scheme.onSurfaceVariant),
                    ),
                ],
              ),
            ),
          ),
        if (summary?.lastAdminLoginTs != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(AppSpacing.lg, AppSpacing.sm, AppSpacing.lg, 0),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                '${strings.securityLastAdminLogin}: ${summary!.lastAdminLoginTs}',
                style: TextStyle(fontSize: AppFontSize.sm, color: scheme.onSurfaceVariant),
              ),
            ),
          ),
        Padding(
          padding: const EdgeInsets.fromLTRB(AppSpacing.lg, AppSpacing.md, AppSpacing.lg, AppSpacing.xs),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _searchCtrl,
                  onSubmitted: (_) => _reload(),
                  decoration: InputDecoration(
                    hintText: strings.securitySearchHint,
                    isDense: true,
                    prefixIcon: const HueIcon(HueIcons.search, size: 20),
                    border: const OutlineInputBorder(),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Builder(
                builder: (context) {
                  final keys = <String>{
                    ...?_summary?.counts.keys,
                    if (_eventFilter.isNotEmpty) _eventFilter,
                  };
                  return DropdownButton<String>(
                    value: _eventFilter,
                    underline: const SizedBox.shrink(),
                    items: [
                      DropdownMenuItem(value: '', child: Text(strings.securityFilterAll, style: const TextStyle(fontSize: AppFontSize.sm))),
                      for (final k in keys)
                        DropdownMenuItem(
                          value: k,
                          child: Text(strings.securityEventLabel(k), style: const TextStyle(fontSize: AppFontSize.sm)),
                        ),
                    ],
                    onChanged: (v) {
                      setState(() => _eventFilter = v ?? '');
                      _reload();
                    },
                  );
                },
              ),
            ],
          ),
        ),
        if (_hasError && _events.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(AppSpacing.lg, AppSpacing.sm, AppSpacing.lg, 0),
            child: ErrorPanel(message: strings.adminLoadFail, onRetry: _loading ? null : _reload),
          ),
        Expanded(
          child: _loading && _events.isEmpty
              ? const SkeletonList(itemCount: 7, itemHeight: 60)
              : _hasError && _events.isEmpty
                  ? ErrorPanel(message: strings.adminLoadFail, onRetry: _reload)
                  : _events.isEmpty
                      ? EmptyState(icon: HueIcons.security, title: strings.securityEmpty)
                      : RefreshIndicator(
                          onRefresh: _reload,
                          child: ListView.separated(
                            padding: const EdgeInsets.all(AppSpacing.lg),
                            itemCount: _events.length + ((_events.length < _total) ? 1 : 0),
                            separatorBuilder: (_, __) => const SizedBox(height: 6),
                            itemBuilder: (context, index) {
                              if (index >= _events.length) {
                                return Padding(
                                  padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
                                  child: Center(
                                    child: _loadingMore
                                        ? const SizedBox(
                                            width: 20,
                                            height: 20,
                                            child: CircularProgressIndicator(strokeWidth: 2.4),
                                          )
                                        : OutlinedButton.icon(
                                            onPressed: _loadMore,
                                            icon: const HueIcon(HueIcons.expandMore, size: 16),
                                            label: Text('${strings.adminLoadMore} ($_total)'),
                                          ),
                                  ),
                                );
                              }
                              final e = _events[index];
                              final color = _eventColor(e.event, context);
                              return Card(
                                margin: EdgeInsets.zero,
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.md)),
                                child: ListTile(
                                  dense: true,
                                  leading: HueIcon(_eventIcon(e.event), color: color, size: 20),
                                  title: Text(
                                    strings.securityEventLabel(e.event),
                                    style: const TextStyle(fontSize: AppFontSize.md, fontWeight: FontWeight.w700),
                                  ),
                                  subtitle: Text(
                                    '${e.ts}\n${_eventSubtitle(e)}',
                                    maxLines: 3,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(fontSize: AppFontSize.xs, height: 1.35),
                                  ),
                                  isThreeLine: true,
                                ),
                              );
                            },
                          ),
                        ),
        ),
        if (_truncated)
          Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.sm),
            child: Text(
              strings.securityTruncated,
              style: TextStyle(fontSize: AppFontSize.xs, color: scheme.onSurfaceVariant),
            ),
          ),
      ],
    );
  }
}
