import 'package:flutter/material.dart';
import 'package:hesabix_ui/services/ai_service.dart';
import 'package:hesabix_ui/utils/error_extractor.dart';
import 'package:hesabix_ui/utils/snackbar_helper.dart' show SnackBarHelper;

/// برگهٔ ویرایش حافظهٔ دستیار (متن آزاد + فیلدهای ساخت‌یافته).
Future<void> showAIChatMemorySheet({
  required BuildContext context,
  required AIService aiService,
  required int? businessId,
}) async {
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (ctx) => _AIChatMemorySheet(
      aiService: aiService,
      businessId: businessId,
    ),
  );
}

class _AIChatMemorySheet extends StatefulWidget {
  final AIService aiService;
  final int? businessId;

  const _AIChatMemorySheet({
    required this.aiService,
    required this.businessId,
  });

  @override
  State<_AIChatMemorySheet> createState() => _AIChatMemorySheetState();
}

class _AIChatMemorySheetState extends State<_AIChatMemorySheet> {
  final _contentCtrl = TextEditingController();
  final _goalCtrl = TextEditingController();
  final _roleCtrl = TextEditingController();
  final _termCtrl = TextEditingController();
  final _termMeaningCtrl = TextEditingController();

  bool _loading = true;
  bool _saving = false;
  bool _clearing = false;
  int _maxChars = 4000;
  String? _updatedAt;
  bool _hasAutoSections = false;
  List<Map<String, dynamic>> _digestSections = [];
  bool _digestEmpty = true;

  String _currency = 'toman';
  String _reportStyle = 'summary';
  String _language = 'fa';

  @override
  void initState() {
    super.initState();
    _contentCtrl.addListener(() => setState(() {}));
    _load();
  }

  @override
  void dispose() {
    _contentCtrl.dispose();
    _goalCtrl.dispose();
    _roleCtrl.dispose();
    _termCtrl.dispose();
    _termMeaningCtrl.dispose();
    super.dispose();
  }

  int get _charCount => _contentCtrl.text.length;

  Map<String, dynamic> _buildStructuredPayload() {
    final goal = double.tryParse(_goalCtrl.text.replaceAll(',', '').trim());
    final terms = <Map<String, String>>[];
    final term = _termCtrl.text.trim();
    if (term.isNotEmpty) {
      terms.add({
        'term': term,
        'meaning': _termMeaningCtrl.text.trim(),
      });
    }
    return {
      if (goal != null && goal > 0) 'sales_goal_monthly': goal,
      'sales_goal_unit': _currency,
      'currency_display': _currency,
      'report_style': _reportStyle,
      'preferred_language': _language,
      if (_roleCtrl.text.trim().isNotEmpty) 'business_role': _roleCtrl.text.trim(),
      if (terms.isNotEmpty) 'internal_terms': terms,
    };
  }

  void _applyStructured(Map<String, dynamic>? structured) {
    if (structured == null) return;
    final goal = structured['sales_goal_monthly'];
    if (goal != null) {
      _goalCtrl.text = goal is num ? goal.toStringAsFixed(0) : '$goal';
    }
    _currency = structured['currency_display'] as String? ?? _currency;
    _reportStyle = structured['report_style'] as String? ?? _reportStyle;
    _language = structured['preferred_language'] as String? ?? _language;
    _roleCtrl.text = structured['business_role'] as String? ?? '';
    final terms = structured['internal_terms'];
    if (terms is List && terms.isNotEmpty) {
      final first = terms.first;
      if (first is Map) {
        _termCtrl.text = first['term'] as String? ?? '';
        _termMeaningCtrl.text = first['meaning'] as String? ?? '';
      }
    }
  }

