import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../api/endpoints/admin_endpoints.dart';
import '../../api/endpoints/auth_endpoints.dart';
import '../../core/theme/app_theme.dart';
import '../../services/admin_reauth.dart';
import '../../services/locale_provider.dart';
import '../../services/server_config.dart';
import '../auth/account_manager_section.dart';
import '../auth/invite_manager_section.dart';

String formatBytes(num bytes) {
  if (bytes < 1024) return '$bytes B';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
  if (bytes < 1024 * 1024 * 1024) return '${(bytes / 1024 / 1024).toStringAsFixed(1)} MB';
  return '${(bytes / 1024 / 1024 / 1024).toStringAsFixed(2)} GB';
}

class AdminScreen extends StatefulWidget {
  const AdminScreen({super.key});

  @override
  State<AdminScreen> createState() => _AdminScreenState();
}

class _AdminScreenState extends State<AdminScreen> with SingleTickerProviderStateMixin {
  late final TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final strings = context.watch<LocaleProvider>().strings;
    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        title: Text(strings.adminTitle),
        automaticallyImplyLeading: false,
      ),
      body: Column(
        children: [
          Material(
            color: Colors.transparent,
            child: TabBar(
              controller: _tabController,
              isScrollable: true,
              tabAlignment: TabAlignment.start,
              tabs: [
                Tab(text: strings.adminTabDashboard),
                Tab(text: strings.adminTabUsers),
                Tab(text: strings.adminTabInvites),
                Tab(text: strings.adminTabStorage),
              ],
            ),
          ),
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: const [
                _DashboardTab(),
                _UsersTab(),
                _InvitesTab(),
                _StorageTab(),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _DashboardTab extends StatefulWidget {
  const _DashboardTab();

  @override
  State<_DashboardTab> createState() => _DashboardTabState();
}

class _DashboardTabState extends State<_DashboardTab> {
  late Future<AdminStats> _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<AdminStats> _load() async {
    final dio = context.read<ServerConfig>().api.dio;
    return AdminEndpoints(dio).stats();
  }

  void _reload() {
    setState(() => _future = _load());
  }

  @override
  Widget build(BuildContext context) {
    final strings = context.watch<LocaleProvider>().strings;
    return RefreshIndicator(
      onRefresh: () async => _reload(),
      child: FutureBuilder<AdminStats>(
        future: _future,
        builder: (context, snap) {
          if (snap.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snap.hasError || !snap.hasData) {
            return ListView(
              children: [
                const SizedBox(height: 48),
                Center(child: Text(strings.adminLoadFail)),
                const SizedBox(height: 12),
                Center(
                  child: TextButton.icon(
                    onPressed: _reload,
                    icon: const Icon(Icons.refresh),
                    label: Text(strings.adminRefresh),
                  ),
                ),
              ],
            );
          }
          final s = snap.data!;
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Card(
                color: s.engineOnline
                    ? AppTheme.emeraldGreen.withValues(alpha: 0.12)
                    : Colors.redAccent.withValues(alpha: 0.10),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                child: ListTile(
                  leading: Icon(
                    s.engineOnline ? Icons.dns : Icons.dns_outlined,
                    color: s.engineOnline ? AppTheme.emeraldGreen : Colors.redAccent,
                  ),
                  title: Text(
                    s.engineOnline ? strings.adminEngineOnline : strings.adminEngineOffline,
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      color: s.engineOnline ? AppTheme.emeraldGreen : Colors.redAccent,
                    ),
                  ),
                  subtitle: s.engineOnline ? null : Text(strings.adminEngineOfflineHint),
                ),
              ),
              const SizedBox(height: 12),
              GridView.count(
                crossAxisCount: MediaQuery.of(context).size.width >= 720 ? 4 : 2,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                mainAxisSpacing: 10,
                crossAxisSpacing: 10,
                childAspectRatio: 2.4,
                children: [
                  _StatCard(
                    icon: Icons.people_alt_outlined,
                    label: strings.adminStatUsers,
                    value: '${s.usersTotal}',
                    sub: '${strings.adminStatActive}: ${s.usersActive}',
                  ),
                  _StatCard(
                    icon: Icons.confirmation_number_outlined,
                    label: strings.adminStatInvites,
                    value: '${s.invitesTotal}',
                    sub: '${strings.adminStatUnused}: ${s.invitesUnused}',
                  ),
                  _StatCard(
                    icon: Icons.library_music_outlined,
                    label: strings.adminStatItems,
                    value: '${s.itemsTotal}',
                    sub: formatBytes(s.itemsBytes),
                  ),
                  _StatCard(
                    icon: Icons.graphic_eq_outlined,
                    label: strings.adminStatDerived,
                    value: '${s.derivedFiles}',
                    sub: formatBytes(s.derivedBytes),
                  ),
                  _StatCard(
                    icon: Icons.auto_awesome_outlined,
                    label: strings.adminStatGenerated,
                    value: formatBytes(s.generatedBytes),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              _TaskGroupCard(title: strings.adminStatTasks, counts: s.tasksByStatus),
              const SizedBox(height: 10),
              _TaskGroupCard(title: strings.adminStatTasksKind, counts: s.tasksByKind),
            ],
          );
        },
      ),
    );
  }
}

class _StatCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final String? sub;

  const _StatCard({
    required this.icon,
    required this.label,
    required this.value,
    this.sub,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Row(
              children: [
                Icon(icon, size: 18, color: AppTheme.primaryPurple),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              value,
              style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
            ),
            if (sub != null)
              Text(
                sub!,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 10.5, color: scheme.onSurfaceVariant),
              ),
          ],
        ),
      ),
    );
  }
}

