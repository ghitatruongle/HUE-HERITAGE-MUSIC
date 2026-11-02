import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/lesson.dart';
import '../../api/endpoints/lesson_api.dart';
import '../../services/locale_provider.dart';
import '../../services/server_config.dart';
import '../../widgets/audio_player_bar.dart';
import '../../widgets/common_button.dart';

class ScalePracticeCard extends StatelessWidget {
  final List<ScaleInfo> scales;
  final ScaleInfo? selected;
  final ValueChanged<ScaleInfo?> onChanged;
  final bool recording;
  final VoidCallback onToggleRecord;
  final bool busy;
  final VoidCallback onSubmit;
  final String? recordPath;
  final ScalePractice? result;

  const ScalePracticeCard({
    super.key,
    required this.scales,
    required this.selected,
    required this.onChanged,
    required this.recording,
    required this.onToggleRecord,
    required this.busy,
    required this.onSubmit,
    required this.recordPath,
    required this.result,
  });

  @override
  Widget build(BuildContext context) {
    final strings = context.watch<LocaleProvider>().strings;
    final dio = context.read<ServerConfig>().api.dio;
    final scale = selected;
    final scheme = Theme.of(context).colorScheme;
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(strings.practiceScaleTitle, style: const TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 4),
            Text(
              strings.practiceScaleHint,
              style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
            ),
            const SizedBox(height: 8),
            DropdownButtonFormField<ScaleInfo>(
              initialValue: scale,
              decoration: InputDecoration(labelText: strings.practiceScale, border: const OutlineInputBorder()),
              items: [
                for (final s in scales)
                  DropdownMenuItem(value: s, child: Text(s.name)),
              ],
              onChanged: onChanged,
            ),
            if (scale != null) ...[
              const SizedBox(height: 8),
              Text('${strings.practiceScaleNotes}: ${scale.noteNames.join(" - ")}', style: const TextStyle(fontSize: 12)),
              const SizedBox(height: 8),
              AudioPlayerBar(url: LessonApi(dio).scaleReferenceUrl(scale.id), label: strings.practiceScaleSample, dio: dio),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 6,
                children: [
                  FilledButton.icon(
                    icon: Icon(recording ? Icons.stop : Icons.mic, size: 16),
                    label: Text(recording ? strings.practiceStopRecord : strings.practiceScaleRecord),
                    style: FilledButton.styleFrom(
                      backgroundColor: recording ? Colors.red : null,
                    ),
                    onPressed: onToggleRecord,
                  ),
                  CommonButton(
                    label: strings.practiceScaleGrade,
                    loading: busy,
                    onPressed: recordPath != null && !busy ? onSubmit : null,
                  ),
                ],
              ),
              if (result != null) ...[
                const Divider(height: 20),
                Text(
                  strings.practiceScaleResult(result!.score.toStringAsFixed(0), (result!.onScaleShare * 100).toStringAsFixed(0)),
                  style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 6,
                  runSpacing: 4,
                  children: [
                    for (final n in result!.notes)
                      Chip(
                        backgroundColor: n.hit ? Colors.green.withAlpha(40) : Colors.red.withAlpha(40),
                        label: Text('${n.name} (${(n.share * 100).toStringAsFixed(0)}%)', style: const TextStyle(fontSize: 11)),
                      ),
                  ],
                ),
              ],
            ],
          ],
        ),
      ),
    );
  }
}
