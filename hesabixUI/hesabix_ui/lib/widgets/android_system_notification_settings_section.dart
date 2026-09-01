import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';

import '../core/android_notification_keepalive_platform.dart';
import '../core/android_notification_prefs.dart';
import '../core/calendar_controller.dart';
import '../services/android_notification_keepalive/android_notification_keepalive_service.dart';
import '../services/in_app_notifications_hub.dart';
import '../utils/snackbar_helper.dart';

/// Android-only controls for system tray personalization + background keep-alive.
class AndroidSystemNotificationSettingsSection extends StatefulWidget {
  const AndroidSystemNotificationSettingsSection({
    super.key,
    required this.enabled,
    required this.calendarController,
  });

  final bool enabled;
  final CalendarController calendarController;

  @override
  State<AndroidSystemNotificationSettingsSection> createState() =>
      _AndroidSystemNotificationSettingsSectionState();
}

class _AndroidSystemNotificationSettingsSectionState extends State<AndroidSystemNotificationSettingsSection> {
  bool _loading = true;
  bool _keepAlive = false;
  bool _keepAliveRunning = false;
  int _accent = AndroidNotificationPrefs.defaultAccentColor;
  String _dateStyle = 'both';
  bool _showTime = true;
  bool _showEventLabel = true;
  bool _showAppBrand = true;
  bool _led = true;
  bool _vibrate = true;
  bool _busy = false;

