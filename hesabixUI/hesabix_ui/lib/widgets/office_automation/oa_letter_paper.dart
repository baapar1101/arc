import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:hesabix_ui/l10n/app_localizations.dart';

/// پیش‌نمایش کاغذی نامه با سربرگ، پس‌زمینه و حاشیه‌ها.
class OaLetterPaper extends StatelessWidget {
  final String subject;
  final String body;
  final String bodyFormat;
  final String sender;
  final String receiver;
  final String number;
  final String dateText;
  final String? footer;
  final ImageProvider? letterhead;
  final ImageProvider? background;
  final int marginTop;
  final int marginRight;
  final int marginBottom;
  final int marginLeft;
  final List<String> paraphs;
  final String? confidentiality;
  final String? urgency;

  const OaLetterPaper({
    super.key,
    required this.subject,
    required this.body,
    this.bodyFormat = 'markdown',
    this.sender = '',
    this.receiver = '',
    this.number = '',
    this.dateText = '',
    this.footer,
    this.letterhead,
    this.background,
    this.marginTop = 20,
    this.marginRight = 20,
    this.marginBottom = 20,
    this.marginLeft = 20,
    this.paraphs = const [],
    this.confidentiality,
    this.urgency,
  });

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final padTop = (marginTop.clamp(8, 60)).toDouble();
    final padRight = (marginRight.clamp(8, 60)).toDouble();
    final padBottom = (marginBottom.clamp(8, 60)).toDouble();
    final padLeft = (marginLeft.clamp(8, 60)).toDouble();
    return AspectRatio(
      aspectRatio: 210 / 297,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(8),
          boxShadow: [
            BoxShadow(
              color: theme.colorScheme.shadow.withValues(alpha: 0.18),
              blurRadius: 18,
              offset: const Offset(0, 8),
            ),
          ],
          image: background == null ? null : DecorationImage(image: background!, fit: BoxFit.cover, opacity: 0.18),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: Padding(
            padding: EdgeInsets.fromLTRB(padLeft, padTop, padRight, padBottom),
            child: DefaultTextStyle(
              style: theme.textTheme.bodyMedium!.copyWith(color: const Color(0xFF1B1B1B), height: 1.7),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (letterhead != null)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: Image(image: letterhead!, height: 64, fit: BoxFit.contain),
                    ),
                  Row(
                    children: [
                      if (number.isNotEmpty)
                        Expanded(child: Text('${t.oaRegistry}: $number', style: const TextStyle(fontSize: 11))),
                      if (dateText.isNotEmpty) Text(dateText, style: const TextStyle(fontSize: 11)),
                    ],
                  ),
                  if ((confidentiality != null && confidentiality != 'normal') || (urgency != null && urgency != 'normal'))
                    Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Wrap(
                        spacing: 8,
                        children: [
                          if (urgency != null && urgency != 'normal')
                            Text(urgency == 'immediate' ? t.oaUrgencyImmediate : t.oaUrgencyUrgent, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 11)),
                          if (confidentiality != null && confidentiality != 'normal')
                            Text(t.oaConfidentialRestricted, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 11)),
                        ],
                      ),
                    ),
                  const SizedBox(height: 10),
                  if (receiver.isNotEmpty) Text('${t.oaReceiver}: $receiver'),
                  if (sender.isNotEmpty) Text('${t.oaSender}: $sender'),
                  const SizedBox(height: 12),
                  Text(subject.isEmpty ? t.oaSubject : subject, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 10),
                  Expanded(
                    child: SingleChildScrollView(
                      child: bodyFormat == 'html'
                          ? OaHtmlPreview(html: body)
                          : MarkdownBody(data: body.isEmpty ? '' : body, selectable: true),
                    ),
                  ),
                  if (paraphs.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Text(t.oaParaph, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 12)),
                    for (final p in paraphs) Text(p, style: const TextStyle(fontSize: 11)),
                  ],
                  if ((footer ?? '').isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Text(footer!, textAlign: TextAlign.center, style: const TextStyle(fontSize: 10, color: Color(0xFF5F5F5F))),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class OaHtmlPreview extends StatelessWidget {
  final String html;
  const OaHtmlPreview({super.key, required this.html});

  @override
  Widget build(BuildContext context) {
    return Text.rich(_parseHtml(html, Theme.of(context).textTheme.bodyMedium!));
  }
}

TextSpan _parseHtml(String raw, TextStyle base) {
  final text = raw
      .replaceAll(RegExp(r'<br\s*/?>', caseSensitive: false), '\n')
      .replaceAll(RegExp(r'</p>', caseSensitive: false), '\n\n')
      .replaceAll(RegExp(r'</h[1-6]>', caseSensitive: false), '\n')
      .replaceAll(RegExp(r'</li>', caseSensitive: false), '\n')
      .replaceAll(RegExp(r'<li[^>]*>', caseSensitive: false), '• ');
  final spans = <InlineSpan>[];
  final tag = RegExp(r'<(/?)(strong|b|em|i|u|h1|h2|h3|blockquote|a)([^>]*)>', caseSensitive: false);
  var cursor = 0;
  var bold = 0;
  var italic = 0;
  var underline = 0;
  var heading = 0;
  TextStyle current() {
    var style = base;
    if (heading > 0) style = style.copyWith(fontSize: (base.fontSize ?? 14) + 4, fontWeight: FontWeight.w700);
    if (bold > 0) style = style.copyWith(fontWeight: FontWeight.w700);
    if (italic > 0) style = style.copyWith(fontStyle: FontStyle.italic);
    if (underline > 0) style = style.copyWith(decoration: TextDecoration.underline);
    return style;
  }

  for (final m in tag.allMatches(text)) {
    if (m.start > cursor) {
      spans.add(TextSpan(text: _strip(text.substring(cursor, m.start)), style: current()));
    }
    final close = m.group(1) == '/';
    final name = (m.group(2) ?? '').toLowerCase();
    final delta = close ? -1 : 1;
    if (name == 'strong' || name == 'b') bold += delta;
    if (name == 'em' || name == 'i') italic += delta;
    if (name == 'u') underline += delta;
    if (name.startsWith('h')) heading += delta;
    cursor = m.end;
  }
  if (cursor < text.length) {
    spans.add(TextSpan(text: _strip(text.substring(cursor)), style: current()));
  }
  if (spans.isEmpty) return TextSpan(text: _strip(raw), style: base);
  return TextSpan(children: spans, style: base);
}

String _strip(String value) => value.replaceAll(RegExp(r'<[^>]+>'), '');
