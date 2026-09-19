import 'package:flutter/foundation.dart';

/// SMS bank assistant is Android-only; web and other platforms stay no-op.
bool get supportsAndroidSmsBankAssistant =>
    !kIsWeb && defaultTargetPlatform == TargetPlatform.android;
