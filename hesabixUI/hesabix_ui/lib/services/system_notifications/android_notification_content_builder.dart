import 'dart:ui' show Brightness, PlatformDispatcher;

import 'package:shamsi_date/shamsi_date.dart';

import '../../core/android_notification_prefs.dart';
import '../../utils/announcement_navigation.dart';

/// Builds richer Android tray title/body from preferences + payload.
class AndroidNotificationContentBuilder {
  AndroidNotificationContentBuilder._();

  /// Small status-bar icon (white silhouette drawable).
  static const String smallIconDrawable = 'ic_stat_hesabix';

  /// Large tray icon drawable name for the current system brightness.
  static String largeIconDrawableForTheme({Brightness? brightness}) {
    final b = brightness ?? PlatformDispatcher.instance.platformBrightness;
    // Dark theme → light logo; light theme → dark/blue logo.
    return b == Brightness.dark ? 'ic_hesabix_logo_light' : 'ic_hesabix_logo';
  }

  static Future<({String title, String body})> build({
    required Map<String, dynamic> item,
    bool appIsJalali = true,
  }) async {
    final prefs = await AndroidNotificationPrefs.snapshot();
    final rawTitle = '${item['title'] ?? 'اعلان'}'.trim();
    final rawBody = '${item['body'] ?? ''}'.trim();
    final eventKey = item['event_key']?.toString();
    final ticketId = AnnouncementNavigation.parseTicketId(item['ticket_id']);
    final now = DateTime.now();

    final titleParts = <String>[];
    if (prefs['showAppBrand'] == true) {
      titleParts.add('حسابیکس');
    }
    titleParts.add(rawTitle.isEmpty ? 'اعلان' : rawTitle);

    final bodyLines = <String>[];
    if (rawBody.isNotEmpty) bodyLines.add(rawBody);

    final meta = <String>[];
    if (prefs['showEventLabel'] == true) {
      final label = eventLabel(eventKey, ticketId);
      if (label != null) meta.add(label);
    }

    meta.addAll(statusMetaLineParts(prefs: prefs, now: now, appIsJalali: appIsJalali));

    if (meta.isNotEmpty) {
      bodyLines.add(meta.join(' · '));
    }

    return (
      title: titleParts.join(' · '),
      body: bodyLines.isEmpty ? rawTitle : bodyLines.join('\n'),
    );
  }

  /// Persistent keep-alive notification title/body from the same personalization prefs.
  static Future<({String title, String body})> buildKeepAlive({
    bool appIsJalali = true,
    DateTime? now,
  }) async {
    final prefs = await AndroidNotificationPrefs.snapshot();
    final ts = now ?? DateTime.now();
    final title = prefs['showAppBrand'] == true
        ? 'حسابیکس · دریافت اعلان‌ها'
        : 'دریافت اعلان‌ها';

    final parts = <String>['اتصال پس‌زمینه فعال است'];
    parts.addAll(statusMetaLineParts(prefs: prefs, now: ts, appIsJalali: appIsJalali));
    parts.add('توقف از تنظیمات ناتیفیکیشن');

    return (title: title, body: parts.join(' · '));
  }

  static List<String> statusMetaLineParts({
    required Map<String, dynamic> prefs,
    required DateTime now,
    required bool appIsJalali,
  }) {
    final meta = <String>[];
    final dateStyle = '${prefs['dateStyle'] ?? 'both'}';
    if (dateStyle != 'none') {
      final dateBits = formatDates(now, dateStyle: dateStyle, appIsJalali: appIsJalali);
      if (dateBits.isNotEmpty) meta.add(dateBits);
    }
    if (prefs['showTime'] == true) {
      meta.add(formatTime(now));
    }
    return meta;
  }

  static String? eventLabel(String? eventKey, int? ticketId) {
    final key = (eventKey ?? '').trim();
    if (key.isEmpty && ticketId == null) return null;
    String base;
    switch (key) {
      case 'support.ticket_created':
        base = 'تیکت جدید';
        break;
      case 'support.user_reply':
        base = 'پاسخ کاربر';
        break;
      case 'support.operator_reply':
        base = 'پاسخ پشتیبانی';
        break;
      case 'support.ticket_assigned':
      case 'support.tickets_bulk_assigned':
        base = 'اختصاص تیکت';
        break;
      case 'support.ticket_status_changed':
      case 'support.tickets_bulk_status_changed':
        base = 'تغییر وضعیت تیکت';
        break;
      case 'system.test':
        base = 'تست سیستم';
        break;
      default:
        if (key.startsWith('support.')) {
          base = 'پشتیبانی';
        } else if (key.isNotEmpty) {
          base = key;
        } else {
          base = 'اعلان';
        }
    }
    if (ticketId != null) return '$base #$ticketId';
    return base;
  }

  static String formatDates(DateTime now, {required String dateStyle, required bool appIsJalali}) {
    final g = '${now.year}/${now.month.toString().padLeft(2, '0')}/${now.day.toString().padLeft(2, '0')}';
    final j = Jalali.fromDateTime(now);
    final jalali = '${j.year}/${j.month.toString().padLeft(2, '0')}/${j.day.toString().padLeft(2, '0')}';
    switch (dateStyle) {
      case 'none':
        return '';
      case 'jalali':
        return 'شمسی $jalali';
      case 'gregorian':
        return 'میلادی $g';
      case 'app':
        return appIsJalali ? 'شمسی $jalali' : 'میلادی $g';
      case 'both':
      default:
        return 'شمسی $jalali | میلادی $g';
    }
  }

  static String formatTime(DateTime now) {
    return '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}';
  }
}
