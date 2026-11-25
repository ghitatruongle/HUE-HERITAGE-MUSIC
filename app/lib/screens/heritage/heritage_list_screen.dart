import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../api/api_client.dart';
import '../../api/endpoints/heritage_api.dart';
import '../../core/constants/app_constants.dart';
import '../../core/theme/app_theme.dart';
import '../../models/heritage_item.dart';
import '../../services/locale_provider.dart';
import '../../core/query_epoch.dart';
import '../../services/server_config.dart';
import '../../widgets/audio_player_bar.dart';
import '../../widgets/empty_state.dart';
import '../../widgets/error_panel.dart';
import '../../widgets/common_button.dart';
import '../../widgets/heritage_motif.dart';
import '../../widgets/hue_icons.dart';
import '../../widgets/skeleton_loader.dart';
import '../../widgets/staggered_entrance.dart';

class HeritageListScreen extends StatefulWidget {
  const HeritageListScreen({super.key});

  @override
  State<HeritageListScreen> createState() => _HeritageListScreenState();
}

class _HeritageListScreenState extends State<HeritageListScreen> {
  final GlobalKey _listKey = GlobalKey();
  final GlobalKey _paneKey = GlobalKey();
  final ValueNotifier<bool> _panePauseSignal = ValueNotifier<bool>(false);
  final _searchCtrl = TextEditingController();
  final List<HeritageItem> _items = [];
  int _total = 0;
  bool _loading = false;
  bool _loadingMore = false;
  bool _hasError = false;
  bool _paneMounted = false;
  HeritageItem? _selectedItem;
  HeritageItem? _paneItem;

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
        if (_selectedItem == null && _items.isNotEmpty) {
          _selectedItem = _items.first;
        }
      });
    } catch (_) {
      if (mounted && _queryEpoch.isCurrent(epoch)) setState(() => _hasError = true);
    } finally {
      if (mounted && _queryEpoch.isCurrent(epoch)) setState(() => _loading = false);
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
      if (mounted && _queryEpoch.isCurrent(epoch)) setState(() => _loadingMore = false);
    }
  }

  void _select(HeritageItem item) {
    setState(() => _selectedItem = item);
  }

  @override
  void dispose() {
    _panePauseSignal.dispose();
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final strings = context.watch<LocaleProvider>().strings;
    final width = MediaQuery.of(context).size.width;
    final isMasterDetail = width >= AppBreakpoints.desktop;
    if (isMasterDetail) {
      _autoSelectFirst();
      if (_selectedItem != null) {
        _paneMounted = true;
        _paneItem = _selectedItem;
        if (_panePauseSignal.value) {
          _panePauseSignal.value = false;
        }
      }
    }

    final listColumn = KeyedSubtree(
      key: _listKey,
      child: Column(
        children: [
          _buildArchiveHeader(strings),
          _buildSearchBar(strings),
          Expanded(
            child: _buildItemsFuture(
              (it, i, isSel) => _buildItemTile(it, i, strings, isMasterDetail && isSel),
              strings,
            ),
          ),
        ],
      ),
    );

    final paneItem = _paneItem;
    final pane = paneItem == null
        ? null
        : KeyedSubtree(
            key: _paneKey,
            child: _buildMusicListeningPane(
              paneItem,
              strings,
              pauseSignal: _panePauseSignal,
            ),
          );

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: isMasterDetail
          ? _buildMasterDetail(context, strings, listColumn, pane)
          : Stack(
              children: [
                if (_paneMounted && pane != null)
                  Positioned.fill(
                    child: Offstage(
                      offstage: true,
                      child: pane,
                    ),
                  ),
                listColumn,
              ],
            ),
    );
  }

  Widget _buildMasterDetail(
    BuildContext context,
    dynamic strings,
    Widget listColumn,
    Widget? pane,
  ) {
    final borderColor = Theme.of(context).colorScheme.outline;

    return Row(
      children: [
        SizedBox(
          width: 380,
          child: listColumn,
        ),
        VerticalDivider(width: 1, color: borderColor),
        Expanded(
          child: pane ??
              EmptyState(
                icon: HueIcons.headphones,
                title: strings.masterDetailEmptyTitle,
                desc: strings.masterDetailEmptySubtitle,
              ),
        ),
      ],
    );
  }

  Widget _buildArchiveHeader(dynamic strings) {
    final primary = Theme.of(context).colorScheme.primary;
    return Container(
      margin: const EdgeInsets.fromLTRB(AppSpacing.md, AppSpacing.md, AppSpacing.md, 0),
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: primary.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: primary.withValues(alpha: 0.3), width: 1.2),
      ),
      child: Row(
        children: [
          HueIcon(HueIcons.headphones, size: 20, color: primary),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  strings.heritageArchiveTitle,
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: AppFontSize.md),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Text(
                  strings.heritageArchiveSubtitle,
                  style: TextStyle(fontSize: AppFontSize.xs, color: Theme.of(context).colorScheme.onSurfaceVariant),
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
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _searchCtrl,
              onSubmitted: (_) => _reload(),
              decoration: InputDecoration(
                hintText: strings.searchHint,
                prefixIcon: const HueIcon(HueIcons.search, size: 20),
                isDense: true,
              ),
            ),
          ),
          const SizedBox(width: 8),
          CommonButton(
            label: strings.searchBtn,
            loading: _loading,
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
      return const SkeletonList(itemCount: 7, itemHeight: 68);
    }
    if (_hasError && _items.isEmpty) {
      return ErrorPanel(message: '${strings.errorPrefix}: ${strings.loadFailGeneric}', onRetry: _reload);
    }
    if (_items.isEmpty) {
      return EmptyState(icon: HueIcons.libraryMusic, title: strings.noRecordings, ctaLabel: strings.learnRetry, onCta: _reload);
    }
    final hasMore = _items.length < _total;
    final list = ListView.builder(
      itemCount: _items.length + (hasMore ? 1 : 0),
      itemBuilder: (context, i) {
        if (i >= _items.length) {
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
            child: Center(
              child: _loadingMore
                  ? const SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(strokeWidth: 2.4),
                    )
                  : OutlinedButton.icon(
                      onPressed: _loadMore,
                      icon: const HueIcon(HueIcons.expandMore, size: 18),
                      label: Text('${strings.adminLoadMore} ($_total)'),
                    ),
            ),
          );
        }
        final it = _items[i];
        return tileBuilder(it, i + 1, _selectedItem?.id == it.id);
      },
    );
    if (_hasError) {
      return Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(AppSpacing.md, 0, AppSpacing.md, AppSpacing.sm),
            child: ErrorPanel(
              message: '${strings.errorPrefix}: ${strings.loadFailGeneric}',
              onRetry: _loading ? null : _reload,
            ),
          ),
          Expanded(child: list),
        ],
      );
    }
    return list;
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

    return StaggeredEntrance(
      index: index,
      maxAnimatedIndex: 11,
      child: Container(
      margin: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.xs),
      decoration: BoxDecoration(
        color: isSelected
            ? scheme.primary.withValues(alpha: isDark ? 0.25 : 0.12)
            : Colors.transparent,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: isSelected
            ? Border.all(color: scheme.primary, width: 1.5)
            : null,
      ),
      child: Material(
        type: MaterialType.transparency,
        child: ListTile(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.lg)),
        leading: Container(
          width: 32,
          height: 32,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: isSelected ? scheme.primary : scheme.surfaceContainerHighest,
          ),
          child: Center(
            child: Text(
              '$index',
              style: TextStyle(
                fontSize: AppFontSize.sm,
                fontWeight: FontWeight.bold,
                color: isSelected ? scheme.onPrimary : scheme.onSurfaceVariant,
              ),
            ),
          ),
        ),
        title: Text(it.title, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: AppFontSize.lg)),
        subtitle: Text(
          [
            if (it.type.isNotEmpty) it.type,
            if (it.artist.isNotEmpty) it.artist,
            if (it.recordedTime.isNotEmpty) it.recordedTime,
          ].join(' • '),
          style: TextStyle(color: scheme.onSurfaceVariant, fontSize: AppFontSize.sm),
        ),
        onTap: () => _openItem(it, strings),
        trailing: IconButton(
          icon: HueIcon(
            isSelected ? HueIcons.headphones : HueIcons.playArrow,
            color: scheme.primary,
            size: 26,
            decorative: true,
          ),
          tooltip: strings.playBtn,
          onPressed: () => _openItem(it, strings),
        ),
        ),
      ),
      ),
    );
  }

  void _openItem(HeritageItem item, dynamic strings) {
    _select(item);
    final width = MediaQuery.of(context).size.width;
    if (width < AppBreakpoints.desktop) {
      _showMobileListeningSheet(item, strings);
    }
  }

  void _showMobileListeningSheet(HeritageItem item, dynamic strings) {
    _panePauseSignal.value = true;
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

  Widget _buildMusicListeningPane(
    HeritageItem item,
    dynamic strings, {
    ValueNotifier<bool>? pauseSignal,
  }) {
    final rows = item.metadataRows();
    final dio = context.read<ServerConfig>().api.dio;
    final audioUrl = HeritageApi(dio).audioUrl(item.id);

    return ListView(
      padding: const EdgeInsets.fromLTRB(AppSpacing.xxxl, AppSpacing.xl, AppSpacing.xxxl, AppSpacing.xxxl),
      children: [
        Card(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.xl)),
          child: Container(
            padding: const EdgeInsets.all(AppSpacing.xxl),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(AppRadius.xl),
              gradient: AppTheme.brandGradientOf(context),
            ),
            child: HeritageMotif(
              color: Colors.white,
              opacity: 0.08,
              radius: 20,
              child: Row(
                children: [
                  Container(
                    width: 80,
                    height: 80,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.4),
                          blurRadius: 12,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: const DanNguyetDisc(size: 80),
                  ),
                const SizedBox(width: 20),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        item.title,
                        style: const TextStyle(fontSize: AppFontSize.headline, fontWeight: FontWeight.w700, color: Colors.white),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        [item.artist, item.type].where((s) => s.isNotEmpty).join(' • '),
                        style: const TextStyle(fontSize: AppFontSize.lg, color: AppTheme.gradientAccentGold, fontWeight: FontWeight.w600),
                      ),
                      if (item.tonal.isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Text(
                          strings.heritageTonal(item.tonal),
                          style: TextStyle(fontSize: AppFontSize.sm, color: Colors.white.withValues(alpha: 0.88)),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
              ),
            ),
          ),
        ),
        const SizedBox(height: 18),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.xl),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    HueIcon(HueIcons.musicNote, size: 20, color: AppTheme.goldReadable(context)),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        strings.heritageNowPlaying(item.title),
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: AppFontSize.xl),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                AudioPlayerBar(
                  url: audioUrl,
                  label: item.title,
                  autoPlay: true,
                  dio: dio,
                  pauseSignal: pauseSignal,
                ),
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
              padding: const EdgeInsets.all(AppSpacing.xl),
              child: SelectableText(
                item.lyrics,
                style: const TextStyle(height: 1.8, fontSize: AppFontSize.lg, fontStyle: FontStyle.italic),
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
            padding: const EdgeInsets.all(AppSpacing.lg),
            child: Column(
              children: [
                for (final e in rows.entries)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SizedBox(
                          width: 150,
                          child: Text(e.key, style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant, fontSize: AppFontSize.md)),
                        ),
                        Expanded(child: Text(e.value, style: const TextStyle(fontSize: AppFontSize.md, fontWeight: FontWeight.w500))),
                      ],
                    ),
                  ),
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SizedBox(
                        width: MediaQuery.of(context).size.width > 500 ? 150 : 110,
                        child: Text('SHA-256', style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant, fontSize: AppFontSize.md)),
                      ),
                      Expanded(
                        child: SelectableText(item.sha256, style: const TextStyle(fontFamily: AppTheme.monoFontFamily, fontSize: AppFontSize.xs)),
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
            HueIcon(HueIcons.verified, size: 16, color: Theme.of(context).colorScheme.primary),
            const SizedBox(width: 8),
            Expanded(child: Text(strings.heritageOriginalNote)),
          ],
        ),
      ],
    );
  }
}
