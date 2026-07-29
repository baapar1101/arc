import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

class ReportTemplateStudioCustomizePanel extends StatelessWidget {
  final Map<String, dynamic> design;
  final String moduleKey;
  final String? subtype;
  final ValueChanged<Map<String, dynamic>> onDesignChanged;

  const ReportTemplateStudioCustomizePanel({
    super.key,
    required this.design,
    required this.moduleKey,
    required this.subtype,
    required this.onDesignChanged,
  });

  String get _layout => (design['layout'] ?? '').toString();

  Map<String, dynamic> _theme() => (design['theme'] as Map?)?.cast<String, dynamic>() ?? {};
  Map<String, dynamic> _sections() => (design['sections'] as Map?)?.cast<String, dynamic>() ?? {};
  Map<String, dynamic> _branding() => (design['branding'] as Map?)?.cast<String, dynamic>() ?? {};
  Map<String, dynamic> _table() => (design['table'] as Map?)?.cast<String, dynamic>() ?? {};
  Map<String, dynamic> _totals() => (design['totals'] as Map?)?.cast<String, dynamic>() ?? {};

  void _patch(void Function(Map<String, dynamic> d) mutate) {
    final copy = Map<String, dynamic>.from(design);
    mutate(copy);
    onDesignChanged(copy);
  }

