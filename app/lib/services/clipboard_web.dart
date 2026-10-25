import 'dart:js_interop';

import 'package:flutter/services.dart';
import 'package:web/web.dart' as web;

Future<bool> copyText(String text) async {
  try {
    final clipboard = web.window.navigator.clipboard;
    await clipboard.writeText(text).toDart;
    return true;
  } catch (_) {}
  try {
    final area = web.HTMLTextAreaElement();
    area.value = text;
    area.setAttribute('readonly', '');
    area.style.position = 'fixed';
    area.style.top = '-9999px';
    area.style.opacity = '0';
    web.document.body!.appendChild(area);
    area.focus();
    area.select();
    area.setSelectionRange(0, text.length);
    final ok = web.document.execCommand('copy');
    area.remove();
    if (ok) {
      return true;
    }
  } catch (_) {}
  try {
    await Clipboard.setData(ClipboardData(text: text));
    return true;
  } catch (_) {
    return false;
  }
}
