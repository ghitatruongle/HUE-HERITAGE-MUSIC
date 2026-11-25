import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/server_config.dart';
import 'hue_icons.dart';

class AvatarView extends StatefulWidget {
  const AvatarView({
    super.key,
    required this.url,
    this.size = 36,
    this.icon = HueIcons.accountCircle,
    this.iconColor,
  });

  final String url;
  final double size;
  final IconData icon;
  final Color? iconColor;

  static final Map<String, Uint8List> _cache = <String, Uint8List>{};
  static final Map<String, DateTime> _negativeAt = <String, DateTime>{};
  static final Map<String, Future<Uint8List?>> _inflight = <String, Future<Uint8List?>>{};

  static String _key(Dio dio, String url) => '${dio.options.baseUrl}$url';

  static Future<Uint8List?> _fetch(String key, Dio dio, String url) {
    return _inflight.putIfAbsent(key, () async {
      try {
        final res = await dio.get<List<int>>(
          url,
          options: Options(responseType: ResponseType.bytes),
        );
        final data = res.data;
        final bytes = (data == null || data.isEmpty) ? Uint8List(0) : Uint8List.fromList(data);
        _cache[key] = bytes;
        return bytes;
      } catch (_) {
        final empty = Uint8List(0);
        _cache[key] = empty;
        _negativeAt[key] = DateTime.now();
        return empty;
      } finally {
        _inflight.remove(key);
      }
    });
  }

  static void evict(String url) {
    final dead = <String>[];
    _cache.forEach((key, _) {
      if (key.endsWith(url)) dead.add(key);
    });
    for (final key in dead) {
      _cache.remove(key);
      _negativeAt.remove(key);
    }
  }

  static void clearCache() {
    _cache.clear();
    _negativeAt.clear();
    _inflight.clear();
  }

  @override
  State<AvatarView> createState() => _AvatarViewState();
}

class _AvatarViewState extends State<AvatarView> {
  @override
  Widget build(BuildContext context) {
    if (widget.url.isEmpty) {
      return _fallback(context);
    }
    final dio = context.read<ServerConfig>().api.dio;
    final key = AvatarView._key(dio, widget.url);
    final cached = AvatarView._cache[key];
    if (cached != null) {
      if (cached.isEmpty) {
        final at = AvatarView._negativeAt[key];
        final fresh = at != null && DateTime.now().difference(at).inSeconds < 60;
        if (fresh) {
          return _fallback(context);
        }
        AvatarView._cache.remove(key);
        AvatarView._negativeAt.remove(key);
      } else {
        return _image(cached);
      }
    }
    return FutureBuilder<Uint8List?>(
      future: AvatarView._fetch(key, dio, widget.url),
      builder: (context, snap) {
        final bytes = snap.data;
        if (bytes != null && bytes.isNotEmpty) {
          return _image(bytes);
        }
        return _fallback(context);
      },
    );
  }

  Widget _image(Uint8List bytes) {
    return ClipOval(
      child: SizedBox(
        width: widget.size,
        height: widget.size,
        child: Image.memory(
          bytes,
          fit: BoxFit.cover,
          gaplessPlayback: true,
          errorBuilder: (context, _, __) => _fallback(context),
        ),
      ),
    );
  }

  Widget _fallback(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return CircleAvatar(
      radius: widget.size / 2,
      backgroundColor: scheme.primaryContainer,
      child: HueIcon(
        widget.icon,
        size: widget.size * 0.55,
        color: widget.iconColor ?? scheme.onPrimaryContainer,
      ),
    );
  }
}
