import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../api/api_client.dart';
import '../../api/endpoints/instrument_api.dart';
import '../../models/instrument_result.dart';
import '../../services/server_config.dart';

class InstrumentsScreen extends StatefulWidget {
  const InstrumentsScreen({super.key});

  @override
  State<InstrumentsScreen> createState() => _InstrumentsScreenState();
}

class _InstrumentsScreenState extends State<InstrumentsScreen> {
  bool _loading = false;
  String? _error;
  InstrumentResult? _result;
  String _source = '';

  Future<void> _pickAndDetect() async {
    final result = await FilePicker.platform.pickFiles(type: FileType.audio, withData: true);
    final file = result?.files.single;
    if (file == null || file.bytes == null) return;
    await _run(file.bytes!, file.name);
  }

  Future<void> _run(Uint8List bytes, String name) async {
    final config = context.read<ServerConfig>();
    if (!config.hasServer) {
      setState(() => _error = 'Chưa cấu hình máy chủ. Vào Cài đặt để nhập địa chỉ.');
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
      _result = null;
      _source = name;
    });
    try {
      final res = await InstrumentApi(config.api.dio).detectBytes(bytes, name);
      setState(() => _result = res);
    } catch (e) {
      setState(() => _error = ApiClient.describe(e));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
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
                const Text(
                  'Nhận diện nhạc cụ truyền thống (đàn tranh, đàn nguyệt, sáo, trống...) '
                  'trong bản thu bằng phân tích tín hiệu. Kết quả mang tính tham khảo.',
                ),
                const SizedBox(height: 12),
                FilledButton.icon(
                  onPressed: _loading ? null : _pickAndDetect,
                  icon: const Icon(Icons.folder_open),
                  label: const Text('Chọn tệp âm thanh'),
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
          Card(
            color: scheme.errorContainer,
            margin: EdgeInsets.zero,
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  Icon(Icons.error_outline, color: scheme.onErrorContainer),
                  const SizedBox(width: 8),
                  Expanded(child: Text(_error!)),
                ],
              ),
            ),
          ),
        ],
        if (_result != null) ...[
          const SizedBox(height: 16),
          Text('Kết quả: $_source', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          ..._result!.segments.map(
            (s) => Card(
              margin: const EdgeInsets.only(bottom: 8),
              child: ListTile(
                leading: const Icon(Icons.music_note),
                title: Text(s.instrument),
                subtitle: Text('${s.start.toStringAsFixed(1)}s – ${s.end.toStringAsFixed(1)}s'),
                trailing: Text('${(s.confidence * 100).toStringAsFixed(0)}%'),
              ),
            ),
          ),
          if (_result!.segments.isEmpty)
            const Card(
              child: Padding(
                padding: EdgeInsets.all(12),
                child: Text('Không nhận diện được nhạc cụ nào trong bản thu này.'),
              ),
            ),
        ],
      ],
    );
  }
}
