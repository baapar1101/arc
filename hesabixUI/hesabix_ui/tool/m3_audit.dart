// ignore_for_file: avoid_print
//
// m3_audit.dart — ابزار سنجش انطباق کد با Material Design 3
//
// اجرا:
//   dart run tool/m3_audit.dart                 گزارش کامل
//   dart run tool/m3_audit.dart --top 15        ۱۵ فایل بدترین برای هر قانون
//   dart run tool/m3_audit.dart --rule raw_material_color   فهرست خط‌به‌خط یک قانون
//   dart run tool/m3_audit.dart --baseline      ذخیرهٔ وضعیت فعلی در tool/m3_baseline.json
//   dart run tool/m3_audit.dart --check         مقایسه با baseline؛ اگر بدتر شده exit 1
//   dart run tool/m3_audit.dart --md            خروجی Markdown
//
// هیچ وابستگی خارجی ندارد — فقط dart:io و dart:convert.

import 'dart:convert';
import 'dart:io';

// ---------------------------------------------------------------------------
// تعریف قوانین
// ---------------------------------------------------------------------------

enum Severity { blocker, major, minor }

class Rule {
  final String id;
  final String title;
  final String why;
  final String fix;
  final RegExp pattern;
  final Severity severity;

  /// مسیرهایی (زیررشته) که این قانون در آن‌ها اعمال نمی‌شود.
  final List<String> exempt;

  const Rule({
    required this.id,
    required this.title,
    required this.why,
    required this.fix,
    required this.pattern,
    required this.severity,
    this.exempt = const [],
  });
}

/// پوشهٔ تم تنها جایی است که اجازهٔ تعریف رنگ/شکل/تایپ خام را دارد.
const _themeOnly = ['/theme/'];

final List<Rule> kRules = [
  Rule(
    id: 'raw_material_color',
    title: 'استفادهٔ مستقیم از Colors.*',
    why: 'رنگ خارج از ColorScheme در دارک‌مود و با تعویض seed خراب می‌شود.',
    fix: 'Theme.of(context).colorScheme.* یا context.semanticColors.*',
    pattern: RegExp(r'\bColors\.[a-zA-Z]'),
    severity: Severity.blocker,
    exempt: _themeOnly,
  ),
  Rule(
    id: 'raw_hex_color',
    title: 'رنگ هگز سخت‌کدشده',
    why: 'توکن رنگ باید تنها یک منبع حقیقت داشته باشد.',
    fix: 'به tokens/color_schemes.dart منتقل شود.',
    pattern: RegExp(r'Color\(\s*0x[0-9a-fA-F]{6,8}'),
    severity: Severity.blocker,
    exempt: _themeOnly,
  ),
  Rule(
    id: 'deprecated_with_opacity',
    title: 'withOpacity منسوخ',
    why: 'در Flutter جدید منسوخ شده و دقت رنگ را کم می‌کند.',
    fix: '.withValues(alpha: ...)',
    pattern: RegExp(r'\.withOpacity\('),
    severity: Severity.major,
  ),
  Rule(
    id: 'raw_border_radius',
    title: 'شعاع گوشهٔ خام',
    why: 'M3 مقیاس مشخص دارد: 0/4/8/12/16/28/full',
    fix: 'context.shape.small / .medium / .large ...',
    pattern: RegExp(r'BorderRadius\.circular\('),
    severity: Severity.major,
    exempt: _themeOnly,
  ),
  Rule(
    id: 'raw_box_shadow',
    title: 'BoxShadow دستی',
    why: 'M3 ارتفاع را با لایه‌های surfaceContainer نشان می‌دهد نه سایهٔ دستی.',
    fix: 'Material(elevation: AppElevation.level2) یا surfaceContainerHigh',
    pattern: RegExp(r'\bBoxShadow\('),
    severity: Severity.major,
    exempt: _themeOnly,
  ),
  Rule(
    id: 'legacy_elevated_button',
    title: 'ElevatedButton',
    why: 'در M3 نقش اصلی با FilledButton است؛ ElevatedButton فقط روی سطوح شلوغ.',
    fix: 'FilledButton یا FilledButton.tonal',
    pattern: RegExp(r'\bElevatedButton\b(?!Theme)'),
    severity: Severity.minor,
    exempt: _themeOnly,
  ),
  Rule(
    id: 'non_directional_padding',
    title: 'EdgeInsets با left/right',
    why: 'در چیدمان راست‌به‌چپ برعکس می‌شود.',
    fix: 'EdgeInsetsDirectional با start/end',
    pattern: RegExp(r'EdgeInsets\.only\([^)]*\b(left|right)\s*:'),
    severity: Severity.blocker,
  ),
  Rule(
    id: 'non_directional_alignment',
    title: 'Alignment جهت‌دار ثابت',
    why: 'centerLeft در فارسی باید centerStart باشد.',
    fix: 'AlignmentDirectional.centerStart / .centerEnd',
    pattern: RegExp(
        r'\bAlignment\.(centerLeft|centerRight|topLeft|topRight|bottomLeft|bottomRight)\b'),
    severity: Severity.blocker,
  ),
  Rule(
    id: 'raw_media_query_width',
    title: 'بررسی خام عرض صفحه',
    why: 'M3 پنج window size class دارد؛ عدد پراکنده باعث ناسازگاری breakpoint می‌شود.',
    fix: 'context.windowSize (Compact/Medium/Expanded/Large/ExtraLarge)',
    pattern: RegExp(r'MediaQuery\.(of\(\s*\w+\s*\)|sizeOf\(\s*\w+\s*\))\.(size\.)?width'),
    severity: Severity.major,
    exempt: _themeOnly,
  ),
  Rule(
    id: 'inline_font_size',
    title: 'fontSize دستی',
    why: 'مقیاس تایپ M3 پانزده نقش دارد؛ عدد دستی سلسله‌مراتب را می‌شکند.',
    fix: 'Theme.of(context).textTheme.bodyMedium و مشابه',
    pattern: RegExp(r'fontSize\s*:\s*\d'),
    severity: Severity.major,
    exempt: _themeOnly,
  ),
  Rule(
    id: 'inline_font_family',
    title: 'fontFamily دستی',
    why: 'انتخاب فونت باید وابسته به locale و متمرکز باشد.',
    fix: 'از textTheme استفاده کنید؛ فونت در tokens/typography.dart تعیین می‌شود.',
    pattern: RegExp(r'fontFamily\s*:'),
    severity: Severity.major,
    exempt: _themeOnly,
  ),
  Rule(
    id: 'raw_icon_size',
    title: 'اندازهٔ آیکون دستی',
    why: 'M3 اندازه‌های ۱۸/۲۰/۲۴/۴۰/۴۸ را استاندارد می‌کند.',
    fix: 'IconTheme یا AppIconSize',
    pattern: RegExp(r'\bIcon\([^)]*\bsize\s*:\s*\d'),
    severity: Severity.minor,
    exempt: _themeOnly,
  ),
];

