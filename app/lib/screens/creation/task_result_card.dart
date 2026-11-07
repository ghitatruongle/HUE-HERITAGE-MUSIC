import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_theme.dart';
import '../../widgets/status_colors.dart' as sc;
import '../../models/music_task.dart';
import '../../services/locale_provider.dart';
import '../../services/server_config.dart';
import '../../widgets/audio_player_bar.dart';

class TaskResultCard extends StatelessWidget {
  final MusicTask task;
  final bool polling;
  final void Function(String taskId) onCancel;

  const TaskResultCard({
    super.key,
    required this.task,
    required this.polling,
    required this.onCancel,
  });

  @override
  Widget build(BuildContext context) {
    final strings = context.watch<LocaleProvider>().strings;
    final server = context.read<ServerConfig>();
    final fullUrl = '${server.baseUrl}${task.audioUrl}';

    final scheme = Theme.of(context).colorScheme;
    final statusColor = sc.statusColor(context, task.status);

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: task.status == 'done' ? AppTheme.imperialGold : scheme.outline,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(strings.taskStatusLabel, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: statusColor.withAlpha(40),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  task.status,
                  style: TextStyle(
                    color: statusColor,
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              if (polling) ...[
                const SizedBox(width: 10),
                const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2)),
              ],
              if (polling &&
                  (task.status == 'running' || task.status == 'pending' || task.status == 'queued')) ...[
                const SizedBox(width: 10),
                TextButton.icon(
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    minimumSize: Size.zero,
                    visualDensity: VisualDensity.compact,
                  ),
                  icon: Icon(Icons.close_rounded, size: 14, color: scheme.onSurfaceVariant),
                  label: Text(strings.cancelBtn, style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant)),
                  onPressed: () => onCancel(task.id),
                ),
              ],
            ],
          ),
          if (task.reason.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(strings.taskNotice(task.reason), style: TextStyle(fontSize: 12.5, color: scheme.onSurfaceVariant)),
          ],
          if (task.status == 'blocked') ...[
            const SizedBox(height: 8),
            Text(
              strings.taskBlockedNote,
              style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
            ),
          ],
          if (task.status == 'done' && task.audioUrl.isNotEmpty) ...[
            const SizedBox(height: 10),
            Row(
              children: [
                const Icon(Icons.verified_rounded, size: 16, color: AppTheme.imperialGold),
                const SizedBox(width: 6),
                Text(
                  strings.taskAiGenerated,
                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: AppTheme.imperialGold),
                ),
              ],
            ),
            const SizedBox(height: 8),
            AudioPlayerBar(key: Key(fullUrl), url: fullUrl, dio: server.api.dio),
          ],
        ],
      ),
    );
  }
}
