import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../api/api_client.dart';
import '../../core/constants/app_constants.dart';
import '../../services/server_config.dart';
import '../../services/theme_provider.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  late final TextEditingController _urlCtrl;
  bool _checking = false;
  String? _healthMessage;

  @override
  void initState() {
    super.initState();
    _urlCtrl = TextEditingController();
    _loadCurrent();
  }

  Future<void> _loadCurrent() async {
    final config = context.read<ServerConfig>();
    setState(() => _urlCtrl.text = config.baseUrl);
  }

  Future<void> _save() async {
    await context.read<ServerConfig>().setOverride(_urlCtrl.text);
    if (mounted) {
      setState(() => _healthMessage = null);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Đã lưu địa chỉ máy chủ.')),
      );
    }
  }

  Future<void> _reset() async {
    await context.read<ServerConfig>().setOverride(null);
    if (mounted) {
      setState(() {
        _urlCtrl.text = context.read<ServerConfig>().baseUrl;
        _healthMessage = null;
      });
    }
  }

  Future<void> _checkHealth() async {
    setState(() {
      _checking = true;
      _healthMessage = null;
    });
    final config = context.read<ServerConfig>();
    try {
      final res = await config.api.health();
      final data = res.data;
      final ok = data is Map && data['status'] == 'ok';
      setState(() {
        _healthMessage = ok ? 'Máy chủ hoạt động bình thường.' : 'Máy chủ phản hồi nhưng trạng thái lạ: $data';
      });
    } catch (e) {
      setState(() => _healthMessage = ApiClient.describe(e));
    } finally {
      if (mounted) setState(() => _checking = false);
    }
  }

  @override
  void dispose() {
    _urlCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final theme = context.watch<ThemeProvider>();
    final config = context.watch<ServerConfig>();
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _sectionLabel(context, 'Máy chủ AI'),
        Card(
          margin: EdgeInsets.zero,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.dns_outlined, size: 20, color: scheme.primary),
                    const SizedBox(width: 8),
                    const Text('Địa chỉ máy chủ API'),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  'Cấu hình tự động từ GHITA_API.json. Bạn có thể ghi đè tạm thời tại đây.',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _urlCtrl,
                  keyboardType: TextInputType.url,
                  decoration: InputDecoration(
                    hintText: 'http://dia-chi-may-chu:8000',
                    border: const OutlineInputBorder(),
                    isDense: true,
                    suffixIcon: config.hasServer
                        ? Icon(Icons.check_circle, color: scheme.primary, size: 20)
                        : const Icon(Icons.warning_amber_rounded, color: Colors.orange, size: 20),
                  ),
                ),
                if (!config.hasServer) ...[
                  const SizedBox(height: 8),
                  const Text(
                    'Chưa cấu hình máy chủ. Các chức năng AI sẽ không hoạt động.',
                    style: TextStyle(color: Colors.orange),
                  ),
                ],
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    FilledButton.icon(
                      onPressed: _save,
                      icon: const Icon(Icons.save_outlined, size: 18),
                      label: const Text('Lưu'),
                    ),
                    OutlinedButton.icon(
                      onPressed: _checking ? null : _checkHealth,
                      icon: _checking
                          ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                          : const Icon(Icons.wifi_tethering, size: 18),
                      label: const Text('Kiểm tra'),
                    ),
                    TextButton.icon(
                      onPressed: _reset,
                      icon: const Icon(Icons.restart_alt, size: 18),
                      label: const Text('Dùng cấu hình mặc định'),
                    ),
                  ],
                ),
                if (_healthMessage != null) ...[
                  const SizedBox(height: 10),
                  Text(_healthMessage!),
                ],
              ],
            ),
          ),
        ),
        const SizedBox(height: 20),
        _sectionLabel(context, 'Giao diện'),
        Card(
          margin: EdgeInsets.zero,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.brightness_6_outlined, size: 20, color: scheme.primary),
                    const SizedBox(width: 8),
                    const Text('Chế độ hiển thị'),
                  ],
                ),
                const SizedBox(height: 12),
                SegmentedButton<ThemeMode>(
                  segments: const [
                    ButtonSegment(
                      value: ThemeMode.system,
                      icon: Icon(Icons.settings_suggest_outlined),
                      label: Text('Hệ thống'),
                    ),
                    ButtonSegment(
                      value: ThemeMode.light,
                      icon: Icon(Icons.light_mode_outlined),
                      label: Text('Sáng'),
                    ),
                    ButtonSegment(
                      value: ThemeMode.dark,
                      icon: Icon(Icons.dark_mode_outlined),
                      label: Text('Tối'),
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
        _sectionLabel(context, 'Thông tin'),
        Card(
          margin: EdgeInsets.zero,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
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
                      width: 84,
                      height: 84,
                      fit: BoxFit.cover,
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                Row(
                  children: [
                    Icon(Icons.info_outline, size: 20, color: scheme.primary),
                    const SizedBox(width: 8),
                    const Text('Ứng dụng'),
                  ],
                ),
                const SizedBox(height: 10),
                _infoRow(context, 'Tên', AppConstants.appName),
                _infoRow(context, 'Phiên bản', AppConstants.appVersion),
                _infoRow(context, 'Máy chủ', config.hasServer ? config.baseUrl : 'Chưa cấu hình'),
                _infoRow(context, 'Mô tả', 'Nền tảng AI bảo tồn di sản âm nhạc Cố đô Huế'),
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
            width: 88,
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