  Future<void> _pickLogo(BuildContext context) async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.image,
      withData: true,
    );
    if (result == null || result.files.isEmpty) return;
    final file = result.files.first;
    final bytes = file.bytes;
    if (bytes == null) return;
    final mime = _mimeFromName(file.name);
    final b64 = base64Encode(bytes);
    final dataUri = 'data:$mime;base64,$b64';
    _patch((d) {
      d['branding'] = {
        ..._branding(),
        'show_logo': true,
        'logo_source': 'custom',
        'custom_logo_data_uri': dataUri,
      };
    });
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('لوگو بارگذاری شد')),
      );
    }
  }

  String _mimeFromName(String name) {
    final lower = name.toLowerCase();
    if (lower.endsWith('.png')) return 'image/png';
    if (lower.endsWith('.jpg') || lower.endsWith('.jpeg')) return 'image/jpeg';
    if (lower.endsWith('.gif')) return 'image/gif';
    if (lower.endsWith('.webp')) return 'image/webp';
    return 'image/png';
  }

  @override
  Widget build(BuildContext context) {
    final theme = _theme();
    final sections = _sections();
    final branding = _branding();
    final logoSource = (branding['logo_source'] ?? 'business').toString();

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text('سفارشی‌سازی', style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold)),
        const SizedBox(height: 4),
        Text(
          'تنظیمات را تغییر دهید؛ پیش‌نمایش PDF به‌صورت خودکار بروز می‌شود.',
          style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
        ),
        const SizedBox(height: 20),
        _sectionTitle(context, 'رنگ و ظاهر'),
        _colorPicker(
          context,
          label: 'رنگ اصلی',
          value: (theme['primary_color'] ?? '#1e3a5f').toString(),
          presets: const ['#1e3a5f', '#2563eb', '#0f766e', '#7c3aed', '#b45309', '#be123c'],
          onChanged: (v) => _patch((d) {
            d['theme'] = {..._theme(), 'primary_color': v};
          }),
        ),
        const SizedBox(height: 8),
        _colorPicker(
          context,
          label: 'رنگ تأکید',
          value: (theme['accent_color'] ?? '#366092').toString(),
          presets: const ['#366092', '#3b82f6', '#14b8a6', '#8b5cf6', '#f59e0b', '#e11d48'],
          onChanged: (v) => _patch((d) {
            d['theme'] = {..._theme(), 'accent_color': v};
          }),
        ),
        const SizedBox(height: 8),
        _sliderField(
          context,
          label: 'اندازه فونت پایه',
          value: ((theme['font_size_base'] as num?) ?? 11).toDouble(),
          min: 8,
          max: 14,
          divisions: 6,
          onChanged: (v) => _patch((d) {
            d['theme'] = {..._theme(), 'font_size_base': v.round()};
          }),
        ),
        const SizedBox(height: 20),
        _sectionTitle(context, 'برندینگ'),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('نمایش لوگو'),
          value: branding['show_logo'] != false,
          onChanged: (v) => _patch((d) {
            d['branding'] = {..._branding(), 'show_logo': v};
          }),
        ),
        if (branding['show_logo'] != false) ...[
          SegmentedButton<String>(
            segments: const [
              ButtonSegment(value: 'business', label: Text('لوگوی کسب‌وکار')),
              ButtonSegment(value: 'custom', label: Text('لوگوی سفارشی')),
              ButtonSegment(value: 'none', label: Text('بدون لوگو')),
            ],
            selected: {logoSource},
            onSelectionChanged: (s) => _patch((d) {
              d['branding'] = {..._branding(), 'logo_source': s.first};
            }),
          ),
          if (logoSource == 'custom') ...[
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: () => _pickLogo(context),
              icon: const Icon(Icons.upload_file, size: 18),
              label: Text(
                (branding['custom_logo_data_uri'] ?? '').toString().isNotEmpty
                    ? 'تغییر لوگو'
                    : 'بارگذاری لوگو',
              ),
            ),
          ],
        ],
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('نمایش نام کسب‌وکار'),
          value: branding['show_business_name'] != false,
          onChanged: (v) => _patch((d) {
            d['branding'] = {..._branding(), 'show_business_name': v};
          }),
        ),
        const SizedBox(height: 20),
        ..._layoutSections(context, sections),
      ],
    );
  }

  List<Widget> _layoutSections(BuildContext context, Map<String, dynamic> sections) {
    switch (_layout) {
      case 'invoice_detail':
        return [
          _sectionTitle(context, 'بخش‌های فاکتور'),
          _switchSection(sections, 'show_seller_info', 'اطلاعات فروشنده'),
          _switchSection(sections, 'show_buyer_info', 'اطلاعات خریدار'),
          _switchSection(sections, 'show_payments', 'لیست پرداخت‌ها'),
          _switchSection(sections, 'show_footer_note', 'یادداشت پاورقی'),
          _switchSection(sections, 'show_qr', 'QR تأیید فاکتور'),
          _switchSection(sections, 'show_signatures', 'ناحیه امضا'),
          if (sections['show_signatures'] != false) ...[
            _switchSection(sections, 'show_seller_signature', 'امضای فروشنده', indent: true),
            _switchSection(sections, 'show_buyer_signature', 'امضای خریدار', indent: true),
          ],
          _switchSection(sections, 'show_print_time', 'زمان چاپ'),
          _switchSection(sections, 'show_preparer', 'نام صادرکننده'),
          const SizedBox(height: 16),
          ..._tableSection(context),
          const SizedBox(height: 16),
          _sectionTitle(context, 'جمع‌بندی مالی'),
          ..._buildTotalsToggles(context),
        ];
      case 'generic_list':
        return [
          _sectionTitle(context, 'بخش‌های گزارش'),
          _switchSection(sections, 'show_title', 'عنوان گزارش'),
          _switchSection(sections, 'show_date', 'تاریخ گزارش'),
          const SizedBox(height: 16),
          ..._tableSection(context),
        ];
      case 'document_detail':
        return [
          _sectionTitle(context, 'بخش‌های سند'),
          _switchSection(sections, 'show_description', 'توضیحات'),
          _switchSection(sections, 'show_totals_row', 'ردیف جمع'),
          _switchSection(sections, 'show_print_time', 'زمان چاپ'),
          const SizedBox(height: 16),
          ..._tableSection(context),
        ];
      case 'receipt_detail':
        return [
          _sectionTitle(context, 'بخش‌های رسید'),
          _switchSection(sections, 'show_description', 'توضیحات'),
          _switchSection(sections, 'show_person_lines', 'اشخاص'),
          _switchSection(sections, 'show_account_lines', 'جدول حساب‌ها'),
          _switchSection(sections, 'show_total', 'جمع کل'),
          const SizedBox(height: 16),
          ..._tableSection(context),
        ];
      case 'transfer_detail':
        return [
          _sectionTitle(context, 'بخش‌های انتقال'),
          _switchSection(sections, 'show_source_dest', 'مبدأ و مقصد'),
          _switchSection(sections, 'show_description', 'توضیحات'),
          _switchSection(sections, 'show_account_lines', 'جدول حساب‌ها'),
          _switchSection(sections, 'show_commission', 'کارمزد'),
          _switchSection(sections, 'show_total', 'جمع کل'),
          const SizedBox(height: 16),
          ..._tableSection(context),
        ];
      case 'postal_label':
        return [
          _sectionTitle(context, 'بخش‌های برچسب'),
          _switchSection(sections, 'show_sender', 'فرستنده'),
          _switchSection(sections, 'show_receiver', 'گیرنده'),
          _switchSection(sections, 'show_warehouse', 'انبار'),
          _switchSection(sections, 'show_lines', 'خلاصه کالا'),
          _switchSection(sections, 'show_delivery', 'روش ارسال'),
          _switchSection(sections, 'show_tracking', 'شماره پیگیری'),
        ];
      default:
        return [
          _sectionTitle(context, 'ستون‌های جدول'),
          ..._buildColumnList(context),
        ];
    }
  }

  List<Widget> _tableSection(BuildContext context) {
    return [
      _sectionTitle(context, 'ستون‌های جدول'),
      if (_layout != 'postal_label')
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('خطوط راه‌راه (Zebra)'),
          value: _table()['striped'] != false,
          onChanged: (v) => _patch((d) {
            d['table'] = {..._table(), 'striped': v};
          }),
        ),
      ..._buildColumnList(context),
    ];
  }

  Widget _sectionTitle(BuildContext context, String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(text, style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
    );
  }

  Widget _colorPicker(
    BuildContext context, {
    required String label,
    required String value,
    required List<String> presets,
    required ValueChanged<String> onChanged,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: Theme.of(context).textTheme.bodyMedium),
        const SizedBox(height: 6),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: presets.map((hex) {
            final selected = hex.toLowerCase() == value.toLowerCase();
            Color c;
            try {
              c = Color(int.parse(hex.substring(1), radix: 16) + 0xFF000000);
            } catch (_) {
              c = Colors.grey;
            }
            return InkWell(
              onTap: () => onChanged(hex),
              borderRadius: BorderRadius.circular(8),
              child: Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: c,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: selected ? Theme.of(context).colorScheme.primary : Colors.transparent,
                    width: 2,
                  ),
                ),
                child: selected ? const Icon(Icons.check, color: Colors.white, size: 18) : null,
              ),
            );
          }).toList(),
        ),
      ],
    );
  }

  Widget _sliderField(
    BuildContext context, {
    required String label,
    required double value,
    required double min,
    required double max,
    required int divisions,
    required ValueChanged<double> onChanged,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('$label: ${value.round()}'),
        Slider(value: value, min: min, max: max, divisions: divisions, onChanged: onChanged),
      ],
    );
  }

  Widget _switchSection(Map<String, dynamic> sections, String key, String label, {bool indent = false}) {
    return SwitchListTile(
      contentPadding: EdgeInsets.only(left: indent ? 16 : 0),
      title: Text(label),
      value: sections[key] != false,
      onChanged: (v) => _patch((d) {
        d['sections'] = {..._sections(), key: v};
      }),
    );
  }

  List<Widget> _buildColumnList(BuildContext context) {
    final columns = List<Map<String, dynamic>>.from((_table()['columns'] as List?) ?? const []);
    if (columns.isEmpty) {
      return [const Text('ستونی تعریف نشده است.')];
    }
    return [
      Text(
        'برای تغییر ترتیب، آیکون کشیدن را بگیرید و بکشید.',
        style: Theme.of(context).textTheme.bodySmall,
      ),
      const SizedBox(height: 8),
      ReorderableListView.builder(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        itemCount: columns.length,
        onReorder: (oldIndex, newIndex) {
          if (newIndex > oldIndex) newIndex -= 1;
          _patch((d) {
            final table = Map<String, dynamic>.from(_table());
            final cols = List<Map<String, dynamic>>.from((table['columns'] as List?) ?? const []);
            final item = cols.removeAt(oldIndex);
            cols.insert(newIndex, item);
            table['columns'] = cols;
            d['table'] = table;
          });
        },
        itemBuilder: (context, index) {
          final col = columns[index];
          final title = (col['title'] ?? col['key'] ?? 'ستون').toString();
          return Card(
            key: ValueKey('col_${col['key']}_$index'),
            margin: const EdgeInsets.only(bottom: 6),
            child: SwitchListTile(
              secondary: const Icon(Icons.drag_handle),
              title: Text(title),
              subtitle: Text((col['key'] ?? '').toString()),
              value: col['visible'] != false,
              onChanged: (v) => _patch((d) {
                final table = Map<String, dynamic>.from(_table());
                final cols = List<Map<String, dynamic>>.from((table['columns'] as List?) ?? const []);
                cols[index] = {...col, 'visible': v};
                table['columns'] = cols;
                d['table'] = table;
              }),
            ),
          );
        },
      ),
    ];
  }

  List<Widget> _buildTotalsToggles(BuildContext context) {
    final rows = List<Map<String, dynamic>>.from((_totals()['rows'] as List?) ?? const []);
    if (rows.isEmpty) {
      return [const Text('ردیف جمع‌بندی تعریف نشده است.')];
    }
    return rows.asMap().entries.map((entry) {
      final row = entry.value;
      final title = (row['title'] ?? row['key'] ?? 'ردیف').toString();
      return SwitchListTile(
        contentPadding: EdgeInsets.zero,
        title: Text(title),
        value: row['visible'] != false,
        onChanged: (v) => _patch((d) {
          final totals = Map<String, dynamic>.from(_totals());
          final list = List<Map<String, dynamic>>.from((totals['rows'] as List?) ?? const []);
          list[entry.key] = {...row, 'visible': v};
          totals['rows'] = list;
          d['totals'] = totals;
        }),
      );
    }).toList();
  }
}
