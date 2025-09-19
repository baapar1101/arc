import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../core/date_utils.dart';
import '../core/calendar_controller.dart';
import 'jalali_date_picker.dart';

/// Custom TextField for date input that handles both Gregorian and Jalali calendars
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
  });

  @override
  State<DateInputField> createState() => _DateInputFieldState();
}

class _DateInputFieldState extends State<DateInputField> {
  late TextEditingController _controller;
  late FocusNode _focusNode;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController();
    _focusNode = FocusNode();
    _updateDisplayValue();
    
    // Listen to calendar controller changes
    widget.calendarController.addListener(_onCalendarChanged);
  }

  void _onCalendarChanged() {
    if (mounted) {
      _updateDisplayValue();
    }
  }

  @override
  void didUpdateWidget(DateInputField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.value != widget.value || 
        (oldWidget.calendarController.isJalali == true) != (widget.calendarController.isJalali == true)) {
      _updateDisplayValue();
    }
  }


  @override
  void dispose() {
    // Remove listener
    widget.calendarController.removeListener(_onCalendarChanged);
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _updateDisplayValue() {
    final displayValue = HesabixDateUtils.formatForDisplay(
      widget.value, 
      widget.calendarController.isJalali == true
    );
    _controller.text = displayValue;
  }

  Future<void> _selectDate() async {
    if (!widget.enabled) return;

    final now = DateTime.now();
    final firstDate = widget.firstDate ?? DateTime(now.year - 2);
    final lastDate = widget.lastDate ?? DateTime(now.year + 2);
    final initialDate = widget.value ?? now;

    DateTime? selectedDate;
    
    if (widget.calendarController.isJalali == true) {
      selectedDate = await showJalaliDatePicker(
        context: context,
        initialDate: initialDate,
        firstDate: firstDate,
        lastDate: lastDate,
        helpText: widget.helpText,
      );
    } else {
      selectedDate = await showDatePicker(
        context: context,
        initialDate: initialDate,
        firstDate: firstDate,
        lastDate: lastDate,
        helpText: widget.helpText,
        locale: const Locale('en', 'US'),
      );
    }

    if (selectedDate != null) {
      widget.onChanged?.call(selectedDate);
    }
  }

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: _controller,
      focusNode: _focusNode,
      readOnly: true,
      enabled: widget.enabled,
      decoration: InputDecoration(
        labelText: widget.labelText,
        hintText: widget.hintText,
        suffixIcon: IconButton(
          icon: const Icon(Icons.calendar_today),
          onPressed: _selectDate,
        ),
        border: const OutlineInputBorder(),
      ),
      onTap: _selectDate,
      inputFormatters: [
        // Prevent manual input
        FilteringTextInputFormatter.deny(RegExp(r'.')),
      ],
    );
  }
}
