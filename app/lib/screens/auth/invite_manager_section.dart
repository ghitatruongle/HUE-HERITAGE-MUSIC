import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../api/api_client.dart';
import '../../api/endpoints/auth_endpoints.dart';
import '../../core/localization/app_strings.dart';
import '../../services/clipboard_helper.dart';
import '../../core/theme/app_theme.dart';
import '../../services/locale_provider.dart';
import '../../core/query_epoch.dart';
import '../../services/server_config.dart';
import '../../widgets/error_panel.dart';
import '../../widgets/empty_state.dart';
import '../../widgets/hue_icons.dart';
import '../../widgets/skeleton_loader.dart';

class InviteManagerSection extends StatefulWidget {
  const InviteManagerSection({super.key, this.workerMode = false});

  final bool workerMode;

  @override
  State<InviteManagerSection> createState() => _InviteManagerSectionState();
}

class _InviteManagerSectionState extends State<InviteManagerSection> {
  final List<InviteEntry> _invites = [];
  final Set<String> _busyIds = {};
  int _total = 0;
  bool _loading = false;
  bool _loadingMore = false;
  bool _creatingInvite = false;
  bool _hasError = false;

  @override
  void initState() {
    super.initState();
    if (!widget.workerMode) {
      _reload();
    }
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
      final page = await AuthEndpoints(dio).listInvites();
      if (!mounted || !_queryEpoch.isCurrent(epoch)) return;
      setState(() {
        _invites
          ..clear()
          ..addAll(page.items);
        _total = page.total;
      });
    } catch (_) {
      if (mounted && _queryEpoch.isCurrent(epoch)) setState(() => _hasError = true);
    } finally {
      if (mounted && _queryEpoch.isCurrent(epoch)) setState(() => _loading = false);
    }
  }

  Future<void> _loadMore() async {
    if (_loadingMore || _invites.length >= _total) return;
    setState(() => _loadingMore = true);
    final epoch = _queryEpoch.value;
    try {
      final dio = context.read<ServerConfig>().api.dio;
      final page = await AuthEndpoints(dio).listInvites(offset: _invites.length);
      if (!mounted || !_queryEpoch.isCurrent(epoch)) return;
      final known = _invites.map((e) => e.id).toSet();
      setState(() {
        for (final inv in page.items) {
          if (!known.contains(inv.id)) _invites.add(inv);
        }
        _total = page.total;
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

  @override
  Widget build(BuildContext context) {
    final strings = context.watch<LocaleProvider>().strings;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            HueIcon(HueIcons.vpnKey, size: 18, color: AppTheme.statusReadable(context, AppStatusKind.warning)),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                widget.workerMode
                    ? strings.authInviteTitle
                    : '${strings.authInviteTitle} ($_total)',
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: AppFontSize.lg),
              ),
            ),
            if (!widget.workerMode)
              IconButton(
                tooltip: strings.adminRefresh,
                onPressed: _loading ? null : _reload,
                icon: const HueIcon(HueIcons.refresh, size: 18),
              ),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          widget.workerMode ? strings.authInviteWorkerHint : strings.authInviteManageHint,
          style: TextStyle(fontSize: AppFontSize.sm, color: Theme.of(context).colorScheme.onSurfaceVariant),
        ),
        const SizedBox(height: 10),
        if (widget.workerMode && _invites.isEmpty)
          EmptyState(icon: HueIcons.personAdd, title: strings.authInviteWorkerEmpty)
        else if (_loading && _invites.isEmpty)
          const Column(
            children: [
              SkeletonLoader(height: 68),
              SkeletonLoader(height: 68),
              SkeletonLoader(height: 68),
            ],
          )
        else if (_hasError && _invites.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
            child: ErrorPanel(message: strings.authInviteLoadFail, onRetry: _loading ? null : _reload),
          )
        else ...[
          if (_hasError)
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.sm),
              child: ErrorPanel(message: strings.authInviteLoadFail, onRetry: _loading ? null : _reload),
            ),
          if (_invites.isEmpty)
            EmptyState(icon: HueIcons.personAdd, title: strings.authInviteEmpty),
          for (final inv in _invites)
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.sm),
              child: Card(
                margin: EdgeInsets.zero,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.sm),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Wrap(
                              spacing: AppSpacing.sm,
                              runSpacing: AppSpacing.xs,
                              crossAxisAlignment: WrapCrossAlignment.center,
                              children: [
                                SelectableText(
                                  inv.code,
                                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: AppFontSize.md),
                                ),
                                _InviteStatusBadge(inv: inv, strings: strings),
                              ],
                            ),
                            const SizedBox(height: AppSpacing.xs),
                            Wrap(
                              spacing: AppSpacing.md,
                              runSpacing: AppSpacing.xs,
                              children: [
                                Text(
                                  _usageLabel(strings, inv),
                                  style: TextStyle(
                                    fontSize: AppFontSize.xs,
                                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                                  ),
                                ),
                                Text(
                                  _expiryLabel(strings, inv),
                                  style: TextStyle(
                                    fontSize: AppFontSize.xs,
                                    color: inv.expired
                                        ? AppTheme.statusReadable(context, AppStatusKind.danger)
                                        : Theme.of(context).colorScheme.onSurfaceVariant,
                                  ),
                                ),
                              ],
                            ),
                            if (inv.note.isNotEmpty) ...[
                              const SizedBox(height: AppSpacing.xs),
                              Text(
                                inv.note,
                                style: TextStyle(
                                  fontSize: AppFontSize.sm,
                                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                      IconButton(
                        icon: const HueIcon(HueIcons.copy, size: 16),
                        tooltip: strings.authInviteCopy,
                        onPressed: () => _copyInvite(inv),
                      ),
                      if (!widget.workerMode)
                        IconButton(
                          icon: const HueIcon(HueIcons.delete, size: 16),
                          tooltip: strings.authInviteDelete,
                          onPressed: _busyIds.contains(inv.id) ? null : () => _deleteInvite(strings, inv),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          if (!widget.workerMode && _invites.length < _total)
            Padding(
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
            ),
        ],
        const SizedBox(height: 6),
        OutlinedButton.icon(
          icon: const HueIcon(HueIcons.addCircle, size: 16),
          label: Text(strings.authInviteCreate),
          onPressed: _creatingInvite ? null : _createInvite,
        ),
      ],
    );
  }

  String _usageLabel(AppStrings strings, InviteEntry inv) {
    if (inv.maxUses == 0) {
      return '${inv.usedCount} · ${strings.authInviteUnlimited}';
    }
    return '${inv.usedCount}/${inv.maxUses} ${strings.authInviteUsesUnit}';
  }

  String _expiryLabel(AppStrings strings, InviteEntry inv) {
    final dt = inv.expiresAt;
    if (dt == null) return strings.authInviteNeverExpires;
    String two(int v) => v.toString().padLeft(2, '0');
    final stamp = '${dt.year}-${two(dt.month)}-${two(dt.day)} ${two(dt.hour)}:${two(dt.minute)}';
    return '${strings.authInviteExpiresAt} $stamp';
  }

  Future<void> _copyInvite(InviteEntry inv) async {
    final strings = context.read<LocaleProvider>().strings;
    final ok = await copyText(inv.code);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          ok
              ? '${strings.authInviteCopied}: ${inv.code}'
              : '${strings.authInviteCopyFail} — ${inv.code}',
        ),
      ),
    );
  }

  Future<void> _createInvite() async {
    if (_creatingInvite) return;
    setState(() => _creatingInvite = true);
    try {
      final spec = await showDialog<_InviteCreateSpec>(
        context: context,
        builder: (ctx) => _InviteCreateDialog(strings: context.read<LocaleProvider>().strings),
      );
      if (!mounted || spec == null) return;
      final dio = context.read<ServerConfig>().api.dio;
      final inv = await AuthEndpoints(dio).createInvite(
        code: spec.code,
        note: spec.note,
        maxUses: spec.maxUses,
        expiresMinutes: spec.expiresMinutes,
        expiresHours: spec.expiresHours,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${context.read<LocaleProvider>().strings.authInviteCreated}: ${inv.code}')),
      );
      setState(() {
        _invites.insert(0, inv);
        _total += 1;
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(ApiClient.describe(e))),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _creatingInvite = false);
      }
    }
  }

  Future<void> _deleteInvite(AppStrings strings, InviteEntry inv) async {
    if (_busyIds.contains(inv.id)) return;
    setState(() => _busyIds.add(inv.id));
    try {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(strings.authInviteDelete),
          content: Text('${strings.authInviteDeleteConfirm}: ${inv.code}?'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(strings.closeBtn)),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(strings.commonOk)),
          ],
        ),
      );
      if (!mounted || confirmed != true) return;
      final dio = context.read<ServerConfig>().api.dio;
      await AuthEndpoints(dio).deleteInvite(inv.id);
      if (!mounted) return;
      setState(() {
        _invites.removeWhere((e) => e.id == inv.id);
        _total = _total > 0 ? _total - 1 : 0;
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(ApiClient.describe(e))),
        );
      }
    } finally {
      if (mounted) setState(() => _busyIds.remove(inv.id));
    }
  }
}

