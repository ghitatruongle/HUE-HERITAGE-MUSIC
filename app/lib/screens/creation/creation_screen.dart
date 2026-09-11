import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../api/endpoints/music_api.dart';
import '../../models/music_task.dart';
import '../../services/server_config.dart';
import '../../widgets/common_button.dart';

class CreationScreen extends StatefulWidget {
  const CreationScreen({super.key});

  @override
  State<CreationScreen> createState() => _CreationScreenState();
}

class _CreationScreenState extends State<CreationScreen> {
  final _prompt = TextEditingController();
  bool _busy = false;
  MusicTask? _task;
  String? _error;
  List<LoraAdapter> _loras = [];
  String _lora = '';

  @override
  void initState() {
    super.initState();
    _loadModels();
  }

  Future<void> _loadModels() async {
    try {
      final dio = context.read<ServerConfig>().api.dio;
      final list = await MusicApi(dio).models();
      if (mounted) {
        setState(() => _loras = list);
      }
    } catch (e) {
      if (mounted) {
        setState(() => _error = 'Không tải được danh sách LoRA: $e');
      }
    }
  }

  Future<void> _run() async {
    if (_prompt.text.trim().isEmpty) {
      setState(() => _error = 'Nhập mô tả bài nhạc');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
      _task = null;
    });
    try {
      final dio = context.read<ServerConfig>().api.dio;
      final t = await MusicApi(dio).generate(prompt: _prompt.text.trim(), lora: _lora);
      if (mounted) {
        setState(() => _task = t);
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

  @override
  void dispose() {
    _prompt.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        TextField(
          controller: _prompt,
          maxLines: 3,
          decoration: const InputDecoration(
            labelText: 'Mô tả (Ca Huế, đàn tranh...)',
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 8),
        DropdownButton<String>(
          value: _lora,
          hint: const Text('LoRA'),
          items: [
            const DropdownMenuItem(value: '', child: Text('Không dùng LoRA')),
            for (final l in _loras)
              DropdownMenuItem(value: l.name, child: Text('${l.name}${l.ready ? '' : ' (chưa có)'}')),
          ],
          onChanged: (v) => setState(() => _lora = v ?? ''),
        ),
        const SizedBox(height: 8),
        CommonButton(label: 'Tạo nhạc', loading: _busy, onPressed: _run),
        if (_error != null)
          Text(_error!, style: const TextStyle(color: Colors.red)),
        if (_task != null) ...[
          Text('Trạng thái: ${_task!.status}'),
          if (_task!.reason.isNotEmpty) Text('Lý do: ${_task!.reason}'),
        ],
      ],
    );
  }
}
