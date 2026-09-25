import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hesabix_ui/l10n/app_localizations.dart';

import '../core/date_utils.dart';
import '../core/calendar_controller.dart';
import 'jalali_date_picker.dart';

/// فیلد تاریخ با ویرایش مستقیم متن و دکمهٔ باز کردن تقویم.
/// پشتیبانی شمسی/میلادی طبق [CalendarController]؛ قالب `YYYY/MM/DD`.
class DateInputField extends StatefulWidget {
  final DateTime? value;
  final ValueChanged<DateTime?>? onChanged;
  final String? labelText;
  final String? hintText;
  final DateTime? firstDate;
  final DateTime? lastDate;
  final String? helpText;
  final bool enabled;
  final CalendarController calendarController;
  final bool isDense;
  final String? Function(String?)? validator;

  const DateInputField({
    super.key,
    this.value,
    this.onChanged,
    this.labelText,
    this.hintText,
    this.firstDate,
    this.lastDate,
    this.helpText,
    this.enabled = true,
    required this.calendarController,
    this.isDense = false,
    this.validator,
  });

  @override
  State<DateInputField> createState() => _DateInputFieldState();
}

class _DateInputFieldState extends State<DateInputField> {
  late final TextEditingController _controller;
  late final FocusNode _focusNode;
  final GlobalKey<FormFieldState<String>> _formFieldKey =
      GlobalKey<FormFieldState<String>>();

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController();
    _focusNode = FocusNode();
    _updateDisplayValue();
    widget.calendarController.addListener(_onCalendarChanged);
    _focusNode.addListener(_onFocusChanged);
  }

  /// اجرای validator برای نمایش خطا (blur/Enter) و هماهنگی با [FormState.validate] هنگام ارسال.
  void _requestFieldValidation() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      _formFieldKey.currentState?.validate();
    });
  }

  void _onFocusChanged() {
    if (!_focusNode.hasFocus) {
      _commitTextToParent();
      _requestFieldValidation();
    }
  }

  void _onCalendarChanged() {
    if (mounted) {
      _updateDisplayValue();
    }
  }

  @override
  void didUpdateWidget(DateInputField oldWidget) {
    super.didUpdateWidget(oldWidget);
    final calChanged = (oldWidget.calendarController.isJalali == true) !=
        (widget.calendarController.isJalali == true);
    if (!_sameDateOnly(oldWidget.value, widget.value) || calChanged) {
      _updateDisplayValue();
    }
  }

  @override
  void dispose() {
    widget.calendarController.removeListener(_onCalendarChanged);
    _focusNode.removeListener(_onFocusChanged);
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  DateTime _effectiveFirst() {
    final now = DateTime.now();
    return widget.firstDate ?? DateTime(now.year - 2);
  }

  DateTime _effectiveLast() {
    final now = DateTime.now();
    return widget.lastDate ?? DateTime(now.year + 2);
  }

  void _updateDisplayValue() {
    final displayValue = HesabixDateUtils.formatForDisplay(
      widget.value,
      widget.calendarController.isJalali == true,
    );
    if (_controller.text == displayValue) {
      return;
    }
    _controller.value = TextEditingValue(
      text: displayValue,
      selection: TextSelection.collapsed(offset: displayValue.length),
    );
  }

  static bool _sameDateOnly(DateTime? a, DateTime? b) {
    if (a == null && b == null) {
      return true;
    }
    if (a == null || b == null) {
      return false;
    }
    final al = a.toLocal();
    final bl = b.toLocal();
    return al.year == bl.year && al.month == bl.month && al.day == bl.day;
  }

  /// پس از ویرایش: اعمال مقدار معتبر به parent (خالی = null).
  void _commitTextToParent() {
    if (!widget.enabled) {
      return;
    }
    final text = _controller.text.trim();
    final isJalali = widget.calendarController.isJalali == true;
    if (text.isEmpty) {
      if (widget.value != null) {
        widget.onChanged?.call(null);
      }
      return;
    }
    final parsed = HesabixDateUtils.parseFromDisplay(text, isJalali);
    if (parsed == null) {
      return;
    }
    if (!HesabixDateUtils.isDateOnlyInRange(
      parsed,
      _effectiveFirst(),
      _effectiveLast(),
    )) {
      return;
    }
    final n = HesabixDateUtils.toDateOnlyLocal(parsed);
    if (!_sameDateOnly(widget.value, n)) {
      widget.onChanged?.call(n);
    }
  }

  String? _validateDateText(String? value) {
    final text = (value ?? '').trim();
    if (text.isEmpty) {
      return null;
    }
    final t = AppLocalizations.of(context);
    final isJalali = widget.calendarController.isJalali == true;
    final parsed = HesabixDateUtils.parseFromDisplay(text, isJalali);
    if (parsed == null) {
      return t.dateInputInvalidFormat;
    }
    if (!HesabixDateUtils.isDateOnlyInRange(
      parsed,
      _effectiveFirst(),
      _effectiveLast(),
    )) {
      return t.dateInputOutOfRange;
    }
    return null;
  }

  String? _combinedValidator(String? v) {
    final e = _validateDateText(v);
    if (e != null) {
      return e;
    }
    return widget.validator?.call(v);
  }

  Future<void> _selectDate() async {
    if (!widget.enabled) {
      return;
    }
    _commitTextToParent();
    if (!context.mounted) {
      return;
    }

    final now = DateTime.now();
    final firstDate = widget.firstDate ?? DateTime(now.year - 2);
    final lastDate = widget.lastDate ?? DateTime(now.year + 2);
    final isJalali = widget.calendarController.isJalali == true;
    var initialDate = widget.value ?? now;
    final fieldText = _controller.text.trim();
    if (fieldText.isNotEmpty) {
      final fromField = HesabixDateUtils.parseFromDisplay(fieldText, isJalali);
      if (fromField != null &&
          HesabixDateUtils.isDateOnlyInRange(fromField, firstDate, lastDate)) {
        initialDate = fromField;
      }
    }

    final selectedDate = await showAdaptiveDatePicker(
      context: context,
      calendarController: widget.calendarController,
      initialDate: initialDate,
      firstDate: firstDate,
      lastDate: lastDate,
      helpText: widget.helpText,
    );

    if (selectedDate != null && context.mounted) {
      widget.onChanged?.call(selectedDate);
      _requestFieldValidation();
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);

    return TextFormField(
      key: _formFieldKey,
      controller: _controller,
      focusNode: _focusNode,
      enabled: widget.enabled,
      keyboardType: TextInputType.datetime,
      textInputAction: TextInputAction.done,
      autovalidateMode: AutovalidateMode.disabled,
      onEditingComplete: () {
        _commitTextToParent();
        _requestFieldValidation();
      },
      onChanged: (_) {
        final st = _formFieldKey.currentState;
        if (st != null && st.hasError) {
          st.validate();
        }
      },
      decoration: InputDecoration(
        labelText: widget.labelText,
        hintText: widget.hintText,
        suffixIcon: IconButton(
          padding: EdgeInsets.zero,
          constraints: widget.isDense
              ? const BoxConstraints(minWidth: 40, minHeight: 40, maxWidth: 44, maxHeight: 44)
              : null,
          icon: Icon(Icons.calendar_today, size: widget.isDense ? 20 : 24),
          tooltip: t.dateInputOpenCalendar,
          onPressed: widget.enabled ? _selectDate : null,
        ),
        suffixIconConstraints: widget.isDense
            ? const BoxConstraints(maxHeight: 44, maxWidth: 48)
            : null,
        border: const OutlineInputBorder(),
        isDense: widget.isDense,
        contentPadding: widget.isDense
            ? const EdgeInsetsDirectional.only(start: 12, top: 10, bottom: 10, end: 12)
            : null,
      ),
      inputFormatters: [
        FilteringTextInputFormatter.allow(RegExp(r'[0-9/]')),
        LengthLimitingTextInputFormatter(10),
      ],
      validator: _combinedValidator,
    );
  }
}