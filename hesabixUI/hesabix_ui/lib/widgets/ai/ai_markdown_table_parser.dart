import 'ai_visualization_spec.dart';

/// استخراج جدول از سطرهای مارک‌داون pipe (GFM).
class AIMarkdownTableParser {
  static final _separatorCell = RegExp(r'^:?-{1,}:?$');

  /// آیا خط شبیه سطر جدول pipe است؟
  static bool isPipeTableRow(String line) {
    final t = line.trim();
    if (!t.startsWith('|')) return false;
    return _splitCells(t).length >= 2;
  }

  /// پارس چند خط متوالی جدول pipe به [AITableSpec].
  static AITableSpec? tryParseLines(List<String> lines) {
    if (lines.length < 2) return null;

    final rows = <List<String>>[];
    for (final line in lines) {
      if (!isPipeTableRow(line)) return null;
      rows.add(_splitCells(line.trim()));
    }

    if (rows.isEmpty) return null;

    var dataStart = 1;
    if (rows.length >= 2 && _isSeparatorRow(rows[1])) {
      dataStart = 2;
    } else if (rows.length < 2) {
      return null;
    }

    final headerCells = rows[0];
    if (headerCells.isEmpty) return null;

    final columns = headerCells
        .asMap()
        .entries
        .map((e) => AITableColumn.fromHeader(e.value, e.key))
        .toList();

    final dataRows = <Map<String, dynamic>>[];
    for (var i = dataStart; i < rows.length; i++) {
      if (_isSeparatorRow(rows[i])) continue;
      final cells = rows[i];
      final map = <String, dynamic>{};
      for (var c = 0; c < columns.length && c < cells.length; c++) {
        map[columns[c].key] = cells[c];
      }
      if (map.isNotEmpty) dataRows.add(map);
    }

    final spec = AITableSpec(columns: columns, rows: dataRows);
    return spec.hasData ? spec : null;
  }

  /// جدا کردن جدول‌های pipe از متن و برگرداندن قطعات متن/جدول.
  static List<AIMarkdownTableSegment> splitText(String text) {
    if (text.trim().isEmpty) return [];

    final lines = text.split('\n');
    final out = <AIMarkdownTableSegment>[];
    final buffer = StringBuffer();

    void flushText() {
      final chunk = buffer.toString();
      buffer.clear();
      if (chunk.trim().isNotEmpty) {
        out.add(AIMarkdownTableSegment.text(chunk));
      }
    }

    var i = 0;
    while (i < lines.length) {
      if (isPipeTableRow(lines[i])) {
        final tableLines = <String>[];
        while (i < lines.length && isPipeTableRow(lines[i])) {
          tableLines.add(lines[i]);
          i++;
        }
        final spec = tryParseLines(tableLines);
        if (spec != null) {
          flushText();
          out.add(AIMarkdownTableSegment.table(spec));
        } else {
          for (final line in tableLines) {
            if (buffer.isNotEmpty) buffer.writeln();
            buffer.write(line);
          }
        }
      } else {
        if (buffer.isNotEmpty) buffer.writeln();
        buffer.write(lines[i]);
        i++;
      }
    }

    flushText();
    if (out.isEmpty && text.trim().isNotEmpty) {
      out.add(AIMarkdownTableSegment.text(text));
    }
    return out;
  }

  static List<String> _splitCells(String row) {
    var s = row.trim();
    if (s.startsWith('|')) s = s.substring(1);
    if (s.endsWith('|')) s = s.substring(0, s.length - 1);
    return s.split('|').map((c) => c.trim()).where((c) => c.isNotEmpty).toList();
  }

  static bool _isSeparatorRow(List<String> cells) {
    if (cells.isEmpty) return false;
    return cells.every((c) {
      final t = c.replaceAll(' ', '');
      return t.isEmpty || _separatorCell.hasMatch(t);
    });
  }

  /// JSON شل، سپس جدول pipe در همان رشته.
  static AITableSpec? tryParseLoose(String raw) {
    final fromJson = AITableSpec.tryParseJsonLoose(raw);
    if (fromJson != null) return fromJson;
    if (!raw.contains('|')) return null;
    return tryParseLines(raw.split('\n'));
  }
}

class AIMarkdownTableSegment {
  final String? text;
  final AITableSpec? tableSpec;

  const AIMarkdownTableSegment._({this.text, this.tableSpec});

  factory AIMarkdownTableSegment.text(String value) =>
      AIMarkdownTableSegment._(text: value);

  factory AIMarkdownTableSegment.table(AITableSpec spec) =>
      AIMarkdownTableSegment._(tableSpec: spec);
}