class _TaskGroupCard extends StatelessWidget {
  final String title;
  final Map<String, int> counts;

  const _TaskGroupCard({required this.title, required this.counts});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final entries = counts.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return Card(
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
            const SizedBox(height: 8),
            if (entries.isEmpty)
              Text('—', style: TextStyle(color: scheme.onSurfaceVariant))
            else
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final e in entries)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                      decoration: BoxDecoration(
                        color: scheme.surfaceContainerHighest.withValues(alpha: 0.6),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Text(
                        '${e.key}: ${e.value}',
                        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                      ),
                    ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}

class _UsersTab extends StatelessWidget {
  const _UsersTab();

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: const [
        _CreateUserCard(),
        SizedBox(height: 12),
        AccountManagerSection(),
      ],
    );
  }
}

class _CreateUserCard extends StatefulWidget {
  const _CreateUserCard();

  @override
  State<_CreateUserCard> createState() => _CreateUserCardState();
}

class _CreateUserCardState extends State<_CreateUserCard> {
  final _usernameCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  bool _busy = false;
  String? _message;

  @override
  void dispose() {
    _usernameCtrl.dispose();
    _emailCtrl.dispose();
    _passwordCtrl.dispose();
    super.dispose();
  }

  bool _validEmail(String email) {
    return RegExp(r'^[A-Za-z0-9._%+\-]+@[A-Za-z0-9.\-]+\.[A-Za-z]{2,}$').hasMatch(email);
  }