class _InviteStatusBadge extends StatelessWidget {
  const _InviteStatusBadge({required this.inv, required this.strings});

  final InviteEntry inv;
  final AppStrings strings;

  @override
  Widget build(BuildContext context) {
    final IconData icon;
    final AppStatusKind kind;
    final String label;
    if (inv.expired) {
      icon = HueIcons.historyToggleOff;
      kind = AppStatusKind.danger;
      label = strings.authInviteExpired;
    } else if (!inv.active || inv.used) {
      icon = HueIcons.block;
      kind = AppStatusKind.warning;
      label = inv.maxUses == 1 ? strings.authInviteUsed : strings.authInviteExhausted;
    } else {
      icon = HueIcons.checkCircle;
      kind = AppStatusKind.success;
      label = strings.authInviteAvailable;
    }
    final color = AppTheme.statusReadable(context, kind);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        HueIcon(icon, size: 14, color: color),
        const SizedBox(width: AppSpacing.xs),
        Text(label, style: TextStyle(fontSize: AppFontSize.xs, color: color)),
      ],
    );
  }
}

class _InviteCreateSpec {
  final String code;
  final String note;
  final int maxUses;
  final int? expiresMinutes;
  final double? expiresHours;

  const _InviteCreateSpec({
    required this.code,
    required this.note,
    required this.maxUses,
    this.expiresMinutes,
    this.expiresHours,
  });
}

