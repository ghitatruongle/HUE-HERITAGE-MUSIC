import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_theme.dart';
import '../../core/localization/app_strings.dart';
import '../../models/lesson.dart';
import '../../api/endpoints/lesson_api.dart';
import '../../services/locale_provider.dart';
import '../../services/server_config.dart';
import '../../services/teaching_utils.dart';
import '../../widgets/audio_player_bar.dart';
import '../../widgets/common_button.dart';
import '../../widgets/hue_icons.dart';
import '../../widgets/result_card.dart';
import 'lesson_practice_view.dart';

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

  String _scoreVerdict(double v) {
    if (v >= 80) return 'ok';
    if (v >= 50) return 'minor';
    return 'off';
  }

  String _scaleVerdictLabel(AppStrings strings, String code) {
    switch (code) {
      case 'ok':
        return strings.verdictOk;
      case 'minor':
        return strings.verdictMinor;
      case 'off':
        return strings.verdictOff;
      default:
        return strings.verdictUnclear;
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
        padding: const EdgeInsets.all(AppSpacing.md),
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
                    icon: Icon(recording ? HueIcons.stop : HueIcons.mic, size: 16),
                    label: Text(recording ? strings.practiceStopRecord : strings.practiceScaleRecord),
                    style: FilledButton.styleFrom(
                      backgroundColor: recording ? AppTheme.statusDanger : null,
                    ),
                    onPressed: onToggleRecord,
                  ),
                  CommonButton(
                    label: strings.practiceScaleGrade,
                    loading: busy,
                    onPressed: recordPath != null && !busy && !recording ? onSubmit : null,
                  ),
                ],
              ),
              if (result != null) ...[
                const Divider(height: 20),
                ResultSummaryCard(
                  title: strings.practiceScaleResult(result!.score.toStringAsFixed(0), (result!.onScaleShare * 100).toStringAsFixed(0)),
                  status: practiceVerdictKind(_scoreVerdict(result!.score)),
                  statusLabel: _scaleVerdictLabel(strings, _scoreVerdict(result!.score)),
                  leadingIcon: HueIcons.workspacePremium,
                  children: [
                    Wrap(
                      spacing: AppSpacing.sm,
                      runSpacing: AppSpacing.sm,
                      children: [
                        ScoreBadge(
                          label: strings.practiceScorePitch,
                          value: result!.pitchScore.toStringAsFixed(0),
                          kind: practiceVerdictKind(_scoreVerdict(result!.pitchScore)),
                        ),
                        ScoreBadge(
                          label: strings.practiceScoreRhythm,
                          value: result!.rhythmScore.toStringAsFixed(0),
                          kind: practiceVerdictKind(_scoreVerdict(result!.rhythmScore)),
                        ),
                        ScoreBadge(
                          label: strings.practiceScoreStability,
                          value: result!.stabilityScore.toStringAsFixed(0),
                          kind: practiceVerdictKind(_scoreVerdict(result!.stabilityScore)),
                        ),
                      ],
                    ),
                    MetricRow(
                      label: strings.practiceScoreTotal,
                      value: result!.score.toStringAsFixed(0),
                      valueKind: practiceVerdictKind(_scoreVerdict(result!.score)),
                    ),
                    if (result!.summaryHint.isNotEmpty || result!.summaryCodes.isNotEmpty)
                      Text(
                        summaryHintText(
                          verdictCounts: result!.verdictCounts,
                          summaryCodes: result!.summaryCodes,
                          missingNotes: 0,
                          fallback: result!.summaryHint,
                          strings: strings,
                        ),
                        style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
                      ),
                  ],
                ),
                if (result!.performance.isNotEmpty) ...[
                  Padding(
                    padding: const EdgeInsets.only(top: AppSpacing.sm),
                    child: Text(strings.practiceScalePerfTitle, style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant)),
                  ),
                  const SizedBox(height: 4),
                  Wrap(
                    spacing: 6,
                    runSpacing: 4,
                    children: [
                      for (final p in result!.performance)
                        Tooltip(
                          message: noteHintText(p.hintCodes, p.errCents, p.onsetErrMs, false, p.hint.isNotEmpty ? p.hint : p.verdict, strings),
                          child: Chip(
                            backgroundColor: switch (practiceVerdictKind(p.verdictCode)) {
                              AppStatusKind.success => AppTheme.statusSuccess.withAlpha(40),
                              AppStatusKind.warning => p.verdictCode == 'octave'
                                  ? AppTheme.statusWarning.withAlpha(70)
                                  : AppTheme.statusWarning.withAlpha(40),
                              AppStatusKind.danger => AppTheme.statusDanger.withAlpha(40),
                              AppStatusKind.info => scheme.onSurfaceVariant.withAlpha(40),
                            },
                            label: Text(
                              '${p.name} ${p.verdictCode == "unclear" || p.errCents == null ? "" : "${p.errCents! > 0 ? "+" : ""}${p.errCents!.toStringAsFixed(0)}c"}',
                              style: const TextStyle(fontSize: 11),
                            ),
                          ),
                        ),
                    ],
                  ),
                ],
                Padding(
                  padding: const EdgeInsets.only(top: AppSpacing.sm),
                  child: Wrap(
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
                ),
              ],
            ],
          ],
        ),
      ),
    );
  }
}
