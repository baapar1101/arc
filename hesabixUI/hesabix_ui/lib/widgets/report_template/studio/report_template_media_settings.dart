import 'package:flutter/material.dart';

import '../../../utils/number_normalizer.dart';

const Map<String, Size> reportTemplateSheetPresetsMm = {
  'A3': Size(297, 420),
  'A4': Size(210, 297),
  'A5': Size(148, 210),
  'A6': Size(105, 148),
  'Letter': Size(215.9, 279.4),
  'Legal': Size(215.9, 355.6),
};

Map<String, dynamic> defaultReportTemplateMedia({bool roll = false}) {
  if (roll) {
    return <String, dynamic>{
      'type': 'roll',
      'preset': '80mm',
      'width_mm': 80,
      'height_mode': 'auto',
      'orientation': 'portrait',
      'margins_mm': <String, dynamic>{
        'top': 3,
        'right': 2,
        'bottom': 4,
        'left': 2,
      },
    };
  }
  return <String, dynamic>{
    'type': 'sheet',
    'preset': 'A4',
    'width_mm': 210,
    'height_mm': 297,
    'orientation': 'portrait',
    'margins_mm': <String, dynamic>{
      'top': 10,
      'right': 10,
      'bottom': 10,
      'left': 10,
    },
  };
}

double? _number(dynamic value) {
  if (value is num) return value.toDouble();
  return double.tryParse((value ?? '').toString().trim());
}

String _compactNumber(double value) {
  return value == value.roundToDouble()
      ? value.toInt().toString()
      : value.toStringAsFixed(1).replaceFirst(RegExp(r'\.0$'), '');
}

Map<String, dynamic> reportTemplateMediaFromLegacy({
  String? paperSize,
  String? orientation,
  Map<String, dynamic>? margins,
  bool preferRoll = false,
}) {
  final token = (paperSize ?? '').trim();
  MapEntry<String, Size>? preset;
  for (final entry in reportTemplateSheetPresetsMm.entries) {
    if (entry.key.toLowerCase() == token.toLowerCase()) {
      preset = entry;
      break;
    }
  }
  Map<String, dynamic> media;
  if (preset != null) {
    media = defaultReportTemplateMedia()
      ..['preset'] = preset.key
      ..['width_mm'] = preset.value.width
      ..['height_mm'] = preset.value.height;
  } else {
    final parts = RegExp(
      r'([0-9]+(?:\.[0-9]+)?)\s*mm',
      caseSensitive: false,
    ).allMatches(token).toList();
    if (parts.length >= 2) {
      media = defaultReportTemplateMedia()
        ..['preset'] = 'custom'
        ..['width_mm'] = double.parse(parts[0].group(1)!)
        ..['height_mm'] = double.parse(parts[1].group(1)!);
    } else if (parts.length == 1 || preferRoll) {
      final width = parts.isEmpty ? 80.0 : double.parse(parts.first.group(1)!);
      media = defaultReportTemplateMedia(roll: true)
        ..['preset'] = '${_compactNumber(width)}mm'
        ..['width_mm'] = width;
    } else {
      media = defaultReportTemplateMedia();
    }
  }
  media['orientation'] = orientation == 'landscape' ? 'landscape' : 'portrait';
  if (margins != null && margins.isNotEmpty) {
    media['margins_mm'] = <String, dynamic>{
      for (final side in const ['top', 'right', 'bottom', 'left'])
        side:
            _number(margins[side]) ??
            ((media['margins_mm'] as Map)[side] as num).toDouble(),
    };
  }
  return media;
}

Map<String, dynamic> normalizedReportTemplateMedia(
  Map<String, dynamic> design, {
  bool preferRoll = false,
}) {
  final raw = design['media'];
  if (raw is! Map) return defaultReportTemplateMedia(roll: preferRoll);
  final type = raw['type'] == 'roll' ? 'roll' : 'sheet';
  final fallback = defaultReportTemplateMedia(roll: type == 'roll');
  final media = <String, dynamic>{...fallback, ...raw.cast<String, dynamic>()};
  final fallbackMargins = (fallback['margins_mm'] as Map)
      .cast<String, dynamic>();
  final rawMargins = raw['margins_mm'];
  media['margins_mm'] = <String, dynamic>{
    ...fallbackMargins,
    if (rawMargins is Map) ...rawMargins.cast<String, dynamic>(),
  };
  return media;
}