  Future<void> _submit() async {
    final strings = context.read<LocaleProvider>().strings;
    final username = _usernameCtrl.text.trim();
    final email = _emailCtrl.text.trim().toLowerCase();
    if (username.length < 3 || (_emailCtrl.text.trim().isNotEmpty && !_validEmail(email))) {
      setState(() => _message = strings.authErrEmail);
      return;
    }
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      final dio = context.read<ServerConfig>().api.dio;
      final api = AuthEndpoints(dio);
      final created = await runWithAdminReauth(
        context,
        () => api.createUser(
          username: username,
          email: email,
          password: _passwordCtrl.text,
        ),
      );
      if (!mounted) return;
      setState(() {
        _message = strings.adminCreateUserDone(created.username, created.tempPassword);
        _usernameCtrl.clear();
        _emailCtrl.clear();
        _passwordCtrl.clear();
      });
    } on AdminReauthCancelled {
      if (!mounted) return;
      setState(() => _message = strings.adminReauthCancelled);
    } catch (_) {
      if (!mounted) return;
      setState(() => _message = strings.adminCreateUserFail);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final strings = context.watch<LocaleProvider>().strings;
    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              strings.adminCreateUserTitle,
              style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _usernameCtrl,
              decoration: InputDecoration(
                labelText: strings.adminCreateUserUsername,
                isDense: true,
                border: const OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _emailCtrl,
              decoration: InputDecoration(
                labelText: strings.adminCreateUserEmail,
                isDense: true,
                border: const OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _passwordCtrl,
              obscureText: true,
              decoration: InputDecoration(
                labelText: strings.adminCreateUserPassword,
                isDense: true,
                border: const OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                FilledButton.icon(
                  onPressed: _busy ? null : _submit,
                  icon: const Icon(Icons.person_add_alt_1, size: 18),
                  label: Text(strings.adminCreateUserButton),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _message == null
                      ? const SizedBox.shrink()
                      : Text(
                          _message!,
                          style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600),
                        ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _InvitesTab extends StatelessWidget {
  const _InvitesTab();

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: const [
        InviteManagerSection(),
      ],
    );
  }
}

class _StorageTab extends StatefulWidget {
  const _StorageTab();

  @override
  State<_StorageTab> createState() => _StorageTabState();
}

class _StorageTabState extends State<_StorageTab> {
  final _searchCtrl = TextEditingController();
  late Future<List<StorageEntry>> _future;
  String _query = '';

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<List<StorageEntry>> _load() async {
    final dio = context.read<ServerConfig>().api.dio;
    return AdminEndpoints(dio).storage(q: _query, limit: 200);
  }

  void _reload() {
    setState(() => _future = _load());
  }

  Future<void> _confirmDelete(StorageEntry entry) async {
    final strings = context.read<LocaleProvider>().strings;
    final ok = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(entry.title),
        content: Text(strings.adminStorageDeleteConfirm),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: Text(strings.adminCancel),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.redAccent),
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text(strings.adminDelete),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    try {
      final dio = context.read<ServerConfig>().api.dio;
      await runWithAdminReauth(context, () => AdminEndpoints(dio).deleteStorageItem(entry.id));
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(strings.adminStorageDeleted)));
    } on AdminReauthCancelled {
      return;
    } catch (_) {
    } finally {
      if (mounted) _reload();
    }
  }

  @override
  Widget build(BuildContext context) {
    final strings = context.watch<LocaleProvider>().strings;
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _searchCtrl,
                  onSubmitted: (v) {
                    _query = v.trim();
                    _reload();
                  },
                  decoration: InputDecoration(
                    hintText: strings.adminSearchHint,
                    isDense: true,
                    prefixIcon: const Icon(Icons.search, size: 20),
                    border: const OutlineInputBorder(),
                  ),
                ),
              ),
              IconButton(
                tooltip: strings.adminRefresh,
                onPressed: _reload,
                icon: const Icon(Icons.refresh),
              ),
            ],
          ),
        ),
        Expanded(
          child: FutureBuilder<List<StorageEntry>>(
            future: _future,
            builder: (context, snap) {
              if (snap.connectionState != ConnectionState.done) {
                return const Center(child: CircularProgressIndicator());
              }
              if (snap.hasError || !snap.hasData) {
                return Center(child: Text(strings.adminLoadFail));
              }
              final items = snap.data!;
              if (items.isEmpty) {
                return Center(child: Text(strings.adminStorageEmpty));
              }
              return ListView.separated(
                padding: const EdgeInsets.all(16),
                itemCount: items.length,
                separatorBuilder: (_, __) => const SizedBox(height: 8),
                itemBuilder: (context, index) {
                  final entry = items[index];
                  return Card(
                    margin: EdgeInsets.zero,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    child: ListTile(
                      title: Text(
                        entry.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13.5),
                      ),
                      subtitle: Text(
                        '${entry.filename} · ${formatBytes(entry.size)}'
                        '${entry.derivedBytes > 0 ? ' + ${formatBytes(entry.derivedBytes)}' : ''}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 11.5),
                      ),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (!entry.originalExists)
                            Tooltip(
                              message: strings.adminStorageOriginalMissing,
                              child: const Icon(Icons.warning_amber_rounded,
                                  color: Colors.amber, size: 20),
                            ),
                          IconButton(
                            tooltip: strings.adminDelete,
                            icon: const Icon(Icons.delete_outline, color: Colors.redAccent),
                            onPressed: () => _confirmDelete(entry),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              );
            },
          ),
        ),
      ],
    );
  }
}
