import 'dart:async';
import 'package:flutter/material.dart';

class SplashController extends ChangeNotifier {
  static const Duration _minimumSplashDuration = Duration(seconds: 2);
  
  bool _isLoading = true;
  DateTime? _startTime;
  Timer? _minimumDurationTimer;
  Completer<void>? _loadingCompleter;

  bool get isLoading => _isLoading;
  
  SplashController() {
    _startTime = DateTime.now();
  }

  /// شروع loading با حداقل زمان نمایش
  Future<void> startLoading() async {
    _isLoading = true;
    _loadingCompleter = Completer<void>();
    notifyListeners();
    
    // شروع تایمر برای حداقل زمان نمایش
    _minimumDurationTimer = Timer(_minimumSplashDuration, () {
      if (_loadingCompleter != null && !_loadingCompleter!.isCompleted) {
        _loadingCompleter!.complete();
      }
    });
    
    return _loadingCompleter!.future;
  }

  /// اتمام loading (فقط اگر حداقل زمان گذشته باشد)
  void finishLoading() {
    if (_minimumDurationTimer != null && _minimumDurationTimer!.isActive) {
      // اگر هنوز حداقل زمان نگذشته، منتظر بمان
      _minimumDurationTimer!.cancel();
      _minimumDurationTimer = Timer(
        _minimumSplashDuration - DateTime.now().difference(_startTime!),
        () {
          _completeLoading();
        },
      );
    } else {
      _completeLoading();
    }
  }

  void _completeLoading() {
    if (_isLoading) {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// بررسی اینکه آیا حداقل زمان گذشته یا نه
  bool get hasMinimumTimePassed {
    if (_startTime == null) return true;
    return DateTime.now().difference(_startTime!) >= _minimumSplashDuration;
  }

  /// دریافت زمان باقی‌مانده تا اتمام حداقل زمان
  Duration get remainingTime {
    if (_startTime == null) return Duration.zero;
    final elapsed = DateTime.now().difference(_startTime!);
    final remaining = _minimumSplashDuration - elapsed;
    return remaining.isNegative ? Duration.zero : remaining;
  }

  @override
  void dispose() {
    _minimumDurationTimer?.cancel();
    super.dispose();
  }
}
