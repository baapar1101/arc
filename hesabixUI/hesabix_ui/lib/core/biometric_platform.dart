import 'package:flutter/foundation.dart';

/// Biometric app-lock is Android-only; web and other platforms are excluded.
bool get supportsBiometricLock =>
    !kIsWeb && defaultTargetPlatform == TargetPlatform.android;
