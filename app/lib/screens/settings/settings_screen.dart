import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/constants/app_constants.dart';
import '../../services/locale_provider.dart';
import '../../services/theme_provider.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final theme = context.watch<ThemeProvider>();
    final locale = context.watch<LocaleProvider>();
    final strings = locale.strings;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _sectionLabel(context, strings.languageTitle),
        Card(
          margin: EdgeInsets.zero,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.language, size: 20, color: scheme.primary),
                    const SizedBox(width: 8),
                    Text(strings.languageTitle, style: const TextStyle(fontWeight: FontWeight.bold)),
                  ],
                ),
                const SizedBox(height: 12),
                SegmentedButton<String>(
                  segments: [
                    ButtonSegment(
                      value: 'en',
                      icon: const Icon(Icons.public),
                      label: Text(strings.langEnglish),
                    ),
                    ButtonSegment(
                      value: 'vi',
                      icon: const Icon(Icons.flag_outlined),
                      label: Text(strings.langVietnamese),
                    ),
                  ],
                  selected: {locale.languageCode},
                  onSelectionChanged: (sel) {
                    locale.setLocale(sel.first);
                  },
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 20),
        _sectionLabel(context, strings.themeModeTitle),
        Card(
          margin: EdgeInsets.zero,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.brightness_6_outlined, size: 20, color: scheme.primary),
                    const SizedBox(width: 8),
                    Text(strings.themeModeTitle, style: const TextStyle(fontWeight: FontWeight.bold)),
                  ],
                ),
                const SizedBox(height: 12),
                SegmentedButton<ThemeMode>(
                  segments: [
                    ButtonSegment(
                      value: ThemeMode.system,
                      icon: const Icon(Icons.settings_suggest_outlined),
                      label: Text(strings.themeSystem),
                    ),
                    ButtonSegment(
                      value: ThemeMode.light,
                      icon: const Icon(Icons.light_mode_outlined),
                      label: Text(strings.themeLight),
                    ),
                    ButtonSegment(
                      value: ThemeMode.dark,
                      icon: const Icon(Icons.dark_mode_outlined),
                      label: Text(strings.themeDark),
                    ),
                  ],
                  selected: {theme.mode},
                  onSelectionChanged: (selection) {
                    context.read<ThemeProvider>().setMode(selection.first);
                  },
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 20),
        _sectionLabel(context, strings.projectInfoTitle),
        Card(
          margin: EdgeInsets.zero,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(18),
                    child: Image.asset(
                      'assets/images/app_logo.png',
                      width: 80,
                      height: 80,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => const Icon(Icons.music_note, size: 60),
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                Row(
                  children: [
                    Icon(Icons.info_outline, size: 20, color: scheme.primary),
                    const SizedBox(width: 8),
                    Text(strings.isVi ? 'Ứng dụng' : 'Application', style: const TextStyle(fontWeight: FontWeight.bold)),
                  ],
                ),
                const SizedBox(height: 10),
                _infoRow(context, strings.isVi ? 'Tên' : 'Name', AppConstants.appName),
                _infoRow(context, strings.isVi ? 'Phiên bản' : 'Version', AppConstants.appVersion),
                _infoRow(context, strings.isVi ? 'Mô tả' : 'Summary', strings.appSubtitle),
              ],
            ),
          ),
        ),
        const SizedBox(height: 24),
      ],
    );
  }

  Widget _sectionLabel(BuildContext context, String text) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 0, 4, 8),
      child: Text(
        text,
        style: Theme.of(context).textTheme.labelLarge?.copyWith(
              color: Theme.of(context).colorScheme.primary,
              fontWeight: FontWeight.w700,
            ),
      ),
    );
  }

  Widget _infoRow(BuildContext context, String label, String value) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 96,
            child: Text(
              label,
              style: TextStyle(color: scheme.onSurfaceVariant),
            ),
          ),
          Expanded(child: Text(value)),
        ],
      ),
    );
  }
}
