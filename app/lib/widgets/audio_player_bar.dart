import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:just_audio/just_audio.dart';

import '../services/locale_provider.dart';

class AudioPlayerBar extends StatefulWidget {
  final String? url;
  final String? filePath;
  final Uint8List? bytes;
  final String label;
  final bool autoPlay;
  final Dio? dio;

  const AudioPlayerBar({
    super.key,
    this.url,
    this.filePath,
    this.bytes,
    this.label = '',
    this.autoPlay = false,
    this.dio,
  });

  @override
  State<AudioPlayerBar> createState() => _AudioPlayerBarState();
}

class _AudioPlayerBarState extends State<AudioPlayerBar> {
  final AudioPlayer _player = AudioPlayer();
  bool _ready = false;
  bool _dragging = false;
  double _dragValue = 0;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant AudioPlayerBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.url != widget.url ||
        oldWidget.filePath != widget.filePath ||
        oldWidget.bytes != widget.bytes) {
      _load();
    }
  }

  String _normalizeUrl(String rawUrl) {
    if (!kIsWeb) return rawUrl;
    final parsed = Uri.tryParse(rawUrl);
    if (parsed == null) return rawUrl;
    if (!parsed.hasScheme || parsed.host.isEmpty) {
      return Uri.base.resolve(rawUrl).toString();
    }
    if ((parsed.host == '127.0.0.1' || parsed.host == 'localhost') &&
        (Uri.base.host == '127.0.0.1' || Uri.base.host == 'localhost')) {
      return parsed.replace(host: Uri.base.host, port: Uri.base.port).toString();
    }
    return rawUrl;
  }

  Future<String?> _signedUrl(String rawUrl) async {
    final dio = widget.dio;
    if (dio == null) {
      return null;
    }
    final parsedRaw = Uri.tryParse(rawUrl);
    if (parsedRaw != null && parsedRaw.queryParameters.containsKey('e') && parsedRaw.queryParameters.containsKey('s')) {
      return null;
    }
    final idx = rawUrl.indexOf('/api/');
    if (idx < 0) {
      return null;
    }
    final pathAndQuery = rawUrl.substring(idx);
    final qIdx = pathAndQuery.indexOf('?');
    final path = qIdx >= 0 ? pathAndQuery.substring(0, qIdx) : pathAndQuery;
    final query = qIdx >= 0 ? pathAndQuery.substring(qIdx + 1) : '';
    try {
      final res = await dio.get('/api/music/play-url', queryParameters: {'path': path});
      final data = res.data;
      if (data is Map && data['url'] is String && (data['url'] as String).isNotEmpty) {
        final signed = data['url'] as String;
        var finalUrl = signed.startsWith('http') ? signed : '${dio.options.baseUrl}$signed';
        if (query.isNotEmpty) {
          finalUrl = finalUrl.contains('?') ? '$finalUrl&$query' : '$finalUrl?$query';
        }
        return finalUrl;
      }
    } catch (_) {}
    return null;
  }

  Future<void> _load() async {
    try {
      if (mounted) {
        setState(() {
          _ready = false;
          _error = null;
        });
      }
      await _player.stop();
      if (widget.url != null && widget.url!.isNotEmpty) {
        var finalUrl = _normalizeUrl(widget.url!);
        final signed = await _signedUrl(finalUrl);
        if (signed != null) {
          finalUrl = _normalizeUrl(signed);
        }
        await _player.setUrl(finalUrl);
      } else if (widget.filePath != null && widget.filePath!.isNotEmpty) {
        await _player.setFilePath(widget.filePath!);
      } else if (widget.bytes != null) {
        await _player.setAudioSource(await _bytesSource(widget.bytes!));
      } else {
        throw StateError('no audio source');
      }
      if (mounted) {
        setState(() => _ready = true);
        if (widget.autoPlay) {
          await _player.play();
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() => _error = context.read<LocaleProvider>().strings.audioLoadFail);
      }
    }
  }

  Future<AudioSource> _bytesSource(Uint8List bytes) async {
    if (kIsWeb) {
      return AudioSource.uri(Uri.dataFromBytes(bytes, mimeType: 'audio/wav'));
    }
    final file = File('${Directory.systemTemp.path}/hue_play_${DateTime.now().millisecondsSinceEpoch}.wav');
    await file.writeAsBytes(bytes);
    return AudioSource.uri(Uri.file(file.path));
  }

  @override
  void dispose() {
    _player.dispose();
    super.dispose();
  }

  String _fmt(Duration? d) {
    if (d == null) {
      return '--:--';
    }
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    if (_error != null) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Expanded(
              child: Text(
                _error!,
                style: const TextStyle(color: Colors.red, fontSize: 12),
              ),
            ),
            IconButton(
              icon: const Icon(Icons.refresh, size: 18),
              onPressed: _load,
              tooltip: context.read<LocaleProvider>().strings.learnRetry,
            ),
          ],
        ),
      );
    }
    if (!_ready) {
      return const Padding(
        padding: EdgeInsets.all(12),
        child: Center(child: CircularProgressIndicator()),
      );
    }
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (widget.label.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Text(widget.label, style: Theme.of(context).textTheme.bodySmall),
          ),
        StreamBuilder<PlayerState>(
          stream: _player.playerStateStream,
          builder: (context, snap) {
            final playing = snap.data?.playing ?? false;
            return IconButton(
              iconSize: 48,
              icon: Icon(playing ? Icons.pause_circle : Icons.play_circle),
              onPressed: () {
                if (playing) {
                  _player.pause();
                } else {
                  _player.play();
                }
              },
            );
          },
        ),
        StreamBuilder<Duration>(
          stream: _player.positionStream,
          builder: (context, snap) {
            final pos = snap.data ?? Duration.zero;
            final total = _player.duration ?? Duration.zero;
            final maxMs = total.inMilliseconds.toDouble();
            final cap = maxMs > 0 ? maxMs : 1.0;
            final cur = _dragging
                ? _dragValue
                : pos.inMilliseconds.toDouble().clamp(0.0, cap).toDouble();
            return Row(
              children: [
                Text(_fmt(pos)),
                Expanded(
                  child: Slider(
                    value: cur,
                    max: cap,
                    onChangeStart: (v) {
                      setState(() {
                        _dragging = true;
                        _dragValue = v;
                      });
                    },
                    onChanged: (v) {
                      setState(() => _dragValue = v);
                    },
                    onChangeEnd: (v) {
                      _player.seek(Duration(milliseconds: v.toInt()));
                      setState(() => _dragging = false);
                    },
                  ),
                ),
                Text(_fmt(total)),
              ],
            );
          },
        ),
      ],
    );
  }
}
