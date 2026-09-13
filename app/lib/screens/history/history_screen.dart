import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../api/api_client.dart';
import '../../api/endpoints/tasks_api.dart';
import '../../services/history_service.dart';
import '../../services/server_config.dart';

class HistoryScreen extends StatefulWidget {
  const HistoryScreen({super.key});

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  bool _loading = false;
  String? _error;
  List<ServerTask> _serverTasks = [];

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    final config = context.read<ServerConfig>();
    if (!config.hasServer) {
      setState(() => _error = 'Chưa cấu hình máy chủ.');
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final tasks = await TasksApi(config.api.dio).list();
      setState(() => _serverTasks = tasks);
    } catch (e) {
      setState(() => _error = ApiClient.describe(e));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final local = context.watch<HistoryService>().entries;
    return RefreshIndicator(
      onRefresh: _refresh,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(16),
        children: [
          Row(
            children: [
              Expanded(child: Text('Tác vụ trên máy chủ', style: Theme.of(context).textTheme.titleMedium)),
              IconButton(
                onPressed: _loading ? null : _refresh,
                icon: const Icon(Icons.refresh),
                tooltip: 'Làm mới',
              ),
            ],
          ),
          if (_loading) const LinearProgressIndicator(),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Text(_error!, style: TextStyle(color: scheme.error)),
            ),
          if (!_loading && _serverTasks.isEmpty && _error == null)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 8),
              child: Text('Chưa có tác vụ nào trên máy chủ.'),
            ),
          ..._serverTasks.map(_serverTile),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(child: Text('Hoạt động trên thiết bị này', style: Theme.of(context).textTheme.titleMedium)),
              TextButton(
                onPressed: () => context.read<HistoryService>().clear(),
                child: const Text('Xóa'),
              ),
            ],
          ),
          if (local.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 8),
              child: Text('Chưa có hoạt động nào được ghi lại.'),
            ),
          ...local.map(_localTile),
        ],
      ),
    );
  }

  Widget _statusChip(String status) {
    final color = switch (status) {
      'done' => Colors.green,
      'error' => Colors.red,
      'blocked' => Colors.orange,
      'rejected' => Colors.deepOrange,
      'running' => Colors.blue,
      _ => Colors.grey,
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(status, style: TextStyle(color: color, fontWeight: FontWeight.w600, fontSize: 12)),
    );
  }

  Widget _serverTile(ServerTask t) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: Icon(_kindIcon(t.kind)),
        title: Text('${_kindLabel(t.kind)} • ${t.id.substring(0, 8)}'),
        subtitle: Text(t.createdAt),
        trailing: _statusChip(t.status),
        onTap: t.status == 'running' || t.status == 'pending' ? _refresh : null,
      ),
    );
  }

  Widget _localTile(HistoryEntry e) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: Icon(_kindIcon(e.kind)),
        title: Text(e.title.isEmpty ? _kindLabel(e.kind) : e.title),
        subtitle: Text(_formatDate(e.at)),
        trailing: _statusChip(e.status),
      ),
    );
  }

  IconData _kindIcon(String kind) => switch (kind) {
        'transcribe' => Icons.music_note,
        'restore' => Icons.healing,
        'instruments' => Icons.piano,
        'generate' => Icons.auto_awesome,
        'cover' => Icons.shuffle,
        'compare' => Icons.graphic_eq,
        'analyze-pitch' => Icons.query_stats,
        _ => Icons.task_outlined,
      };

  String _kindLabel(String kind) => switch (kind) {
        'transcribe' => 'Ký âm tự động',
        'restore' => 'Phục dựng',
        'instruments' => 'Nhận diện nhạc cụ',
        'generate' => 'AI sáng tạo',
        'cover' => 'Cover',
        'compare' => 'So sánh học hát',
        'analyze-pitch' => 'Phân tích cao độ',
        _ => kind.isEmpty ? 'Tác vụ' : kind,
      };

  String _formatDate(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year} '
      '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
}
