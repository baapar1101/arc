import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum CalendarType {
  gregorian,
  jalali,
}

extension CalendarTypeExtension on CalendarType {
  String get value {
    switch (this) {
      case CalendarType.gregorian:
        return 'gregorian';
      case CalendarType.jalali:
        return 'jalali';
    }
  }

  String get displayName {
    switch (this) {
      case CalendarType.gregorian:
        return 'میلادی';
      case CalendarType.jalali:
        return 'شمسی';
    }
  }

  String get englishDisplayName {
    switch (this) {
      case CalendarType.gregorian:
        return 'Gregorian';
      case CalendarType.jalali:
        return 'Jalali';
    }
  }

  static CalendarType fromString(String value) {
    switch (value.toLowerCase()) {
      case 'jalali':
      case 'persian':
      case 'shamsi':
        return CalendarType.jalali;
      case 'gregorian':
      case 'miladi':
      default:
        return CalendarType.gregorian;
    }
  }
}

class CalendarController extends ChangeNotifier {
  static const String _prefsKey = 'app_calendar_type';

  CalendarType _calendarType;
  CalendarType get calendarType => _calendarType;

  CalendarController._(this._calendarType);

  static const List<CalendarType> supportedCalendars = <CalendarType>[
    CalendarType.jalali,
    CalendarType.gregorian,
  ];

  static Future<CalendarController> load() async {
    final prefs = await SharedPreferences.getInstance();
    final calendarValue = prefs.getString(_prefsKey);
    CalendarType initial = CalendarType.jalali; // Default to Jalali for Persian users
    
    if (calendarValue != null) {
      initial = CalendarTypeExtension.fromString(calendarValue);
    }
    
    return CalendarController._(initial);
  }

  Future<void> setCalendarType(CalendarType calendarType) async {
    if (_calendarType == calendarType) return;
    
    _calendarType = calendarType;
    notifyListeners();
    
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefsKey, calendarType.value);
  }

  bool get isJalali => _calendarType == CalendarType.jalali;
  bool get isGregorian => _calendarType == CalendarType.gregorian;
}
