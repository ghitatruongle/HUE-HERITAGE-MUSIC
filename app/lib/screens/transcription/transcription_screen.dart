import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../api/api_client.dart';
import '../../api/endpoints/transcription_api.dart';
import '../../models/transcribe_result.dart';
import '../../services/history_service.dart';
import '../../services/locale_provider.dart';
import '../../services/download_helper.dart';
import '../../services/file_saver.dart';
import '../../services/server_config.dart';
import '../../services/session_media.dart';
import '../../widgets/common_button.dart';
import '../../widgets/sheet_music_view.dart';
import '../../widgets/waveform_view.dart';
import '../../widgets/error_panel.dart';

class TranscriptionScreen extends StatefulWidget {
  const TranscriptionScreen({super.key});

  @override
  State<TranscriptionScreen> createState() => _TranscriptionScreenState();
}

class _TranscriptionScreenState extends State<TranscriptionScreen> {
  final _bpm = TextEditingController(text: '60');
  String _engine = 'basic_pitch';
  String _sourceLabel = '';
  Uint8List? _pickedBytes;
  WaveformData? _waveform;
  bool _busy = false;
  TranscribeResult? _result;
  String? _error;
  double _progress = 0;

  Future<void> _pickFile() async {
    final picked = await FilePicker.platform.pickFiles(type: FileType.audio, withData: true);
    final file = picked?.files.single;
    if (file == null) return;
    Uint8List? bytes = file.bytes;
    if (bytes == null && !kIsWeb && file.path != null) {
      bytes = await File(file.path!).readAsBytes();
    }
    if (bytes == null) return;
    await _applyPicked(bytes, file.name);
  }

  Future<void> _applyPicked(Uint8List bytes, String label) async {
    WaveformData? wave;
    try {
      wave = await compute(parseWaveformData, bytes);
    } catch (_) {}
    if (!mounted) return;
    setState(() {
      _pickedBytes = bytes;
      _waveform = wave;
      _sourceLabel = label;
      _result = null;
      _error = null;
    });
  }

  Future<void> _useRecording() async {
    final strings = context.read<LocaleProvider>().strings;
    final media = context.read<SessionMedia>();
    if (media.recordingBytes == null) {
      setState(() => _error = strings.transcribeNoTake);
      return;
    }
    await _applyPicked(media.recordingBytes!, strings.transcribeRecordedSource);
  }