String reportTemplatePaperSizeFromMedia(Map<String, dynamic> media) {
  if (media['type'] == 'roll') {
    return '${_compactNumber(_number(media['width_mm']) ?? 80)}mm';
  }
  final preset = (media['preset'] ?? '').toString();
  if (reportTemplateSheetPresetsMm.containsKey(preset)) return preset;
  final width = _number(media['width_mm']) ?? 210;
  final height = _number(media['height_mm']) ?? 297;
  return '${_compactNumber(width)}mm ${_compactNumber(height)}mm';
}

Size reportTemplateMediaSizeMm(Map<String, dynamic> media) {
  var width = _number(media['width_mm']) ?? 210;
  var height = media['type'] == 'roll'
      ? width * 3.4
      : (_number(media['height_mm']) ?? 297);
  if (media['type'] != 'roll' && media['orientation'] == 'landscape') {
    final swap = width;
    width = height;
    height = swap;
  }
  return Size(width, height);
}

class ReportTemplateMediaSettings extends StatelessWidget {
  final Map<String, dynamic> media;
  final ValueChanged<Map<String, dynamic>> onChanged;
  final bool compact;

  const ReportTemplateMediaSettings({
    super.key,
    required this.media,
    required this.onChanged,
    this.compact = false,
  });

  Map<String, dynamic> _copy() {
    final margins = (media['margins_mm'] as Map?)?.cast<String, dynamic>();
    return <String, dynamic>{
      ...media,
      'margins_mm': <String, dynamic>{...?margins},
    };
  }

  void _patch(String key, dynamic value) {
    onChanged(_copy()..[key] = value);
  }

  void _setPreset(String preset) {
    if (media['type'] == 'roll') {
      final width = double.tryParse(preset.replaceAll('mm', ''));
      final next = _copy()..['preset'] = preset;
      if (width != null) next['width_mm'] = width;
      onChanged(next);
      return;
    }
    final size = reportTemplateSheetPresetsMm[preset];
    final next = _copy()..['preset'] = preset;
    if (size != null) {
      next['width_mm'] = size.width;
      next['height_mm'] = size.height;
    }
    onChanged(next);
  }

  void _setDimension(String key, String raw) {
    final value = double.tryParse(raw.trim());
    if (value == null || value < 20 || value > 2000) return;
    final next = _copy()
      ..['preset'] = 'custom'
      ..[key] = value;
    onChanged(next);
  }

  void _setMargin(String side, String raw) {
    final value = double.tryParse(raw.trim());
    if (value == null || value < 0 || value > 100) return;
    final next = _copy();
    (next['margins_mm'] as Map<String, dynamic>)[side] = value;
    onChanged(next);
  }

