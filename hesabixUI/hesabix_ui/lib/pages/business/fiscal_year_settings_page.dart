import 'package:flutter/material.dart';
import 'package:hesabix_ui/services/business_dashboard_service.dart';
import 'package:hesabix_ui/core/api_client.dart';
import '../../utils/error_extractor.dart';
import '../../utils/snackbar_helper.dart';
import '../../widgets/business_subpage_back_leading.dart';
import '../../core/calendar_controller.dart';
import '../../widgets/date_input_field.dart';
import '../../core/date_utils.dart';
import 'package:shamsi_date/shamsi_date.dart';

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
  /// برای محدودهٔ عریض تقویم و کنترل همپوشانی قبل از ذخیره
  List<Map<String, dynamic>> _fiscalYearsForBounds = const [];

  final _formKey = GlobalKey<FormState>();
  final _titleController = TextEditingController();
  DateTime? _startDate;
  DateTime? _endDate;

  late final BusinessDashboardService _dashboardService;
  CalendarController? _calendarController;

  @override
  void initState() {
    super.initState();
    _dashboardService = BusinessDashboardService(ApiClient());
    _loadCalendarController();
    _loadData();
  }

  Future<void> _loadCalendarController() async {
    final controller = await CalendarController.load();
    if (mounted) {
      setState(() {
        _calendarController = controller;
      });
      // اضافه کردن listener برای تغییرات تقویم
      _calendarController!.addListener(_onCalendarChanged);
    }
  }

  void _onCalendarChanged() {
    if (mounted && _endDate != null) {
      // اگر عنوان به صورت خودکار تولید شده، آن را به‌روزرسانی کن
      const autoPrefix = 'سال مالی منتهی به';
      final currentTitle = _titleController.text.trim();
      if (currentTitle.isEmpty || currentTitle.startsWith(autoPrefix)) {
        setState(() {
          _titleController.text = _autoTitle();
        });
      }
    }
  }

  String _autoTitle() {
    if (_endDate == null || _calendarController == null) return '';
    final isJalali = _calendarController!.isJalali;
    final endStr = HesabixDateUtils.formatForDisplay(_endDate, isJalali);
    return 'سال مالی منتهی به $endStr';
  }

  @override
  void dispose() {
    _titleController.dispose();
    _calendarController?.removeListener(_onCalendarChanged);
    super.dispose();
  }

  Future<void> _loadData() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      List<Map<String, dynamic>> years = const [];
      try {
        years = await _dashboardService.listFiscalYears(widget.businessId);
      } catch (_) {
        years = const [];
      }

      final current = await _dashboardService.getCurrentFiscalYear(widget.businessId);

      if (mounted) {
        if (current == null || current.isEmpty) {
          setState(() {
            _currentFiscalYear = null;
            _fiscalYearsForBounds = years;
            _titleController.text = '';
            _startDate = null;
            _endDate = null;
            _loading = false;
          });
          return;
        }

        // پارس کردن تاریخ‌ها
        // اولویت: start_date_raw (ISO format میلادی) > start_date_formatted (Map) > start_date (string شمسی)
        // start_date_raw همیشه ISO format میلادی است و می‌تواند مستقیماً با DateTime.tryParse پارس شود
        final startDateRaw = current['start_date_raw'];
        final startDateFormatted = current['start_date_formatted'];
        final startDateStr = current['start_date'];
        
        final endDateRaw = current['end_date_raw'];
        final endDateFormatted = current['end_date_formatted'];
        final endDateStr = current['end_date'];
        
        // استفاده از start_date_raw که ISO format میلادی است (مثل صفحه ویرایش فاکتور)
        DateTime? parsedStartDate;
        if (startDateRaw != null) {
          parsedStartDate = DateTime.tryParse(startDateRaw.toString());
        } else if (startDateFormatted != null) {
          parsedStartDate = _parseDate(startDateFormatted);
        } else if (startDateStr != null) {
          parsedStartDate = _parseDate(startDateStr);
        }
        
        DateTime? parsedEndDate;
        if (endDateRaw != null) {
          parsedEndDate = DateTime.tryParse(endDateRaw.toString());
        } else if (endDateFormatted != null) {
          parsedEndDate = _parseDate(endDateFormatted);
        } else if (endDateStr != null) {
          parsedEndDate = _parseDate(endDateStr);
        }

        setState(() {
          _currentFiscalYear = current;
          _fiscalYearsForBounds = years;
          _titleController.text = current['title'] as String? ?? '';
          _startDate = parsedStartDate;
          _endDate = parsedEndDate;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = ErrorExtractor.forContext(e, context);
          _loading = false;
        });
      }
    }
  }

  DateTime? _parseDate(dynamic date) {
    if (date == null) return null;
    try {
      // اگر Map است (مثل start_date_formatted)، سال‌ها Jalali هستند
      if (date is Map) {
        final year = date['year'] as int?;
        final month = date['month'] as int?;
        final day = date['day'] as int?;
        if (year != null && month != null && day != null) {
          // اگر سال بزرگتر از 1500 است، Jalali است
          if (year > 1500) {
            final jalali = Jalali(year, month, day);
            final dt = jalali.toDateTime();
            // اطمینان از اینکه DateTime به صورت local است
            return DateTime(dt.year, dt.month, dt.day);
          } else {
            // سال میلادی است
            return DateTime(year, month, day);
          }
        }
        return null;
      }
      
      // اگر String است
      if (date is String) {
        // بررسی فرمت Jalali: YYYY/MM/DD (مثل "1404/08/30")
        if (date.contains('/') && !date.contains('-')) {
          final parts = date.split('/');
          if (parts.length == 3) {
            try {
              final year = int.parse(parts[0]);
              final month = int.parse(parts[1]);
              final day = int.parse(parts[2]);
              
              // اعتبارسنجی محدوده‌های معتبر
              if (month < 1 || month > 12 || day < 1 || day > 31) {
                // تاریخ نامعتبر - skip
                return null;
              }
              
              // اگر سال بزرگتر از 1500 است، Jalali است
              if (year > 1500) {
                // اعتبارسنجی محدوده سال شمسی (معمولاً 1300-1500)
                if (year < 1300 || year > 1500) {
                  return null;
                }
                // استفاده مستقیم از Jalali برای تبدیل
                final jalali = Jalali(year, month, day);
                final dt = jalali.toDateTime();
                // اطمینان از اینکه DateTime به صورت local است و فقط تاریخ دارد
                return DateTime(dt.year, dt.month, dt.day);
              } else {
                // سال میلادی است - اعتبارسنجی محدوده معتبر (1900-2100)
                if (year < 1900 || year > 2100) {
                  return null;
                }
                // اعتبارسنجی ماه و روز
                if (month < 1 || month > 12 || day < 1 || day > 31) {
                  return null;
                }
                try {
                  return DateTime(year, month, day);
                } catch (e) {
                  // اگر تاریخ نامعتبر بود (مثلاً 31 فوریه)
                  return null;
                }
              }
            } catch (e) {
              // اگر پارس ناموفق بود، ادامه بده
              return null;
            }
          }
        }
        
        // تلاش برای پارس کردن به عنوان ISO format (Gregorian)
        try {
          final parsed = DateTime.parse(date);
          // اگر فقط تاریخ است (بدون زمان)، فقط تاریخ را برگردان
          return DateTime(parsed.year, parsed.month, parsed.day);
        } catch (e) {
          return null;
        }
      }
      
      return null;
    } catch (e) {
      return null;
    }
  }

  DateTime? _tryParseIsoDateOnly(dynamic value) {
    if (value == null) return null;
    final parsed = DateTime.tryParse(value.toString());
    if (parsed == null) return null;
    return DateTime(parsed.year, parsed.month, parsed.day);
  }

  DateTime? _dateFromFiscalRow(Map<String, dynamic> row, String fieldPrefix) {
    final raw = row['${fieldPrefix}_raw'];
    final fromRaw = _tryParseIsoDateOnly(raw);
    if (fromRaw != null) return fromRaw;
    return _parseDate(row[fieldPrefix]);
  }

  bool _rangesOverlap(DateTime aStart, DateTime aEnd, DateTime bStart, DateTime bEnd) {
    return !aStart.isAfter(bEnd) && !aEnd.isBefore(bStart);
  }

  String? _overlapErrorFor(DateTime start, DateTime end) {
    final s = HesabixDateUtils.toDateOnlyLocal(start);
    final e = HesabixDateUtils.toDateOnlyLocal(end);
    final sid = _currentFiscalYear?['id'];
    final currentId = sid is int ? sid : int.tryParse('$sid');
    for (final row in _fiscalYearsForBounds) {
      final idVal = row['id'];
      final oid = idVal is int ? idVal : int.tryParse('$idVal');
      if (currentId != null && oid != null && oid == currentId) {
        continue;
      }
      final os = _dateFromFiscalRow(row, 'start_date');
      final oe = _dateFromFiscalRow(row, 'end_date');
      if (os == null || oe == null) continue;
      final os0 = HesabixDateUtils.toDateOnlyLocal(os);
      final oe0 = HesabixDateUtils.toDateOnlyLocal(oe);
      if (!_rangesOverlap(s, e, os0, oe0)) continue;
      final title = row['title']?.toString() ?? 'سال مالی دیگر';
      return 'بازهٔ انتخاب‌شده با سال مالی «$title» همپوشانی دارد.';
    }
    return null;
  }

  ({DateTime first, DateTime last}) _pickerBounds() {
    const marginDays = 365 * 8;
    final now = DateTime.now();
    final seeds = <DateTime>[
      DateTime(now.year - 30, 1, 1),
      DateTime(now.year + 30, 12, 31),
    ];
    for (final row in _fiscalYearsForBounds) {
      final s = _dateFromFiscalRow(row, 'start_date');
      final e = _dateFromFiscalRow(row, 'end_date');
      if (s != null) seeds.add(HesabixDateUtils.toDateOnlyLocal(s));
      if (e != null) seeds.add(HesabixDateUtils.toDateOnlyLocal(e));
    }
    if (_startDate != null) {
      seeds.add(HesabixDateUtils.toDateOnlyLocal(_startDate!));
    }
    if (_endDate != null) {
      seeds.add(HesabixDateUtils.toDateOnlyLocal(_endDate!));
    }
    var lo = seeds.reduce((a, b) => a.isBefore(b) ? a : b);
    var hi = seeds.reduce((a, b) => a.isAfter(b) ? a : b);
    lo = lo.subtract(const Duration(days: marginDays));
    hi = hi.add(const Duration(days: marginDays));
    return (first: lo, last: hi);
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

    final overlapMsg = _overlapErrorFor(_startDate!, _endDate!);
    if (overlapMsg != null) {
      SnackBarHelper.show(context, message: overlapMsg, isError: true);
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
        final message = _currentFiscalYear == null
            ? 'سال مالی جدید با موفقیت ایجاد شد'
            : 'سال مالی جاری با موفقیت به‌روزرسانی شد';
        SnackBarHelper.show(context, message: message, isError: false);
        await _loadData();
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = ErrorExtractor.forContext(e, context);
        });
        SnackBarHelper.show(
          context,
          message:
              'خطا در به‌روزرسانی سال مالی جاری: ${ErrorExtractor.forContext(e, context)}',
          isError: true,
        );
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
    final cs = Theme.of(context).colorScheme;

    if (_calendarController == null) {
      return Scaffold(
        appBar: AppBar(
          title: const Text('ویرایش سال مالی جاری'),
          leading: businessSubpageBackLeading(context, widget.businessId),
          backgroundColor: cs.surface,
          foregroundColor: cs.onSurface,
        ),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    final picker = _pickerBounds();

    return Scaffold(
      appBar: AppBar(
        title: const Text('ویرایش سال مالی جاری'),
        leading: businessSubpageBackLeading(context, widget.businessId),
        backgroundColor: cs.surface,
        foregroundColor: cs.onSurface,
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
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
                          color: _currentFiscalYear == null 
                              ? Colors.orange.shade50 
                              : cs.primaryContainer,
                          child: Padding(
                            padding: const EdgeInsets.all(16),
                            child: Row(
                              children: [
                                Icon(
                                  _currentFiscalYear == null 
                                      ? Icons.warning_amber_rounded 
                                      : Icons.info_outline, 
                                  color: _currentFiscalYear == null 
                                      ? Colors.orange.shade900 
                                      : cs.onPrimaryContainer,
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Text(
                                    _currentFiscalYear == null
                                        ? 'سال مالی جاری برای این کسب‌وکار وجود ندارد. لطفاً اطلاعات سال مالی جدید را وارد کنید تا به عنوان سال مالی جاری ایجاد شود.'
                                        : 'شما می‌توانید عنوان و تاریخ‌های سال مالی جاری را ویرایش کنید. توجه داشته باشید که تغییر این اطلاعات ممکن است بر روی گزارش‌ها تأثیر بگذارد.',
                                    style: TextStyle(
                                      color: _currentFiscalYear == null 
                                          ? Colors.orange.shade900 
                                          : cs.onPrimaryContainer,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: 24),
                        Text(
                          'سال مالی',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w600,
                            color: cs.onSurface,
                          ),
                        ),
                        const SizedBox(height: 16),
                        Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: cs.surface,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: cs.outline.withOpacity(0.3),
                            ),
                          ),
                          child: Column(
                            children: [
                              // تاریخ‌ها کنار هم
                              Row(
                                children: [
                                  Expanded(
                                    child: DateInputField(
                                      value: _startDate,
                                      labelText: 'تاریخ شروع *',
                                      firstDate: picker.first,
                                      lastDate: picker.last,
                                      calendarController: _calendarController!,
                                      onChanged: (d) {
                                        setState(() {
                                          _startDate = d;
                                          if (_startDate != null) {
                                            final suggestedEnd =
                                                HesabixDateUtils.fiscalYearInclusiveEndFromStart(
                                              _startDate!,
                                              _calendarController!.isJalali,
                                            );
                                            if (_endDate == null ||
                                                !_endDate!.isAfter(_startDate!)) {
                                              _endDate = suggestedEnd;
                                            }
                                            const autoPrefix = 'سال مالی منتهی به';
                                            if (_titleController.text.trim().isEmpty ||
                                                _titleController.text.trim().startsWith(autoPrefix)) {
                                              _titleController.text = _autoTitle();
                                            }
                                          }
                                        });
                                      },
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: DateInputField(
                                      value: _endDate,
                                      labelText: 'تاریخ پایان *',
                                      firstDate: picker.first,
                                      lastDate: picker.last,
                                      calendarController: _calendarController!,
                                      onChanged: (d) {
                                        setState(() {
                                          _endDate = d;
                                          const autoPrefix = 'سال مالی منتهی به';
                                          if (_titleController.text.trim().isEmpty ||
                                              _titleController.text.trim().startsWith(autoPrefix)) {
                                            _titleController.text = _autoTitle();
                                          }
                                        });
                                      },
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 16),
                              // فیلد عنوان
                              TextFormField(
                                controller: _titleController,
                                decoration: const InputDecoration(
                                  labelText: 'عنوان سال مالی *',
                                  border: OutlineInputBorder(),
                                ),
                                validator: (value) {
                                  if (value == null || value.trim().isEmpty) {
                                    return 'لطفاً عنوان سال مالی را وارد کنید';
                                  }
                                  return null;
                                },
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 16),
                        Align(
                          alignment: Alignment.centerRight,
                          child: Text(
                            'پرکردن عنوان، تاریخ شروع و پایان الزامی است.',
                            style: TextStyle(
                              color: cs.onSurface.withOpacity(0.7),
                              fontSize: 12,
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
                            label: Text(
                              _saving 
                                  ? 'در حال ذخیره...' 
                                  : (_currentFiscalYear == null 
                                      ? 'ایجاد سال مالی' 
                                      : 'ذخیره تغییرات'),
                            ),
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
