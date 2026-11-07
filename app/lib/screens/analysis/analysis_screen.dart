import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../api/api_client.dart';
import '../../api/endpoints/instrument_api.dart';
import '../../models/instrument_result.dart';
import '../../models/pitch_data.dart';
import '../../api/endpoints/sing_api.dart';
import '../../services/locale_provider.dart';
import '../../services/server_config.dart';
import '../../widgets/pitch_contour_chart.dart';
import '../../widgets/waveform_view.dart';
import '../../widgets/error_panel.dart';

class AnalysisScreen extends StatefulWidget {
  const AnalysisScreen({super.key});

  @override
  State<AnalysisScreen> createState() => _AnalysisScreenState();
}

class _AnalysisScreenState extends State<AnalysisScreen> {
  bool _loading = false;
  String? _error;
  PitchData? _pitch;
  InstrumentResult? _instruments;
  bool _instrumentsFailed = false;
  WaveformData? _wave;
  String _source = '';

  Future<void> _pickAndAnalyze() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.audio,
      withData: kIsWeb,
    );
    final file = result?.files.single;
    if (file == null) return;
    Uint8List? bytes = file.bytes;
    if (bytes == null && !kIsWeb && file.path != null) {
      bytes = await File(file.path!).readAsBytes();
    }
    if (bytes == null) return;
    await _run(bytes, file.name);
  }

  Future<void> _run(Uint8List bytes, String name) async {
    final config = context.read<ServerConfig>();
    if (!config.hasServer) {
      setState(() => _error = context.read<LocaleProvider>().strings.analysisNoServer);
      return;
    }
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

  @override
  Widget build(BuildContext context) {
    final strings = context.watch<LocaleProvider>().strings;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Card(
          margin: EdgeInsets.zero,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(strings.analysisPickHint),
                const SizedBox(height: 12),
                FilledButton.icon(
                  onPressed: _loading ? null : _pickAndAnalyze,
                  icon: const Icon(Icons.folder_open),
                  label: Text(strings.analysisPickBtn),
                ),
              ],
            ),
          ),
        ),
        if (_loading) ...[
          const SizedBox(height: 16),
          const LinearProgressIndicator(),
        ],
        if (_error != null) ...[
          const SizedBox(height: 16),
          ErrorPanel(message: _error!, onRetry: _loading ? null : _pickAndAnalyze),
        ],
        if (_source.isNotEmpty) ...[
          const SizedBox(height: 16),
          Text(strings.analysisFileLabel(_source), style: Theme.of(context).textTheme.bodySmall),
          const SizedBox(height: 8),
          if (_wave != null) WaveformView(data: _wave!),
        ],
        if (_pitch != null) ...[
          const SizedBox(height: 16),
          Text(strings.analysisF0Title, style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          PitchContourChart(data: _pitch!),
          const SizedBox(height: 8),
          Text(
            strings.analysisMeanF0(_pitch!.meanF0.toStringAsFixed(1)),
            style: Theme.of(context).textTheme.bodyMedium,
          ),
        ],
        if (_instrumentsFailed) ...[
          const SizedBox(height: 16),
          Text(strings.analysisInstrumentsFail, style: Theme.of(context).textTheme.bodySmall),
        ],
        if (_instruments != null) ...[
          const SizedBox(height: 16),
          Text(strings.analysisInstrumentsTitle, style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          ..._instruments!.segments.map(
            (s) => ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.piano),
              title: Text(s.instrument),
              subtitle: Text('${s.start.toStringAsFixed(1)}s – ${s.end.toStringAsFixed(1)}s'),
              trailing: Text('${(s.confidence * 100).toStringAsFixed(0)}%'),
            ),
          ),
          if (_instruments!.segments.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Text(strings.analysisNoInstruments),
            ),
        ],
      ],
    );
  }
}
