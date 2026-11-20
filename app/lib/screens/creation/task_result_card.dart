import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_theme.dart';
import '../../widgets/status_colors.dart' as sc;
import '../../models/music_task.dart';
import '../../services/locale_provider.dart';
import '../../services/server_config.dart';
import '../../widgets/audio_player_bar.dart';
import '../../widgets/error_panel.dart';
import '../../widgets/hue_icons.dart';

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
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(
          color: task.status == 'done' ? AppTheme.goldReadable(context) : scheme.outline,
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
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm, vertical: AppSpacing.xs),
                decoration: BoxDecoration(
                  color: statusColor.withAlpha(40),
                  borderRadius: BorderRadius.circular(AppRadius.sm),
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
                Container(
                  width: 20,
                  height: 20,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(color: AppTheme.goldReadable(context), width: 1.4),
                  ),
                  child: SizedBox(
                    width: 12,
                    height: 12,
                    child: CircularProgressIndicator(
                      strokeWidth: 1.6,
                      color: AppTheme.goldReadable(context),
                    ),
                  ),
                ),
              ],
              if (polling &&
                  (task.status == 'running' || task.status == 'pending' || task.status == 'queued')) ...[
                const SizedBox(width: 10),
                TextButton.icon(
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
                    minimumSize: const Size(44, 44),
                  ),
                  icon: HueIcon(HueIcons.close, size: 14, color: scheme.onSurfaceVariant),
                  label: Text(strings.cancelBtn, style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant)),
                  onPressed: () => onCancel(task.id),
                ),
              ],
            ],
          ),
          if (task.reason.isNotEmpty &&
              task.status != 'failed' &&
              task.status != 'error') ...[
            const SizedBox(height: 6),
            Text(strings.taskNotice(task.reason), style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant)),
          ],
          if (task.status == 'failed' || task.status == 'error') ...[
            const SizedBox(height: 8),
            ErrorPanel(
              message: task.reason.isNotEmpty
                  ? strings.taskNotice(task.reason)
                  : strings.taskFailedGeneric,
            ),
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
                HueIcon(HueIcons.verified, size: 16, color: AppTheme.goldReadable(context)),
                const SizedBox(width: 6),
                Text(
                  strings.taskAiGenerated,
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: AppTheme.goldReadable(context)),
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
