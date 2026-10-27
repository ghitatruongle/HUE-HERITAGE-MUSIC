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
  bool _creatingInvite = false;

  @override
  Widget build(BuildContext context) {
    final strings = context.watch<LocaleProvider>().strings;
    final dio = context.read<ServerConfig>().api.dio;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            const Icon(Icons.vpn_key_outlined, size: 18, color: Colors.amber),
            const SizedBox(width: 8),
            Text(strings.authInviteTitle, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          strings.authInviteManageHint,
          style: const TextStyle(fontSize: 12, color: Colors.grey),
        ),
        const SizedBox(height: 10),
        FutureBuilder<List<InviteEntry>>(
          future: AuthEndpoints(dio).listInvites(),
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
            final invites = snap.data ?? [];
            return Column(
              children: [
                if (invites.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    child: Text(strings.authInviteEmpty, style: const TextStyle(fontSize: 12.5)),
                  ),
                for (final inv in invites)
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
              ],
            );
          },
        ),
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
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${context.read<LocaleProvider>().strings.authInviteCreated}: ${inv.code}')),
        );
        setState(() {});
      }
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
      if (mounted) setState(() {});
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(ApiClient.describe(e))),
        );
      }
    }
  }
}
