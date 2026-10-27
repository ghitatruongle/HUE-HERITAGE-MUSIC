// Onboarding desktop: lần chạy đầu chưa có máy chủ → hiện hộp Kết nối máy chủ.
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/locale_provider.dart';
import '../services/server_config.dart';

class ServerOnboardingDialog extends StatefulWidget {
  const ServerOnboardingDialog({super.key});

  @override
  State<ServerOnboardingDialog> createState() => _ServerOnboardingDialogState();
}

class _ServerOnboardingDialogState extends State<ServerOnboardingDialog> {
  final _ctrl = TextEditingController();
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Future<void> _connect() async {
    final strings = context.read<LocaleProvider>().strings;
    final url = _ctrl.text.trim();
    if (url.isEmpty) {
      setState(() => _error = strings.onboardingEnterUrl);
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await context.read<ServerConfig>().saveServerUrl(url);
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (_) {
      if (mounted) {
        setState(() => _error = strings.onboardingSaveFail);
      }
    } finally {
      if (mounted) {
        setState(() => _saving = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final strings = context.watch<LocaleProvider>().strings;
    return AlertDialog(
      title: Text(strings.onboardingTitle),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(strings.onboardingHint, style: const TextStyle(fontSize: 12.5)),
          const SizedBox(height: 12),
          TextField(
            controller: _ctrl,
            decoration: InputDecoration(
              labelText: strings.onboardingUrlLabel,
              hintText: 'http://192.0.2.10:8000',
              border: const OutlineInputBorder(),
            ),
            onSubmitted: (_) => _connect(),
          ),
          if (_error != null) ...[
            const SizedBox(height: 8),
            Text(_error!, style: const TextStyle(color: Colors.red, fontSize: 12)),
          ],
        ],
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.of(context).pop(false),
          child: Text(strings.onboardingLater),
        ),
        FilledButton(
          onPressed: _saving ? null : _connect,
          child: Text(strings.onboardingConnect),
        ),
      ],
    );
  }
}