// ---------------------------------------------------------------------------
// پویش
// ---------------------------------------------------------------------------

class Hit {
  final String file;
  final int line;
  final String text;
  Hit(this.file, this.line, this.text);
}

final _lineComment = RegExp(r'//.*$');
final _skipFile = RegExp(r'\.(g|freezed|gr|config|mocks)\.dart$');

bool _isExempt(String path, Rule rule) {
  final norm = path.replaceAll('\\', '/');
  return rule.exempt.any((e) => norm.contains(e.replaceAll('\\', '/')));
}

Map<String, List<Hit>> scan(Directory root) {
  final results = <String, List<Hit>>{for (final r in kRules) r.id: <Hit>[]};

  final files = root
      .listSync(recursive: true)
      .whereType<File>()
      .where((f) => f.path.endsWith('.dart'))
      .where((f) => !_skipFile.hasMatch(f.path))
      .where((f) => !f.path.replaceAll('\\', '/').contains('/l10n/'))
      .toList()
    ..sort((a, b) => a.path.compareTo(b.path));

  for (final file in files) {
    final rel = file.path.replaceAll('\\', '/');
    List<String> lines;
    try {
      lines = file.readAsLinesSync();
    } on FileSystemException {
      continue;
    }

    for (var i = 0; i < lines.length; i++) {
      final raw = lines[i];
      final trimmed = raw.trimLeft();
      if (trimmed.startsWith('//') || trimmed.startsWith('///')) continue;
      // حذف کامنت انتهای خط تا شمارش کاذب نشود
      if (raw.contains('m3-ignore')) continue;
      final code = raw.replaceAll(_lineComment, '');
      if (code.trim().isEmpty) continue;

      for (final rule in kRules) {
        if (_isExempt(rel, rule)) continue;
        for (final _ in rule.pattern.allMatches(code)) {
          results[rule.id]!.add(Hit(rel, i + 1, raw.trim()));
        }
      }
    }
  }
  return results;
}

// ---------------------------------------------------------------------------
// خروجی
// ---------------------------------------------------------------------------

String _bar(int value, int max, {int width = 24}) {
  if (max == 0) return '';
  final filled = (value / max * width).round().clamp(0, width);
  return '${'█' * filled}${'·' * (width - filled)}';
}

String _sevLabel(Severity s) => switch (s) {
      Severity.blocker => 'BLOCKER',
      Severity.major => 'MAJOR  ',
      Severity.minor => 'MINOR  ',
    };

