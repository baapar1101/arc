/// نرمال‌سازی محافظه‌کارانه‌ی markdown دستیار برای CommonMark.
///
/// مدل‌ها اغلب تأکید را با فاصله می‌نویسند (`** متن **`) که بولد نمی‌شود.
/// بلوک کد و inline code دست‌نخورده می‌مانند.
String normalizeAssistantMarkdown(String input) {
  if (input.isEmpty) return input;
  final codeSpans = RegExp(r'```[\s\S]*?```|`[^`\n]*`');
  final buffer = StringBuffer();
  var last = 0;
  for (final m in codeSpans.allMatches(input)) {
    if (m.start > last) {
      buffer.write(_normalizeEmphasis(input.substring(last, m.start)));
    }
    buffer.write(m.group(0));
    last = m.end;
  }
  if (last < input.length) {
    buffer.write(_normalizeEmphasis(input.substring(last)));
  }
  return buffer.toString();
}

const _ws = ' \t\u00a0\u200c\u200b\u2009\u202f';
final _boldSpaced = RegExp('\\*\\*[$_ws]*(\\S(?:.*?\\S)?)[$_ws]*\\*\\*');
final _boldUnderscoreSpaced = RegExp('__[$_ws]*(\\S(?:.*?\\S)?)[$_ws]*__');

String _normalizeEmphasis(String s) {
  var out = s.replaceAllMapped(_boldSpaced, (m) => '**${m[1]}**');
  out = out.replaceAllMapped(_boldUnderscoreSpaced, (m) => '__${m[1]}__');
  return out;
}