  static const _swatches = <int>[
    0xFF0F4C81, // classic blue
    0xFF00A8BD, // turquoise sea
    0xFF0F766E, // emerald forest
    0xFFB45309, // warm copper
    0xFF2E7D32, // green
    0xFFC62828, // red
    0xFFEF6C00, // orange
    0xFF455A64, // blue grey
  ];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (!supportsAndroidNotificationKeepAlive) {
      setState(() => _loading = false);
      return;
    }
    final snap = await AndroidNotificationPrefs.snapshot();
    final running = await createAndroidNotificationKeepAliveService().isRunning();
    if (!mounted) return;
    setState(() {
      _keepAlive = snap['keepAliveEnabled'] == true;
      _accent = snap['accentColor'] as int? ?? AndroidNotificationPrefs.defaultAccentColor;
      _dateStyle = '${snap['dateStyle'] ?? 'both'}';
      _showTime = snap['showTime'] != false;
      _showEventLabel = snap['showEventLabel'] != false;
      _showAppBrand = snap['showAppBrand'] != false;
      _led = snap['ledEnabled'] != false;
      _vibrate = snap['vibrate'] != false;
      _keepAliveRunning = running;
      _loading = false;
    });
  }

  Future<void> _setKeepAlive(bool value) async {
    setState(() {
      _busy = true;
      _keepAlive = value;
    });
    await AndroidNotificationPrefs.setKeepAliveEnabled(value);
    InAppNotificationsHub.instance.setAppIsJalali(widget.calendarController.isJalali);
    await InAppNotificationsHub.instance.reloadDeliveryMode();
    final running = await createAndroidNotificationKeepAliveService().isRunning();
    if (!mounted) return;
    setState(() {
      _keepAliveRunning = running;
      _busy = false;
    });
    if (value && !running && mounted) {
      SnackBarHelper.show(
        context,
        message: 'سرویس پس‌زمینه فعال نشد. مجوز ناتیفیکیشن و محدودیت باتری دستگاه را بررسی کنید.',
      );
    }
  }

  Future<void> _openBatterySettings() async {
    try {
      await Permission.ignoreBatteryOptimizations.request();
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    if (!supportsAndroidNotificationKeepAlive) {
      return const SizedBox.shrink();
    }
    if (!widget.enabled) {
      return const SizedBox.shrink();
    }
    if (_loading) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 12),
        child: Center(child: SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2))),
      );
    }

    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 16),
        const Divider(),
        const SizedBox(height: 8),
        Text(
          'اعلان سیستم اندروید',
          style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 4),
        Text(
          'شخصی‌سازی ظاهر اعلان‌های دریافتی و اعلان دائمی پس‌زمینه (ساعت، تاریخ، برند و آیکون حسابیکس).',
          style: theme.textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
        ),
        const SizedBox(height: 12),
        SwitchListTile.adaptive(
          contentPadding: EdgeInsets.zero,
          title: const Text('دریافت اعلان در پس‌زمینه'),
          subtitle: Text(
            _keepAlive
                ? (_keepAliveRunning
                    ? 'سرویس فعال است (یک اعلان دائمی کم‌اهمیت در سینی نمایش داده می‌شود).'
                    : 'فعال شده؛ در حال راه‌اندازی سرویس…')
                : 'با روشن کردن این گزینه، اتصال اعلان‌ها در پس‌زمینه حفظ می‌شود.',
          ),
          value: _keepAlive,
          onChanged: _busy ? null : _setKeepAlive,
        ),
        if (_keepAlive) ...[
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: TextButton.icon(
              onPressed: _openBatterySettings,
              icon: const Icon(Icons.battery_saver_outlined, size: 18),
              label: const Text('مجوز بدون محدودیت باتری'),
            ),
          ),
        ],
        const SizedBox(height: 8),
        Text('رنگ تاکید اعلان', style: theme.textTheme.labelLarge),
        const SizedBox(height: 8),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            for (final c in _swatches)
              InkWell(
                onTap: () async {
                  setState(() => _accent = c);
                  await AndroidNotificationPrefs.setAccentColor(c);
                  await _refreshKeepAliveStatus();
                },
                borderRadius: BorderRadius.circular(20),
                child: Container(
                  width: 34,
                  height: 34,
                  decoration: BoxDecoration(
                    color: Color(c),
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: _accent == c ? cs.onSurface : Colors.transparent,
                      width: 2.5,
                    ),
                  ),
                  child: _accent == c ? const Icon(Icons.check, size: 16, color: Colors.white) : null,
                ),
              ),
          ],
        ),
        const SizedBox(height: 16),
        Text(
          'محتوای اعلان (دریافتی و دائمی)',
          style: theme.textTheme.labelLarge,
        ),
        const SizedBox(height: 8),
        DropdownButtonFormField<String>(
          value: _dateStyle,
          decoration: const InputDecoration(
            labelText: 'نمایش تاریخ',
            border: OutlineInputBorder(),
          ),
          items: const [
            DropdownMenuItem(value: 'both', child: Text('شمسی و میلادی')),
            DropdownMenuItem(value: 'jalali', child: Text('فقط شمسی')),
            DropdownMenuItem(value: 'gregorian', child: Text('فقط میلادی')),
            DropdownMenuItem(value: 'app', child: Text('مطابق تقویم برنامه')),
            DropdownMenuItem(value: 'none', child: Text('بدون تاریخ')),
          ],
          onChanged: (v) async {
            if (v == null) return;
            setState(() => _dateStyle = v);
            await AndroidNotificationPrefs.setDateStyle(v);
            await _refreshKeepAliveStatus();
          },
        ),
        SwitchListTile.adaptive(
          contentPadding: EdgeInsets.zero,
          title: const Text('نمایش ساعت'),
          subtitle: const Text('روی اعلان‌های دریافتی و اعلان دائمی پس‌زمینه'),
          value: _showTime,
          onChanged: (v) async {
            setState(() => _showTime = v);
            await AndroidNotificationPrefs.setShowTime(v);
            await _refreshKeepAliveStatus();
          },
        ),
        SwitchListTile.adaptive(
          contentPadding: EdgeInsets.zero,
          title: const Text('برچسب نوع رویداد (مثلاً تیکت)'),
          subtitle: const Text('فقط برای اعلان‌های دریافتی'),
          value: _showEventLabel,
          onChanged: (v) async {
            setState(() => _showEventLabel = v);
            await AndroidNotificationPrefs.setShowEventLabel(v);
          },
        ),
        SwitchListTile.adaptive(
          contentPadding: EdgeInsets.zero,
          title: const Text('نام برند «حسابیکس» در عنوان'),
          value: _showAppBrand,
          onChanged: (v) async {
            setState(() => _showAppBrand = v);
            await AndroidNotificationPrefs.setShowAppBrand(v);
            await _refreshKeepAliveStatus();
          },
        ),
        SwitchListTile.adaptive(
          contentPadding: EdgeInsets.zero,
          title: const Text('چراغ LED اعلان'),
          value: _led,
          onChanged: (v) async {
            setState(() => _led = v);
            await AndroidNotificationPrefs.setLedEnabled(v);
          },
        ),
        SwitchListTile.adaptive(
          contentPadding: EdgeInsets.zero,
          title: const Text('لرزش اعلان سیستم'),
          value: _vibrate,
          onChanged: (v) async {
            setState(() => _vibrate = v);
            await AndroidNotificationPrefs.setVibrate(v);
          },
        ),
        const SizedBox(height: 4),
        Text(
          'آیکون اعلان: سیلوئت سفید حسابیکس در نوار وضعیت؛ لوگوی رنگی مطابق تم روشن/تاریک گوشی در پنل اعلان. Force Stop یا قاتل‌باتری برخی گوشی‌ها سرویس را متوقف می‌کند.',
          style: theme.textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
        ),
      ],
    );
  }

  Future<void> _refreshKeepAliveStatus() async {
    if (!_keepAlive) return;
    await createAndroidNotificationKeepAliveService().refreshStatusNotification(
      appIsJalali: widget.calendarController.isJalali,
    );
  }
}