  Future<void> _run() async {
    final strings = context.read<LocaleProvider>().strings;
    final bpm = double.tryParse(_bpm.text.trim()) ?? 0;
    if (bpm <= 0 || bpm > 300) {
      setState(() => _error = strings.transcribeBpmRange);
      return;
    }
    if (_pickedBytes == null) {
      setState(() => _error = strings.transcribePickFile);
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
      _progress = 0;
      _result = null;
    });
    try {
      final dio = context.read<ServerConfig>().api.dio;
      final history = context.read<HistoryService>();
      final media = context.read<SessionMedia>();
      final data = await TranscriptionApi(dio).transcribeBytes(
        _pickedBytes!,
        bpm: bpm,
        engine: _engine,
        onProgress: (a, b) {
          if (mounted && b > 0) {
            setState(() => _progress = a / b);
          }
        },
      );
      media.clearRecording();
      history.add(
            HistoryEntry(
              id: HistoryService.newId(),
              kind: 'transcribe',
              title: strings.transcribeHistoryTitle(_sourceLabel, data.notes.length),
              status: 'done',
              at: DateTime.now(),
            ),
          );
      if (mounted) {
        setState(() => _result = data);
      }
    } catch (e) {
      if (mounted) {
        setState(() => _error = ApiClient.describe(e));
      }
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  Future<void> _save(bool midi) async {
    final strings = context.read<LocaleProvider>().strings;
    final r = _result;
    if (r == null) {
      return;
    }
    if (r.sha.isEmpty || r.sha.length < 8) {
      setState(() => _error = strings.transcribeNoSha);
      return;
    }
    try {
      final dio = context.read<ServerConfig>().api.dio;
      final api = TranscriptionApi(dio);
      final ext = midi ? 'mid' : 'musicxml';
      final name = 'hue_${r.sha.substring(0, 8)}.$ext';
      if (kIsWeb) {
        final url = midi ? api.midiUrl(r.sha, bpm: r.bpm) : api.xmlUrl(r.sha, bpm: r.bpm);
        var dl = url;
        try {
          final raw = url.substring(url.indexOf('/api/'));
          final qIdx = raw.indexOf('?');
          final pathOnly = qIdx >= 0 ? raw.substring(0, qIdx) : raw;
          final query = qIdx >= 0 ? raw.substring(qIdx + 1) : '';
          final res = await dio.get('/api/music/play-url', queryParameters: {'path': pathOnly});
          final data = res.data;
          if (data is Map && data['url'] is String && (data['url'] as String).isNotEmpty) {
            var signed = data['url'] as String;
            if (!signed.startsWith('http')) signed = '${dio.options.baseUrl}$signed';
            if (query.isNotEmpty) signed = signed.contains('?') ? '$signed&$query' : '$signed?$query';
            dl = signed;
          }
        } catch (_) {}
        triggerDownload(dl, name);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(strings.transcribeDownloadedFile(name))),
          );
        }
        return;
      }
      var savePath = '${Directory.systemTemp.path}/$name';
      var savedNote = strings.transcribeSavedTempFile(name);
      if (Platform.isWindows || Platform.isMacOS || Platform.isLinux) {
        try {
          final picked = await FilePicker.platform.saveFile(
            dialogTitle: strings.saveFileDialog(name),
            fileName: name,
          );
          if (picked == null) {
            return;
          }
          savePath = picked;
          savedNote = strings.transcribeSavedTo(savePath);
        } catch (_) {}
      }
      await api.download(midi ? api.midiUrl(r.sha, bpm: r.bpm) : api.xmlUrl(r.sha, bpm: r.bpm), savePath);
      if (Platform.isAndroid || Platform.isIOS) {
        await shareDownloadedFile(savePath, name);
        try {
          await File(savePath).delete();
        } catch (_) {}
        savedNote = strings.transcribeShareDialog(name);
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(savedNote)),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _error = ApiClient.describe(e));
      }
    }
  }

  @override
  void dispose() {
    _bpm.dispose();
    super.dispose();
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
                Text(strings.transcribePickHint),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    FilledButton.icon(
                      onPressed: _busy ? null : _pickFile,
                      icon: const Icon(Icons.folder_open),
                      label: Text(strings.transcribePickBtn),
                    ),
                    OutlinedButton.icon(
                      onPressed: _busy ? null : _useRecording,
                      icon: const Icon(Icons.mic),
                      label: Text(strings.transcribeUseLast),
                    ),
                  ],
                ),
                if (_sourceLabel.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  Text('${strings.transcribeSource}: $_sourceLabel', style: Theme.of(context).textTheme.bodySmall),
                  if (_waveform != null) ...[
                    const SizedBox(height: 8),
                    WaveformView(data: _waveform!),
                  ],
                ],
                const SizedBox(height: 12),
                Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    SizedBox(
                      width: 110,
                      child: TextField(
                        controller: _bpm,
                        keyboardType: TextInputType.number,
                        decoration: InputDecoration(
                          labelText: strings.transcribeBpm,
                          border: const OutlineInputBorder(),
                          isDense: true,
                        ),
                      ),
                    ),
                    Text('${strings.transcribeEngine}:'),
                    SegmentedButton<String>(
                      segments: const [
                        ButtonSegment(value: 'basic_pitch', label: Text('Basic Pitch')),
                        ButtonSegment(value: 'dsp', label: Text('DSP')),
                      ],
                      selected: {_engine},
                      onSelectionChanged: (s) => setState(() => _engine = s.first),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                CommonButton(
                  label: strings.transcribeRunBtn,
                  loading: _busy,
                  onPressed: _run,
                ),
              ],
            ),
          ),
        ),
        if (_busy) ...[
          const SizedBox(height: 12),
          LinearProgressIndicator(value: _progress > 0 ? _progress : null),
        ],
        if (_error != null) ...[
          const SizedBox(height: 12),
          ErrorPanel(message: _error!),
        ],
        if (_result != null) ...[
          const SizedBox(height: 16),
          Text(strings.transcribeNotesSummary(_result!.label, _result!.notes.length), style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          SheetMusicView(
            notes: _result!.notes
                .map((n) => SheetNote(midi: n.midi, start: n.start, end: n.end))
                .toList(),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              CommonButton(label: strings.transcribeMidiBtn, onPressed: () => _save(true)),
              CommonButton(label: strings.transcribeXmlBtn, onPressed: () => _save(false)),
            ],
          ),
          const SizedBox(height: 12),
          for (final n in _result!.notes.take(50))
            ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.music_note, size: 18),
              title: Text(n.name),
              subtitle: Text('${n.start}s - ${n.end}s'),
            ),
          if (_result!.notes.length > 50)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                strings.transcribeMoreNotes(_result!.notes.length - 50),
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
        ],
      ],
    );
  }
}
