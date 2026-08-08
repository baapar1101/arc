import 'package:flutter/material.dart';

import '../../core/biometric_lock_controller.dart';

class BiometricLockScope extends InheritedNotifier<BiometricLockController> {
  const BiometricLockScope({
    super.key,
    required BiometricLockController controller,
    required super.child,
  }) : super(notifier: controller);

  static BiometricLockController of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<BiometricLockScope>();
    assert(scope != null, 'BiometricLockScope not found in widget tree');
    return scope!.notifier!;
  }

  static BiometricLockController? maybeOf(BuildContext context) {
    return context
        .dependOnInheritedWidgetOfExactType<BiometricLockScope>()
        ?.notifier;
  }

  /// Non-listening lookup safe to call outside [build].
  static BiometricLockController? maybeRead(BuildContext context) {
    final element =
        context.getElementForInheritedWidgetOfExactType<BiometricLockScope>();
    final widget = element?.widget;
    if (widget is! BiometricLockScope) return null;
    return widget.notifier;
  }
}
