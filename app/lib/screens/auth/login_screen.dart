import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../api/api_client.dart';
import '../../api/endpoints/auth_endpoints.dart';
import 'account_manager_section.dart';
import 'invite_manager_section.dart';
import '../../core/localization/app_strings.dart';
import '../../services/auth_service.dart';
import '../../services/locale_provider.dart';
import '../../services/server_config.dart';
import '../../widgets/common_button.dart';

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
      await auth.save(token: user.token, username: user.username, email: user.email, role: user.role);
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

  Future<void> _submitRegister() async {
    final strings = context.read<LocaleProvider>().strings;
    final username = _regUsernameCtrl.text.trim();
    final email = _regEmailCtrl.text.trim().toLowerCase();
    final password = _regPasswordCtrl.text;
    final inviteCode = _regInviteCodeCtrl.text.trim();

    if (username.length < 3) {
      setState(() => _error = strings.authErrUsernameShort);
      return;
    }
    if (!email.endsWith('@gmail.com') || email.length <= 10) {
      setState(() => _error = strings.authErrGmail);
      return;
    }
    if (password.length < 6) {
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
      await auth.save(token: user.token, username: user.username, email: user.email, role: user.role);
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
    await context.read<AuthService>().clearToken();
    setState(() {
      _error = null;
    });
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
                  Tab(icon: const Icon(Icons.login), text: strings.authTabLogin),
                  Tab(icon: const Icon(Icons.person_add_alt_1), text: strings.authTabRegister),
                ],
              ),
      ),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
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
                          margin: const EdgeInsets.only(bottom: 16),
                          child: Padding(
                            padding: const EdgeInsets.all(12),
                            child: Row(
                              children: [
                                Icon(Icons.key_off_outlined, color: scheme.onTertiaryContainer),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    strings.authStorageWarning,
                                    style: TextStyle(color: scheme.onTertiaryContainer, fontSize: 12.5),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                      if (_error != null) ...[
                        Card(
                          color: scheme.errorContainer,
                          margin: const EdgeInsets.only(bottom: 16),
                          child: Padding(
                            padding: const EdgeInsets.all(12),
                            child: Row(
                              children: [
                                Icon(Icons.error_outline, color: scheme.onErrorContainer),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(_error!, style: TextStyle(color: scheme.onErrorContainer)),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                      SizedBox(
                        height: 480,
                        child: TabBarView(
                          controller: _tabController,
                          children: [
                            _buildLoginTab(strings),
                            _buildRegisterTab(strings),
                          ],
                        ),
                      ),
                    ],
                  ),
          ),
        ),
      ),
    );
  }

  Widget _buildLoggedInCard(BuildContext context, AuthService auth, ColorScheme scheme, AppStrings strings) {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            CircleAvatar(
              radius: 36,
              backgroundColor: scheme.primary.withValues(alpha: 0.15),
              child: Icon(Icons.verified_user, size: 40, color: scheme.primary),
            ),
            const SizedBox(height: 16),
            Text(
              auth.username ?? strings.authDefaultUser,
              style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
            ),
            if (auth.email != null && auth.email!.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(auth.email!, style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: Colors.grey)),
            ],
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: auth.isAdmin ? Colors.amber.shade50 : Colors.blue.shade50,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: auth.isAdmin ? Colors.amber.shade300 : Colors.blue.shade300),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    auth.isAdmin ? Icons.admin_panel_settings : Icons.person,
                    size: 14,
                    color: auth.isAdmin ? Colors.amber.shade800 : Colors.blue.shade700,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    auth.isAdmin ? strings.authRoleAdmin : strings.authRoleUser,
                    style: TextStyle(
                      color: auth.isAdmin ? Colors.amber.shade900 : Colors.blue.shade700,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.green.shade50,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.green.shade300),
              ),
              child: Text(strings.authLoggedInChip, style: const TextStyle(color: Colors.green, fontSize: 12, fontWeight: FontWeight.w600)),
            ),
            const SizedBox(height: 24),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _busy ? null : _logout,
                    icon: const Icon(Icons.logout),
                    label: Text(strings.authLogoutBtn),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton.tonalIcon(
                    onPressed: _busy ? null : _chooseGuestMode,
                    icon: const Icon(Icons.person_outline),
                    label: Text(strings.authGuestModeBtn),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: _busy ? null : _openChangePassword,
              icon: const Icon(Icons.lock_reset, size: 16),
              label: Text(strings.changePasswordBtn),
            ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: _busy ? null : _logoutEverywhere,
              icon: const Icon(Icons.phonelink_erase, size: 16),
              label: Text(strings.logoutEverywhereBtn),
            ),
            if (auth.isAdmin) ...[
              const SizedBox(height: 16),
              const Divider(),
              const InviteManagerSection(),
              const SizedBox(height: 16),
              const AccountManagerSection(),
            ],
          ],
        ),
      ),
    );
  }

  Future<void> _openChangePassword() async {
    final strings = context.read<LocaleProvider>().strings;
    final oldCtrl = TextEditingController();
    final newCtrl = TextEditingController();
    final confirmCtrl = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(strings.changePasswordBtn),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(controller: oldCtrl, obscureText: true, decoration: InputDecoration(labelText: strings.changePasswordOld)),
            TextField(controller: newCtrl, obscureText: true, decoration: InputDecoration(labelText: strings.changePasswordNew)),
            TextField(controller: confirmCtrl, obscureText: true, decoration: InputDecoration(labelText: strings.changePasswordConfirm)),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(strings.closeBtn)),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('OK')),
        ],
      ),
    );
    if (!mounted || confirmed != true) return;
    if (newCtrl.text != confirmCtrl.text || newCtrl.text.length < 6) {
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
        await auth.save(token: newToken, username: auth.username ?? '', email: auth.email, role: auth.isAdmin ? 'admin' : 'user');
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
  }

  Future<void> _logoutEverywhere() async {
    final strings = context.read<LocaleProvider>().strings;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(strings.logoutEverywhereBtn),
        content: Text(strings.logoutEverywhereConfirm),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(strings.closeBtn)),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('OK')),
        ],
      ),
    );
    if (!mounted || confirmed != true) return;
    try {
      final dio = context.read<ServerConfig>().api.dio;
      await AuthEndpoints(dio).revokeAllTokens();
    } catch (_) {}
    if (!mounted) return;
    await context.read<AuthService>().clearToken();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(strings.logoutEverywhereDone)));
    }
  }

  Widget _buildLoginTab(AppStrings strings) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          controller: _loginIdCtrl,
          decoration: InputDecoration(
            labelText: strings.authLoginIdLabel,
            hintText: strings.authLoginIdHint,
            border: const OutlineInputBorder(),
            prefixIcon: const Icon(Icons.account_circle_outlined),
          ),
          enabled: !_busy,
        ),
        const SizedBox(height: 16),
        TextField(
          controller: _loginPasswordCtrl,
          obscureText: true,
          decoration: InputDecoration(
            labelText: strings.authPasswordLabel,
            border: const OutlineInputBorder(),
            prefixIcon: const Icon(Icons.lock_outline),
          ),
          enabled: !_busy,
          onSubmitted: (_) => _submitLogin(),
        ),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: Colors.amber.shade50,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: Colors.amber.shade300),
          ),
          child: Row(
            children: [
              const Icon(Icons.info_outline, size: 16, color: Colors.amber),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  strings.authNoResetNote,
                  style: const TextStyle(fontSize: 11, color: Colors.brown),
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
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Text(strings.authOrDivider, style: const TextStyle(color: Colors.grey, fontSize: 12)),
            ),
            const Expanded(child: Divider()),
          ],
        ),
        const SizedBox(height: 16),
        OutlinedButton.icon(
          style: OutlinedButton.styleFrom(
            padding: const EdgeInsets.symmetric(vertical: 14),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
          onPressed: _busy ? null : _chooseGuestMode,
          icon: const Icon(Icons.visibility_outlined),
          label: Text(strings.authGuestBtn, style: const TextStyle(fontWeight: FontWeight.bold)),
        ),
        const SizedBox(height: 6),
        Text(
          strings.authGuestNote,
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 11, color: Colors.grey),
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
            prefixIcon: const Icon(Icons.person_outline),
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
            prefixIcon: const Icon(Icons.alternate_email),
          ),
          enabled: !_busy,
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _regPasswordCtrl,
          obscureText: true,
          decoration: InputDecoration(
            labelText: strings.authPasswordMinLabel,
            border: const OutlineInputBorder(),
            prefixIcon: const Icon(Icons.lock_outline),
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
            prefixIcon: const Icon(Icons.vpn_key_outlined),
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
          style: const TextStyle(fontSize: 11, color: Colors.grey),
        ),
      ],
    );
  }
}