class _InviteCreateDialog extends StatefulWidget {
  const _InviteCreateDialog({required this.strings});

  final AppStrings strings;

  @override
  State<_InviteCreateDialog> createState() => _InviteCreateDialogState();
}

class _InviteCreateDialogState extends State<_InviteCreateDialog> {
  final TextEditingController _codeCtrl = TextEditingController();
  final TextEditingController _noteCtrl = TextEditingController();
  final TextEditingController _customUsesCtrl = TextEditingController(text: '5');
  final TextEditingController _customExpiryCtrl = TextEditingController(text: '60');
  int _usesPreset = 1;
  int? _expiryMinutesPreset;
  bool _customExpiryHours = false;
  String? _errorText;

  @override
  void dispose() {
    _codeCtrl.dispose();
    _noteCtrl.dispose();
    _customUsesCtrl.dispose();
    _customExpiryCtrl.dispose();
    super.dispose();
  }

  void _submit() {
    final s = widget.strings;
    final code = _codeCtrl.text.trim();
    if (code.isNotEmpty && (code.length < 4 || code.length > 64)) {
      setState(() => _errorText = s.authInviteInvalidCode);
      return;
    }
    int maxUses = _usesPreset;
    if (_usesPreset == -1) {
      final parsed = int.tryParse(_customUsesCtrl.text.trim());
      if (parsed == null || parsed < 0 || parsed > 10000) {
        setState(() => _errorText = s.authInviteInvalidUses);
        return;
      }
      maxUses = parsed;
    }
    int? expiresMinutes;
    double? expiresHours;
    if (_expiryMinutesPreset == -1) {
      if (_customExpiryHours) {
        final parsed = double.tryParse(_customExpiryCtrl.text.trim().replaceAll(',', '.'));
        if (parsed == null || parsed.isNaN || parsed.isInfinite || parsed <= 0 || parsed > 8760) {
          setState(() => _errorText = s.authInviteInvalidExpiry);
          return;
        }
        expiresHours = parsed;
      } else {
        final parsed = int.tryParse(_customExpiryCtrl.text.trim());
        if (parsed == null || parsed < 1 || parsed > 525600) {
          setState(() => _errorText = s.authInviteInvalidExpiry);
          return;
        }
        expiresMinutes = parsed;
      }
    } else {
      expiresMinutes = _expiryMinutesPreset;
    }
    Navigator.pop(
      context,
      _InviteCreateSpec(
        code: code,
        note: _noteCtrl.text.trim(),
        maxUses: maxUses,
        expiresMinutes: expiresMinutes,
        expiresHours: expiresHours,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.strings;
    final useChoices = <(int, String)>[
      (1, s.authInvitePresetOne),
      (5, '5 ${s.authInviteUsesUnit}'),
      (10, '10 ${s.authInviteUsesUnit}'),
      (50, '50 ${s.authInviteUsesUnit}'),
      (0, s.authInvitePresetUnlimited),
      (-1, s.authInvitePresetCustom),
    ];
    final expiryChoices = <(int?, String)>[
      (null, s.authInviteNeverExpires),
      (30, s.authInvitePreset30m),
      (120, s.authInvitePreset2h),
      (1440, s.authInvitePreset24h),
      (10080, s.authInvitePreset7d),
      (43200, s.authInvitePreset30d),
      (-1, s.authInvitePresetCustom),
    ];
    return AlertDialog(
      title: Text(s.authInviteCreate),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 440),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextField(
                controller: _codeCtrl,
                decoration: InputDecoration(labelText: s.authInviteCodeLabel, isDense: true),
              ),
              const SizedBox(height: AppSpacing.md),
              TextField(
                controller: _noteCtrl,
                decoration: InputDecoration(labelText: s.authInviteNoteLabel, isDense: true),
              ),
              const SizedBox(height: AppSpacing.lg),
              Text(
                s.authInviteUsesLabel,
                style: const TextStyle(fontWeight: FontWeight.w600, fontSize: AppFontSize.sm),
              ),
              const SizedBox(height: AppSpacing.xs),
              Wrap(
                spacing: AppSpacing.sm,
                runSpacing: AppSpacing.xs,
                children: [
                  for (final item in useChoices)
                    ChoiceChip(
                      label: Text(item.$2),
                      selected: _usesPreset == item.$1,
                      onSelected: (_) => setState(() {
                        _usesPreset = item.$1;
                        _errorText = null;
                      }),
                    ),
                ],
              ),
              if (_usesPreset == -1) ...[
                const SizedBox(height: AppSpacing.sm),
                TextField(
                  controller: _customUsesCtrl,
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(labelText: s.authInviteCustomUsesLabel, isDense: true),
                ),
              ],
              const SizedBox(height: AppSpacing.lg),
              Text(
                s.authInviteExpiryLabel,
                style: const TextStyle(fontWeight: FontWeight.w600, fontSize: AppFontSize.sm),
              ),
              const SizedBox(height: AppSpacing.xs),
              Wrap(
                spacing: AppSpacing.sm,
                runSpacing: AppSpacing.xs,
                children: [
                  for (final item in expiryChoices)
                    ChoiceChip(
                      label: Text(item.$2),
                      selected: _expiryMinutesPreset == item.$1,
                      onSelected: (_) => setState(() {
                        _expiryMinutesPreset = item.$1;
                        _errorText = null;
                      }),
                    ),
                ],
              ),
              if (_expiryMinutesPreset == -1) ...[
                const SizedBox(height: AppSpacing.sm),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    TextField(
                      controller: _customExpiryCtrl,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      decoration: InputDecoration(labelText: s.authInviteCustomExpiryLabel, isDense: true),
                    ),
                    const SizedBox(height: AppSpacing.xs),
                    Wrap(
                      spacing: AppSpacing.sm,
                      runSpacing: AppSpacing.xs,
                      children: [
                        ChoiceChip(
                          label: Text(s.authInviteDurationMinutes),
                          selected: !_customExpiryHours,
                          onSelected: (_) => setState(() => _customExpiryHours = false),
                        ),
                        ChoiceChip(
                          label: Text(s.authInviteDurationHours),
                          selected: _customExpiryHours,
                          onSelected: (_) => setState(() => _customExpiryHours = true),
                        ),
                      ],
                    ),
                  ],
                ),
              ],
              if (_errorText != null) ...[
                const SizedBox(height: AppSpacing.sm),
                Text(
                  _errorText!,
                  style: TextStyle(fontSize: AppFontSize.sm, color: Theme.of(context).colorScheme.error),
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: Text(s.closeBtn)),
        FilledButton(onPressed: _submit, child: Text(s.commonOk)),
      ],
    );
  }
}