  @override
  Widget build(BuildContext context) {
    final isRoll = media['type'] == 'roll';
    final preset = (media['preset'] ?? (isRoll ? '80mm' : 'A4')).toString();
    final sheetItems = <String>[...reportTemplateSheetPresetsMm.keys, 'custom'];
    const rollItems = ['58mm', '60mm', '80mm', '100mm', 'custom'];
    final items = isRoll ? rollItems : sheetItems;
    final selectedPreset = items.contains(preset) ? preset : 'custom';
    final margins =
        (media['margins_mm'] as Map?)?.cast<String, dynamic>() ?? const {};

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SegmentedButton<String>(
          segments: const [
            ButtonSegment(
              value: 'sheet',
              icon: Icon(Icons.description_outlined),
              label: Text('کاغذ صفحه‌ای'),
            ),
            ButtonSegment(
              value: 'roll',
              icon: Icon(Icons.receipt_long_outlined),
              label: Text('رول'),
            ),
          ],
          selected: {isRoll ? 'roll' : 'sheet'},
          onSelectionChanged: (selection) => onChanged(
            defaultReportTemplateMedia(roll: selection.first == 'roll'),
          ),
        ),
        const SizedBox(height: 12),
        DropdownButtonFormField<String>(
          key: ValueKey('media-preset-$isRoll-$selectedPreset'),
          initialValue: selectedPreset,
          decoration: const InputDecoration(
            labelText: 'اندازه کاغذ',
            border: OutlineInputBorder(),
            isDense: true,
          ),
          items: items
              .map(
                (value) => DropdownMenuItem(
                  value: value,
                  child: Text(value == 'custom' ? 'اندازه سفارشی' : value),
                ),
              )
              .toList(),
          onChanged: (value) {
            if (value != null) _setPreset(value);
          },
        ),
        if (selectedPreset == 'custom') ...[
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: _numberField(
                  keyName: 'media-width',
                  label: 'عرض (mm)',
                  value: media['width_mm'],
                  onSubmitted: (value) => _setDimension('width_mm', value),
                ),
              ),
              if (!isRoll) ...[
                const SizedBox(width: 8),
                Expanded(
                  child: _numberField(
                    keyName: 'media-height',
                    label: 'ارتفاع (mm)',
                    value: media['height_mm'],
                    onSubmitted: (value) => _setDimension('height_mm', value),
                  ),
                ),
              ],
            ],
          ),
        ],
        if (!isRoll) ...[
          const SizedBox(height: 12),
          SegmentedButton<String>(
            segments: const [
              ButtonSegment(value: 'portrait', label: Text('عمودی')),
              ButtonSegment(value: 'landscape', label: Text('افقی')),
            ],
            selected: {
              media['orientation'] == 'landscape' ? 'landscape' : 'portrait',
            },
            onSelectionChanged: (selection) =>
                _patch('orientation', selection.first),
          ),
        ],
        const SizedBox(height: 14),
        Text(
          'حاشیه چاپ (میلی‌متر)',
          style: Theme.of(context).textTheme.labelLarge,
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            for (final entry in const [
              ('top', 'بالا'),
              ('right', 'راست'),
              ('bottom', 'پایین'),
              ('left', 'چپ'),
            ]) ...[
              Expanded(
                child: _numberField(
                  keyName: 'media-margin-${entry.$1}',
                  label: entry.$2,
                  value: margins[entry.$1] ?? 0,
                  onSubmitted: (value) => _setMargin(entry.$1, value),
                ),
              ),
              if (entry.$1 != 'left') const SizedBox(width: 6),
            ],
          ],
        ),
        if (isRoll) ...[
          const SizedBox(height: 8),
          Text(
            'ارتفاع رول با محتوای فاکتور افزایش می‌یابد؛ PDFهای بسیار بلند در چند برش تولید می‌شوند.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ],
    );
  }

  Widget _numberField({
    required String keyName,
    required String label,
    required dynamic value,
    required ValueChanged<String> onSubmitted,
  }) {
    return _ReportTemplateNumberField(
      key: ValueKey(keyName),
      label: label,
      value: _compactNumber(_number(value) ?? 0),
      onCommitted: onSubmitted,
    );
  }
}

class _ReportTemplateNumberField extends StatefulWidget {
  final String label;
  final String value;
  final ValueChanged<String> onCommitted;

  const _ReportTemplateNumberField({
    super.key,
    required this.label,
    required this.value,
    required this.onCommitted,
  });

  @override
  State<_ReportTemplateNumberField> createState() =>
      _ReportTemplateNumberFieldState();
}

class _ReportTemplateNumberFieldState
    extends State<_ReportTemplateNumberField> {
  late final TextEditingController _controller;
  late final FocusNode _focusNode;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.value);
    _focusNode = FocusNode()..addListener(_handleFocus);
  }

  @override
  void didUpdateWidget(covariant _ReportTemplateNumberField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_focusNode.hasFocus && widget.value != _controller.text) {
      _controller.text = widget.value;
    }
  }

  void _handleFocus() {
    if (!_focusNode.hasFocus) widget.onCommitted(_controller.text);
  }

  @override
  void dispose() {
    _focusNode
      ..removeListener(_handleFocus)
      ..dispose();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: _controller,
      focusNode: _focusNode,
      decoration: InputDecoration(
        labelText: widget.label,
        border: const OutlineInputBorder(),
        isDense: true,
      ),
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      inputFormatters: const [EnglishDigitsFormatter()],
      onSubmitted: widget.onCommitted,
    );
  }
}
