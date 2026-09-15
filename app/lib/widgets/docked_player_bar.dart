import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';
import 'package:provider/provider.dart';

import '../core/theme/app_theme.dart';
import '../services/locale_provider.dart';
import '../services/session_media.dart';

class DockedPlayerBar extends StatefulWidget {
  const DockedPlayerBar({super.key});

  @override
  State<DockedPlayerBar> createState() => _DockedPlayerBarState();
}

class _DockedPlayerBarState extends State<DockedPlayerBar> {
  final AudioPlayer _player = AudioPlayer();
  String? _loadedKey;
  bool _dragging = false;
  double _dragValue = 0;
  bool _looping = false;
  double _volume = 1.0;

  @override
  void dispose() {
    _player.dispose();
    super.dispose();
  }

  Future<void> _loadTrack(SessionMedia media) async {
    final key = '${media.currentAudioUrl}_${media.currentAudioPath}_${media.currentAudioBytes?.length}';
    if (_loadedKey == key) {
      return;
    }
    _loadedKey = key;

    try {
      if (media.currentAudioUrl != null && media.currentAudioUrl!.isNotEmpty) {
        await _player.setUrl(media.currentAudioUrl!);
      } else if (media.currentAudioPath != null && media.currentAudioPath!.isNotEmpty) {
        await _player.setFilePath(media.currentAudioPath!);
      } else if (media.currentAudioBytes != null) {
        final src = await _bytesSource(media.currentAudioBytes!);
        await _player.setAudioSource(src);
      }
      if (mounted) {
        await _player.play();
      }
    } catch (_) {}
  }

  Future<AudioSource> _bytesSource(Uint8List bytes) async {
    if (kIsWeb) {
      return AudioSource.uri(Uri.dataFromBytes(bytes, mimeType: 'audio/wav'));
    }
    final file = File('${Directory.systemTemp.path}/hue_dock_play_${DateTime.now().millisecondsSinceEpoch}.wav');
    await file.writeAsBytes(bytes);
    return AudioSource.uri(Uri.file(file.path));
  }

  String _fmt(Duration? d) {
    if (d == null) return '00:00';
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    final media = context.watch<SessionMedia>();
    if (!media.hasActiveTrack) {
      return const SizedBox.shrink();
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _loadTrack(media);
      }
    });

    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bgColor = isDark ? const Color(0xFF131120) : const Color(0xFFFFFFFF);
    final borderColor = isDark ? const Color(0xFF2E2B48) : const Color(0xFFE4DFEE);

    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: bgColor,
        border: Border(top: BorderSide(color: borderColor, width: 1.5)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.35 : 0.08),
            blurRadius: 16,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: SafeArea(
        top: false,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final isWide = constraints.maxWidth > 700;
            return isWide ? _buildWideLayout(media) : _buildNarrowLayout(media);
          },
        ),
      ),
    );
  }

  Widget _buildWideLayout(SessionMedia media) {
    final strings = context.read<LocaleProvider>().strings;
    return Row(
      children: [
        Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [AppTheme.primaryPurple, AppTheme.primaryPurpleLight],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(10),
          ),
          child: const Icon(Icons.music_note, color: Colors.white, size: 22),
        ),
        const SizedBox(width: 12),
        Expanded(
          flex: 3,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                media.currentTrackTitle ?? '',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
              ),
              if ((media.currentTrackSubtitle ?? '').isNotEmpty)
                Text(
                  media.currentTrackSubtitle!,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                    fontSize: 12,
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          flex: 6,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  IconButton(
                    iconSize: 20,
                    icon: const Icon(Icons.replay_5),
                    tooltip: '-5s',
                    onPressed: () {
                      final pos = _player.position;
                      _player.seek(pos - const Duration(seconds: 5));
                    },
                  ),
                  StreamBuilder<PlayerState>(
                    stream: _player.playerStateStream,
                    builder: (context, snap) {
                      final playing = snap.data?.playing ?? false;
                      return IconButton(
                        iconSize: 34,
                        color: AppTheme.primaryPurpleLight,
                        icon: Icon(playing ? Icons.pause_circle_filled : Icons.play_circle_fill),
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
                  IconButton(
                    iconSize: 20,
                    icon: const Icon(Icons.forward_5),
                    tooltip: '+5s',
                    onPressed: () {
                      final pos = _player.position;
                      _player.seek(pos + const Duration(seconds: 5));
                    },
                  ),
                  IconButton(
                    iconSize: 20,
                    color: _looping ? AppTheme.amberGold : null,
                    icon: const Icon(Icons.repeat),
                    tooltip: strings.loopTrack,
                    onPressed: () {
                      setState(() {
                        _looping = !_looping;
                        _player.setLoopMode(_looping ? LoopMode.one : LoopMode.off);
                      });
                    },
                  ),
                ],
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
                      Text(_fmt(pos), style: const TextStyle(fontSize: 11)),
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
                          onChanged: (v) => setState(() => _dragValue = v),
                          onChangeEnd: (v) {
                            _player.seek(Duration(milliseconds: v.toInt()));
                            setState(() => _dragging = false);
                          },
                        ),
                      ),
                      Text(_fmt(total), style: const TextStyle(fontSize: 11)),
                    ],
                  );
                },
              ),
            ],
          ),
        ),
        const SizedBox(width: 16),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              _volume == 0 ? Icons.volume_off : Icons.volume_up,
              size: 20,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
            SizedBox(
              width: 80,
              child: Slider(
                value: _volume,
                min: 0,
                max: 1,
                onChanged: (v) {
                  setState(() {
                    _volume = v;
                    _player.setVolume(v);
                  });
                },
              ),
            ),
            IconButton(
              iconSize: 20,
              icon: const Icon(Icons.close),
              tooltip: strings.closeBtn,
              onPressed: () {
                _player.stop();
                media.closePlayer();
              },
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildNarrowLayout(SessionMedia media) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [AppTheme.primaryPurple, AppTheme.primaryPurpleLight],
                ),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(Icons.music_note, color: Colors.white, size: 18),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    media.currentTrackTitle ?? '',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
                  ),
                  if ((media.currentTrackSubtitle ?? '').isNotEmpty)
                    Text(
                      media.currentTrackSubtitle!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                        fontSize: 11,
                      ),
                    ),
                ],
              ),
            ),
            StreamBuilder<PlayerState>(
              stream: _player.playerStateStream,
              builder: (context, snap) {
                final playing = snap.data?.playing ?? false;
                return IconButton(
                  iconSize: 28,
                  color: AppTheme.primaryPurpleLight,
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
            IconButton(
              iconSize: 18,
              icon: const Icon(Icons.close),
              onPressed: () {
                _player.stop();
                media.closePlayer();
              },
            ),
          ],
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
            return Slider(
              value: cur,
              max: cap,
              onChangeStart: (v) {
                setState(() {
                  _dragging = true;
                  _dragValue = v;
                });
              },
              onChanged: (v) => setState(() => _dragValue = v),
              onChangeEnd: (v) {
                _player.seek(Duration(milliseconds: v.toInt()));
                setState(() => _dragging = false);
              },
            );
          },
        ),
      ],
    );
  }
}
