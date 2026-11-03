import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../api/endpoints/auth_endpoints.dart';
import '../core/localization/app_strings.dart';
import '../services/locale_provider.dart';
import '../services/server_config.dart';

class AdminReauthCancelled implements Exception {}

Future<T> runWithAdminReauth<T>(BuildContext context, Future<T> Function() action) async {
  try {
    return await action();
  } on DioException catch (e) {
    final data = e.response?.data;
    final isReauth = e.response?.statusCode == 403 &&
        ((data is Map && data['detail'] == 'admin reauth required') || data == 'admin reauth required');
    if (!isReauth || !context.mounted) {
      rethrow;
    }
    final unlocked = await _promptAdminPassword(context);
    if (!unlocked) {
      throw AdminReauthCancelled();
    }
    return await action();
  }
}

class _AdminReauthDialog extends StatefulWidget {
  final AppStrings strings;
  final Dio dio;

  const _AdminReauthDialog({required this.strings, required this.dio});

  @override
  State<_AdminReauthDialog> createState() => _AdminReauthDialogState();
}

class _AdminReauthDialogState extends State<_AdminReauthDialog> {
  final TextEditingController _ctrl = TextEditingController();
  String? _error;
  bool _busy = false;

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Future<void> _confirm() async {
    if (_busy) {
      return;
    }
    setState(() => _busy = true);
    try {
      await AuthEndpoints(widget.dio).adminUnlock(_ctrl.text);
      if (mounted) {
        Navigator.pop(context, true);
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _error = widget.strings.adminReauthWrong;
          _busy = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.strings.adminReauthTitle),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(widget.strings.adminReauthBody, style: const TextStyle(fontSize: 13)),
          const SizedBox(height: 12),
          TextField(
            controller: _ctrl,
            obscureText: true,
            autofocus: true,
            enabled: !_busy,
            onSubmitted: (_) => _confirm(),
            decoration: InputDecoration(
              labelText: widget.strings.adminReauthPasswordLabel,
              errorText: _error,
              border: const OutlineInputBorder(),
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.pop(context, false),
          child: Text(widget.strings.adminCancel),
        ),
        FilledButton(
          onPressed: _busy ? null : _confirm,
          child: Text(widget.strings.adminReauthConfirm),
        ),
      ],
    );
  }
}

Future<bool> _promptAdminPassword(BuildContext context) async {
  final strings = context.read<LocaleProvider>().strings;
  final dio = context.read<ServerConfig>().api.dio;
  final result = await showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (dialogContext) => _AdminReauthDialog(strings: strings, dio: dio),
  );
  return result == true;
}
