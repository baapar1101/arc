import 'package:flutter/foundation.dart';

/// Android-only foreground keep-alive for notification WebSocket.
bool get supportsAndroidNotificationKeepAlive =>
    !kIsWeb && defaultTargetPlatform == TargetPlatform.android;
