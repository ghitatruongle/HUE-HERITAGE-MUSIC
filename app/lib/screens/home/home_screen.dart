import 'package:flutter/material.dart';

import '../../core/constants/app_constants.dart';
import '../creation/creation_screen.dart';
import '../heritage/heritage_list_screen.dart';
import '../learning/learning_screen.dart';
import '../settings/settings_screen.dart';
import '../transcription/transcription_screen.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  void _open(BuildContext context, String title, Widget page) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => Scaffold(
          appBar: AppBar(title: Text(title)),
          body: SafeArea(child: page),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final features = [
      const _Feature(
        icon: Icons.mic,
        color: Color(0xFF5B3B8C),
        title: 'Học hát Ca Huế',
        subtitle: 'Thu âm giọng hát, so sánh cao độ với bản mẫu của nghệ nhân',
        page: LearningScreen(),
        screenTitle: 'Học hát Ca Huế',
      ),
      const _Feature(
        icon: Icons.library_music,
        color: Color(0xFF00796B),
        title: 'Kho di sản số',
        subtitle: 'Lưu trữ bản ghi, phục dựng âm thanh, nhận diện nhạc cụ',
        page: HeritageListScreen(),
        screenTitle: 'Kho di sản số',
      ),
      const _Feature(
        icon: Icons.music_note,
        color: Color(0xFF8F6C00),
        title: 'Ký âm tự động',
        subtitle: 'Chuyển bản thu âm thành file MIDI và bản nhạc MusicXML',
        page: TranscriptionScreen(),
        screenTitle: 'Ký âm tự động',
      ),
      const _Feature(
        icon: Icons.auto_awesome,
        color: Color(0xFFAD3B6F),
        title: 'AI Sáng tạo',
        subtitle: 'Sáng tác bản nhạc mới, cover mang âm hưởng Huế',
        page: CreationScreen(),
        screenTitle: 'AI Sáng tạo',
      ),
    ];
    return Scaffold(
      appBar: AppBar(
        title: const Text(AppConstants.appName),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings_outlined),
            tooltip: 'Cài đặt',
            onPressed: () => _open(context, 'Cài đặt', const SettingsScreen()),
          ),
        ],
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
          children: [
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(24),
                gradient: const LinearGradient(
                  colors: [Color(0xFF5B3B8C), Color(0xFF8B5CF6)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(14),
                        child: Image.asset(
                          'assets/images/app_logo.png',
                          width: 52,
                          height: 52,
                          fit: BoxFit.cover,
                        ),
                      ),
                      const SizedBox(width: 12),
                      const Expanded(
                        child: Text(
                          'Di sản âm nhạc Huế',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 20,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  const Text(
                    'Nền tảng AI bảo tồn, truyền dạy và phát huy ca Huế, nhã nhạc cung đình và nhạc cụ truyền thống.',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 14,
                      height: 1.5,
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 24, 4, 12),
              child: Text(
                'Chức năng',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                      color: scheme.onSurface,
                    ),
              ),
            ),
            for (final f in features) ...[
              _FeatureCard(feature: f, onOpen: _open),
              const SizedBox(height: 12),
            ],
            const SizedBox(height: 12),
            Text(
              'Phiên bản ${AppConstants.appVersion}',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Feature {
  final IconData icon;
  final Color color;
  final String title;
  final String subtitle;
  final Widget page;
  final String screenTitle;

  const _Feature({
    required this.icon,
    required this.color,
    required this.title,
    required this.subtitle,
    required this.page,
    required this.screenTitle,
  });
}

class _FeatureCard extends StatelessWidget {
  final _Feature feature;
  final void Function(BuildContext, String, Widget) onOpen;

  const _FeatureCard({required this.feature, required this.onOpen});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: scheme.surfaceContainerHighest.withValues(alpha: 0.5),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.6)),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: () => onOpen(context, feature.screenTitle, feature.page),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  color: feature.color.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Icon(feature.icon, color: feature.color, size: 28),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      feature.title,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w700,
                            color: scheme.onSurface,
                          ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      feature.subtitle,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: scheme.onSurfaceVariant,
                            height: 1.4,
                          ),
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right, color: scheme.onSurfaceVariant),
            ],
          ),
        ),
      ),
    );
  }
}
