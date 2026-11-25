import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';
import 'package:provider/provider.dart';

import '../../api/api_client.dart';
import '../../api/endpoints/instrument_api.dart';
import '../../models/instrument_result.dart';
import '../../models/pitch_data.dart';
import '../../api/endpoints/sing_api.dart';
import '../../services/locale_provider.dart';
import '../../services/connectivity_guard.dart';
import '../../services/server_config.dart';
import '../../widgets/feature_header.dart';
import '../../widgets/hue_chip.dart';
import '../../widgets/pitch_contour_chart.dart';
import '../../widgets/stat_card.dart';
import '../../widgets/waveform_view.dart';
import '../../widgets/error_panel.dart';
import '../../widgets/hue_icons.dart';
import '../../widgets/skeleton_loader.dart';

class AnalysisScreen extends StatefulWidget {
  const AnalysisScreen({super.key});

  @override
  State<AnalysisScreen> createState() => _AnalysisScreenState();
}

class _AnalysisScreenState extends State<AnalysisScreen> {
  bool _loading = false;
  bool _picking = false;
  String? _error;
  PitchData? _pitch;
  InstrumentResult? _instruments;
  bool _instrumentsFailed = false;
  WaveformData? _wave;
  String _source = '';

  Future<void> _pickAndAnalyze() async {
    if (_loading || _picking) return;
    setState(() => _picking = true);
    Uint8List? bytes;
    String name = '';
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.audio,
        withData: kIsWeb,
      );
      final file = (result == null || result.files.isEmpty) ? null : result.files.first;
      if (file == null) return;
      name = file.name;
      bytes = file.bytes;
      if (bytes == null && !kIsWeb && file.path != null) {
        bytes = await File(file.path!).readAsBytes();
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = ApiClient.describe(e);
        _loading = false;
      });
      return;
    } finally {
      if (mounted) {
        setState(() => _picking = false);
      }
    }
    if (bytes == null) return;
    await _run(bytes, name);
  }

  Future<void> _run(Uint8List bytes, String name) async {
    if (!mounted || _loading) return;
    final config = context.read<ServerConfig>();
    if (!config.hasServer) {
      setState(() => _error = context.read<LocaleProvider>().strings.analysisNoServer);
      return;
    }
    if (!await ConnectivityGuard.instance.isOnline) {
      if (mounted) {
        setState(() => _error = context.read<LocaleProvider>().strings.offlineMessage);
      }
      return;
    }
    if (!mounted) return;
    setState(() {
      _loading = true;
      _error = null;
      _pitch = null;
      _instruments = null;
      _instrumentsFailed = false;
      _wave = null;
      _source = name;
    });
    WaveformData? wave;
    try {
      wave = await compute(parseWaveformData, bytes);
    } catch (_) {}
    if (!mounted) return;
    try {
      final pitch = await SingApi(config.api.dio).analyzePitchBytes(bytes);
      InstrumentResult? instruments;
      bool instrumentsFailed = false;
      try {
        instruments = await InstrumentApi(config.api.dio).detectBytes(bytes, name);
      } catch (_) {
        instrumentsFailed = true;
        instruments = null;
      }
      if (!mounted) return;
      setState(() {
        _pitch = pitch;
        _instruments = instruments;
        _instrumentsFailed = instrumentsFailed;
        _wave = wave;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _wave = wave;
        _source = name;
        _error = ApiClient.describe(e);
      });
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  AppStatusKind _confidenceKind(double confidence) {
    if (confidence >= 0.8) return AppStatusKind.success;
    if (confidence >= 0.4) return AppStatusKind.warning;
    return AppStatusKind.info;
  }

  @override
  Widget build(BuildContext context) {
    final strings = context.watch<LocaleProvider>().strings;
    final scheme = Theme.of(context).colorScheme;
    return ListView(
      padding: EdgeInsets.zero,
      children: [
        FeatureHeader(
          title: strings.featAnalysisTitle,
          subtitle: strings.analysisHeaderSubtitle,
          icon: HueIcons.queryStats,
        ),
        Padding(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Card(
                margin: EdgeInsets.zero,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.lg)),
                child: Padding(
                  padding: const EdgeInsets.all(AppSpacing.lg),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(strings.analysisPickHint),
                      const SizedBox(height: AppSpacing.md),
                      FilledButton.icon(
                        onPressed: (_loading || _picking) ? null : _pickAndAnalyze,
                        icon: const HueIcon(HueIcons.folderOpen),
                        label: Text(strings.analysisPickBtn),
                      ),
                    ],
                  ),
                ),
              ),
              if (_loading) ...[
                const SizedBox(height: AppSpacing.lg),
                const LinearProgressIndicator(),
                const SizedBox(height: AppSpacing.md),
                const SkeletonLoader(height: 160),
                const SizedBox(height: AppSpacing.md),
                const Row(
                  children: [
                    Expanded(child: SkeletonLoader(height: 68)),
                    SizedBox(width: AppSpacing.md),
                    Expanded(child: SkeletonLoader(height: 68)),
                  ],
                ),
              ],
              if (_error != null) ...[
                const SizedBox(height: AppSpacing.lg),
                ErrorPanel(message: _error!, onRetry: (_loading || _picking) ? null : _pickAndAnalyze),
              ],
              if (_source.isNotEmpty) ...[
                const SizedBox(height: AppSpacing.lg),
                Text(strings.analysisFileLabel(_source), style: Theme.of(context).textTheme.bodySmall),
                const SizedBox(height: AppSpacing.sm),
                if (_wave != null) WaveformView(data: _wave!),
              ],
              if (_pitch != null) ...[
                const SizedBox(height: AppSpacing.lg),
                Text(strings.analysisF0Title, style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: AppSpacing.sm),
                PitchContourChart(data: _pitch!),
                if (_pitch!.truncated) ...[
                  const SizedBox(height: AppSpacing.xs),
                  Row(
                    children: [
                      HueIcon(HueIcons.warning, size: 14, color: AppTheme.statusReadable(context, AppStatusKind.warning)),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          strings.analysisTruncatedNote(
                            '${_pitch!.maxSeconds?.toStringAsFixed(0) ?? '35'}s',
                            _pitch!.durationFull?.toStringAsFixed(1),
                          ),
                          style: TextStyle(fontSize: AppFontSize.sm, color: Theme.of(context).colorScheme.onSurfaceVariant),
                        ),
                      ),
                    ],
                  ),
                ],
                const SizedBox(height: AppSpacing.md),
                Row(
                  children: [
                    Expanded(
                      child: StatCard(
                        icon: HueIcons.graphicEq,
                        label: 'Mean F0',
                        value: '${_pitch!.meanF0.toStringAsFixed(1)} Hz',
                      ),
                    ),
                    const SizedBox(width: AppSpacing.md),
                    Expanded(
                      child: StatCard(
                        icon: HueIcons.schedule,
                        label: 'Frames',
                        value: '${_pitch!.frames}',
                      ),
                    ),
                  ],
                ),
              ],
              if (_instrumentsFailed) ...[
                const SizedBox(height: AppSpacing.lg),
                Text(strings.analysisInstrumentsFail, style: Theme.of(context).textTheme.bodySmall),
              ],
              if (_instruments != null) ...[
                const SizedBox(height: AppSpacing.lg),
                Text(strings.analysisInstrumentsTitle, style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: AppSpacing.sm),
                if (_instruments!.segments.isEmpty)
                  Text(
                    strings.analysisNoInstruments,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                  )
                else
                  for (final s in _instruments!.segments)
                    Padding(
                      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          HueChip(
                            label: '${s.instrument} ${(s.confidence * 100).toStringAsFixed(0)}%',
                            icon: HueIcons.piano,
                            kind: _confidenceKind(s.confidence),
                          ),
                          const SizedBox(height: AppSpacing.xs),
                          LinearProgressIndicator(
                            value: s.confidence.clamp(0.0, 1.0),
                            minHeight: 6,
                            borderRadius: BorderRadius.circular(AppRadius.xs),
                            color: AppTheme.statusReadable(context, _confidenceKind(s.confidence)),
                            backgroundColor: scheme.surfaceContainerHighest,
                          ),
                        ],
                      ),
                    ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}
