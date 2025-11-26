import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hesabix_ui/l10n/app_localizations.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../core/api_client.dart';
import '../../core/calendar_controller.dart';
import '../../core/date_utils.dart';
import '../../services/notifications_service.dart';
import '../../services/telegram_integration_service.dart';
import '../../utils/snackbar_helper.dart';

class UserNotificationsPage extends StatefulWidget {
  final CalendarController calendarController;
  const UserNotificationsPage({super.key, required this.calendarController});

  @override
  State<UserNotificationsPage> createState() => _UserNotificationsPageState();
}

class _ChannelOption {
  const _ChannelOption({
    required this.key,
    required this.enabled,
    required this.icon,
    required this.title,
    required this.description,
    required this.onChanged,
  });

  final String key;
  final bool enabled;
  final IconData icon;
  final String title;
  final String description;
  final ValueChanged<bool> onChanged;
}

class _UserNotificationsPageState extends State<UserNotificationsPage> {
  final _svc = NotificationsService(ApiClient());
  final _telegramSvc = TelegramIntegrationService(ApiClient());
  bool _loading = true;
  String? _error;
  bool _telegram = true;
  bool _email = true;
  bool _sms = true;
  bool _inapp = true;
  bool _saving = false;
  // Telegram connection state
  bool _telegramLinked = false;
  String? _telegramConnectedAt;
  bool _telegramLoading = false;
  bool _telegramConnecting = false;
  String? _telegramLinkToken;
  String? _telegramDeepLink;
  DateTime? _telegramLinkExpiresAt;
  Timer? _timer;
  int _remainingSeconds = 0;
  bool _isPolling = false; // برای جلوگیری از بسته شدن بخش در حین polling
  bool _showLinkSection = false; // متغیر جداگانه برای کنترل نمایش بخش QR code

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      setState(() {
        _loading = true;
        _error = null;
      });
      final s = await _svc.getSettings();
      await _loadTelegramStatus();
      if (!mounted) return;
      setState(() {
        _telegram = (s['telegram_enabled'] ?? true) == true;
        _email = (s['email_enabled'] ?? true) == true;
        _sms = (s['sms_enabled'] ?? true) == true;
        _inapp = (s['inapp_enabled'] ?? true) == true;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = '$e';
        _loading = false;
      });
    }
  }

  Future<void> _loadTelegramStatus({bool updateLoading = true, bool skipSetState = false}) async {
    debugPrint('[TelegramStatus] _loadTelegramStatus called - updateLoading: $updateLoading, skipSetState: $skipSetState');
    debugPrint('[TelegramStatus] Current state - _telegramLinkToken: ${_telegramLinkToken != null ? "exists" : "null"}, _showLinkSection: $_showLinkSection');
    try {
      if (updateLoading && mounted && !skipSetState) {
        debugPrint('[TelegramStatus] Setting _telegramLoading = true');
        setState(() => _telegramLoading = true);
      }
      final status = await _telegramSvc.getStatus();
      if (!mounted) {
        debugPrint('[TelegramStatus] Widget not mounted, returning');
        return;
      }
      
      // فقط متغیرهای status را به‌روزرسانی کن، نه link token و deep link
      final newLinked = status['linked'] == true;
      final newConnectedAt = status['connected_at']?.toString();
      debugPrint('[TelegramStatus] Status received - linked: $newLinked, connectedAt: $newConnectedAt');
      
      // اگر skipSetState true باشد، فقط متغیرها را به‌روزرسانی کن بدون setState
      if (skipSetState) {
        debugPrint('[TelegramStatus] skipSetState=true, updating variables without setState');
        debugPrint('[TelegramStatus] Before: _telegramLinked=$_telegramLinked, _telegramConnectedAt=$_telegramConnectedAt');
        _telegramLinked = newLinked;
        _telegramConnectedAt = newConnectedAt;
        debugPrint('[TelegramStatus] After: _telegramLinked=$_telegramLinked, _telegramConnectedAt=$_telegramConnectedAt');
        debugPrint('[TelegramStatus] _telegramLinkToken: ${_telegramLinkToken != null ? "exists" : "null"}, _showLinkSection: $_showLinkSection');
        return;
      }
      
      // فقط اگر مقدار تغییر کرده باشد، setState را صدا بزن
      if (newLinked != _telegramLinked || newConnectedAt != _telegramConnectedAt) {
        debugPrint('[TelegramStatus] Status changed, calling setState');
        debugPrint('[TelegramStatus] Before setState - _telegramLinkToken: ${_telegramLinkToken != null ? "exists" : "null"}, _showLinkSection: $_showLinkSection');
        if (mounted) {
          setState(() {
            _telegramLinked = newLinked;
            _telegramConnectedAt = newConnectedAt;
            if (updateLoading) {
              _telegramLoading = false;
            }
            // مهم: متغیرهای link token و deep link را دست نزن
            // تا بخش QR code باز بماند
          });
          debugPrint('[TelegramStatus] After setState - _telegramLinkToken: ${_telegramLinkToken != null ? "exists" : "null"}, _showLinkSection: $_showLinkSection');
        }
      } else if (updateLoading && mounted) {
        // اگر فقط loading باید تغییر کند
        debugPrint('[TelegramStatus] Only loading changed, calling setState for loading');
        setState(() {
          _telegramLoading = false;
        });
      } else {
        debugPrint('[TelegramStatus] No changes, skipping setState');
      }
    } catch (_) {
      if (!mounted) return;
      if (skipSetState) {
        _telegramLinked = false;
        return;
      }
      final wasLinked = _telegramLinked;
      if (wasLinked || updateLoading) {
        // فقط اگر مقدار تغییر کرده باشد، setState را صدا بزن
        if (mounted) {
          setState(() {
            _telegramLinked = false;
            if (updateLoading) {
              _telegramLoading = false;
            }
            // مهم: متغیرهای link token و deep link را دست نزن
          });
        }
      }
    }
  }

  Future<void> _connectTelegram(AppLocalizations t) async {
    debugPrint('[TelegramConnect] _connectTelegram called');
    try {
      setState(() => _telegramConnecting = true);
      final linkData = await _telegramSvc.createLink();
      debugPrint('[TelegramConnect] Link data received: ${linkData.keys}');
      if (!mounted) {
        debugPrint('[TelegramConnect] Widget not mounted, returning');
        return;
      }
      final expiresAtStr = linkData['expires_at']?.toString();
      DateTime? expiresAt;
      if (expiresAtStr != null) {
        try {
          // زمان از سرور به صورت ISO format می‌آید
          // سرور زمان را به صورت UTC برمی‌گرداند (با isoformat())
          String utcStr = expiresAtStr.trim();
          
          // بررسی کن که آیا Z یا timezone offset دارد یا نه
          final hasZ = utcStr.endsWith('Z');
          final hasTimezoneOffset = RegExp(r'[+-]\d{2}:?\d{2}$').hasMatch(utcStr);
          
          if (!hasZ && !hasTimezoneOffset) {
            // اگر Z ندارد و timezone offset هم ندارد، Z اضافه کن
            // این یعنی سرور زمان را بدون timezone فرستاده و باید آن را UTC در نظر بگیریم
            utcStr = '${utcStr}Z';
            debugPrint('[TelegramConnect] Added Z to expires_at: $utcStr');
          }
          
          // Parse به عنوان UTC
          expiresAt = DateTime.parse(utcStr);
          debugPrint('[TelegramConnect] Parsed expires_at: $expiresAt (isUtc: ${expiresAt.isUtc})');
          
          // اگر هنوز UTC نیست، به UTC تبدیل کن
          if (!expiresAt.isUtc) {
            debugPrint('[TelegramConnect] Converting to UTC');
            expiresAt = expiresAt.toUtc();
          }
          
          // بررسی کن که آیا زمان در آینده است یا نه
          final now = DateTime.now().toUtc();
          final diff = expiresAt.difference(now).inSeconds;
          debugPrint('[TelegramConnect] Expires at: $expiresAt (UTC: ${expiresAt.isUtc})');
          debugPrint('[TelegramConnect] Current time: $now (UTC)');
          debugPrint('[TelegramConnect] Difference: $diff seconds (${diff / 60} minutes)');
          
          if (diff <= 0) {
            debugPrint('[TelegramConnect] WARNING: Expires time is in the past! This should not happen.');
            debugPrint('[TelegramConnect] However, we will still show the QR code.');
          }
        } catch (e) {
          debugPrint('[TelegramConnect] ERROR: Failed to parse expires_at: $expiresAtStr, error: $e');
          expiresAt = null;
        }
      }
      debugPrint('[TelegramConnect] Before setState - _telegramLinkToken: ${_telegramLinkToken != null ? "exists" : "null"}, _showLinkSection: $_showLinkSection');
      setState(() {
        _telegramLinkToken = linkData['link_token']?.toString();
        _telegramDeepLink = linkData['deep_link']?.toString();
        _telegramLinkExpiresAt = expiresAt;
        _showLinkSection = true; // همیشه فعال کردن نمایش بخش QR code
        debugPrint('[TelegramConnect] Inside setState - _telegramLinkToken: ${_telegramLinkToken != null ? "exists" : "null"}, _showLinkSection: $_showLinkSection');
        if (_telegramLinkExpiresAt != null) {
          // محاسبه زمان باقیمانده قبل از شروع تایمر
          final now = DateTime.now().toUtc();
          final expiresAtUtc = _telegramLinkExpiresAt!.isUtc 
              ? _telegramLinkExpiresAt! 
              : _telegramLinkExpiresAt!.toUtc();
          final difference = expiresAtUtc.difference(now);
          _remainingSeconds = difference.inSeconds;
          debugPrint('[TelegramConnect] Time calculation - now: $now, expiresAt: $expiresAtUtc, difference: ${difference.inSeconds} seconds');
          if (_remainingSeconds > 0) {
            _startTimer();
          } else {
            debugPrint('[TelegramConnect] Time already expired or in past, not starting timer but keeping QR section visible');
            // حتی اگر زمان منقضی شده باشد، بخش QR را نمایش بده
            // فقط تایمر را شروع نکن
            _remainingSeconds = 0;
          }
        } else {
          // اگر expires_at وجود نداشت، باز هم بخش را نمایش بده
          _remainingSeconds = 0;
        }
        _telegramConnecting = false;
      });
      debugPrint('[TelegramConnect] After setState - _telegramLinkToken: ${_telegramLinkToken != null ? "exists" : "null"}, _showLinkSection: $_showLinkSection');
      debugPrint('[TelegramConnect] Starting poll');
      _pollTelegramStatus(t);
    } catch (e) {
      debugPrint('[TelegramConnect] Error: $e');
      if (!mounted) return;
      setState(() => _telegramConnecting = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${t.notificationsTelegramConnectionError}\n$e')),
      );
    }
  }

  void _startTimer() {
    debugPrint('[TelegramTimer] _startTimer called');
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        debugPrint('[TelegramTimer] Widget not mounted, canceling timer');
        timer.cancel();
        return;
      }
      _updateRemainingTime();
      debugPrint('[TelegramTimer] Remaining seconds: $_remainingSeconds, _showLinkSection: $_showLinkSection');
      // فقط اگر زمان واقعاً منقضی شده باشد (منفی یا صفر)، بخش را ببند
      if (_remainingSeconds <= 0) {
        debugPrint('[TelegramTimer] Time expired, closing section');
        timer.cancel();
        if (mounted) {
          setState(() {
            debugPrint('[TelegramTimer] Before setState - _telegramLinkToken: ${_telegramLinkToken != null ? "exists" : "null"}, _showLinkSection: $_showLinkSection');
            _telegramLinkToken = null;
            _telegramDeepLink = null;
            _telegramLinkExpiresAt = null;
            _remainingSeconds = 0;
            _showLinkSection = false; // بستن بخش QR code
            debugPrint('[TelegramTimer] After setState - _telegramLinkToken: ${_telegramLinkToken != null ? "exists" : "null"}, _showLinkSection: $_showLinkSection');
          });
        }
      }
    });
  }

  void _updateRemainingTime() {
    if (_telegramLinkExpiresAt != null) {
      // استفاده از UTC برای مقایسه صحیح
      final now = DateTime.now().toUtc();
      final expiresAt = _telegramLinkExpiresAt!.isUtc 
          ? _telegramLinkExpiresAt! 
          : _telegramLinkExpiresAt!.toUtc();
      final difference = expiresAt.difference(now);
      final oldSeconds = _remainingSeconds;
      _remainingSeconds = difference.inSeconds;
      debugPrint('[TelegramTimer] _updateRemainingTime - now: $now, expiresAt: $expiresAt, difference: ${difference.inSeconds} seconds, oldSeconds: $oldSeconds');
      // فقط اگر زمان باقیمانده مثبت باشد، setState را صدا بزن
      if (mounted && _remainingSeconds >= 0) {
        if (oldSeconds != _remainingSeconds) {
          debugPrint('[TelegramTimer] Time updated: $_remainingSeconds seconds remaining');
        }
        setState(() {});
      } else if (_remainingSeconds < 0) {
        debugPrint('[TelegramTimer] Time expired (negative: $_remainingSeconds), not calling setState');
      }
    } else {
      debugPrint('[TelegramTimer] _updateRemainingTime called but _telegramLinkExpiresAt is null');
    }
  }

  Future<void> _pollTelegramStatus(AppLocalizations t) async {
    debugPrint('[TelegramPoll] _pollTelegramStatus called - _isPolling: $_isPolling');
    if (_isPolling) {
      debugPrint('[TelegramPoll] Already polling, returning');
      return; // جلوگیری از polling همزمان
    }
    _isPolling = true;
    debugPrint('[TelegramPoll] Starting poll - _telegramLinkToken: ${_telegramLinkToken != null ? "exists" : "null"}, _showLinkSection: $_showLinkSection');
    int attempts = 0;
    const maxAttempts = 120;
    try {
      while (attempts < maxAttempts && mounted) {
        await Future.delayed(const Duration(seconds: 5));
        debugPrint('[TelegramPoll] Poll attempt ${attempts + 1}/$maxAttempts');
        debugPrint('[TelegramPoll] Before _loadTelegramStatus - _telegramLinkToken: ${_telegramLinkToken != null ? "exists" : "null"}, _showLinkSection: $_showLinkSection');
        // استفاده از skipSetState=true تا کاملاً از rebuild جلوگیری شود
        await _loadTelegramStatus(updateLoading: false, skipSetState: true);
        debugPrint('[TelegramPoll] After _loadTelegramStatus - _telegramLinkToken: ${_telegramLinkToken != null ? "exists" : "null"}, _showLinkSection: $_showLinkSection, _telegramLinked: $_telegramLinked');
        if (_telegramLinked) {
          debugPrint('[TelegramPoll] Telegram linked! Closing section');
          _timer?.cancel();
          if (mounted) {
            setState(() {
              _telegramLinkToken = null;
              _telegramDeepLink = null;
              _telegramLinkExpiresAt = null;
              _remainingSeconds = 0;
              _isPolling = false;
              _showLinkSection = false; // بستن بخش QR code
            });
          }
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text(t.notificationsTelegramConnectionSuccess)),
            );
          }
          break;
        }
        attempts++;
      }
      // فقط اگر بعد از تمام تلاش‌ها هنوز متصل نشده باشد، بخش را ببند
      if (!_telegramLinked && mounted && _showLinkSection) {
        // بررسی کن که آیا زمان انقضا گذشته یا نه
        if (_telegramLinkExpiresAt != null) {
          final now = DateTime.now().toUtc();
          final expiresAt = _telegramLinkExpiresAt!.isUtc 
              ? _telegramLinkExpiresAt! 
              : _telegramLinkExpiresAt!.toUtc();
          final difference = expiresAt.difference(now);
          // فقط اگر زمان واقعاً منقضی شده باشد، بخش را ببند
          if (difference.inSeconds <= 0) {
            _timer?.cancel();
            if (mounted) {
              setState(() {
                _telegramLinkToken = null;
                _telegramDeepLink = null;
                _telegramLinkExpiresAt = null;
                _remainingSeconds = 0;
                _isPolling = false;
                _showLinkSection = false; // بستن بخش QR code
              });
            }
          } else {
            // اگر زمان هنوز باقی مانده، فقط flag را reset کن
            if (mounted) {
              setState(() {
                _isPolling = false;
              });
            }
          }
        } else {
          // اگر expires_at وجود نداشت، فقط flag را reset کن
          if (mounted) {
            setState(() {
              _isPolling = false;
            });
          }
        }
      } else if (mounted) {
        setState(() {
          _isPolling = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isPolling = false;
        });
      }
    }
  }

  Future<void> _disconnectTelegram(AppLocalizations t) async {
    try {
      setState(() => _telegramLoading = true);
      await _telegramSvc.unlink();
      if (!mounted) return;
      setState(() {
        _telegramLinked = false;
        _telegramConnectedAt = null;
        _telegramLoading = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(t.notificationsTelegramDisconnectSuccess)),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _telegramLoading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${t.notificationsTelegramDisconnectError}\n$e')),
      );
    }
  }

  Future<void> _save(AppLocalizations t) async {
    setState(() => _saving = true);
    try {
      await _svc.updateSettings(
        telegramEnabled: _telegram,
        emailEnabled: _email,
        smsEnabled: _sms,
        inappEnabled: _inapp,
      );
      if (!mounted) return;
      SnackBarHelper.show(context, message: t.notificationsSaveSuccess);
    } catch (e) {
      if (!mounted) return;
      SnackBarHelper.showError(context, message: '${t.notificationsSaveError}\n$e');
    } finally {
      if (!mounted) return;
      setState(() => _saving = false);
    }
  }


  Future<void> _copyToClipboard(String value, String confirmationMessage) async {
    await Clipboard.setData(ClipboardData(text: value));
    if (!mounted) return;
    SnackBarHelper.show(context, message: confirmationMessage);
  }

  String _formatRemainingTime(int seconds) {
    if (seconds <= 0) return 'منقضی شده';
    final minutes = seconds ~/ 60;
    final remainingSecs = seconds % 60;
    if (minutes > 0) {
      return '${minutes} دقیقه و ${remainingSecs} ثانیه باقیمانده';
    } else {
      return '${remainingSecs} ثانیه باقیمانده';
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final t = AppLocalizations.of(context);

    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline, size: 56),
            const SizedBox(height: 8),
            Text('${t.dataLoadingError}\n$_error', textAlign: TextAlign.center),
            const SizedBox(height: 8),
            OutlinedButton(onPressed: _load, child: Text(t.retry)),
          ],
        ),
      );
    }

    final channelOptions = <_ChannelOption>[
      _ChannelOption(
        key: 'telegram',
        enabled: _telegram,
        icon: Icons.telegram,
        title: t.notificationsChannelTelegram,
        description: t.notificationsChannelTelegramDescription,
        onChanged: (v) => setState(() => _telegram = v),
      ),
      _ChannelOption(
        key: 'email',
        enabled: _email,
        icon: Icons.email_outlined,
        title: t.notificationsChannelEmail,
        description: t.notificationsChannelEmailDescription,
        onChanged: (v) => setState(() => _email = v),
      ),
      _ChannelOption(
        key: 'sms',
        enabled: _sms,
        icon: Icons.sms_outlined,
        title: t.notificationsChannelSms,
        description: t.notificationsChannelSmsDescription,
        onChanged: (v) => setState(() => _sms = v),
      ),
      _ChannelOption(
        key: 'inapp',
        enabled: _inapp,
        icon: Icons.notifications_active_outlined,
        title: t.notificationsChannelInApp,
        description: t.notificationsChannelInAppDescription,
        onChanged: (v) => setState(() => _inapp = v),
      ),
    ];

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildHeader(t, theme, colorScheme),
          const SizedBox(height: 16),
          _buildChannelsCard(t, theme, colorScheme, channelOptions),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  Widget _buildHeader(AppLocalizations t, ThemeData theme, ColorScheme colorScheme) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                t.notificationsSettingsTitle,
                style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 4),
              Text(
                t.notificationsSettingsSubtitle,
                style: theme.textTheme.bodyMedium?.copyWith(color: colorScheme.onSurfaceVariant),
              ),
            ],
          ),
        ),
        const SizedBox(width: 16),
        FilledButton.icon(
          onPressed: _saving ? null : () => _save(t),
          icon: _saving
              ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
              : const Icon(Icons.save_outlined),
          label: Text(t.save),
        ),
      ],
    );
  }

  Widget _buildChannelsCard(AppLocalizations t, ThemeData theme, ColorScheme colorScheme, List<_ChannelOption> options) {
    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(t.notificationsChannelsSectionTitle, style: theme.textTheme.titleMedium),
                const SizedBox(height: 4),
                Text(
                  t.notificationsChannelsSectionSubtitle,
                  style: theme.textTheme.bodySmall?.copyWith(color: colorScheme.onSurfaceVariant),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          for (var i = 0; i < options.length; i++) ...[
            if (options[i].key == 'telegram') ...[
              _buildTelegramChannelTile(t, theme, colorScheme, options[i]),
            ] else ...[
              SwitchListTile.adaptive(
                value: options[i].enabled,
                onChanged: options[i].onChanged,
                title: Text(options[i].title),
                subtitle: Text(options[i].description),
                secondary: Icon(
                  options[i].icon,
                  color: options[i].enabled ? colorScheme.primary : colorScheme.onSurfaceVariant,
                ),
                activeColor: colorScheme.primary,
                contentPadding: const EdgeInsets.symmetric(horizontal: 16),
              ),
            ],
            if (i != options.length - 1) const Divider(height: 1),
          ],
          const SizedBox(height: 8),
        ],
      ),
    );
  }

  Widget _buildTelegramChannelTile(AppLocalizations t, ThemeData theme, ColorScheme colorScheme, _ChannelOption option) {
    debugPrint('[TelegramUI] _buildTelegramChannelTile called - _telegramLinkToken: ${_telegramLinkToken != null ? "exists" : "null"}, _showLinkSection: $_showLinkSection');
    return Column(
      children: [
        SwitchListTile.adaptive(
          value: option.enabled,
          onChanged: option.onChanged,
          title: Text(option.title),
          subtitle: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(option.description),
              const SizedBox(height: 8),
              Row(
                children: [
                  Icon(
                    _telegramLinked ? Icons.check_circle : Icons.cancel,
                    size: 16,
                    color: _telegramLinked ? Colors.green : Colors.red,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    _telegramLinked ? t.notificationsTelegramConnected : t.notificationsTelegramNotConnected,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: _telegramLinked ? Colors.green : Colors.red,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  if (_telegramLinked && _telegramConnectedAt != null) ...[
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        t.notificationsTelegramConnectedSince(
                          HesabixDateUtils.formatForDisplay(
                            DateTime.tryParse(_telegramConnectedAt!),
                            widget.calendarController.isJalali,
                          ),
                        ),
                        style: theme.textTheme.bodySmall?.copyWith(color: colorScheme.onSurfaceVariant),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ],
              ),
              if (option.enabled && !_telegramLinked) ...[
                const SizedBox(height: 4),
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.orange.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.orange.withValues(alpha: 0.3)),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.warning_amber_rounded, size: 16, color: Colors.orange),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          t.notificationsTelegramConnectionWarning,
                          style: theme.textTheme.bodySmall?.copyWith(color: Colors.orange.shade700),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
          secondary: Icon(
            option.icon,
            color: option.enabled ? colorScheme.primary : colorScheme.onSurfaceVariant,
          ),
          activeColor: colorScheme.primary,
          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            children: [
              if (_telegramLinked) ...[
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _telegramLoading ? null : () => _disconnectTelegram(t),
                    icon: _telegramLoading
                        ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                        : const Icon(Icons.link_off, size: 18),
                    label: Text(t.notificationsTelegramDisconnectButton),
                  ),
                ),
              ] else ...[
                Expanded(
                  child: FilledButton.icon(
                    onPressed: (_telegramConnecting || _telegramLoading) ? null : () => _connectTelegram(t),
                    icon: _telegramConnecting || _telegramLoading
                        ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                        : const Icon(Icons.link, size: 18),
                    label: Text(_telegramConnecting ? t.notificationsTelegramConnecting : t.notificationsTelegramConnectButton),
                  ),
                ),
              ],
            ],
          ),
        ),
        Builder(
          builder: (context) {
            debugPrint('[TelegramUI] Checking QR section condition - _showLinkSection: $_showLinkSection, _telegramLinkToken: ${_telegramLinkToken != null ? "exists" : "null"}');
            if (_showLinkSection && _telegramLinkToken != null) {
              debugPrint('[TelegramUI] Building QR section');
              return Column(
                children: [
                  const SizedBox(height: 8),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.4),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: colorScheme.outline.withValues(alpha: 0.2)),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            t.notificationsTelegramLinkInstructions(_telegramLinkToken!),
                            style: theme.textTheme.bodySmall,
                          ),
                          if (_telegramDeepLink != null) ...[
                            const SizedBox(height: 12),
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                // QR Code
                                Container(
                                  padding: const EdgeInsets.all(8),
                                  decoration: BoxDecoration(
                                    color: Colors.white,
                                    borderRadius: BorderRadius.circular(8),
                                    border: Border.all(color: colorScheme.outline.withValues(alpha: 0.2)),
                                  ),
                                  child: QrImageView(
                                    data: _telegramDeepLink!,
                                    version: QrVersions.auto,
                                    size: 120,
                                    backgroundColor: Colors.white,
                                  ),
                                ),
                                const SizedBox(width: 12),
                                // Link and copy button
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        t.copyLink,
                                        style: theme.textTheme.bodySmall?.copyWith(
                                          fontWeight: FontWeight.w500,
                                          color: colorScheme.onSurfaceVariant,
                                        ),
                                      ),
                                      const SizedBox(height: 4),
                                      SelectableText(
                                        _telegramDeepLink!,
                                        style: theme.textTheme.bodySmall?.copyWith(
                                          fontFamily: 'monospace',
                                          color: colorScheme.primary,
                                        ),
                                      ),
                                      const SizedBox(height: 8),
                                      OutlinedButton.icon(
                                        onPressed: () => _copyToClipboard(_telegramDeepLink!, t.copied),
                                        icon: const Icon(Icons.copy_all_outlined, size: 16),
                                        label: Text(t.copyLink),
                                        style: OutlinedButton.styleFrom(
                                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ],
                          if (_telegramLinkExpiresAt != null) ...[
                            const SizedBox(height: 12),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                              decoration: BoxDecoration(
                                color: _remainingSeconds <= 0
                                    ? Colors.orange.withValues(alpha: 0.1)
                                    : (_remainingSeconds < 60 
                                        ? Colors.red.withValues(alpha: 0.1)
                                        : colorScheme.primaryContainer.withValues(alpha: 0.3)),
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(
                                  color: _remainingSeconds <= 0
                                      ? Colors.orange.withValues(alpha: 0.3)
                                      : (_remainingSeconds < 60 
                                          ? Colors.red.withValues(alpha: 0.3)
                                          : colorScheme.primary.withValues(alpha: 0.3)),
                                ),
                              ),
                              child: Row(
                                children: [
                                  Icon(
                                    _remainingSeconds <= 0 ? Icons.warning_amber_rounded : Icons.timer_outlined,
                                    size: 16,
                                    color: _remainingSeconds <= 0
                                        ? Colors.orange
                                        : (_remainingSeconds < 60 
                                            ? Colors.red
                                            : colorScheme.primary),
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      _remainingSeconds <= 0 
                                          ? t.notificationsTelegramLinkExpired
                                          : _formatRemainingTime(_remainingSeconds),
                                      style: theme.textTheme.bodySmall?.copyWith(
                                        color: _remainingSeconds <= 0
                                            ? Colors.orange.shade700
                                            : (_remainingSeconds < 60 
                                                ? Colors.red.shade700
                                                : colorScheme.onPrimaryContainer),
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                ],
              );
            } else {
              debugPrint('[TelegramUI] QR section NOT shown - _showLinkSection: $_showLinkSection, _telegramLinkToken: ${_telegramLinkToken != null ? "exists" : "null"}');
              return const SizedBox.shrink();
            }
          },
        ),
      ],
    );
  }
}

