import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../api/api_client.dart';
import '../../api/endpoints/auth_endpoints.dart';
import '../../services/admin_reauth.dart';
import '../../services/auth_service.dart';
import '../../services/clipboard_helper.dart';
import '../../core/theme/app_theme.dart';
import '../../services/locale_provider.dart';
import '../../core/query_epoch.dart';
import '../../services/server_config.dart';
import '../../widgets/avatar_view.dart';
import '../../widgets/error_panel.dart';
import '../../widgets/empty_state.dart';
import '../../widgets/hue_icons.dart';
import '../../widgets/skeleton_loader.dart';

class AccountManagerSection extends StatefulWidget {
  const AccountManagerSection({super.key});

  @override
  State<AccountManagerSection> createState() => _AccountManagerSectionState();
}

class _AccountManagerSectionState extends State<AccountManagerSection> {
  final List<AccountEntry> _accounts = [];
  final Set<String> _busyIds = {};
  int _total = 0;
  bool _loading = false;
  bool _loadingMore = false;
  bool _hasError = false;

  @override
  void initState() {
    super.initState();
    _reload();
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
      final page = await AuthEndpoints(dio).listAccounts();
      if (!mounted || !_queryEpoch.isCurrent(epoch)) return;
      setState(() {
        _accounts
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
    if (_loadingMore || _accounts.length >= _total) return;
    setState(() => _loadingMore = true);
    final epoch = _queryEpoch.value;
    try {
      final dio = context.read<ServerConfig>().api.dio;
      final page = await AuthEndpoints(dio).listAccounts(offset: _accounts.length);
      if (!mounted || !_queryEpoch.isCurrent(epoch)) return;
      final known = _accounts.map((e) => e.id).toSet();
      setState(() {
        for (final acc in page.items) {
          if (!known.contains(acc.id)) _accounts.add(acc);
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

  void _replaceLocal(AccountEntry updated) {
    final idx = _accounts.indexWhere((e) => e.id == updated.id);
    if (idx >= 0 && mounted) {
      setState(() => _accounts[idx] = updated);
    }
  }

  @override
  Widget build(BuildContext context) {
    final strings = context.watch<LocaleProvider>().strings;
    final viewerWorker = context.watch<AuthService>().role == 'worker';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            HueIcon(HueIcons.manageAccounts, size: 18, color: AppTheme.statusReadable(context, AppStatusKind.warning)),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                '${strings.accountManagerTitle} ($_total)',
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
        const SizedBox(height: 4),
        Text(
          viewerWorker ? strings.accountManagerHintWorker : strings.accountManagerHint,
          style: TextStyle(fontSize: AppFontSize.sm, color: Theme.of(context).colorScheme.onSurfaceVariant),
        ),
        const SizedBox(height: 10),
        if (_loading && _accounts.isEmpty)
          const Column(
            children: [
              SkeletonLoader(height: 68),
              SkeletonLoader(height: 68),
              SkeletonLoader(height: 68),
            ],
          )
        else if (_hasError && _accounts.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
            child: ErrorPanel(message: strings.accountManagerLoadFail, onRetry: _loading ? null : _reload),
          )
        else ...[
          if (_hasError)
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.sm),
              child: ErrorPanel(message: strings.accountManagerLoadFail, onRetry: _loading ? null : _reload),
            ),
          if (_accounts.isEmpty)
            EmptyState(icon: HueIcons.accountCircle, title: strings.accountEmpty),
          for (final acc in _accounts)
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.sm),
              child: Card(
                margin: EdgeInsets.zero,
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final info = Row(
                      children: [
                        Padding(
                          padding: const EdgeInsets.only(left: AppSpacing.md, right: AppSpacing.sm),
                          child: AvatarView(
                            url: acc.avatar,
                            size: 36,
                            icon: acc.role == 'admin'
                                ? HueIcons.adminPanel
                                : (acc.role == 'worker' ? HueIcons.engineering : HueIcons.person),
                          ),
                        ),
                        Expanded(
                          child: Padding(
                            padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Wrap(
                                  spacing: 6,
                                  runSpacing: 2,
                                  crossAxisAlignment: WrapCrossAlignment.center,
                                  children: [
                                    Text(acc.username, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: AppFontSize.md)),
                                    if (acc.role == 'admin')
                                      HueIcon(HueIcons.adminPanel, size: 13, color: AppTheme.statusReadable(context, AppStatusKind.warning))
                                    else if (acc.role == 'worker')
                                      HueIcon(HueIcons.engineering, size: 13, color: AppTheme.statusReadable(context, AppStatusKind.info))
                                    else
                                      HueIcon(HueIcons.person, size: 13, color: AppTheme.statusReadable(context, AppStatusKind.info)),
                                    if (!acc.active)
                                      HueIcon(HueIcons.block, size: 13, color: AppTheme.statusReadable(context, AppStatusKind.danger)),
                                  ],
                                ),
                                if (acc.email.isNotEmpty)
                                  Text(
                                    acc.email,
                                    softWrap: true,
                                    style: TextStyle(fontSize: AppFontSize.sm, color: Theme.of(context).colorScheme.onSurfaceVariant),
                                  ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    );
                    if (viewerWorker) {
                      return info;
                    }
                    final rowBusy = _busyIds.contains(acc.id);
                    final controls = <Widget>[
                      IconButton(
                        icon: HueIcon(
                          acc.role == 'worker' ? HueIcons.person : HueIcons.engineering,
                          size: 16,
                          color: acc.role == 'admin'
                              ? null
                              : AppTheme.statusReadable(
                                  context,
                                  acc.role == 'worker' ? AppStatusKind.info : AppStatusKind.warning,
                                ),
                        ),
                        tooltip: acc.role == 'worker' ? strings.accountRevokeWorker : strings.accountMakeWorker,
                        onPressed: acc.role == 'admin' || rowBusy ? null : () => _toggleAccountRole(acc),
                      ),
                      IconButton(
                        icon: const HueIcon(HueIcons.vpnKey, size: 16),
                        tooltip: strings.accountResetPassword,
                        onPressed: rowBusy ? null : () => _resetAccountPassword(acc),
                      ),
                      IconButton(
                        icon: HueIcon(HueIcons.personRemove, size: 16, color: AppTheme.statusReadable(context, AppStatusKind.danger)),
                        tooltip: strings.accountDeleteTitle,
                        onPressed: acc.role == 'admin' || rowBusy ? null : () => _deleteAccount(acc),
                      ),
                      Switch(
                        value: acc.active,
                        onChanged: acc.role == 'admin' || rowBusy ? null : (v) => _toggleAccountActive(acc, v),
                      ),
                    ];
                    if (constraints.maxWidth < 460) {
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          info,
                          Padding(
                            padding: const EdgeInsets.only(right: AppSpacing.sm, bottom: AppSpacing.xs),
                            child: Align(
                              alignment: Alignment.centerRight,
                              child: Wrap(
                                spacing: AppSpacing.xs,
                                crossAxisAlignment: WrapCrossAlignment.center,
                                children: controls,
                              ),
                            ),
                          ),
                        ],
                      );
                    }
                    return Row(
                      children: [
                        Expanded(child: info),
                        ...controls,
                      ],
                    );
                  },
                ),
              ),
            ),
          if (_accounts.length < _total)
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
      ],
    );
  }

  Future<void> _deleteAccount(AccountEntry acc) async {
    if (_busyIds.contains(acc.id)) return;
    setState(() => _busyIds.add(acc.id));
    final strings = context.read<LocaleProvider>().strings;
    try {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(strings.accountDeleteTitle),
          content: Text('${strings.accountDeleteConfirm}: ${acc.username}? ${strings.accountDeleteIrreversible}'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(strings.closeBtn)),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: Theme.of(ctx).colorScheme.error,
                foregroundColor: Theme.of(ctx).colorScheme.onError,
              ),
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(strings.commonOk),
            ),
          ],
        ),
      );
      if (!mounted || confirmed != true) return;
      final dio = context.read<ServerConfig>().api.dio;
      await runWithAdminReauth(context, () => AuthEndpoints(dio).deleteAccount(acc.id));
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${strings.accountDeleted}: ${acc.username}')),
      );
      setState(() {
        _accounts.removeWhere((e) => e.id == acc.id);
        _total = _total > 0 ? _total - 1 : 0;
      });
    } on AdminReauthCancelled {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(strings.adminReauthCancelled)));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(ApiClient.describe(e))));
      }
    } finally {
      if (mounted) setState(() => _busyIds.remove(acc.id));
    }
  }

  Future<void> _toggleAccountActive(AccountEntry acc, bool active) async {
    if (_busyIds.contains(acc.id)) return;
    setState(() => _busyIds.add(acc.id));
    final strings = context.read<LocaleProvider>().strings;
    try {
      final dio = context.read<ServerConfig>().api.dio;
      await runWithAdminReauth(context, () => AuthEndpoints(dio).setAccountActive(acc.id, active));
      if (!mounted) return;
      _replaceLocal(AccountEntry(
        id: acc.id,
        username: acc.username,
        email: acc.email,
        role: acc.role,
        active: active,
        mustChangePassword: acc.mustChangePassword,
        avatar: acc.avatar,
      ));
    } on AdminReauthCancelled {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(strings.adminReauthCancelled)));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(ApiClient.describe(e))));
      }
    } finally {
      if (mounted) setState(() => _busyIds.remove(acc.id));
    }
  }

  Future<void> _toggleAccountRole(AccountEntry acc) async {
    if (_busyIds.contains(acc.id) || acc.role == 'admin') return;
    setState(() => _busyIds.add(acc.id));
    final strings = context.read<LocaleProvider>().strings;
    final targetRole = acc.role == 'worker' ? 'user' : 'worker';
    try {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(strings.accountRoleChangeTitle),
          content: Text(
            '${targetRole == 'worker' ? strings.accountRolePromoteConfirm : strings.accountRoleDemoteConfirm}: ${acc.username}?',
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(strings.closeBtn)),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(strings.commonOk)),
          ],
        ),
      );
      if (!mounted || confirmed != true) return;
      final dio = context.read<ServerConfig>().api.dio;
      final updatedRole = await runWithAdminReauth(
        context,
        () => AuthEndpoints(dio).setAccountRole(acc.id, targetRole),
      );
      if (!mounted) return;
      _replaceLocal(AccountEntry(
        id: acc.id,
        username: acc.username,
        email: acc.email,
        role: updatedRole,
        active: acc.active,
        mustChangePassword: acc.mustChangePassword,
        avatar: acc.avatar,
      ));
      final roleLabel = updatedRole == 'worker' ? strings.adminRoleWorker : strings.adminRoleUser;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${strings.accountRoleUpdated}: ${acc.username} ($roleLabel)')),
      );
    } on AdminReauthCancelled {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(strings.adminReauthCancelled)));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(ApiClient.describe(e))));
      }
    } finally {
      if (mounted) setState(() => _busyIds.remove(acc.id));
    }
  }

  Future<void> _resetAccountPassword(AccountEntry acc) async {
    if (_busyIds.contains(acc.id)) return;
    setState(() => _busyIds.add(acc.id));
    final strings = context.read<LocaleProvider>().strings;
    try {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(strings.accountResetPassword),
          content: Text('${strings.accountResetConfirm}: ${acc.username}?'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(strings.closeBtn)),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(strings.commonOk)),
          ],
        ),
      );
      if (!mounted || confirmed != true) return;
      final dio = context.read<ServerConfig>().api.dio;
      final temp = await runWithAdminReauth(context, () => AuthEndpoints(dio).resetAccountPassword(acc.id));
      final copied = await copyText(temp);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          duration: const Duration(seconds: 10),
          content: Text(
            '${strings.accountTempPassword}: $temp${copied ? ' (${strings.authInviteCopied.toLowerCase()})' : ''}',
          ),
        ),
      );
    } on AdminReauthCancelled {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(strings.adminReauthCancelled)));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(ApiClient.describe(e))));
      }
    } finally {
      if (mounted) setState(() => _busyIds.remove(acc.id));
    }
  }
}
