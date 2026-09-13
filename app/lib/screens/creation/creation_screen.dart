import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../api/api_client.dart';
import '../../api/endpoints/music_api.dart';
import '../../models/music_task.dart';
import '../../services/history_service.dart';
import '../../services/server_config.dart';
import '../../widgets/audio_player_bar.dart';
import '../../widgets/common_button.dart';

class CreationScreen extends StatefulWidget {
  final bool coverMode;

  const CreationScreen({super.key, this.coverMode = false});

  @override
  State<CreationScreen> createState() => _CreationScreenState();
}

class _CreationScreenState extends State<CreationScreen> {
  final _prompt = TextEditingController();
  final _lyrics = TextEditingController();
  final _genre = TextEditingController(text: 'Ca Huế');
  final _instruments = TextEditingController(text: 'đàn tranh, đàn nguyệt, sáo');
  final _style = TextEditingController();
  String _tempo = 'Chậm';
  String _mood = 'Trữ tình';
  String _vocal = 'Nữ';
  int _duration = 60;
  double _strength = 0.8;
  bool _busy = false;
  bool _polling = false;
  MusicTask? _task;
  String? _error;
  String? _info;
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
        setState(() {
          _loras = list;
          _info = list.any((l) => l.ready) ? null : 'Chưa có LoRA nào trên máy chủ.';
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _info = 'Không tải được danh sách LoRA: ${ApiClient.describe(e)}');
      }
    }
  }

  Future<void> _run() async {
    if (!widget.coverMode && _prompt.text.trim().isEmpty) {
      setState(() => _error = 'Nhập mô tả bài nhạc');
      return;
    }
    if (widget.coverMode && _style.text.trim().isEmpty) {
      setState(() => _error = 'Nhập phong cách cover mong muốn');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
      _task = null;
    });
    final history = context.read<HistoryService>();
    final server = context.read<ServerConfig>();
    try {
      final dio = server.api.dio;
      final api = MusicApi(dio);
      final t = widget.coverMode
          ? await api.cover(
              heritageId: '',
              style: _style.text.trim(),
              duration: _duration,
              lora: _lora,
              strength: _strength,
              tempo: _tempo,
              mood: _mood,
              vocal: _vocal,
            )
          : await api.generate(
              prompt: _prompt.text.trim(),
              duration: _duration,
              lora: _lora,
              strength: _strength,
              lyrics: _lyrics.text.trim(),
              genre: _genre.text.trim(),
              instruments: _instruments.text.trim(),
              tempo: _tempo,
              mood: _mood,
              vocal: _vocal,
            );
      history.add(
            HistoryEntry(
              id: t.id,
              kind: widget.coverMode ? 'cover' : 'generate',
              title: widget.coverMode ? 'Cover: ${_style.text.trim()}' : _prompt.text.trim(),
              status: t.status,
              at: DateTime.now(),
            ),
          );
      if (!mounted) return;
      setState(() => _task = t);
      if (t.status == 'running' || t.status == 'pending') {
        unawaited(_poll(t.id));
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

  Future<void> _poll(String id) async {
    setState(() => _polling = true);
    final server = context.read<ServerConfig>();
    final history = context.read<HistoryService>();
    for (int i = 0; i < 60; i++) {
      await Future<void>.delayed(const Duration(seconds: 2));
      if (!mounted) return;
      try {
        final t = await MusicApi(server.api.dio).task(id);
        setState(() => _task = t);
        if (t.status != 'running' && t.status != 'pending') {
          await history.updateStatus(id, t.status);
          break;
        }
      } catch (_) {
        break;
      }
    }
    if (mounted) {
      setState(() => _polling = false);
    }
  }

  @override
  void dispose() {
    _prompt.dispose();
    _lyrics.dispose();
    _genre.dispose();
    _instruments.dispose();
    _style.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        Card(
          color: scheme.secondaryContainer,
          margin: EdgeInsets.zero,
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                Icon(Icons.science_outlined, size: 20, color: scheme.onSecondaryContainer),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Chức năng sinh nhạc cần model ACE-Step + HueMusic-LoRA đã được huấn luyện trên máy chủ. '
                    'Hiện tại máy chủ chưa có trọng số nên tác vụ sẽ trả về trạng thái "blocked".',
                    style: TextStyle(color: scheme.onSecondaryContainer, height: 1.4),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        if (!widget.coverMode) ...[
          TextField(
            controller: _prompt,
            maxLines: 3,
            decoration: const InputDecoration(
              labelText: 'Mô tả bài nhạc *',
              hintText: 'VD: Tác phẩm Ca Huế nhẹ nhàng với đàn tranh, đàn nguyệt và sáo',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _lyrics,
            maxLines: 3,
            decoration: const InputDecoration(
              labelText: 'Lời bài hát (tùy chọn)',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 10),
          _row([
            _field('Thể loại', _genre),
            _field('Nhạc cụ', _instruments),
          ]),
          const SizedBox(height: 10),
        ] else ...[
          TextField(
            controller: _style,
            maxLines: 2,
            decoration: const InputDecoration(
              labelText: 'Phong cách cover mong muốn *',
              hintText: 'VD: chuyển sang âm hưởng Ca Huế, thay đàn guitar bằng đàn tranh',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 10),
        ],
        _row([
          _dropdown('Tempo', _tempo, ['Chậm', 'Vừa', 'Nhanh'], (v) => setState(() => _tempo = v)),
          _dropdown('Cảm xúc', _mood, ['Trữ tình', 'Hùng tráng', 'Tươi vui', 'Trầm lắng'], (v) => setState(() => _mood = v)),
          _dropdown('Giọng hát', _vocal, ['Nữ', 'Nam', 'Không lời'], (v) => setState(() => _vocal = v)),
        ]),
        const SizedBox(height: 10),
        _row([
          _dropdown('Thời lượng (giây)', '$_duration', ['30', '60', '120', '180'], (v) => setState(() => _duration = int.parse(v))),
          _dropdown('LoRA strength', _strength.toStringAsFixed(1), ['0.4', '0.6', '0.8', '1.0'],
              (v) => setState(() => _strength = double.parse(v))),
        ]),
        const SizedBox(height: 10),
        DropdownButtonFormField<String>(
          initialValue: _lora.isEmpty ? '' : _lora,
          decoration: const InputDecoration(labelText: 'LoRA adapter', border: OutlineInputBorder()),
          items: [
            const DropdownMenuItem(value: '', child: Text('Không dùng LoRA')),
            for (final l in _loras)
              DropdownMenuItem(value: l.name, child: Text('${l.name}${l.ready ? '' : ' (chưa có)'}')),
          ],
          onChanged: (v) => setState(() => _lora = v ?? ''),
        ),
        const SizedBox(height: 12),
        CommonButton(
          label: widget.coverMode ? 'Tạo cover' : 'Tạo nhạc',
          loading: _busy,
          onPressed: _run,
        ),
        if (_info != null) ...[
          const SizedBox(height: 8),
          Text(_info!, style: Theme.of(context).textTheme.bodySmall),
        ],
        if (_error != null) ...[
          const SizedBox(height: 8),
          Text(_error!, style: TextStyle(color: scheme.error)),
        ],
        if (_task != null) ...[
          const SizedBox(height: 16),
          Card(
            margin: EdgeInsets.zero,
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Text('Trạng thái:', style: TextStyle(fontWeight: FontWeight.w600)),
                      const SizedBox(width: 8),
                      Text(_task!.status),
                      if (_polling) ...[
                        const SizedBox(width: 8),
                        const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2)),
                      ],
                    ],
                  ),
                  if (_task!.reason.isNotEmpty) ...[
                    const SizedBox(height: 6),
                    Text('Lý do: ${_task!.reason}'),
                  ],
                  if (_task!.status == 'done' && _task!.audioUrl.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Icon(Icons.label_important_outline, size: 16, color: scheme.primary),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            'TÁC PHẨM ĐƯỢC AI TẠO MỚI (AI_GENERATED)',
                            style: Theme.of(context).textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w700),
                          ),
                        ),
                      ],
                    ),
                    Builder(
                      builder: (context) {
                        final fullUrl = '${context.read<ServerConfig>().baseUrl}${_task!.audioUrl}';
                        return AudioPlayerBar(url: fullUrl);
                      },
                    ),
                    if (_task!.info.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 6),
                        child: Text(_task!.info, style: Theme.of(context).textTheme.bodySmall),
                      ),
                  ],
                  if (_task!.status == 'blocked') ...[
                    const SizedBox(height: 6),
                    const Text(
                      'Máy chủ chưa có model AI sinh nhạc đã huấn luyện. '
                      'Tác phẩm AI cần HuếMusic-LoRA được huấn luyện từ dataset Ca Huế / Nhã nhạc.',
                    ),
                  ],
                  if (_task!.status == 'done') ...[
                    const SizedBox(height: 6),
                    const Text('Tác phẩm AI đã tạo xong (đánh dấu AI_GENERATED).'),
                  ],
                ],
              ),
            ),
          ),
        ],
      ],
    );
  }

  Widget _row(List<Widget> children) {
    return Row(
      children: [
        for (int i = 0; i < children.length; i++) ...[
          Expanded(child: children[i]),
          if (i < children.length - 1) const SizedBox(width: 10),
        ],
      ],
    );
  }

  Widget _field(String label, TextEditingController ctrl) {
    return TextField(
      controller: ctrl,
      decoration: InputDecoration(labelText: label, border: const OutlineInputBorder(), isDense: true),
    );
  }

  Widget _dropdown(String label, String value, List<String> items, ValueChanged<String> onChanged) {
    return DropdownButtonFormField<String>(
      initialValue: value,
      decoration: InputDecoration(labelText: label, border: const OutlineInputBorder(), isDense: true),
      items: [for (final it in items) DropdownMenuItem(value: it, child: Text(it))],
      onChanged: (v) => onChanged(v ?? value),
    );
  }
}
