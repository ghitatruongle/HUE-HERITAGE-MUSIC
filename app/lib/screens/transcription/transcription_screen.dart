import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../api/endpoints/transcription_api.dart';
import '../../models/transcribe_result.dart';
import '../../services/server_config.dart';
import '../../services/session_media.dart';
import '../../widgets/common_button.dart';

class TranscriptionScreen extends StatefulWidget {
  const TranscriptionScreen({super.key});

  @override
  State<TranscriptionScreen> createState() => _TranscriptionScreenState();
}

class _TranscriptionScreenState extends State<TranscriptionScreen> {
  final _bpm = TextEditingController(text: '60');
  bool _busy = false;
  TranscribeResult? _result;
  String? _error;
  double _progress = 0;

  String _srcPath() {
    return '${Directory.systemTemp.path}/hue_learn.wav';
  }

  Future<void> _run() async {
    final bpm = double.tryParse(_bpm.text.trim()) ?? 0;
    if (bpm <= 0 || bpm > 300) {
      setState(() => _error = 'BPM trong khoảng 1-300');
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
      final api = TranscriptionApi(dio);
      TranscribeResult data;
      if (kIsWeb) {
        final bytes = context.read<SessionMedia>().recordingBytes;
        if (bytes == null) {
          setState(() => _error = 'Chưa có bản thu (sang màn Học hát để thu âm trước)');
          return;
        }
        data = await api.transcribeBytes(
          bytes,
          bpm: bpm,
          onProgress: (a, b) {
            if (mounted && b > 0) {
              setState(() => _progress = a / b);
            }
          },
        );
      } else {
        final path = _srcPath();
        if (!File(path).existsSync()) {
          setState(() => _error = 'Chưa có bản thu (sang màn Học hát để thu âm trước)');
          return;
        }
        data = await api.transcribe(
          path,
          bpm: bpm,
          onProgress: (a, b) {
            if (mounted && b > 0) {
              setState(() => _progress = a / b);
            }
          },
        );
      }
      if (mounted) {
        setState(() => _result = data);
      }
    } catch (e) {
      if (mounted) {
        setState(() => _error = e.toString());
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
      if (kIsWeb) {
        final url = midi ? api.midiUrl(r.sha) : api.xmlUrl(r.sha);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Mở link để tải: $url')),
          );
        }
        return;
      }
      final ext = midi ? 'mid' : 'musicxml';
      final savePath = '${Directory.systemTemp.path}/hue_${r.sha.substring(0, 8)}.$ext';
      await api.download(midi ? api.midiUrl(r.sha) : api.xmlUrl(r.sha), savePath);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Đã lưu $savePath')),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _error = e.toString());
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
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(8),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _bpm,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'BPM',
                    border: OutlineInputBorder(),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              CommonButton(
                label: 'Phân tích',
                loading: _busy,
                onPressed: _run,
              ),
            ],
          ),
        ),
        if (_busy) LinearProgressIndicator(value: _progress > 0 ? _progress : null),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.all(8),
            child: Text(_error!, style: const TextStyle(color: Colors.red)),
          ),
        if (_result != null) ...[
          Padding(
            padding: const EdgeInsets.all(8),
            child: Text('${_result!.label} · ${_result!.notes.length} nốt'),
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              CommonButton(label: 'Tải MIDI', onPressed: () => _save(true)),
              CommonButton(label: 'Tải MusicXML', onPressed: () => _save(false)),
            ],
          ),
          Expanded(
            child: ListView.builder(
              itemCount: _result!.notes.length,
              itemBuilder: (context, i) {
                final n = _result!.notes[i];
                return ListTile(
                  title: Text(n.name),
                  subtitle: Text('${n.start}s - ${n.end}s'),
                );
              },
            ),
          ),
        ],
      ],
    );
  }
}
