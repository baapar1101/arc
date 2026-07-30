import 'sms_bank_models.dart';

/// Queues SMS bank quick-capture until UI (BusinessShell / bootstrap) is ready.
class SmsBankCaptureNavigation {
  SmsBankCaptureNavigation._();

  static final SmsBankCaptureNavigation instance = SmsBankCaptureNavigation._();

  SmsBankEvent? _pending;
  final List<void Function(SmsBankEvent event)> _listeners = [];

  void enqueue(SmsBankEvent event) {
    if (event.status != SmsBankEventStatus.pending) return;
    _pending = event;
    for (final l in List.of(_listeners)) {
      l(event);
    }
  }

  SmsBankEvent? peek() => _pending;

  SmsBankEvent? consume() {
    final e = _pending;
    _pending = null;
    return e;
  }

  void clear() => _pending = null;

  void addListener(void Function(SmsBankEvent event) listener) {
    _listeners.add(listener);
  }

  void removeListener(void Function(SmsBankEvent event) listener) {
    _listeners.remove(listener);
  }
}
