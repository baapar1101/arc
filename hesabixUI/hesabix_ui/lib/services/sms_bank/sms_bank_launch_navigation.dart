import '../../services/deep_link_handler.dart';

/// Normalizes SMS-bank notification / deep-link launches for GoRouter.
///
/// Native notifications use `hesabix://sms-bank/capture?id=…` which Flutter
/// maps to `/capture?id=…` — a path with no registered route. Bootstrap shows
/// the quick-capture sheet instead; routing must not land on 404.
class SmsBankLaunchNavigation {
  SmsBankLaunchNavigation._();

  static bool isSmsBankCaptureUri(Uri uri) {
    if (uri.scheme == 'hesabix' && uri.host == 'sms-bank') {
      return uri.path.contains('capture') ||
          (uri.queryParameters['id']?.isNotEmpty ?? false);
    }
    return false;
  }

  static bool isSmsBankCaptureGoRoutePath(String path, [Uri? uri]) {
    if (path == '/capture' || path == '/sms-bank/capture') {
      return uri?.queryParameters.containsKey('id') ?? true;
    }
    return false;
  }

  static bool isSmsBankCaptureNotification(Map<String, dynamic> item) {
    final eventKey = '${item['event_key'] ?? ''}';
    if (eventKey == 'sms_bank_capture') return true;
    final smsId = '${item['sms_bank_event_id'] ?? ''}';
    if (smsId.isNotEmpty) return true;
    final deep = '${item['deep_link'] ?? ''}';
    if (deep.contains('sms-bank')) return true;
    final uri = Uri.tryParse(deep);
    return uri != null && isSmsBankCaptureUri(uri);
  }

  static String? extractEventId(Uri uri) {
    final id = uri.queryParameters['id'];
    if (id != null && id.isNotEmpty) return id;
    return null;
  }

  static String? extractEventIdFromNotification(Map<String, dynamic> item) {
    final smsId = '${item['sms_bank_event_id'] ?? ''}';
    if (smsId.isNotEmpty) return smsId;
    final deep = '${item['deep_link'] ?? ''}';
    if (deep.isEmpty) return null;
    return extractEventId(Uri.tryParse(deep) ?? Uri());
  }

  /// GoRouter [initialLocation]: never start on the synthetic `/capture` path.
  ///
  /// On desktop (especially Windows), [Uri.base] is a `file://` URI to the
  /// executable / working directory (e.g. `/C:/Program Files/Hesabix/...`).
  /// Using that as the initial route lands on the 404 page. Web uses http(s)
  /// and keeps the real path; Android typically has `file:///` with path `/`.
  static String normalizeInitialLocation(Uri base) {
    if (isSmsBankCaptureUri(base) || isSmsBankCaptureGoRoutePath(base.path, base)) {
      return '/';
    }
    if (_isDesktopFilesystemBase(base)) {
      return '/';
    }
    final path = base.path.isNotEmpty ? base.path : '/';
    final query = base.hasQuery ? '?${base.query}' : '';
    final fragment = base.fragment.isNotEmpty ? '#${base.fragment}' : '';
    return '$path$query$fragment';
  }

  /// Whether GoRouter must ignore the platform default route (mirrors [Uri.base]
  /// on desktop) so a filesystem path does not override [normalizeInitialLocation].
  static bool shouldOverridePlatformDefault(Uri base) {
    return _isDesktopFilesystemBase(base);
  }

  /// True for paths that came from a desktop filesystem location, not an app route
  /// (e.g. `/C:/Program Files/Hesabix/...`).
  static bool isFilesystemRoutePath(String path) {
    if (path.isEmpty || path == '/') return false;
    // Windows drive letter as first segment: /C:/... or /C:\...
    if (RegExp(r'^/[A-Za-z]:').hasMatch(path)) return true;
    // Some Windows builds omit the colon: /D/hesabixArc/...
    if (RegExp(r'^/[A-Za-z]/').hasMatch(path)) return true;
    if (path.contains(r'\') || path.toLowerCase().endsWith('.exe')) return true;
    return false;
  }

  /// Registered GoRouter paths (plus synthetic paths handled by redirect).
  /// On desktop, anything else often comes from [Uri.base] filesystem URLs.
  static bool isRecognizedAppRoutePath(String path) {
    if (path.isEmpty || path == '/') return true;
    if (path == '/login' || path == '/404') return true;
    if (path == '/capture' || path.startsWith('/sms-bank/')) return true;
    if (path.startsWith('/public/')) return true;
    if (path.startsWith('/i/') || path.startsWith('/p/')) return true;
    if (path.startsWith('/wallet/')) return true;
    if (path.startsWith('/mobile-launcher/')) return true;
    if (path.startsWith('/user/profile/')) return true;
    if (path.startsWith('/business/')) return true;
    return false;
  }

  /// Redirect desktop / stale route information away from non-app paths (404).
  static bool shouldRedirectUnknownPathToRoot(String path) {
    return isFilesystemRoutePath(path) || !isRecognizedAppRoutePath(path);
  }

  static bool _isDesktopFilesystemBase(Uri base) {
    if (base.scheme != 'file') return false;
    return isFilesystemRoutePath(base.path) ||
        (base.path.isNotEmpty && base.path != '/');
  }

  static bool shouldRedirectAwayFromCapture(Uri uri) {
    return isSmsBankCaptureUri(uri) || isSmsBankCaptureGoRoutePath(uri.path, uri);
  }

  /// Resolve explicit announcement deep links to in-app paths only.
  static String? resolveAnnouncementDeepLink(String explicit) {
    if (explicit.isEmpty) return null;
    final uri = Uri.tryParse(explicit);
    if (uri != null && isSmsBankCaptureUri(uri)) return null;
    if (explicit.startsWith('/')) return explicit;
    if (uri != null && uri.scheme == 'hesabix') {
      return DeepLinkHandler.getRouteFromDeepLink(uri);
    }
    return null;
  }
}
