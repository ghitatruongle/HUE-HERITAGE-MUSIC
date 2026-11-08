import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:just_audio/just_audio.dart';

import '../services/locale_provider.dart';
import 'error_panel.dart';

class AudioPlayerBar extends StatefulWidget {
  final String? url;
  final String? filePath;
  final Uint8List? bytes;
  final String label;
  final bool autoPlay;
  final bool compact;
  final Dio? dio;

  const AudioPlayerBar({
    super.key,
    this.url,
    this.filePath,
    this.bytes,
    this.label = '',
    this.autoPlay = false,
    this.compact = false,
    this.dio,
  });

  @override
  State<AudioPlayerBar> createState() => _AudioPlayerBarState();
}

class _AudioPlayerBarState extends State<AudioPlayerBar> with WidgetsBindingObserver {
  final AudioPlayer _player = AudioPlayer();
  int _loadGen = 0;
  bool _ready = false;
  bool _dragging = false;
  double _dragValue = 0;
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _load();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused || state == AppLifecycleState.hidden) {
      try {
        _player.pause();
      } catch (_) {}
    }
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

  Future<String?> _signedUrl(String rawUrl, {bool forceResign = false}) async {
    final dio = widget.dio;
    if (dio == null) {
      return null;
    }
    final parsedRaw = Uri.tryParse(rawUrl);
    final alreadySigned = parsedRaw != null &&
        parsedRaw.queryParameters.containsKey('e') &&
        parsedRaw.queryParameters.containsKey('s');
    if (alreadySigned && !forceResign) {
      return null;
    }
    final idx = rawUrl.indexOf('/api/');
    if (idx < 0) {
      return null;
    }
    final pathAndQuery = rawUrl.substring(idx);
    final qIdx = pathAndQuery.indexOf('?');
    final path = qIdx >= 0 ? pathAndQuery.substring(0, qIdx) : pathAndQuery;
    var query = qIdx >= 0 ? pathAndQuery.substring(qIdx + 1) : '';
    if (forceResign && query.isNotEmpty) {
      final kept = <String>[];
      for (final part in query.split('&')) {
        final key = part.split('=').first;
        if (key == 'e' || key == 's') continue;
        kept.add(part);
      }
      query = kept.join('&');
    }
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

  Future<void> _load({bool forceResign = false}) async {
    final gen = ++_loadGen;
    try {
      if (mounted) {
        setState(() {
          _ready = false;
          _error = null;
        });
      }
      await _player.stop();
      if (gen != _loadGen || !mounted) return;
      if (widget.url != null && widget.url!.isNotEmpty) {
        var finalUrl = _normalizeUrl(widget.url!);
        final signed = await _signedUrl(finalUrl, forceResign: forceResign);
        if (gen != _loadGen) return;
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
      if (gen != _loadGen || !mounted) return;
      setState(() => _ready = true);
      if (widget.autoPlay) {
        await _player.play();
      }
    } catch (e) {
      if (gen != _loadGen || !mounted) return;
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
    WidgetsBinding.instance.removeObserver(this);
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
        child: ErrorPanel(
          message: _error!,
          onRetry: () => _load(forceResign: true),
        ),
      );
    }
    if (!_ready) {
      return const SizedBox(
        height: 56,
        child: Center(
          child: SizedBox(
            width: 18,
            height: 18,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        ),
      );
    }
    final strings = context.read<LocaleProvider>().strings;
    final playButton = StreamBuilder<PlayerState>(
      stream: _player.playerStateStream,
      builder: (context, snap) {
        final state = snap.data?.processingState ?? ProcessingState.idle;
        final playing = snap.data?.playing ?? false;
        final buffering = state == ProcessingState.loading || state == ProcessingState.buffering;
        return IconButton(
          iconSize: 48,
          tooltip: playing ? strings.audioPause : strings.playBtn,
          icon: buffering
              ? const SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(strokeWidth: 2.2),
                )
              : Icon(playing ? Icons.pause_circle : Icons.play_circle),
          onPressed: () {
            if (playing) {
              _player.pause();
            } else {
              _player.play();
            }
          },
        );
      },
    );
    final sliderRow = StreamBuilder<Duration>(
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
    );
    if (widget.compact) {
      return Row(
        children: [
          playButton,
          Expanded(child: sliderRow),
        ],
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
        playButton,
        sliderRow,
      ],
    );
  }
}
