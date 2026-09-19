import 'package:flutter/foundation.dart';

/// Sideloaded APK auto-update is Android-only; web and other platforms are excluded.
bool get supportsAndroidApkUpdate =>
    !kIsWeb && defaultTargetPlatform == TargetPlatform.android;
