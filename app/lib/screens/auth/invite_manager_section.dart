import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../api/api_client.dart';
import '../../api/endpoints/auth_endpoints.dart';
import '../../core/localization/app_strings.dart';
import '../../services/clipboard_helper.dart';
import '../../services/locale_provider.dart';
import '../../services/server_config.dart';

class InviteManagerSection extends StatefulWidget {
  const InviteManagerSection({super.key});

  @override
  State<InviteManagerSection> createState() => _InviteManagerSectionState();
}

class _InviteManagerSectionState extends State<InviteManagerSection> {
  final List<InviteEntry> _invites = [];
  int _total = 0;
  bool _loading = false;
  bool _loadingMore = false;
  bool _creatingInvite = false;
  bool _hasError = false;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  Future<void> _reload() async {
    setState(() {
      _loading = true;
      _hasError = false;
    });
    try {
      final dio = context.read<ServerConfig>().api.dio;
      final page = await AuthEndpoints(dio).listInvites();
      if (!mounted) return;
      setState(() {
        _invites
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
    if (_loadingMore || _invites.length >= _total) return;
    setState(() => _loadingMore = true);
    try {
      final dio = context.read<ServerConfig>().api.dio;
      final page = await AuthEndpoints(dio).listInvites(offset: _invites.length);
      if (!mounted) return;
      final known = _invites.map((e) => e.id).toSet();
      setState(() {
        for (final inv in page.items) {
          if (!known.contains(inv.id)) _invites.add(inv);
        }
        _total = page.total;
      });
    } catch (_) {
    } finally {
      if (mounted) setState(() => _loadingMore = false);
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
            const Icon(Icons.vpn_key_outlined, size: 18, color: Colors.amber),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                '${strings.authInviteTitle} ($_total)',
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
        Text(
          strings.authInviteManageHint,
          style: const TextStyle(fontSize: 12, color: Colors.grey),
        ),
        const SizedBox(height: 10),
        if (_loading && _invites.isEmpty)
          const Center(child: Padding(padding: EdgeInsets.all(8), child: CircularProgressIndicator()))
        else if (_hasError && _invites.isEmpty)
          Text(
            strings.authInviteLoadFail,
            style: const TextStyle(fontSize: 12, color: Colors.red),
          )
        else ...[
          if (_invites.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Text(strings.authInviteEmpty, style: const TextStyle(fontSize: 12.5)),
            ),
          for (final inv in _invites)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            SelectableText(
                              inv.code,
                              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                            ),
                            const SizedBox(width: 8),
                            Icon(
                              inv.used ? Icons.check_circle : Icons.schedule,
                              size: 14,
                              color: inv.used ? Colors.green : Colors.amber,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              inv.used ? strings.authInviteUsed : strings.authInviteAvailable,
                              style: TextStyle(
                                fontSize: 11,
                                color: inv.used ? Colors.green : Colors.amber.shade800,
                              ),
                            ),
                          ],
                        ),
                        if (inv.note.isNotEmpty)
                          Text(inv.note, style: const TextStyle(fontSize: 11.5, color: Colors.grey)),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.copy, size: 16),
                    tooltip: strings.authInviteCopy,
                    onPressed: () => _copyInvite(inv),
                  ),
                  IconButton(
                    icon: const Icon(Icons.delete_outline, size: 16),
                    tooltip: strings.authInviteDelete,
                    onPressed: () => _deleteInvite(strings, inv),
                  ),
                ],
              ),
            ),
          if (_invites.length < _total)
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
        const SizedBox(height: 6),
        OutlinedButton.icon(
          icon: const Icon(Icons.add_circle_outline, size: 16),
          label: Text(strings.authInviteCreate),
          onPressed: _creatingInvite ? null : _createInvite,
        ),
      ],
    );
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
    setState(() => _creatingInvite = true);
    try {
      final dio = context.read<ServerConfig>().api.dio;
      final inv = await AuthEndpoints(dio).createInvite();
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
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(strings.authInviteDelete),
        content: Text('${strings.authInviteDeleteConfirm}: ${inv.code}?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(strings.closeBtn)),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('OK')),
        ],
      ),
    );
    if (!mounted || confirmed != true) return;
    try {
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
    }
  }
}
