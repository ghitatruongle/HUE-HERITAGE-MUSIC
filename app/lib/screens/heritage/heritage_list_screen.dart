import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../api/api_client.dart';
import '../../api/endpoints/heritage_api.dart';
import '../../api/endpoints/instrument_api.dart';
import '../../api/endpoints/restoration_api.dart';
import '../../models/heritage_item.dart';
import '../../models/instrument_result.dart';
import '../../models/restore_result.dart';
import '../../services/history_service.dart';
import '../../services/server_config.dart';
import '../../services/session_media.dart';
import '../../widgets/audio_player_bar.dart';
import '../../widgets/common_button.dart';

class HeritageListScreen extends StatefulWidget {
  final bool restorationMode;

  const HeritageListScreen({super.key, this.restorationMode = false});

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

  void _reload() {
    setState(() => _future = _load(_search.text));
  }

  void _log(String kind, String title, String status) {
    context.read<HistoryService>().add(
          HistoryEntry(id: DateTime.now().microsecondsSinceEpoch.toString(), kind: kind, title: title, status: status, at: DateTime.now()),
        );
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
              label: 'Xem thông tin chi tiết',
              onPressed: () {
                Navigator.pop(context);
                _showDetail(item);
              },
            ),
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

  void _showDetail(HeritageItem item) {
    final rows = item.metadataRows();
    showModalBottomSheet(
      context: context,
      showDragHandle: true,
      builder: (_) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(item.title, style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 4),
              Text(
                'Mã SHA-256: ${item.sha256.substring(0, 16)}...',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
              ),
              const Divider(height: 24),
              for (final e in rows.entries)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SizedBox(
                        width: 140,
                        child: Text(e.key, style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant)),
                      ),
                      Expanded(child: Text(e.value)),
                    ],
                  ),
                ),
              if (item.description.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(item.description),
              ],
              if (item.lyrics.isNotEmpty) ...[
                const SizedBox(height: 12),
                Text('Lời bài hát', style: Theme.of(context).textTheme.titleSmall),
                const SizedBox(height: 4),
                Text(item.lyrics),
              ],
              const SizedBox(height: 12),
              Row(
                children: [
                  Icon(Icons.verified_outlined, size: 16, color: Theme.of(context).colorScheme.primary),
                  const SizedBox(width: 6),
                  const Expanded(child: Text('Bản thu gốc (ORIGINAL) được bảo toàn, không ghi đè.')),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _uploadDialog() async {
    final config = context.read<ServerConfig>();
    if (!config.hasServer) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Chưa cấu hình máy chủ. Vào Cài đặt để nhập địa chỉ.')),
      );
      return;
    }
    final picked = await FilePicker.platform.pickFiles(type: FileType.audio, withData: !kIsWeb);
    final file = picked?.files.single;
    if (file == null) return;
    final data = await _metadataForm();
    if (data == null) return;
    try {
      final api = HeritageApi(config.api.dio);
      final item = kIsWeb
          ? await api.uploadBytes(bytes: file.bytes!, filename: file.name, data: data)
          : await api.upload(filePath: file.path!, data: data);
      _log('heritage-upload', item.title, 'done');
      _reload();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Đã thêm "${item.title}" vào kho di sản.')));
      }
    } catch (e) {
      _log('heritage-upload', file.name, 'error');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(ApiClient.describe(e))));
      }
    }
  }

  Future<HeritageUploadData?> _metadataForm() async {
    final ctrls = {
      'title': TextEditingController(),
      'type': TextEditingController(),
      'artist': TextEditingController(),
      'genre': TextEditingController(),
      'composer': TextEditingController(),
      'performers': TextEditingController(),
      'artisans': TextEditingController(),
      'collector': TextEditingController(),
      'recorded_time': TextEditingController(),
      'location': TextEditingController(),
      'source': TextEditingController(),
      'license': TextEditingController(),
      'instruments': TextEditingController(),
      'tonal': TextEditingController(),
      'description': TextEditingController(),
      'notes': TextEditingController(),
      'lyrics': TextEditingController(),
      'bpm': TextEditingController(),
    };
    final labels = {
      'title': 'Tên tác phẩm *',
      'type': 'Loại hình (Ca Huế, Nhã nhạc...)',
      'artist': 'Nghệ nhân / Nghệ sĩ',
      'genre': 'Thể loại',
      'composer': 'Tác giả',
      'performers': 'Người biểu diễn',
      'artisans': 'Nghệ nhân liên quan',
      'collector': 'Người sưu tầm',
      'recorded_time': 'Thời gian thu',
      'location': 'Địa điểm',
      'source': 'Nguồn',
      'license': 'Quyền sử dụng',
      'instruments': 'Nhạc cụ',
      'tonal': 'Cung bậc / Tông',
      'description': 'Mô tả',
      'notes': 'Ghi chú nghiên cứu',
      'lyrics': 'Lời bài hát',
      'bpm': 'BPM (nếu biết)',
    };
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Thông tin tác phẩm'),
        content: SizedBox(
          width: 420,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (final e in labels.entries) ...[
                  TextField(
                    controller: ctrls[e.key],
                    decoration: InputDecoration(labelText: e.value, isDense: true, border: const OutlineInputBorder()),
                    minLines: e.key == 'lyrics' || e.key == 'description' ? 2 : 1,
                    maxLines: e.key == 'lyrics' || e.key == 'description' ? 4 : 1,
                    keyboardType: e.key == 'bpm' ? TextInputType.number : TextInputType.text,
                  ),
                  const SizedBox(height: 8),
                ],
              ],
            ),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Hủy')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Thêm vào kho')),
        ],
      ),
    );
    if (ok != true) return null;
    return HeritageUploadData(
      title: ctrls['title']!.text.trim(),
      type: ctrls['type']!.text.trim(),
      artist: ctrls['artist']!.text.trim(),
      genre: ctrls['genre']!.text.trim(),
      composer: ctrls['composer']!.text.trim(),
      performers: ctrls['performers']!.text.trim(),
      artisans: ctrls['artisans']!.text.trim(),
      collector: ctrls['collector']!.text.trim(),
      recordedTime: ctrls['recorded_time']!.text.trim(),
      location: ctrls['location']!.text.trim(),
      source: ctrls['source']!.text.trim(),
      license: ctrls['license']!.text.trim(),
      instruments: ctrls['instruments']!.text.trim(),
      tonal: ctrls['tonal']!.text.trim(),
      description: ctrls['description']!.text.trim(),
      notes: ctrls['notes']!.text.trim(),
      lyrics: ctrls['lyrics']!.text.trim(),
      bpm: ctrls['bpm']!.text.trim(),
    );
  }

  void _restore(HeritageItem item) {
    final dio = context.read<ServerConfig>().api.dio;
    final fut = RestorationApi(dio).restoreItem(item.id);
    _log('restore', item.title, 'running');
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
              return Text('Lỗi: ${ApiClient.describe(snap.error!)}');
            }
            final r = snap.data!;
            final url = RestorationApi(dio).restoredUrl(r.sha);
            WidgetsBinding.instance.addPostFrameCallback((_) => _log('restore', item.title, 'done'));
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
          SnackBar(content: Text(ApiClient.describe(e))),
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
              return Text('Lỗi: ${ApiClient.describe(snap.error!)}');
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
    return Scaffold(
      backgroundColor: Colors.transparent,
      floatingActionButton: FloatingActionButton.extended(
        heroTag: 'heritage-upload',
        onPressed: _uploadDialog,
        icon: const Icon(Icons.upload_file),
        label: const Text('Thêm bản ghi'),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(8),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _search,
                    onSubmitted: (_) => _reload(),
                    decoration: const InputDecoration(
                      hintText: 'Tìm theo tên, nghệ nhân, nhạc cụ, thời gian, địa điểm...',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                CommonButton(
                  label: 'Tìm',
                  onPressed: _reload,
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
                  return Center(child: Text('Lỗi: ${ApiClient.describe(snap.error!)}'));
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
                      subtitle: Text(
                        [
                          if (it.type.isNotEmpty) it.type,
                          if (it.artist.isNotEmpty) it.artist,
                          if (it.recordedTime.isNotEmpty) it.recordedTime,
                        ].join(' • '),
                      ),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            icon: const Icon(Icons.play_arrow),
                            tooltip: 'Nghe bản gốc',
                            onPressed: () => _play(it),
                          ),
                          if (widget.restorationMode)
                            IconButton(
                              icon: const Icon(Icons.healing),
                              tooltip: 'Phục dựng',
                              onPressed: () => _restore(it),
                            )
                          else ...[
                            IconButton(
                              icon: const Icon(Icons.info_outline),
                              tooltip: 'Chi tiết',
                              onPressed: () => _showDetail(it),
                            ),
                            IconButton(
                              icon: const Icon(Icons.school),
                              tooltip: 'Dùng làm bản mẫu luyện hát',
                              onPressed: () => _useAsSample(it),
                            ),
                          ],
                        ],
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
