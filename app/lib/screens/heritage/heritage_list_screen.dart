import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../api/endpoints/heritage_api.dart';
import '../../api/endpoints/instrument_api.dart';
import '../../api/endpoints/restoration_api.dart';
import '../../models/heritage_item.dart';
import '../../models/instrument_result.dart';
import '../../models/restore_result.dart';
import '../../services/server_config.dart';
import '../../services/session_media.dart';
import '../../widgets/audio_player_bar.dart';
import '../../widgets/common_button.dart';

class HeritageListScreen extends StatefulWidget {
  const HeritageListScreen({super.key});

  @override
  State<HeritageListScreen> createState() => _HeritageListScreenState();
}

class _HeritageListScreenState extends State<HeritageListScreen> {
  final _search = TextEditingController();
  Future<List<HeritageItem>>? _future;

  @override
  void initState() {
    super.initState();
    _future = _load('');
  }

  Future<List<HeritageItem>> _load(String q) {
    final dio = context.read<ServerConfig>().api.dio;
    return HeritageApi(dio).list(q: q);
  }

  void _play(HeritageItem item) {
    final dio = context.read<ServerConfig>().api.dio;
    final url = HeritageApi(dio).audioUrl(item.id);
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(item.title),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            AudioPlayerBar(url: url),
            const SizedBox(height: 8),
            CommonButton(
              label: 'Phục dựng bản ghi',
              onPressed: () {
                Navigator.pop(context);
                _restore(item);
              },
            ),
            const SizedBox(height: 8),
            CommonButton(
              label: 'Nhận diện nhạc cụ',
              onPressed: () {
                Navigator.pop(context);
                _detect(item);
              },
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Đóng'),
          ),
        ],
      ),
    );
  }

  void _restore(HeritageItem item) {
    final dio = context.read<ServerConfig>().api.dio;
    final fut = RestorationApi(dio).restoreItem(item.id);
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Bản phục dựng'),
        content: FutureBuilder<RestoreResult>(
          future: fut,
          builder: (context, snap) {
            if (snap.connectionState == ConnectionState.waiting) {
              return const Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CircularProgressIndicator(),
                  SizedBox(height: 8),
                  Text('Đang xử lý...'),
                ],
              );
            }
            if (snap.hasError) {
              return Text('Lỗi: ${snap.error}');
            }
            final r = snap.data!;
            final url = RestorationApi(dio).restoredUrl(r.sha);
            return Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(r.label),
                Text('DC: ${r.dcRemoved} · Clicks: ${r.clicksFixed}'),
                Text('Peak: ${r.peakBefore} -> ${r.peakAfter}'),
                AudioPlayerBar(url: url),
              ],
            );
          },
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Đóng'),
          ),
        ],
      ),
    );
  }

  void _useAsSample(HeritageItem item) async {
    try {
      final dio = context.read<ServerConfig>().api.dio;
      final api = HeritageApi(dio);
      final media = context.read<SessionMedia>();
      if (kIsWeb) {
        final bytes = await api.audioBytes(item.id);
        if (!mounted) {
          return;
        }
        media.setSample(bytes: bytes);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Đã chọn bản mẫu')),
        );
        return;
      }
      final savePath = '${Directory.systemTemp.path}/hue_sample.wav';
      await api.downloadAudio(item.id, savePath);
      if (!mounted) {
        return;
      }
      media.setSample(path: savePath);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Đã tải bản mẫu')),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Loi: $e')),
        );
      }
    }
  }

  void _detect(HeritageItem item) {
    final dio = context.read<ServerConfig>().api.dio;
    final fut = InstrumentApi(dio).detectByItem(item.id);
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Nhạc cụ'),
        content: FutureBuilder<InstrumentResult>(
          future: fut,
          builder: (context, snap) {
            if (snap.connectionState == ConnectionState.waiting) {
              return const Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CircularProgressIndicator(),
                  SizedBox(height: 8),
                  Text('Đang phân tích...'),
                ],
              );
            }
            if (snap.hasError) {
              return Text('Lỗi: ${snap.error}');
            }
            final r = snap.data!;
            return Flexible(
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(r.label),
                    for (final s in r.segments)
                      ListTile(
                        title: Text(s.instrument),
                        subtitle: Text('${s.start}s - ${s.end}s'),
                        trailing: Text('${(s.confidence * 100).toInt()}%'),
                      ),
                  ],
                ),
              ),
            );
          },
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Đóng'),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _search.dispose();
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
                  controller: _search,
                  decoration: const InputDecoration(
                    hintText: 'Tìm tên, nghệ nhân, loại hình',
                    border: OutlineInputBorder(),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              CommonButton(
                label: 'Tìm',
                onPressed: () => setState(() => _future = _load(_search.text)),
              ),
            ],
          ),
        ),
        Expanded(
          child: FutureBuilder<List<HeritageItem>>(
            future: _future,
            builder: (context, snap) {
              if (snap.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }
              if (snap.hasError) {
                return Center(child: Text('Loi: ${snap.error}'));
              }
              final items = snap.data ?? [];
              if (items.isEmpty) {
                return const Center(child: Text('Chưa có bản ghi'));
              }
              return ListView.builder(
                itemCount: items.length,
                itemBuilder: (context, i) {
                  final it = items[i];
                  return ListTile(
                    title: Text(it.title),
                    subtitle: Text('${it.artist} - ${it.type}'),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          icon: const Icon(Icons.play_arrow),
                          onPressed: () => _play(it),
                        ),
                        IconButton(
                          icon: const Icon(Icons.school),
                          onPressed: () => _useAsSample(it),
                        ),
                      ],
                    ),
                  );
                },
              );
            },
          ),
        ),
      ],
    );
  }
}
