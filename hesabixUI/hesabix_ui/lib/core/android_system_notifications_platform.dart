import 'package:flutter/foundation.dart';

/// System-tray notifications are Android-only; web and other platforms stay no-op.
bool get supportsAndroidSystemNotifications =>
    !kIsWeb && defaultTargetPlatform == TargetPlatform.android;
