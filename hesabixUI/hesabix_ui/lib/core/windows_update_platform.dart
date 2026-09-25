import 'package:flutter/foundation.dart';

/// Sideloaded Windows installer auto-update; web / Android / other desktops excluded.
bool get supportsWindowsDesktopUpdate =>
    !kIsWeb && defaultTargetPlatform == TargetPlatform.windows;
