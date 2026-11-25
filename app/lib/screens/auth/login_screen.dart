import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../api/api_client.dart';
import '../../api/endpoints/auth_endpoints.dart';
import '../../core/localization/app_strings.dart';
import '../../services/auth_service.dart';
import '../../core/theme/app_theme.dart';
import '../../services/history_service.dart';
import '../../services/locale_provider.dart';
import '../../services/practice_resume.dart';
import '../../services/server_config.dart';
import '../../services/session_media.dart';
import '../../widgets/avatar_view.dart';
import '../../widgets/feature_header.dart';
import '../../widgets/common_button.dart';
import '../../widgets/error_panel.dart';
import '../../widgets/hue_icons.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> with SingleTickerProviderStateMixin {
  late final TabController _tabController;

  final _loginIdCtrl = TextEditingController();
  final _loginPasswordCtrl = TextEditingController();

  final _regUsernameCtrl = TextEditingController();
  final _regEmailCtrl = TextEditingController();
  final _regPasswordCtrl = TextEditingController();
  final _regInviteCodeCtrl = TextEditingController();

  bool _busy = false;
  bool _obscureLogin = true;
  bool _obscureRegister = true;
  bool _obscureDialog = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    _loginIdCtrl.dispose();
    _loginPasswordCtrl.dispose();
    _regUsernameCtrl.dispose();
    _regEmailCtrl.dispose();
    _regPasswordCtrl.dispose();
    _regInviteCodeCtrl.dispose();
    super.dispose();
  }

  Future<void> _submitLogin() async {
    if (_busy) return;
    final strings = context.read<LocaleProvider>().strings;
    final identifier = _loginIdCtrl.text.trim();
    final password = _loginPasswordCtrl.text;
    if (identifier.isEmpty) {
      setState(() => _error = strings.authErrLoginId);
      return;
    }
    if (password.isEmpty) {
      setState(() => _error = strings.authErrPasswordEmpty);
      return;
    }

    setState(() {
      _busy = true;
      _error = null;
    });

    try {
      final dio = context.read<ServerConfig>().api.dio;
      final api = AuthEndpoints(dio);
      final auth = context.read<AuthService>();
      final user = await api.login(identifier: identifier, password: password);
      await auth.save(
        token: user.token,
        username: user.username,
        email: user.email,
        role: user.role,
        mustChangePassword: user.mustChangePassword,
        avatar: user.avatar,
      );
      if (mounted) {
        Navigator.of(context).maybePop();
      }
    } catch (e) {
      if (mounted) {
        setState(() => _error = ApiClient.describe(e));
      }
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  bool _passwordMeetsPolicy(String password) =>
      password.length >= 8 &&
      RegExp(r'[A-Za-z]').hasMatch(password) &&
      RegExp(r'[0-9]').hasMatch(password);

  void _clearSessionCaches() {
    AvatarView.clearCache();
    PracticeResume.clear();
    if (!mounted) return;
    try {
      context.read<SessionMedia>().clearRecording();
    } catch (_) {}
    try {
      unawaited(context.read<HistoryService>().clear());
    } catch (_) {}
  }

  Future<void> _submitRegister() async {
    if (_busy) return;
    final strings = context.read<LocaleProvider>().strings;
    final username = _regUsernameCtrl.text.trim();
    final email = _regEmailCtrl.text.trim().toLowerCase();
    final password = _regPasswordCtrl.text;
    final inviteCode = _regInviteCodeCtrl.text.trim();

    if (username.length < 3) {
      setState(() => _error = strings.authErrUsernameShort);
      return;
    }
    if (!RegExp(r'^[A-Za-z0-9._%+\-]+@[A-Za-z0-9.\-]+\.[A-Za-z]{2,}$').hasMatch(email)) {
      setState(() => _error = strings.authErrEmail);
      return;
    }
    if (!_passwordMeetsPolicy(password)) {
      setState(() => _error = strings.authErrPasswordShort);
      return;
    }
    if (inviteCode.isEmpty) {
      setState(() => _error = strings.authErrInvite);
      return;
    }

    setState(() {
      _busy = true;
      _error = null;
    });

    try {
      final dio = context.read<ServerConfig>().api.dio;
      final api = AuthEndpoints(dio);
      final auth = context.read<AuthService>();
      final user = await api.register(
        username: username,
        email: email,
        password: password,
        inviteCode: inviteCode,
      );
      await auth.save(
        token: user.token,
        username: user.username,
        email: user.email,
        role: user.role,
        mustChangePassword: user.mustChangePassword,
        avatar: user.avatar,
      );
      if (mounted) {
        Navigator.of(context).maybePop();
      }
    } catch (e) {
      if (mounted) {
        setState(() => _error = ApiClient.describe(e));
      }
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  void _chooseGuestMode() {
    final strings = context.read<LocaleProvider>().strings;
    context.read<AuthService>().continueAsGuest(displayName: strings.authGuestUsername);
    Navigator.of(context).maybePop();
  }

  Future<void> _logout() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await context.read<AuthService>().clearToken();
      if (!mounted) return;
      _clearSessionCaches();
      setState(() {
        _error = null;
      });
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthService>();
    final strings = context.watch<LocaleProvider>().strings;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: Text(strings.authScreenTitle),
        bottom: auth.isLoggedIn
            ? null
            : TabBar(
                controller: _tabController,
                tabs: [
                  Tab(icon: const HueIcon(HueIcons.login), text: strings.authTabLogin),
                  Tab(icon: const HueIcon(HueIcons.personAdd), text: strings.authTabRegister),
                ],
              ),
      ),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xxl, vertical: AppSpacing.xl),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: auth.isLoggedIn
                ? _buildLoggedInCard(context, auth, scheme, strings)
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (auth.secureStorageBroken) ...[
                        Card(
                          color: scheme.tertiaryContainer,
                          margin: const EdgeInsets.only(bottom: AppSpacing.lg),
                          child: Padding(
                            padding: const EdgeInsets.all(AppSpacing.md),
                            child: Row(
                              children: [
                                HueIcon(HueIcons.keyOff, color: scheme.onTertiaryContainer),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    strings.authStorageWarning,
                                    style: TextStyle(color: scheme.onTertiaryContainer, fontSize: AppFontSize.sm),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                      if (_error != null) ...[
                        Padding(
                          padding: const EdgeInsets.only(bottom: AppSpacing.lg),
                          child: ErrorPanel(message: _error!),
                        ),
                      ],
                      FeatureHeader(
                        title: strings.appTitle,
                        subtitle: strings.appSubtitle,
                        icon: HueIcons.vpnKey,
                      ),
                      AnimatedBuilder(
                        animation: _tabController,
                        builder: (context, _) => _tabController.index == 0
                            ? _buildLoginTab(strings)
                            : _buildRegisterTab(strings),
                      ),
                    ],
                  ),
          ),
        ),
      ),
    );
  }

  Widget _buildLoggedInCard(BuildContext context, AuthService auth, ColorScheme scheme, AppStrings strings) {
    final roleColor = auth.isAdmin
        ? AppTheme.statusReadable(context, AppStatusKind.warning)
        : auth.role == 'worker'
            ? AppTheme.emeraldReadable(context)
            : AppTheme.statusReadable(context, AppStatusKind.info);
    final roleIcon = auth.isAdmin
        ? HueIcons.adminPanel
        : auth.role == 'worker'
            ? HueIcons.engineering
            : HueIcons.person;
    final roleLabel = auth.isAdmin
        ? strings.authRoleAdmin
        : auth.role == 'worker'
            ? strings.authRoleWorker
            : strings.authRoleUser;
    final loggedColor = AppTheme.statusReadable(context, AppStatusKind.success);
    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.lg)),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xxl),
        child: Column(
          children: [
            AvatarView(
              url: auth.avatar,
              size: 72,
              icon: HueIcons.verified,
              iconColor: scheme.primary,
            ),
            const SizedBox(height: 16),
            Text(
              auth.username ?? strings.authDefaultUser,
              style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
            ),
            if (auth.email != null && auth.email!.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(auth.email!, style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant)),
            ],
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.xs),
              decoration: BoxDecoration(
                color: roleColor.withAlpha(40),
                borderRadius: BorderRadius.circular(AppRadius.md),
                border: Border.all(color: roleColor),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  HueIcon(roleIcon, size: 14, color: roleColor),
                  const SizedBox(width: 6),
                  Text(
                    roleLabel,
                    style: TextStyle(
                      color: roleColor,
                      fontSize: AppFontSize.sm,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.xs),
              decoration: BoxDecoration(
                color: loggedColor.withAlpha(40),
                borderRadius: BorderRadius.circular(AppRadius.md),
                border: Border.all(color: loggedColor),
              ),
              child: Text(strings.authLoggedInChip, style: TextStyle(color: loggedColor, fontSize: AppFontSize.sm, fontWeight: FontWeight.w600)),
            ),
            const SizedBox(height: 24),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _busy ? null : _logout,
                    icon: const HueIcon(HueIcons.logout),
                    label: Text(strings.authLogoutBtn),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton.tonalIcon(
                    onPressed: _busy ? null : _chooseGuestMode,
                    icon: const HueIcon(HueIcons.person),
                    label: Text(strings.authGuestModeBtn),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: _busy ? null : _openChangePassword,
              icon: const HueIcon(HueIcons.lockReset, size: 16),
              label: Text(strings.changePasswordBtn),
            ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: _busy ? null : _logoutEverywhere,
              icon: const HueIcon(HueIcons.phonelinkErase, size: 16),
              label: Text(strings.logoutEverywhereBtn),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _openChangePassword() async {
    if (_busy) return;
    setState(() => _obscureDialog = true);
    final strings = context.read<LocaleProvider>().strings;
    final oldCtrl = TextEditingController();
    final newCtrl = TextEditingController();
    final confirmCtrl = TextEditingController();
    try {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (ctx) => StatefulBuilder(
          builder: (ctx, setDialogState) => AlertDialog(
          title: Text(strings.changePasswordBtn),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(controller: oldCtrl, obscureText: true, decoration: InputDecoration(labelText: strings.changePasswordOld)),
              TextField(controller: newCtrl, obscureText: _obscureDialog, decoration: InputDecoration(labelText: strings.changePasswordNew, suffixIcon: IconButton(tooltip: _obscureDialog ? strings.obscureShowPassword : strings.obscureHidePassword, icon: HueIcon(_obscureDialog ? HueIcons.visibility : HueIcons.visibilityOff, size: 20, decorative: true), onPressed: () => setDialogState(() => _obscureDialog = !_obscureDialog)))),
              TextField(controller: confirmCtrl, obscureText: true, decoration: InputDecoration(labelText: strings.changePasswordConfirm)),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(strings.closeBtn)),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(strings.commonOk)),
          ],
        ),
        ),
      );
      if (!mounted || confirmed != true) return;
      if (newCtrl.text != confirmCtrl.text || !_passwordMeetsPolicy(newCtrl.text)) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(strings.changePasswordMismatch)));
        }
        return;
      }
      setState(() => _busy = true);
      final dio = context.read<ServerConfig>().api.dio;
      final auth = context.read<AuthService>();
      try {
        final newToken = await AuthEndpoints(dio).changePassword(
          oldPassword: oldCtrl.text,
          newPassword: newCtrl.text,
        );
        if (newToken.isNotEmpty) {
          await auth.save(token: newToken, username: auth.username ?? '', email: auth.email, role: auth.role, avatar: auth.avatar);
        }
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(strings.changePasswordDone)));
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(ApiClient.describe(e))));
        }
      } finally {
        if (mounted) {
          setState(() => _busy = false);
        }
      }
    } finally {
      unawaited(Future<void>.delayed(const Duration(milliseconds: 400), () {
        oldCtrl.dispose();
        newCtrl.dispose();
        confirmCtrl.dispose();
      }));
    }
  }

  Future<void> _logoutEverywhere() async {
    if (_busy) return;
    final strings = context.read<LocaleProvider>().strings;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(strings.logoutEverywhereBtn),
        content: Text(strings.logoutEverywhereConfirm),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(strings.closeBtn)),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(strings.commonOk)),
        ],
      ),
    );
    if (!mounted || confirmed != true) return;
    setState(() => _busy = true);
    Object? revokeError;
    try {
      final dio = context.read<ServerConfig>().api.dio;
      await AuthEndpoints(dio).revokeAllTokens();
    } catch (e) {
      revokeError = e;
    }
    try {
      if (!mounted) return;
      await context.read<AuthService>().clearToken();
      if (!mounted) return;
      _clearSessionCaches();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            revokeError != null ? ApiClient.describe(revokeError) : strings.logoutEverywhereDone,
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Widget _buildLoginTab(AppStrings strings) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Semantics(
          label: strings.authLoginIdLabel,
          child: TextField(
            controller: _loginIdCtrl,
            decoration: InputDecoration(
              labelText: strings.authLoginIdLabel,
              hintText: strings.authLoginIdHint,
              border: const OutlineInputBorder(),
              prefixIcon: const HueIcon(HueIcons.accountCircle),
            ),
            enabled: !_busy,
          ),
        ),
        const SizedBox(height: 16),
        Semantics(
          label: strings.authPasswordLabel,
          child: TextField(
            controller: _loginPasswordCtrl,
            obscureText: _obscureLogin,
            decoration: InputDecoration(
              labelText: strings.authPasswordLabel,
              border: const OutlineInputBorder(),
              prefixIcon: const HueIcon(HueIcons.lock),
              suffixIcon: IconButton(
                icon: HueIcon(_obscureLogin ? HueIcons.visibility : HueIcons.visibilityOff, size: 20, decorative: true),
                tooltip: strings.authTogglePassword,
                onPressed: () => setState(() => _obscureLogin = !_obscureLogin),
              ),
            ),
            enabled: !_busy,
            onSubmitted: (_) => _submitLogin(),
          ),
        ),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.sm),
          decoration: BoxDecoration(
            color: AppTheme.statusWarning.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(AppRadius.sm),
            border: Border.all(color: AppTheme.statusReadable(context, AppStatusKind.warning).withValues(alpha: 0.35)),
          ),
          child: Row(
            children: [
              HueIcon(HueIcons.info, size: 16, color: AppTheme.statusReadable(context, AppStatusKind.warning)),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  strings.authNoResetNote,
                  style: TextStyle(
                    fontSize: AppFontSize.xs,
                    color: Theme.of(context).colorScheme.onSurface,
                    height: 1.4,
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        CommonButton(
          label: strings.authLoginBtn,
          loading: _busy,
          onPressed: _submitLogin,
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            const Expanded(child: Divider()),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
              child: Text(strings.authOrDivider, style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant, fontSize: AppFontSize.sm)),
            ),
            const Expanded(child: Divider()),
          ],
        ),
        const SizedBox(height: 16),
        OutlinedButton.icon(
          style: OutlinedButton.styleFrom(
            padding: const EdgeInsets.symmetric(vertical: AppSpacing.lg),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.md)),
          ),
          onPressed: _busy ? null : _chooseGuestMode,
          icon: const HueIcon(HueIcons.visibility),
          label: Text(strings.authGuestBtn, style: const TextStyle(fontWeight: FontWeight.bold)),
        ),
        const SizedBox(height: 6),
        Text(
          strings.authGuestNote,
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: AppFontSize.xs, color: Theme.of(context).colorScheme.onSurfaceVariant),
        ),
      ],
    );
  }

  Widget _buildRegisterTab(AppStrings strings) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          controller: _regUsernameCtrl,
          decoration: InputDecoration(
            labelText: strings.authUsernameLabel,
            border: const OutlineInputBorder(),
            prefixIcon: const HueIcon(HueIcons.person),
          ),
          enabled: !_busy,
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _regEmailCtrl,
          keyboardType: TextInputType.emailAddress,
          decoration: InputDecoration(
            labelText: strings.authGmailLabel,
            hintText: strings.authGmailHint,
            border: const OutlineInputBorder(),
            prefixIcon: const HueIcon(HueIcons.alternateEmail),
          ),
          enabled: !_busy,
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _regPasswordCtrl,
          obscureText: _obscureRegister,
          decoration: InputDecoration(
            labelText: strings.authPasswordMinLabel,
            border: const OutlineInputBorder(),
            prefixIcon: const HueIcon(HueIcons.lock),
            suffixIcon: IconButton(
              icon: HueIcon(_obscureRegister ? HueIcons.visibility : HueIcons.visibilityOff, size: 20, decorative: true),
              tooltip: strings.authTogglePassword,
              onPressed: () => setState(() => _obscureRegister = !_obscureRegister),
            ),
          ),
          enabled: !_busy,
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _regInviteCodeCtrl,
          decoration: InputDecoration(
            labelText: strings.authInviteLabel,
            hintText: strings.authInviteHint,
            border: const OutlineInputBorder(),
            prefixIcon: const HueIcon(HueIcons.vpnKey),
          ),
          enabled: !_busy,
        ),
        const SizedBox(height: 16),
        CommonButton(
          label: strings.authRegisterBtn,
          loading: _busy,
          onPressed: _submitRegister,
        ),
        const SizedBox(height: 8),
        Text(
          strings.authRegisterFootnote,
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: AppFontSize.xs, color: Theme.of(context).colorScheme.onSurfaceVariant),
        ),
      ],
    );
  }
}
