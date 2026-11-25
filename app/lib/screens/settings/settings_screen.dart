import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../api/endpoints/auth_endpoints.dart';
import '../../core/constants/app_constants.dart';
import '../../core/theme/app_theme.dart';
import '../../services/auth_service.dart';
import '../../services/locale_provider.dart';
import '../../services/server_config.dart';
import '../../services/theme_provider.dart';
import '../../widgets/app_logo.dart';
import '../../widgets/avatar_view.dart';
import '../../widgets/hue_button.dart';
import '../../widgets/server_onboarding_dialog.dart';
import '../../widgets/storage_quota_card.dart';
import '../../widgets/hue_icons.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  bool _avatarBusy = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final auth = context.read<AuthService>();
      final config = context.read<ServerConfig>();
      if (auth.isLoggedIn && config.hasServer) {
        auth.validateSession(config.baseUrl);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final theme = context.watch<ThemeProvider>();
    final locale = context.watch<LocaleProvider>();
    final auth = context.watch<AuthService>();
    final strings = locale.strings;

    return ListView(
      padding: const EdgeInsets.all(AppSpacing.lg),
      children: [
        if (auth.isLoggedIn) ...[
          _sectionLabel(context, strings.accountAvatarTitle),
          _buildAccountCard(context, strings, auth),
          const SizedBox(height: 20),
        ],
        _sectionLabel(context, strings.languageTitle),
        Card(
          margin: EdgeInsets.zero,
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.lg),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    HueIcon(HueIcons.language, size: 20, color: scheme.primary),
                    const SizedBox(width: 8),
                    Text(strings.languageTitle, style: const TextStyle(fontWeight: FontWeight.bold)),
                  ],
                ),
                const SizedBox(height: 12),
                SegmentedButton<String>(
                  segments: [
                    ButtonSegment(
                      value: 'en',
                      icon: const HueIcon(HueIcons.language),
                      label: Text(strings.langEnglish),
                    ),
                    ButtonSegment(
                      value: 'vi',
                      icon: const HueIcon(HueIcons.flag),
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
            padding: const EdgeInsets.all(AppSpacing.lg),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    HueIcon(HueIcons.brightness, size: 20, color: scheme.primary),
                    const SizedBox(width: 8),
                    Text(strings.themeModeTitle, style: const TextStyle(fontWeight: FontWeight.bold)),
                  ],
                ),
                const SizedBox(height: 12),
                SegmentedButton<ThemeMode>(
                  segments: [
                    ButtonSegment(
                      value: ThemeMode.system,
                      icon: const HueIcon(HueIcons.settingsSuggest),
                      label: Text(strings.themeSystem),
                    ),
                    ButtonSegment(
                      value: ThemeMode.light,
                      icon: const HueIcon(HueIcons.lightMode),
                      label: Text(strings.themeLight),
                    ),
                    ButtonSegment(
                      value: ThemeMode.dark,
                      icon: const HueIcon(HueIcons.darkMode),
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
        if (auth.isLoggedIn && auth.isStaff) ...[
          const SizedBox(height: 20),
          _buildServerSection(context, strings),
        ],
        if (auth.isLoggedIn && auth.storageUsedBytes != null) ...[
          const SizedBox(height: 20),
          _sectionLabel(context, strings.storageTitle),
          StorageQuotaCard(
            strings: strings,
            usedBytes: auth.storageUsedBytes ?? 0,
            quotaBytes: auth.storageQuotaBytes,
          ),
        ],
        const SizedBox(height: 20),
        _sectionLabel(context, strings.projectInfoTitle),
        Card(
          margin: EdgeInsets.zero,
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.lg),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: AppLogo(size: 80, borderRadius: 18, iconSize: 60, iconColor: scheme.primary),
                ),
                const SizedBox(height: 14),
                Row(
                  children: [
                    HueIcon(HueIcons.info, size: 20, color: scheme.primary),
                    const SizedBox(width: 8),
                    Text(strings.settingsAppInfo, style: const TextStyle(fontWeight: FontWeight.bold)),
                  ],
                ),
                const SizedBox(height: 10),
                _infoRow(context, strings.settingsName, AppConstants.appName),
                _infoRow(context, strings.versionLabel, AppConstants.appVersion),
                _infoRow(context, strings.settingsDescription, strings.appSubtitle),
              ],
            ),
          ),
        ),
        const SizedBox(height: 24),
      ],
    );
  }

  Widget _buildAccountCard(BuildContext context, dynamic strings, AuthService auth) {
    final scheme = Theme.of(context).colorScheme;
    final roleLabel = auth.role == 'admin'
        ? strings.adminRoleAdmin
        : auth.role == 'worker'
            ? strings.adminRoleWorker
            : strings.adminRoleUser;
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final infoRow = Row(
              children: [
                AvatarView(
                  url: auth.avatar,
                  size: 56,
                  icon: auth.role == 'worker' ? HueIcons.engineering : HueIcons.accountCircle,
                ),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        auth.username ?? '',
                        style: const TextStyle(fontWeight: FontWeight.w700, fontSize: AppFontSize.xl),
                      ),
                      if ((auth.email ?? '').isNotEmpty)
                        Text(
                          auth.email!,
                          style: TextStyle(fontSize: AppFontSize.sm, color: scheme.onSurfaceVariant),
                        ),
                      const SizedBox(height: AppSpacing.xs),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm, vertical: AppSpacing.xs),
                        decoration: BoxDecoration(
                          color: scheme.primaryContainer,
                          borderRadius: BorderRadius.circular(AppRadius.xs),
                        ),
                        child: Text(
                          roleLabel,
                          style: TextStyle(fontSize: AppFontSize.xs, color: scheme.onPrimaryContainer, fontWeight: FontWeight.w600),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            );
            if (!auth.isStaff) {
              return infoRow;
            }
            final avatarButton = HueButton(
              label: strings.accountAvatarChange,
              icon: HueIcons.edit,
              variant: HueButtonVariant.ghost,
              size: HueButtonSize.small,
              loading: _avatarBusy,
              onPressed: _avatarBusy ? null : () => _changeAvatar(strings, auth),
            );
            if (constraints.maxWidth < 400) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  infoRow,
                  const SizedBox(height: AppSpacing.md),
                  Align(alignment: Alignment.centerRight, child: avatarButton),
                ],
              );
            }
            return Row(
              children: [
                Expanded(child: infoRow),
                const SizedBox(width: AppSpacing.sm),
                avatarButton,
              ],
            );
          },
        ),
      ),
    );
  }

  Future<void> _changeAvatar(dynamic strings, AuthService auth) async {
    if (_avatarBusy) return;
    setState(() => _avatarBusy = true);
    try {
      final picked = await FilePicker.platform.pickFiles(
        type: FileType.image,
        withData: true,
      );
      final file = picked?.files.single;
      final bytes = file?.bytes;
      if (!mounted) return;
      if (file == null || bytes == null || bytes.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(strings.accountAvatarPickFail)));
        return;
      }
      final lower = file.name.toLowerCase();
      final contentType = lower.endsWith('.png') ? 'image/png' : 'image/jpeg';
      final dio = context.read<ServerConfig>().api.dio;
      final url = await AuthEndpoints(dio).uploadAvatar(
        bytes: bytes,
        filename: file.name,
        contentType: contentType,
      );
      if (!mounted) return;
      if (url.isNotEmpty) {
        AvatarView.evict(url);
        auth.setAvatar(url);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(strings.accountAvatarUpdated)));
      } else {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(strings.accountAvatarFail)));
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(strings.accountAvatarFail)));
      }
    } finally {
      if (mounted) {
        setState(() => _avatarBusy = false);
      }
    }
  }

  Widget _buildServerSection(BuildContext context, dynamic strings) {
    final scheme = Theme.of(context).colorScheme;
    final server = context.watch<ServerConfig>();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionLabel(context, strings.serverSectionTitle),
        Card(
          margin: EdgeInsets.zero,
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.lg),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    HueIcon(HueIcons.dns, size: 20, color: scheme.primary),
                    const Spacer(),
                    Container(
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: server.hasServer ? AppTheme.emeraldReadable(context) : AppTheme.statusReadable(context, AppStatusKind.danger),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                _infoRow(
                  context,
                  strings.onboardingUrlLabel,
                  server.hasServer ? server.baseUrl : strings.serverNotConfigured,
                ),
                const SizedBox(height: 10),
                HueButton(
                  label: strings.serverChangeAction,
                  variant: HueButtonVariant.gold,
                  icon: HueIcons.edit,
                  size: HueButtonSize.small,
                  onPressed: () {
                    showDialog<void>(
                      context: context,
                      builder: (_) => const ServerOnboardingDialog(),
                    );
                  },
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _sectionLabel(BuildContext context, String text) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(AppSpacing.xs, 0, AppSpacing.xs, AppSpacing.sm),
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
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
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
