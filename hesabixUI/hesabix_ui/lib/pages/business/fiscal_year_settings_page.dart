import 'package:flutter/material.dart';
import 'package:hesabix_ui/services/business_dashboard_service.dart';
import 'package:hesabix_ui/core/api_client.dart';
import 'package:hesabix_ui/l10n/app_localizations.dart';
import '../../utils/snackbar_helper.dart';
import 'package:intl/intl.dart';

class FiscalYearSettingsPage extends StatefulWidget {
  final int businessId;

  const FiscalYearSettingsPage({super.key, required this.businessId});

  @override
  State<FiscalYearSettingsPage> createState() => _FiscalYearSettingsPageState();
}

class _FiscalYearSettingsPageState extends State<FiscalYearSettingsPage> {
  bool _loading = true;
  bool _saving = false;
  String? _error;

  Map<String, dynamic>? _currentFiscalYear;

  final _formKey = GlobalKey<FormState>();
  final _titleController = TextEditingController();
  DateTime? _startDate;
  DateTime? _endDate;

  late final BusinessDashboardService _dashboardService;

  @override
  void initState() {
    super.initState();
    _dashboardService = BusinessDashboardService(ApiClient());
    _loadData();
  }

  @override
  void dispose() {
    _titleController.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final fiscalYears = await _dashboardService.listFiscalYears(widget.businessId);
      final current = fiscalYears.firstWhere(
        (fy) => fy['is_current'] == true,
        orElse: () => <String, dynamic>{},
      );

      if (mounted) {
        if (current.isEmpty) {
          setState(() {
            _error = 'سال مالی جاری یافت نشد';
            _loading = false;
          });
          return;
        }

        _currentFiscalYear = current;
        _titleController.text = current['title'] as String? ?? '';
        
        // پارس کردن تاریخ شروع
        final startDateStr = current['start_date'];
        if (startDateStr != null) {
          _startDate = _parseDate(startDateStr);
        }
        
        // پارس کردن تاریخ پایان
        final endDateStr = current['end_date'];
        if (endDateStr != null) {
          _endDate = _parseDate(endDateStr);
        }

        setState(() {
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _loading = false;
        });
      }
    }
  }

  DateTime? _parseDate(dynamic date) {
    if (date == null) return null;
    try {
      if (date is String) {
        return DateTime.parse(date);
      } else if (date is Map) {
        final year = date['year'] as int?;
        final month = date['month'] as int?;
        final day = date['day'] as int?;
        if (year != null && month != null && day != null) {
          return DateTime(year, month, day);
        }
      }
      return null;
    } catch (e) {
      return null;
    }
  }

  String _formatDate(DateTime? date) {
    if (date == null) return '';
    return DateFormat('yyyy/MM/dd', 'fa').format(date);
  }

  Future<void> _selectStartDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _startDate ?? DateTime.now(),
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
      locale: const Locale('fa', 'IR'),
    );
    if (picked != null) {
      setState(() {
        _startDate = picked;
        // اگر تاریخ پایان قبل از تاریخ شروع جدید باشد، آن را تنظیم کن
        if (_endDate != null && _endDate!.isBefore(picked)) {
          _endDate = DateTime(picked.year + 1, picked.month, picked.day);
        }
      });
    }
  }

  Future<void> _selectEndDate() async {
    if (_startDate == null) {
      SnackBarHelper.show(context, message: 'لطفاً ابتدا تاریخ شروع را انتخاب کنید', isError: true);
      return;
    }

    final picked = await showDatePicker(
      context: context,
      initialDate: _endDate ?? _startDate!.add(const Duration(days: 365)),
      firstDate: _startDate!.add(const Duration(days: 1)),
      lastDate: DateTime(2100),
      locale: const Locale('fa', 'IR'),
    );
    if (picked != null) {
      setState(() {
        _endDate = picked;
      });
    }
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    if (_startDate == null || _endDate == null) {
      SnackBarHelper.show(context, message: 'لطفاً تاریخ شروع و پایان را انتخاب کنید', isError: true);
      return;
    }

    if (_startDate!.isAfter(_endDate!) || _startDate!.isAtSameMomentAs(_endDate!)) {
      SnackBarHelper.show(context, message: 'تاریخ شروع باید قبل از تاریخ پایان باشد', isError: true);
      return;
    }

    setState(() {
      _saving = true;
      _error = null;
    });

    try {
      await _dashboardService.updateCurrentFiscalYear(
        widget.businessId,
        title: _titleController.text.trim(),
        startDate: _startDate!,
        endDate: _endDate!,
      );

      if (mounted) {
        SnackBarHelper.show(context, message: 'سال مالی جاری با موفقیت به‌روزرسانی شد', isError: false);
        await _loadData();
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
        });
        SnackBarHelper.show(context, message: 'خطا در به‌روزرسانی سال مالی جاری: $e', isError: true);
      }
    } finally {
      if (mounted) {
        setState(() {
          _saving = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('ویرایش سال مالی جاری'),
        backgroundColor: cs.surface,
        foregroundColor: cs.onSurface,
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null && _currentFiscalYear == null
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.error_outline, size: 64, color: cs.error),
                      const SizedBox(height: 16),
                      Text(
                        'خطا در بارگذاری داده‌ها',
                        style: TextStyle(color: cs.error, fontSize: 18),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        _error!,
                        style: TextStyle(color: cs.onSurfaceVariant),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 16),
                      FilledButton.icon(
                        onPressed: _loadData,
                        icon: const Icon(Icons.refresh),
                        label: const Text('تلاش مجدد'),
                      ),
                    ],
                  ),
                )
              : SingleChildScrollView(
                  padding: const EdgeInsets.all(16),
                  child: Form(
                    key: _formKey,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Card(
                          color: cs.primaryContainer,
                          child: Padding(
                            padding: const EdgeInsets.all(16),
                            child: Row(
                              children: [
                                Icon(Icons.info_outline, color: cs.onPrimaryContainer),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Text(
                                    'شما می‌توانید عنوان و تاریخ‌های سال مالی جاری را ویرایش کنید. توجه داشته باشید که تغییر این اطلاعات ممکن است بر روی گزارش‌ها تأثیر بگذارد.',
                                    style: TextStyle(color: cs.onPrimaryContainer),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: 24),
                        Text(
                          'اطلاعات سال مالی جاری',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w600,
                            color: cs.onSurface,
                          ),
                        ),
                        const SizedBox(height: 16),
                        TextFormField(
                          controller: _titleController,
                          decoration: InputDecoration(
                            labelText: 'عنوان سال مالی',
                            hintText: 'مثال: سال مالی 1403',
                            prefixIcon: const Icon(Icons.title),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          validator: (value) {
                            if (value == null || value.trim().isEmpty) {
                              return 'لطفاً عنوان سال مالی را وارد کنید';
                            }
                            return null;
                          },
                        ),
                        const SizedBox(height: 16),
                        InkWell(
                          onTap: _selectStartDate,
                          child: InputDecorator(
                            decoration: InputDecoration(
                              labelText: 'تاریخ شروع',
                              prefixIcon: const Icon(Icons.calendar_today),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                            child: Text(
                              _startDate != null
                                  ? _formatDate(_startDate)
                                  : 'انتخاب تاریخ شروع',
                              style: TextStyle(
                                color: _startDate != null
                                    ? cs.onSurface
                                    : cs.onSurfaceVariant,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 16),
                        InkWell(
                          onTap: _selectEndDate,
                          child: InputDecorator(
                            decoration: InputDecoration(
                              labelText: 'تاریخ پایان',
                              prefixIcon: const Icon(Icons.event),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                            child: Text(
                              _endDate != null
                                  ? _formatDate(_endDate)
                                  : 'انتخاب تاریخ پایان',
                              style: TextStyle(
                                color: _endDate != null
                                    ? cs.onSurface
                                    : cs.onSurfaceVariant,
                              ),
                            ),
                          ),
                        ),
                        if (_error != null) ...[
                          const SizedBox(height: 16),
                          Card(
                            color: cs.errorContainer,
                            child: Padding(
                              padding: const EdgeInsets.all(12),
                              child: Row(
                                children: [
                                  Icon(Icons.error_outline, color: cs.onErrorContainer),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Text(
                                      _error!,
                                      style: TextStyle(color: cs.onErrorContainer),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                        const SizedBox(height: 24),
                        SizedBox(
                          width: double.infinity,
                          child: FilledButton.icon(
                            onPressed: _saving ? null : _save,
                            icon: _saving
                                ? const SizedBox(
                                    width: 20,
                                    height: 20,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: Colors.white,
                                    ),
                                  )
                                : const Icon(Icons.save),
                            label: Text(_saving ? 'در حال ذخیره...' : 'ذخیره تغییرات'),
                            style: FilledButton.styleFrom(
                              padding: const EdgeInsets.symmetric(vertical: 16),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
    );
  }
}
