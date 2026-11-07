import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_theme.dart';
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
  final int transpose;
  final ValueChanged<int> onTransposeChanged;

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
    required this.transpose,
    required this.onTransposeChanged,
  });

  Color _verdictColor(String code, BuildContext context) {
    switch (code) {
      case 'ok':
        return AppTheme.statusSuccess.withAlpha(40);
      case 'minor':
        return AppTheme.statusWarning.withAlpha(40);
      case 'octave':
        return AppTheme.statusWarning.withAlpha(70);
      case 'off':
        return AppTheme.statusDanger.withAlpha(40);
      default:
        return Theme.of(context).colorScheme.onSurfaceVariant.withAlpha(40);
    }
  }

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
              Row(
                children: [
                  Text('${strings.practiceScaleNotes}: ${scale.noteNames.join(" - ")}', style: const TextStyle(fontSize: 12)),
                  const Spacer(),
                  Text(strings.practiceTranspose, style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant)),
                  const SizedBox(width: 6),
                  Tooltip(
                    message: strings.practiceTranspose,
                    child: DropdownButton<int>(
                    value: transpose,
                    underline: const SizedBox.shrink(),
                    items: [
                      for (final v in const [-6, -5, -4, -3, -2, -1, 0, 1, 2, 3, 4, 5, 6])
                        DropdownMenuItem(value: v, child: Text(strings.practiceTransposeValue(v.toString()), style: const TextStyle(fontSize: 12))),
                    ],
                    onChanged: (v) {
                      if (v != null) onTransposeChanged(v);
                    },
                  ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              AudioPlayerBar(
                url: LessonApi(dio).scaleReferenceUrl(scale.id, transpose: transpose),
                label: strings.practiceScaleSample,
                dio: dio,
                key: ValueKey('${scale.id}_$transpose'),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 6,
                children: [
                  FilledButton.icon(
                    icon: Icon(recording ? Icons.stop : Icons.mic, size: 16),
                    label: Text(recording ? strings.practiceStopRecord : strings.practiceScaleRecord),
                    style: FilledButton.styleFrom(
                      backgroundColor: recording ? AppTheme.statusDanger : null,
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
                Text(
                  '${strings.practiceScorePitch}: ${result!.pitchScore.toStringAsFixed(0)} · ${strings.practiceScoreRhythm}: ${result!.rhythmScore.toStringAsFixed(0)} · ${strings.practiceScoreStability}: ${result!.stabilityScore.toStringAsFixed(0)}',
                  style: TextStyle(fontSize: 11.5, color: scheme.onSurfaceVariant),
                ),
                if (result!.summaryHint.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(result!.summaryHint, style: TextStyle(fontSize: 11.5, color: scheme.onSurfaceVariant)),
                  ),
                const SizedBox(height: 6),
                if (result!.performance.isNotEmpty) ...[
                  Text(strings.practiceScalePerfTitle, style: TextStyle(fontSize: 11.5, color: scheme.onSurfaceVariant)),
                  const SizedBox(height: 4),
                  Wrap(
                    spacing: 6,
                    runSpacing: 4,
                    children: [
                      for (final p in result!.performance)
                        Tooltip(
                          message: p.hint.isNotEmpty ? p.hint : p.verdict,
                          child: Chip(
                            backgroundColor: _verdictColor(p.verdictCode, context),
                            label: Text(
                              '${p.name} ${p.verdictCode == "unclear" ? "" : "${p.errCents > 0 ? "+" : ""}${p.errCents.toStringAsFixed(0)}c"}',
                              style: const TextStyle(fontSize: 11),
                            ),
                          ),
                        ),
                    ],
                  ),
                ],
                const SizedBox(height: 6),
                Wrap(
                  spacing: 6,
                  runSpacing: 4,
                  children: [
                    for (final n in result!.notes)
                      Chip(
                        backgroundColor: n.hit ? AppTheme.statusSuccess.withAlpha(40) : AppTheme.statusDanger.withAlpha(40),
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