void printReport(Map<String, List<Hit>> results, {int top = 5}) {
  final max = results.values.fold<int>(0, (m, l) => l.length > m ? l.length : m);
  final total = results.values.fold<int>(0, (s, l) => s + l.length);

  print('');
  print('  گزارش انطباق Material 3');
  print('  ${'─' * 68}');

  for (final sev in Severity.values) {
    final rules = kRules.where((r) => r.severity == sev).toList()
      ..sort((a, b) => results[b.id]!.length.compareTo(results[a.id]!.length));
    if (rules.isEmpty) continue;
    print('');
    for (final rule in rules) {
      final hits = results[rule.id]!;
      final mark = hits.isEmpty ? '✓' : '✗';
      print('  $mark ${_sevLabel(rule.severity)}  ${rule.id.padRight(28)} '
          '${hits.length.toString().padLeft(5)}  ${_bar(hits.length, max)}');
      if (hits.isEmpty) continue;
      print('      ${rule.title} → ${rule.fix}');

      final byFile = <String, int>{};
      for (final h in hits) {
        byFile[h.file] = (byFile[h.file] ?? 0) + 1;
      }
      final worst = byFile.entries.toList()
        ..sort((a, b) => b.value.compareTo(a.value));
      for (final e in worst.take(top)) {
        print('        ${e.value.toString().padLeft(4)}  ${e.key}');
      }
      if (worst.length > top) {
        print('        ...  و ${worst.length - top} فایل دیگر');
      }
    }
  }

  print('');
  print('  ${'─' * 68}');
  print('  مجموع تخلفات: $total');
  print('');
}

void printMarkdown(Map<String, List<Hit>> results) {
  print('| قانون | شدت | تعداد | راه‌حل |');
  print('|---|---|---:|---|');
  final sorted = [...kRules]
    ..sort((a, b) => results[b.id]!.length.compareTo(results[a.id]!.length));
  for (final r in sorted) {
    print('| `${r.id}` | ${_sevLabel(r.severity).trim()} | '
        '${results[r.id]!.length} | ${r.fix} |');
  }
}

void printRule(Map<String, List<Hit>> results, String id) {
  final hits = results[id];
  if (hits == null) {
    stderr.writeln('قانون ناشناخته: $id');
    stderr.writeln('قوانین موجود: ${kRules.map((r) => r.id).join(', ')}');
    exit(2);
  }
  final rule = kRules.firstWhere((r) => r.id == id);
  print('${rule.title} — ${hits.length} مورد');
  print('چرا: ${rule.why}');
  print('راه‌حل: ${rule.fix}');
  print('');
  for (final h in hits) {
    print('${h.file}:${h.line}');
    print('    ${h.text}');
  }
}

// ---------------------------------------------------------------------------
// baseline
// ---------------------------------------------------------------------------

const _baselinePath = 'tool/m3_baseline.json';

void writeBaseline(Map<String, List<Hit>> results) {
  final data = <String, int>{
    for (final e in results.entries) e.key: e.value.length,
  };
  File(_baselinePath)
    ..createSync(recursive: true)
    ..writeAsStringSync('${const JsonEncoder.withIndent('  ').convert(data)}\n');
  print('baseline نوشته شد → $_baselinePath');
  print(data.entries.map((e) => '  ${e.key}: ${e.value}').join('\n'));
}

int checkAgainstBaseline(Map<String, List<Hit>> results) {
  final file = File(_baselinePath);
  if (!file.existsSync()) {
    stderr.writeln('baseline پیدا نشد. اول اجرا کنید: dart run tool/m3_audit.dart --baseline');
    return 2;
  }
  final base = (jsonDecode(file.readAsStringSync()) as Map).cast<String, dynamic>();

  var failed = false;
  var improved = 0;
  print('');
  for (final rule in kRules) {
    final now = results[rule.id]!.length;
    final was = (base[rule.id] as num?)?.toInt() ?? 0;
    final delta = now - was;
    if (delta > 0) {
      failed = true;
      print('  ✗ ${rule.id.padRight(28)} $was → $now  (+$delta)');
    } else if (delta < 0) {
      improved -= delta;
      print('  ✓ ${rule.id.padRight(28)} $was → $now  ($delta)');
    }
  }
  print('');
  if (failed) {
    print('  رد شد — تخلف جدید اضافه شده است.');
    print('  اگر عمدی است: dart run tool/m3_audit.dart --baseline');
    return 1;
  }
  print(improved > 0
      ? '  قبول — $improved تخلف کمتر از baseline. baseline را به‌روز کنید.'
      : '  قبول — بدون رگرسیون.');
  return 0;
}

// ---------------------------------------------------------------------------

void main(List<String> args) {
  final libDir = Directory('lib');
  if (!libDir.existsSync()) {
    stderr.writeln('پوشهٔ lib/ پیدا نشد. از ریشهٔ پکیج Flutter اجرا کنید.');
    exit(2);
  }

  final results = scan(libDir);

  if (args.contains('--baseline')) {
    writeBaseline(results);
    return;
  }
  if (args.contains('--check')) {
    exit(checkAgainstBaseline(results));
  }
  if (args.contains('--md')) {
    printMarkdown(results);
    return;
  }
  final ruleIdx = args.indexOf('--rule');
  if (ruleIdx != -1 && ruleIdx + 1 < args.length) {
    printRule(results, args[ruleIdx + 1]);
    return;
  }
  var top = 5;
  final topIdx = args.indexOf('--top');
  if (topIdx != -1 && topIdx + 1 < args.length) {
    top = int.tryParse(args[topIdx + 1]) ?? 5;
  }
  printReport(results, top: top);
}
