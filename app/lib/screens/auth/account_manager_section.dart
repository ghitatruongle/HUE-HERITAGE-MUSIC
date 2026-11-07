import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../api/api_client.dart';
import '../../api/endpoints/auth_endpoints.dart';
import '../../services/admin_reauth.dart';
import '../../services/clipboard_helper.dart';
import '../../core/theme/app_theme.dart';
import '../../services/locale_provider.dart';
import '../../core/query_epoch.dart';
import '../../services/server_config.dart';

class AccountManagerSection extends StatefulWidget {
  const AccountManagerSection({super.key});

  @override
  State<AccountManagerSection> createState() => _AccountManagerSectionState();
}

class _AccountManagerSectionState extends State<AccountManagerSection> {
  final List<AccountEntry> _accounts = [];
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
      if (mounted) setState(() => _hasError = true);
    } finally {
      if (mounted) setState(() => _loading = false);
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
    } catch (_) {
    } finally {
      if (mounted) setState(() => _loadingMore = false);
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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            const Icon(Icons.manage_accounts, size: 18, color: AppTheme.statusWarning),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                '${strings.accountManagerTitle} ($_total)',
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
              ),
            ),
            IconButton(
              tooltip: strings.adminRefresh,
              onPressed: _loading ? null : _reload,
              icon: const Icon(Icons.refresh, size: 18),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Text(strings.accountManagerHint, style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurfaceVariant)),
        const SizedBox(height: 10),
        if (_loading && _accounts.isEmpty)
          const Center(child: Padding(padding: EdgeInsets.all(8), child: CircularProgressIndicator()))
        else if (_hasError && _accounts.isEmpty)
          Text(
            strings.authInviteLoadFail,
            style: const TextStyle(fontSize: 12, color: AppTheme.statusDanger),
          )
        else ...[
          for (final acc in _accounts)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Card(
                margin: EdgeInsets.zero,
                child: Row(
                  children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Text(acc.username, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                            const SizedBox(width: 6),
                            if (acc.role == 'admin')
                              const Icon(Icons.admin_panel_settings, size: 13, color: AppTheme.statusWarning)
                            else
                              const Icon(Icons.person, size: 13, color: AppTheme.statusInfo),
                            if (!acc.active) ...[
                              const SizedBox(width: 6),
                              const Icon(Icons.block, size: 13, color: AppTheme.statusDanger),
                            ],
                          ],
                        ),
                        if (acc.email.isNotEmpty)
                          Text(acc.email, style: TextStyle(fontSize: 11.5, color: Theme.of(context).colorScheme.onSurfaceVariant)),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.vpn_key_outlined, size: 16),
                    tooltip: strings.accountResetPassword,
                    onPressed: () => _resetAccountPassword(acc),
                  ),
                  IconButton(
                    icon: const Icon(Icons.person_remove, size: 16, color: AppTheme.statusDanger),
                    tooltip: strings.accountDeleteTitle,
                    onPressed: acc.role == 'admin' ? null : () => _deleteAccount(acc),
                  ),
                  Switch(
                    value: acc.active,
                    onChanged: acc.role == 'admin' ? null : (v) => _toggleAccountActive(acc, v),
                  ),
                  ],
                ),
              ),
            ),
          if (_accounts.length < _total)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Center(
                child: _loadingMore
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2.4),
                      )
                    : OutlinedButton.icon(
                        onPressed: _loadMore,
                        icon: const Icon(Icons.expand_more, size: 16),
                        label: Text('${strings.adminLoadMore} ($_total)'),
                      ),
              ),
            ),
        ],
      ],
    );
  }

  Future<void> _deleteAccount(AccountEntry acc) async {
    final strings = context.read<LocaleProvider>().strings;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(strings.accountDeleteTitle),
        content: Text('${strings.accountDeleteConfirm}: ${acc.username}? ${strings.accountDeleteIrreversible}'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(strings.closeBtn)),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppTheme.statusDanger),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(strings.commonOk),
          ),
        ],
      ),
    );
    if (!mounted || confirmed != true) return;
    try {
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
    }
  }

  Future<void> _toggleAccountActive(AccountEntry acc, bool active) async {
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
      ));
    } on AdminReauthCancelled {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(strings.adminReauthCancelled)));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(ApiClient.describe(e))));
      }
    }
  }

  Future<void> _resetAccountPassword(AccountEntry acc) async {
    final strings = context.read<LocaleProvider>().strings;
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
    try {
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
    }
  }
}
