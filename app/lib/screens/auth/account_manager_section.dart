import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../api/api_client.dart';
import '../../api/endpoints/auth_endpoints.dart';
import '../../services/clipboard_helper.dart';
import '../../services/locale_provider.dart';
import '../../services/server_config.dart';

class AccountManagerSection extends StatefulWidget {
  const AccountManagerSection({super.key});

  @override
  State<AccountManagerSection> createState() => _AccountManagerSectionState();
}

class _AccountManagerSectionState extends State<AccountManagerSection> {
  @override
  Widget build(BuildContext context) {
    final strings = context.watch<LocaleProvider>().strings;
    final dio = context.read<ServerConfig>().api.dio;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            const Icon(Icons.manage_accounts, size: 18, color: Colors.amber),
            const SizedBox(width: 8),
            Text(strings.accountManagerTitle, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
          ],
        ),
        const SizedBox(height: 4),
        Text(strings.accountManagerHint, style: const TextStyle(fontSize: 12, color: Colors.grey)),
        const SizedBox(height: 10),
        FutureBuilder<List<AccountEntry>>(
          future: AuthEndpoints(dio).listAccounts(),
          builder: (context, snap) {
            if (snap.connectionState != ConnectionState.done) {
              return const Center(child: Padding(padding: EdgeInsets.all(8), child: CircularProgressIndicator()));
            }
            if (snap.hasError) {
              return Text(
                '${strings.authInviteLoadFail}: ${ApiClient.describe(snap.error!)}',
                style: const TextStyle(fontSize: 12, color: Colors.red),
              );
            }
            final accounts = snap.data ?? [];
            return Column(
              children: [
                for (final acc in accounts)
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
                                  Text(acc.username, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                                  const SizedBox(width: 6),
                                  if (acc.role == 'admin')
                                    const Icon(Icons.admin_panel_settings, size: 13, color: Colors.amber)
                                  else
                                    const Icon(Icons.person, size: 13, color: Colors.blueGrey),
                                  if (!acc.active) ...[
                                    const SizedBox(width: 6),
                                    const Icon(Icons.block, size: 13, color: Colors.red),
                                  ],
                                ],
                              ),
                              if (acc.email.isNotEmpty)
                                Text(acc.email, style: const TextStyle(fontSize: 11.5, color: Colors.grey)),
                            ],
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.vpn_key_outlined, size: 16),
                          tooltip: strings.accountResetPassword,
                          onPressed: () => _resetAccountPassword(acc),
                        ),
                        IconButton(
                          icon: const Icon(Icons.person_remove, size: 16, color: Colors.red),
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
              ],
            );
          },
        ),
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
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('OK'),
          ),
        ],
      ),
    );
    if (!mounted || confirmed != true) return;
    try {
      final dio = context.read<ServerConfig>().api.dio;
      await AuthEndpoints(dio).deleteAccount(acc.id);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${strings.accountDeleted}: ${acc.username}')),
        );
        setState(() {});
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(ApiClient.describe(e))));
      }
    }
  }

  Future<void> _toggleAccountActive(AccountEntry acc, bool active) async {
    try {
      final dio = context.read<ServerConfig>().api.dio;
      await AuthEndpoints(dio).setAccountActive(acc.id, active);
      if (mounted) setState(() {});
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
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('OK')),
        ],
      ),
    );
    if (!mounted || confirmed != true) return;
    try {
      final dio = context.read<ServerConfig>().api.dio;
      final temp = await AuthEndpoints(dio).resetAccountPassword(acc.id);
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
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(ApiClient.describe(e))));
      }
    }
  }
}
