import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../api/api_client.dart';
import '../../api/endpoints/heritage_api.dart';
import '../../core/theme/app_theme.dart';
import '../../models/heritage_item.dart';
import '../../services/locale_provider.dart';
import '../../core/query_epoch.dart';
import '../../services/server_config.dart';
import '../../widgets/audio_player_bar.dart';
import '../../widgets/empty_state.dart';
import '../../widgets/error_panel.dart';
import '../../widgets/common_button.dart';

class HeritageListScreen extends StatefulWidget {
  const HeritageListScreen({super.key});

  @override
  State<HeritageListScreen> createState() => _HeritageListScreenState();
}

class _HeritageListScreenState extends State<HeritageListScreen> {
  final _searchCtrl = TextEditingController();
  final List<HeritageItem> _items = [];
  int _total = 0;
  bool _loading = false;
  bool _loadingMore = false;
  bool _hasError = false;
  HeritageItem? _selectedItem;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  final QueryEpoch _queryEpoch = QueryEpoch();

  Future<void> _reload() async {
    final epoch = _queryEpoch.next();
    setState(() {
      _loading = true;
      _hasError = false;
    });
    try {
      final dio = context.read<ServerConfig>().api.dio;
      final page = await HeritageApi(dio).list(q: _searchCtrl.text.trim());
      if (!mounted || !_queryEpoch.isCurrent(epoch)) return;
      setState(() {
        _items
          ..clear()
          ..addAll(page.items);
        _total = page.total;
      });
    } catch (_) {
      if (mounted) setState(() => _hasError = true);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _loadMore() async {
    if (_loadingMore || _items.length >= _total) return;
    setState(() => _loadingMore = true);
    final epoch = _queryEpoch.value;
    try {
      final dio = context.read<ServerConfig>().api.dio;
      final page = await HeritageApi(dio).list(
        q: _searchCtrl.text.trim(),
        offset: _items.length,
      );
      if (!mounted || !_queryEpoch.isCurrent(epoch)) return;
      final known = _items.map((e) => e.id).toSet();
      setState(() {
        for (final it in page.items) {
          if (!known.contains(it.id)) _items.add(it);
        }
        _total = page.total;
      });
    } catch (e) {
      if (mounted && _queryEpoch.isCurrent(epoch)) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(ApiClient.describe(e))),
        );
      }
    } finally {
      if (mounted) setState(() => _loadingMore = false);
    }
  }

  void _select(HeritageItem item) {
    setState(() => _selectedItem = item);
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final strings = context.watch<LocaleProvider>().strings;
    final width = MediaQuery.of(context).size.width;
    final isMasterDetail = width >= 900;

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: isMasterDetail ? _buildMasterDetail(context, strings) : _buildSingleList(context, strings),
    );
  }

  Widget _buildSingleList(BuildContext context, dynamic strings) {
    return Column(
      children: [
        _buildArchiveHeader(strings),
        _buildSearchBar(strings),
        Expanded(
          child: _buildItemsFuture(
            (it, i, _) => _buildItemTile(it, i, strings, false),
            strings,
          ),
        ),
      ],
    );
  }

  Widget _buildMasterDetail(BuildContext context, dynamic strings) {
    final borderColor = Theme.of(context).colorScheme.outline;

    return Row(
      children: [
        SizedBox(
          width: 380,
          child: Column(
            children: [
              _buildArchiveHeader(strings),
              _buildSearchBar(strings),
              Expanded(
                child: _buildItemsFuture(
                  (it, i, isSel) {
                    _autoSelectFirst();
                    return _buildItemTile(it, i, strings, isSel);
                  },
                  strings,
                ),
              ),
            ],
          ),
        ),
        VerticalDivider(width: 1, color: borderColor),
        Expanded(
          child: _selectedItem == null
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.headphones, size: 64, color: AppTheme.primaryPurple.withValues(alpha: 0.4)),
                      const SizedBox(height: 16),
                      Text(strings.masterDetailEmptyTitle, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                      const SizedBox(height: 6),
                      Text(strings.masterDetailEmptySubtitle, style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant)),
                    ],
                  ),
                )
              : _buildMusicListeningPane(_selectedItem!, strings),
        ),
      ],
    );
  }

  Widget _buildArchiveHeader(dynamic strings) {
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 12, 12, 0),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppTheme.primaryPurple.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.primaryPurple.withValues(alpha: 0.3), width: 1.2),
      ),
      child: Row(
        children: [
          const Icon(Icons.headphones, size: 20, color: AppTheme.primaryPurpleLight),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  strings.heritageArchiveTitle,
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Text(
                  strings.heritageArchiveSubtitle,
                  style: TextStyle(fontSize: 11, color: Theme.of(context).colorScheme.onSurfaceVariant),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSearchBar(dynamic strings) {
    return Padding(
      padding: const EdgeInsets.all(12),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _searchCtrl,
              onSubmitted: (_) => _reload(),
              decoration: InputDecoration(
                hintText: strings.searchHint,
                prefixIcon: const Icon(Icons.search, size: 20),
                isDense: true,
              ),
            ),
          ),
          const SizedBox(width: 8),
          CommonButton(
            label: strings.searchBtn,
            onPressed: _reload,
          ),
        ],
      ),
    );
  }

  Widget _buildItemsFuture(
    Widget Function(HeritageItem item, int index, bool isSelected) tileBuilder,
    dynamic strings,
  ) {
    if (_loading && _items.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_hasError && _items.isEmpty) {
      return ErrorPanel(message: '${strings.errorPrefix}: ${strings.loadFailGeneric}', onRetry: _reload);
    }
    if (_items.isEmpty) {
      return EmptyState(icon: Icons.library_music_rounded, title: strings.noRecordings, ctaLabel: strings.learnRetry, onCta: _reload);
    }
    final hasMore = _items.length < _total;
    return ListView.builder(
      itemCount: _items.length + (hasMore ? 1 : 0),
      itemBuilder: (context, i) {
        if (i >= _items.length) {
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 10),
            child: Center(
              child: _loadingMore
                  ? const SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(strokeWidth: 2.4),
                    )
                  : OutlinedButton.icon(
                      onPressed: _loadMore,
                      icon: const Icon(Icons.expand_more, size: 18),
                      label: Text('${strings.adminLoadMore} ($_total)'),
                    ),
            ),
          );
        }
        final it = _items[i];
        return tileBuilder(it, i + 1, _selectedItem?.id == it.id);
      },
    );
  }

  void _autoSelectFirst() {
    if (_selectedItem == null && _items.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _selectedItem == null && _items.isNotEmpty) {
          setState(() => _selectedItem = _items.first);
        }
      });
    }
  }

  Widget _buildItemTile(HeritageItem it, int index, dynamic strings, bool isSelected) {
    final scheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: isSelected
            ? AppTheme.primaryPurple.withValues(alpha: isDark ? 0.25 : 0.12)
            : Colors.transparent,
        borderRadius: BorderRadius.circular(14),
        border: isSelected
            ? Border.all(color: AppTheme.primaryPurpleLight, width: 1.5)
            : null,
      ),
      child: ListTile(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        leading: Container(
          width: 32,
          height: 32,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: isSelected ? AppTheme.primaryPurple : scheme.surfaceContainerHighest,
          ),
          child: Center(
            child: Text(
              '$index',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.bold,
                color: isSelected ? Colors.white : scheme.onSurfaceVariant,
              ),
            ),
          ),
        ),
        title: Text(it.title, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
        subtitle: Text(
          [
            if (it.type.isNotEmpty) it.type,
            if (it.artist.isNotEmpty) it.artist,
            if (it.recordedTime.isNotEmpty) it.recordedTime,
          ].join(' • '),
          style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 12),
        ),
        onTap: () {
          _select(it);
          final width = MediaQuery.of(context).size.width;
          if (width < 900) {
            _showMobileListeningSheet(it, strings);
          }
        },
        trailing: IconButton(
          icon: Icon(
            isSelected ? Icons.headphones : Icons.play_arrow,
            color: AppTheme.primaryPurpleLight,
            size: 26,
          ),
          tooltip: strings.playBtn,
          onPressed: () {
            _select(it);
            final width = MediaQuery.of(context).size.width;
            if (width < 900) {
              _showMobileListeningSheet(it, strings);
            }
          },
        ),
      ),
    );
  }

  void _showMobileListeningSheet(HeritageItem item, dynamic strings) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => SizedBox(
        height: MediaQuery.of(context).size.height * 0.85,
        child: _buildMusicListeningPane(item, strings),
      ),
    );
  }

  Widget _buildMusicListeningPane(HeritageItem item, dynamic strings) {
    final rows = item.metadataRows();
    final dio = context.read<ServerConfig>().api.dio;
    final audioUrl = HeritageApi(dio).audioUrl(item.id);

    return ListView(
      padding: const EdgeInsets.fromLTRB(28, 20, 28, 40),
      children: [
        Card(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          child: Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(20),
              gradient: AppTheme.brandGradient,
            ),
            child: Row(
              children: [
                Container(
                  width: 80,
                  height: 80,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: const Color(0xFF1B0E33),
                    border: Border.all(color: AppTheme.amberGold, width: 2),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.4),
                        blurRadius: 12,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: const Center(
                    child: Icon(Icons.album, size: 48, color: AppTheme.amberGold),
                  ),
                ),
                const SizedBox(width: 20),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        item.title,
                        style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w800, color: Colors.white),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        [item.artist, item.type].where((s) => s.isNotEmpty).join(' • '),
                        style: const TextStyle(fontSize: 14, color: AppTheme.amberGold, fontWeight: FontWeight.w600),
                      ),
                      if (item.tonal.isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Text(
                          strings.heritageTonal(item.tonal),
                          style: TextStyle(fontSize: 12, color: Colors.white.withValues(alpha: 0.75)),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 18),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.music_note, size: 20, color: AppTheme.amberGold),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        strings.heritageNowPlaying(item.title),
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                AudioPlayerBar(url: audioUrl, label: item.title, autoPlay: true, dio: dio),
              ],
            ),
          ),
        ),
        if (item.lyrics.isNotEmpty) ...[
          const SizedBox(height: 18),
          Text(
            strings.heritageLyricsTitle,
            style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold, letterSpacing: 0.5),
          ),
          const SizedBox(height: 8),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: SelectableText(
                item.lyrics,
                style: const TextStyle(height: 1.8, fontSize: 14.5, fontStyle: FontStyle.italic),
              ),
            ),
          ),
        ],
        const SizedBox(height: 18),
        Text(
          strings.heritageInfoTitle,
          style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 8),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                for (final e in rows.entries)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 5),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SizedBox(
                          width: 150,
                          child: Text(e.key, style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant, fontSize: 13)),
                        ),
                        Expanded(child: Text(e.value, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500))),
                      ],
                    ),
                  ),
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 5),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SizedBox(
                        width: MediaQuery.of(context).size.width > 500 ? 150 : 110,
                        child: Text('SHA-256', style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant, fontSize: 13)),
                      ),
                      Expanded(
                        child: SelectableText(item.sha256, style: const TextStyle(fontFamily: 'monospace', fontSize: 11)),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            Icon(Icons.verified_outlined, size: 16, color: Theme.of(context).colorScheme.primary),
            const SizedBox(width: 8),
            Expanded(child: Text(strings.heritageOriginalNote)),
          ],
        ),
      ],
    );
  }
}
