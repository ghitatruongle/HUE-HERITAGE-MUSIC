import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../api/api_client.dart';
import '../../api/endpoints/transcription_api.dart';
import '../../models/transcribe_result.dart';
import '../../services/history_service.dart';
import '../../services/download_helper.dart';
import '../../services/server_config.dart';
import '../../services/session_media.dart';
import '../../widgets/common_button.dart';
import '../../widgets/sheet_music_view.dart';
import '../../widgets/waveform_view.dart';

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
    setState(() {
      _pickedBytes = bytes;
      _sourceLabel = file.name;
      _result = null;
      _error = null;
    });
  }

  void _useRecording() {
    final media = context.read<SessionMedia>();
    if (media.recordingBytes == null) {
      setState(() => _error = 'Chưa có bản thu. Hãy thu âm ở màn Học hát hoặc chọn tệp.');
      return;
    }
    setState(() {
      _pickedBytes = media.recordingBytes;
      _sourceLabel = 'bản thu vừa ghi';
      _result = null;
      _error = null;
    });
  }

  Future<void> _run() async {
    final bpm = double.tryParse(_bpm.text.trim()) ?? 0;
    if (bpm <= 0 || bpm > 300) {
      setState(() => _error = 'BPM trong khoảng 1-300');
      return;
    }
    if (_pickedBytes == null) {
      setState(() => _error = 'Chưa chọn tệp âm thanh.');
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
      history.add(
            HistoryEntry(
              id: data.sha,
              kind: 'transcribe',
              title: 'Ký âm $_sourceLabel (${data.notes.length} nốt)',
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
    final r = _result;
    if (r == null) {
      return;
    }
    if (r.sha.isEmpty || r.sha.length < 8) {
      setState(() => _error = 'Thiếu mã băm để tải file');
      return;
    }
    try {
      final dio = context.read<ServerConfig>().api.dio;
      final api = TranscriptionApi(dio);
      final ext = midi ? 'mid' : 'musicxml';
      final name = 'hue_${r.sha.substring(0, 8)}.$ext';
      if (kIsWeb) {
        final url = midi ? api.midiUrl(r.sha, bpm: r.bpm) : api.xmlUrl(r.sha, bpm: r.bpm);
        triggerDownload(url, name);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Đã tải xuống $name')),
          );
        }
        return;
      }
      final savePath = '${Directory.systemTemp.path}/$name';
      await api.download(midi ? api.midiUrl(r.sha, bpm: r.bpm) : api.xmlUrl(r.sha, bpm: r.bpm), savePath);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Đã lưu $name vào thư mục tạm')),
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
    final scheme = Theme.of(context).colorScheme;
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
                const Text('Chọn tệp âm thanh (bản thu đã lưu ở máy chủ sẽ được liên kết khi ký âm).'),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    FilledButton.icon(
                      onPressed: _busy ? null : _pickFile,
                      icon: const Icon(Icons.folder_open),
                      label: const Text('Chọn tệp'),
                    ),
                    OutlinedButton.icon(
                      onPressed: _busy ? null : _useRecording,
                      icon: const Icon(Icons.mic),
                      label: const Text('Dùng bản thu vừa ghi'),
                    ),
                  ],
                ),
                if (_sourceLabel.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  Text('Nguồn: $_sourceLabel', style: Theme.of(context).textTheme.bodySmall),
                  if (_pickedBytes != null) ...[
                    const SizedBox(height: 8),
                    WaveformView(data: WaveformData.fromWavBytes(_pickedBytes!)),
                  ],
                ],
                const SizedBox(height: 12),
                Row(
                  children: [
                    SizedBox(
                      width: 110,
                      child: TextField(
                        controller: _bpm,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(
                          labelText: 'BPM',
                          border: OutlineInputBorder(),
                          isDense: true,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    const Text('Bộ máy:'),
                    const SizedBox(width: 8),
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
                  label: 'Phân tích ký âm',
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
          Card(
            color: scheme.errorContainer,
            margin: EdgeInsets.zero,
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Text(_error!, style: TextStyle(color: scheme.onErrorContainer)),
            ),
          ),
        ],
        if (_result != null) ...[
          const SizedBox(height: 16),
          Text('${_result!.label} · ${_result!.notes.length} nốt', style: Theme.of(context).textTheme.titleMedium),
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
              CommonButton(label: 'Tải MIDI', onPressed: () => _save(true)),
              CommonButton(label: 'Tải MusicXML', onPressed: () => _save(false)),
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
                '... và ${_result!.notes.length - 50} nốt nữa (xem trong tệp MIDI/MusicXML)',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
        ],
      ],
    );
  }
}
