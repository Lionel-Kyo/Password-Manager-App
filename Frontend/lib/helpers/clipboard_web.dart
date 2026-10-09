import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:web/web.dart' as web;

Future<void> copyToClipboard(String text) async {
  try {
    await Clipboard.setData(ClipboardData(text: text));
  } catch (e) {
    _webHttpClipboardFallback(text);
  }
}

void _webHttpClipboardFallback(String text) {
  final textarea = web.document.createElement('textarea') as web.HTMLTextAreaElement;
  textarea.value = text;
  
  textarea.style.position = 'fixed';
  textarea.style.top = '0';
  textarea.style.left = '0';
  textarea.style.opacity = '0';
  
  web.document.body!.appendChild(textarea);
  textarea.focus();
  textarea.select();
  
  try {
    web.document.execCommand('copy');
  } catch (err) {
    debugPrint('Fallback copy failed: $err');
  }
  
  web.document.body!.removeChild(textarea);
}
