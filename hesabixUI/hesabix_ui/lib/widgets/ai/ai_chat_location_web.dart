// ignore_for_file: avoid_web_libraries_in_flutter, deprecated_member_use

import 'dart:html' as html;

void replaceAiChatSessionPath({int? sessionId}) {
  final uri = Uri.base;
  final match = RegExp(r'^(.*?/ai/chat)(?:/\d+)?$').firstMatch(uri.path);
  if (match == null) return;
  final next = sessionId == null ? match.group(1)! : '${match.group(1)}/$sessionId';
  if (next == uri.path) return;
  final query = uri.hasQuery ? '?${uri.query}' : '';
  final fragment = uri.hasFragment ? '#${uri.fragment}' : '';
  html.window.history.replaceState(
    html.window.history.state,
    '',
    '$next$query$fragment',
  );
}
