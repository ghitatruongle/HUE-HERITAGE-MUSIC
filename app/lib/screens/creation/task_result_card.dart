import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_theme.dart';
import '../../models/music_task.dart';
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
    final server = context.read<ServerConfig>();
    final fullUrl = '${server.baseUrl}${task.audioUrl}';

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppTheme.darkSurface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: task.status == 'done' ? AppTheme.imperialGold : AppTheme.darkBorder,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text('Trạng thái tác vụ:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: task.status == 'done'
                      ? Colors.green.withAlpha(40)
                      : task.status == 'blocked' || task.status == 'cancelled'
                          ? Colors.amber.withAlpha(40)
                          : Colors.blue.withAlpha(40),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  task.status,
                  style: TextStyle(
                    color: task.status == 'done'
                        ? Colors.greenAccent
                        : task.status == 'blocked' || task.status == 'cancelled'
                            ? Colors.amberAccent
                            : Colors.lightBlueAccent,
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
                  icon: const Icon(Icons.close_rounded, size: 14, color: Colors.white70),
                  label: const Text('Hủy', style: TextStyle(fontSize: 12, color: Colors.white70)),
                  onPressed: () => onCancel(task.id),
                ),
              ],
            ],
          ),
          if (task.reason.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text('Thông báo: ${task.reason}', style: const TextStyle(fontSize: 12.5, color: Colors.white70)),
          ],
          if (task.status == 'blocked') ...[
            const SizedBox(height: 8),
            const Text(
              'Máy chủ AI đang ở chế độ chờ kiểm thử trọng số. '
              'Tác phẩm AI cần HuếMusic-LoRA được nạp từ các checkpoint đã huấn luyện.',
              style: TextStyle(fontSize: 12, color: Colors.white60),
            ),
          ],
          if (task.status == 'done' && task.audioUrl.isNotEmpty) ...[
            const SizedBox(height: 10),
            const Row(
              children: [
                Icon(Icons.verified_rounded, size: 16, color: AppTheme.imperialGold),
                SizedBox(width: 6),
                Text(
                  'TÁC PHẨM ĐƯỢC AI TẠO MỚI (AI_GENERATED)',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: AppTheme.imperialGold),
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