  Future<void> _load() async {
    try {
      final data = await widget.aiService.getAIMemory(businessId: widget.businessId);
      if (!mounted) return;
      _contentCtrl.text = data['content'] as String? ?? '';
      _maxChars = data['max_chars'] as int? ?? 4000;
      _updatedAt = data['updated_at'] as String?;
      _hasAutoSections = data['has_auto_sections'] as bool? ?? false;
      _applyStructured(data['structured'] as Map<String, dynamic>?);

      final digest = await widget.aiService.getAIMemoryDigest(businessId: widget.businessId);
      if (!mounted) return;
      final sections = digest['sections'];
      if (sections is List) {
        _digestSections = sections
            .whereType<Map>()
            .map((e) => Map<String, dynamic>.from(e))
            .toList();
      }
      _digestEmpty = digest['is_empty'] as bool? ?? true;
    } catch (e) {
      if (mounted) {
        SnackBarHelper.show(
          context,
          message: 'خطا در بارگذاری حافظه: ${ErrorExtractor.forContext(e, context)}',
          isError: true,
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      await widget.aiService.updateAIMemory(
        content: _contentCtrl.text,
        businessId: widget.businessId,
        structured: _buildStructuredPayload(),
      );
      if (!mounted) return;
      Navigator.of(context).pop();
      SnackBarHelper.show(context, message: 'حافظه ذخیره شد');
    } catch (e) {
      if (!mounted) return;
      SnackBarHelper.show(
        context,
        message: 'خطا: ${ErrorExtractor.forContext(e, context)}',
        isError: true,
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _clear() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('پاک کردن حافظه'),
        content: const Text(
          'تمام یادداشت‌ها و تنظیمات ساخت‌یافته حذف می‌شوند. ادامه می‌دهید؟',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('انصراف')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('پاک کردن')),
        ],
      ),
    );
    if (ok != true || !mounted) return;

    setState(() => _clearing = true);
    try {
      await widget.aiService.deleteAIMemory(businessId: widget.businessId);
      if (!mounted) return;
      _contentCtrl.clear();
      _goalCtrl.clear();
      _roleCtrl.clear();
      _termCtrl.clear();
      _termMeaningCtrl.clear();
      setState(() {
        _updatedAt = null;
        _hasAutoSections = false;
        _digestSections = [];
        _digestEmpty = true;
      });
      SnackBarHelper.show(context, message: 'حافظه پاک شد');
    } catch (e) {
      if (!mounted) return;
      SnackBarHelper.show(
        context,
        message: 'خطا: ${ErrorExtractor.forContext(e, context)}',
        isError: true,
      );
    } finally {
      if (mounted) setState(() => _clearing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final bottom = MediaQuery.viewInsetsOf(context).bottom;
    final overLimit = _charCount > _maxChars;

    return Padding(
      padding: EdgeInsets.fromLTRB(20, 0, 20, 20 + bottom),
      child: ListView(
        children: [
              Text(
                'حافظه دستیار',
                style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 8),
              Text(
                'ترجیحات پایدار، اهداف و اصطلاحات — جدا از دانشنامه و تاریخچهٔ چت.',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              if (_updatedAt != null) ...[
                const SizedBox(height: 6),
                Text(
                  'آخرین به‌روزرسانی: ${_formatUpdatedAt(_updatedAt!)}',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.outline,
                  ),
                ),
              ],
              if (_hasAutoSections) ...[
                const SizedBox(height: 6),
                Text(
                  'بخش‌هایی از متن آزاد به‌صورت خودکار از مکالمه اضافه شده‌اند.',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.tertiary,
                  ),
                ),
              ],
              if (!_digestEmpty && _digestSections.isNotEmpty) ...[
                const SizedBox(height: 16),
                Text('خلاصهٔ فعلی', style: theme.textTheme.titleSmall),
                const SizedBox(height: 8),
                ..._digestSections.map(
                  (s) => Card(
                    margin: const EdgeInsets.only(bottom: 8),
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            s['title'] as String? ?? '',
                            style: theme.textTheme.labelLarge?.copyWith(
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            s['body'] as String? ?? '',
                            style: theme.textTheme.bodySmall,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
              const SizedBox(height: 16),
              if (_loading)
                const Padding(
                  padding: EdgeInsets.all(24),
                  child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
                )
              else ...[
                Text('تنظیمات ساخت‌یافته', style: theme.textTheme.titleSmall),
                const SizedBox(height: 12),
                TextField(
                  controller: _goalCtrl,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'هدف فروش ماهانه (عدد)',
                    hintText: 'مثال: 500000000',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  value: _currency,
                  decoration: const InputDecoration(
                    labelText: 'واحد نمایش مبالغ',
                    border: OutlineInputBorder(),
                  ),
                  items: const [
                    DropdownMenuItem(value: 'toman', child: Text('تومان')),
                    DropdownMenuItem(value: 'rial', child: Text('ریال')),
                  ],
                  onChanged: (v) => setState(() => _currency = v ?? 'toman'),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  value: _reportStyle,
                  decoration: const InputDecoration(
                    labelText: 'سبک گزارش',
                    border: OutlineInputBorder(),
                  ),
                  items: const [
                    DropdownMenuItem(value: 'summary', child: Text('خلاصه')),
                    DropdownMenuItem(value: 'table', child: Text('جدولی')),
                    DropdownMenuItem(value: 'detailed', child: Text('مفصل')),
                  ],
                  onChanged: (v) => setState(() => _reportStyle = v ?? 'summary'),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  value: _language,
                  decoration: const InputDecoration(
                    labelText: 'زبان پاسخ',
                    border: OutlineInputBorder(),
                  ),
                  items: const [
                    DropdownMenuItem(value: 'fa', child: Text('فارسی')),
                    DropdownMenuItem(value: 'en', child: Text('انگلیسی')),
                  ],
                  onChanged: (v) => setState(() => _language = v ?? 'fa'),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _roleCtrl,
                  decoration: const InputDecoration(
                    labelText: 'نقش شما (اختیاری)',
                    hintText: 'مثال: مدیر فروش',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _termCtrl,
                  decoration: const InputDecoration(
                    labelText: 'اصطلاح داخلی',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: _termMeaningCtrl,
                  decoration: const InputDecoration(
                    labelText: 'معنی اصطلاح',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 20),
                Text('یادداشت آزاد', style: theme.textTheme.titleSmall),
                const SizedBox(height: 8),
                TextField(
                  controller: _contentCtrl,
                  maxLines: 6,
                  minLines: 3,
                  decoration: InputDecoration(
                    hintText: 'هر نکتهٔ دیگری که دستیار باید بداند…',
                    border: const OutlineInputBorder(),
                    errorText: overLimit ? 'حداکثر $_maxChars کاراکتر' : null,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  '$_charCount / $_maxChars کاراکتر',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: overLimit ? theme.colorScheme.error : theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
              const SizedBox(height: 16),
              Row(
                children: [
                  TextButton(
                    onPressed: _loading || _saving || _clearing ? null : _clear,
                    child: _clearing
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Text('پاک کردن'),
                  ),
                  const Spacer(),
                  FilledButton(
                    onPressed: _loading || _saving || _clearing || overLimit ? null : _save,
                    child: _saving
                        ? const SizedBox(
                            width: 22,
                            height: 22,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                          )
                        : const Text('ذخیره'),
                  ),
                ],
              ),
        ],
      ),
    );
  }

  String _formatUpdatedAt(String iso) {
    try {
      final dt = DateTime.parse(iso).toLocal();
      return '${dt.year}/${dt.month.toString().padLeft(2, '0')}/${dt.day.toString().padLeft(2, '0')} '
          '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
    } catch (_) {
      return iso;
    }
  }
}
