import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../core/api_client.dart';
import '../core/auth_store.dart';

/// هر [interval] یک‌بار درخواست ضربان به سرور می‌فرستد تا [users.last_activity_at] به‌روز شود.
class UserActivityHeartbeat extends StatefulWidget {
  final AuthStore authStore;
  final Widget child;
  /// کمی بزرگ‌تر از throttle سمت سرور (~۴۵ ثانیه) تا فشار روی DB کم بماند.
  final Duration interval;

  const UserActivityHeartbeat({
    super.key,
    required this.authStore,
    required this.child,
    this.interval = const Duration(seconds: 55),
  });

  @override
  State<UserActivityHeartbeat> createState() => _UserActivityHeartbeatState();
}

class _UserActivityHeartbeatState extends State<UserActivityHeartbeat> {
  Timer? _timer;
  VoidCallback? _authListener;

  @override
  void initState() {
    super.initState();
    _authListener = _onAuthChanged;
    widget.authStore.addListener(_authListener!);
    _scheduleOrCancel();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _sendHeartbeat();
    });
  }

  @override
  void didUpdateWidget(covariant UserActivityHeartbeat oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.authStore != widget.authStore) {
      oldWidget.authStore.removeListener(_authListener!);
      widget.authStore.addListener(_authListener!);
      _scheduleOrCancel();
    }
  }

  void _onAuthChanged() => _scheduleOrCancel();

  void _scheduleOrCancel() {
    final key = widget.authStore.apiKey;
    if (key == null || key.isEmpty) {
      _timer?.cancel();
      _timer = null;
      return;
    }
    _timer?.cancel();
    _timer = Timer.periodic(widget.interval, (_) => _sendHeartbeat());
  }

  Future<void> _sendHeartbeat() async {
    final key = widget.authStore.apiKey;
    if (key == null || key.isEmpty) return;
    try {
      await ApiClient().post<Map<String, dynamic>>('/api/v1/auth/activity', data: const {});
    } catch (_) {
      // نبودن شبکه یا ۴۰۱ نباید تجربهٔ کاربر را خراب کند
      if (kDebugMode) {
        debugPrint('[UserActivityHeartbeat] ping skipped or failed');
      }
    }
  }

  @override
  void dispose() {
    if (_authListener != null) {
      widget.authStore.removeListener(_authListener!);
    }
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
