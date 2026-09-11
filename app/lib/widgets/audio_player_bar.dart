import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';

class AudioPlayerBar extends StatefulWidget {
  final String url;

  const AudioPlayerBar({super.key, required this.url});

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
    _player.setUrl(widget.url).then((_) {
      if (mounted) {
        setState(() => _ready = true);
      }
    }).catchError((Object e) {
      if (mounted) {
        setState(() => _error = e.toString());
      }
    });
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
      return Text(_error!);
    }
    if (!_ready) {
      return const CircularProgressIndicator();
    }
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
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
