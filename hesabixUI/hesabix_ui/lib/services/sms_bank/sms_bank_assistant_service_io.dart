import 'dart:async';
import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

import '../../core/android_sms_bank_platform.dart';
import '../system_notifications/system_notifications_service.dart';
import 'sms_bank_match_policy.dart';
import 'sms_bank_models.dart';
import 'sms_bank_pattern_engine.dart';
import 'sms_bank_seed_patterns.dart';

const _kChannel = 'ir.hsxn.hesabix_ui/sms_bank';
const _kPrefsSettings = 'sms_bank_settings_v1';
const _kPrefsPatterns = 'sms_bank_patterns_v1';
const _kPrefsEvents = 'sms_bank_events_v1';
const _kPrefsFingerprints = 'sms_bank_fingerprints_v1';
const _kPrefsLaunchEvent = 'sms_bank_launch_event_id';

/// Android SMS bank assistant: pattern match, native sync, notifications.
class SmsBankAssistantService {
  SmsBankAssistantService();

  static const _uuid = Uuid();
  final MethodChannel _channel = const MethodChannel(_kChannel);
  final SystemNotificationsService _notifications = createSystemNotificationsService();

  void Function(SmsBankEvent event)? _onEvent;
  bool _initialized = false;
  String? _launchEventId;

  Future<void> initialize({
    void Function(SmsBankEvent event)? onEvent,
  }) async {
    if (!supportsAndroidSmsBankAssistant) return;
    _onEvent = onEvent;
    if (_initialized) return;

    _channel.setMethodCallHandler(_onNativeCall);
    await _ensureSeedPatterns();
    await syncNativeConfig();
    await _notifications.initialize();

    try {
      final launch = await _channel.invokeMethod<String>('getLaunchEventId');
      if (launch != null && launch.isNotEmpty) {
        _launchEventId = launch;
      }
    } catch (_) {}

    _initialized = true;
  }

  void setOnEvent(void Function(SmsBankEvent event)? onEvent) {
    _onEvent = onEvent;
  }

  Future<dynamic> _onNativeCall(MethodCall call) async {
    switch (call.method) {
      case 'onSmsReceived':
        final args = Map<String, dynamic>.from(call.arguments as Map? ?? {});
        final sender = '${args['sender'] ?? ''}';
        final body = '${args['body'] ?? ''}';
        final ts = args['received_at_ms'];
        final receivedAt = ts is int
            ? DateTime.fromMillisecondsSinceEpoch(ts)
            : DateTime.now();
        // Native may already have matched; prefer provided event JSON if present
        final eventJson = args['event'];
        if (eventJson is Map) {
          final event = SmsBankEvent.fromJson(Map<String, dynamic>.from(eventJson));
          await _persistEvent(event);
          _onEvent?.call(event);
          return true;
        }
        await processIncomingSms(
          sender: sender,
          body: body,
          receivedAt: receivedAt,
          notify: true,
        );
        return true;
      case 'onNotificationAction':
        final args = Map<String, dynamic>.from(call.arguments as Map? ?? {});
        final eventId = '${args['event_id'] ?? ''}';
        final action = '${args['action'] ?? ''}';
        if (action == 'dismiss' && eventId.isNotEmpty) {
          await updateEventStatus(eventId, SmsBankEventStatus.dismissed);
        } else if (eventId.isNotEmpty) {
          _launchEventId = eventId;
          var event = await getEvent(eventId);
          event ??= await takePendingEvent(eventId);
          if (event != null) _onEvent?.call(event);
        }
        return true;
      default:
        return null;
    }
  }

  Future<SmsBankSettings> getSettings() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_kPrefsSettings);
    if (raw == null || raw.isEmpty) return const SmsBankSettings();
    try {
      var settings = SmsBankSettings.fromJson(jsonDecode(raw) as Map<String, dynamic>);
      // Migrate legacy global-enable → per-business enable list.
      if (settings.enabled &&
          settings.enabledBusinessIds.isEmpty &&
          settings.activeBusinessId != null) {
        settings = settings.copyWith(
          enabledBusinessIds: [settings.activeBusinessId!],
        );
        await prefs.setString(_kPrefsSettings, jsonEncode(settings.toJson()));
      }
      return settings;
    } catch (_) {
      return const SmsBankSettings();
    }
  }

  Future<void> saveSettings(SmsBankSettings settings) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kPrefsSettings, jsonEncode(settings.toJson()));
    await syncNativeConfig();
  }

  Future<List<SmsBankPattern>> getPatterns({int? businessId}) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_kPrefsPatterns);
    if (raw == null || raw.isEmpty) return const [];
    try {
      final list = jsonDecode(raw) as List<dynamic>;
      var all = list
          .whereType<Map>()
          .map((e) => SmsBankPattern.fromJson(Map<String, dynamic>.from(e)))
          .toList();
      final migrated = SmsBankSeedPatterns.migrate(all);
      if (!identical(migrated, all)) {
        all = migrated;
        await prefs.setString(
          _kPrefsPatterns,
          jsonEncode(all.map((e) => e.toJson()).toList()),
        );
        // Keep native matcher in sync with tightened seeds.
        unawaited(syncNativeConfig());
      }
      if (businessId == null) return all;
      return all.where((p) => p.businessId == businessId).toList();
    } catch (_) {
      return const [];
    }
  }

  /// Replace all patterns (all businesses). Prefer [savePatternsForBusiness].
  Future<void> savePatterns(List<SmsBankPattern> patterns) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _kPrefsPatterns,
      jsonEncode(patterns.map((e) => e.toJson()).toList()),
    );
    await syncNativeConfig();
  }

  /// Persist patterns for one business without touching other businesses' patterns.
  Future<void> savePatternsForBusiness(int businessId, List<SmsBankPattern> patterns) async {
    final all = await getPatterns();
    final others = all.where((p) => p.businessId != businessId).toList();
    final scoped = patterns
        .map((p) => p.copyWith(businessId: businessId, updatedAt: DateTime.now()))
        .toList();
    await savePatterns([...others, ...scoped]);
  }

  Future<void> ensureSeedPatternsForBusiness({
    required int businessId,
    String? businessName,
  }) async {
    final existing = await getPatterns(businessId: businessId);
    if (existing.isNotEmpty) return;
    final seeds = SmsBankSeedPatterns.build(businessId: businessId)
        .map((p) => p.copyWith(businessName: businessName))
        .toList();
    await savePatternsForBusiness(businessId, seeds);
  }

  Future<void> _ensureSeedPatterns() async {
    // Seeds are created per-business when that business opens settings / enables capture.
    // Do not invent a global orphan seed list here.
  }

  /// Patterns that may participate in background matching.
  Future<List<SmsBankPattern>> getMatchablePatterns(SmsBankSettings settings) async {
    final all = await getPatterns();
    return all.where((p) {
      if (!p.enabled) return false;
      final bid = p.businessId;
      if (bid == null) return false;
      return settings.isBusinessEnabled(bid);
    }).toList();
  }

  Future<void> updateEvent(SmsBankEvent event) async {
    await _persistEvent(event);
    try {
      await _channel.invokeMethod('updateEventStatus', <String, dynamic>{
        'event_id': event.id,
        'status': event.status.wireName,
        'event': event.toJson(),
      });
    } catch (_) {}
  }

  Future<bool> hasSmsPermission() async {
    if (!supportsAndroidSmsBankAssistant) return false;
    final receive = await Permission.sms.status;
    return receive.isGranted;
  }

  Future<bool> ensureSmsPermission({bool requestIfNeeded = true}) async {
    if (!supportsAndroidSmsBankAssistant) return false;
    final status = await Permission.sms.status;
    if (status.isGranted) return true;
    if (!requestIfNeeded) return false;
    if (status.isPermanentlyDenied) return false;
    final result = await Permission.sms.request();
    return result.isGranted;
  }

  Future<void> syncNativeConfig() async {
    if (!supportsAndroidSmsBankAssistant) return;
    final settings = await getSettings();
    // Native needs ALL enabled businesses' patterns to route while Flutter is dead.
    final patterns = await getMatchablePatterns(settings);
    try {
      await _channel.invokeMethod('syncConfig', <String, dynamic>{
        ...settings.toJson(),
        'patterns': patterns.map((e) => e.toJson()).toList(),
      });
    } catch (_) {
      // Native side may be unavailable in tests.
    }
  }

  Future<List<SmsBankEvent>> listEvents() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_kPrefsEvents);
    if (raw == null || raw.isEmpty) return const [];
    try {
      final list = jsonDecode(raw) as List<dynamic>;
      return list
          .whereType<Map>()
          .map((e) => SmsBankEvent.fromJson(Map<String, dynamic>.from(e)))
          .toList()
        ..sort((a, b) => b.receivedAt.compareTo(a.receivedAt));
    } catch (_) {
      return const [];
    }
  }

  Future<void> _saveEvents(List<SmsBankEvent> events) async {
    final prefs = await SharedPreferences.getInstance();
    // Keep last 100
    final trimmed = events.length > 100 ? events.sublist(0, 100) : events;
    await prefs.setString(
      _kPrefsEvents,
      jsonEncode(trimmed.map((e) => e.toJson()).toList()),
    );
  }

  Future<void> _persistEvent(SmsBankEvent event) async {
    final events = await listEvents();
    final idx = events.indexWhere((e) => e.id == event.id || e.fingerprint == event.fingerprint);
    if (idx >= 0) {
      events[idx] = event;
    } else {
      events.insert(0, event);
    }
    await _saveEvents(events);
  }

  Future<List<SmsBankEvent>> drainPendingEvents({bool onlyPending = true}) async {
    // Merge native pending queue
    try {
      final native = await _channel.invokeMethod<List<dynamic>>('drainPendingEvents');
      if (native != null) {
        for (final item in native) {
          if (item is Map) {
            final event = SmsBankEvent.fromJson(Map<String, dynamic>.from(item));
            await _persistEvent(event);
          }
        }
      }
    } catch (_) {}

    final all = await listEvents();
    if (!onlyPending) return all;
    return all.where((e) => e.status == SmsBankEventStatus.pending).toList();
  }

  Future<void> updateEventStatus(String eventId, SmsBankEventStatus status) async {
    final events = await listEvents();
    final idx = events.indexWhere((e) => e.id == eventId);
    if (idx < 0) return;
    events[idx] = events[idx].copyWith(status: status);
    await _saveEvents(events);
    try {
      await _channel.invokeMethod('updateEventStatus', <String, dynamic>{
        'event_id': eventId,
        'status': status.wireName,
      });
    } catch (_) {}
  }

  Future<SmsBankEvent?> getEvent(String id) async {
    final events = await listEvents();
    try {
      return events.firstWhere((e) => e.id == id);
    } catch (_) {
      return null;
    }
  }

  Future<SmsBankMatchResult> testMatch({
    required String body,
    required String sender,
    List<SmsBankPattern>? patterns,
    int? preferredBusinessId,
  }) async {
    final settings = await getSettings();
    final list = patterns ?? await getMatchablePatterns(settings);
    return SmsBankPatternEngine.matchResolved(
      body: body,
      sender: sender,
      patterns: list,
      preferredBusinessId: preferredBusinessId ?? settings.activeBusinessId,
    );
  }

  Future<bool> _isDuplicate(String fingerprint) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getStringList(_kPrefsFingerprints) ?? <String>[];
    if (raw.contains(fingerprint)) return true;
    raw.insert(0, fingerprint);
    if (raw.length > 200) {
      raw.removeRange(200, raw.length);
    }
    await prefs.setStringList(_kPrefsFingerprints, raw);
    return false;
  }

  Future<SmsBankEvent?> processIncomingSms({
    required String sender,
    required String body,
    DateTime? receivedAt,
    bool notify = false,
    int? preferredBusinessId,
  }) async {
    if (!supportsAndroidSmsBankAssistant) return null;
    final settings = await getSettings();
    if (!settings.enabled) return null;

    final when = receivedAt ?? DateTime.now();
    final fp = SmsBankPatternEngine.fingerprint(sender, body, when);
    if (await _isDuplicate(fp)) return null;

    final patterns = await getMatchablePatterns(settings);
    if (patterns.isEmpty) return null;

    final match = SmsBankPatternEngine.matchResolved(
      body: body,
      sender: sender,
      patterns: patterns,
      preferredBusinessId: preferredBusinessId ?? settings.activeBusinessId,
    );
    if (!match.matched || match.amount < settings.minAmount) return null;
    if (match.confidence < SmsBankMatchPolicy.minAcceptConfidence) return null;

    // Never invent a business from activeBusinessId when disambiguation is required.
    final businessId = match.needsBusinessChoice
        ? null
        : (match.businessId ??
            (match.candidates.length == 1
                ? match.candidates.first.businessId
                : null));

    final event = SmsBankEvent(
      id: _uuid.v4(),
      fingerprint: fp,
      sender: sender,
      body: body,
      amount: match.amount,
      direction: match.direction,
      balance: match.balance,
      accountMask: match.accountMask,
      channel: match.channel,
      patternId: match.patternId,
      patternName: match.patternName,
      bankAccountId: match.bankAccountId,
      bankAccountName: match.bankAccountName,
      businessId: businessId,
      businessName: match.businessName,
      receivedAt: when,
      confidence: match.confidence,
      needsBusinessChoice: match.needsBusinessChoice || businessId == null,
      candidates: match.candidates,
    );

    await _persistEvent(event);

    final quiet = settings.isInQuietHours(when);
    if (notify && !quiet) {
      await _showEventNotification(event, settings);
    }

    _onEvent?.call(event);
    return event;
  }

  Future<void> _showEventNotification(SmsBankEvent event, SmsBankSettings settings) async {
    // Prefer native notification (action buttons + works with killed process path).
    try {
      await _channel.invokeMethod('showNotification', event.toJson());
      return;
    } catch (_) {}

    final dirLabel = event.direction == SmsBankDirection.credit
        ? 'واریز'
        : event.direction == SmsBankDirection.debit
            ? 'برداشت'
            : 'تراکنش';
    final amountStr = _formatAmount(event.amount);
    final account = event.bankAccountName ?? event.accountMask ?? event.patternName ?? '';
    final title = event.needsBusinessChoice
        ? 'تراکنش بانکی — انتخاب کسب‌وکار'
        : 'تراکنش بانکی شناسایی شد';
    final bizHint = event.businessName ??
        (event.needsBusinessChoice ? '${event.candidates.length} کسب‌وکار محتمل' : '');
    final body = '$dirLabel $amountStr ریال'
        '${account.isNotEmpty ? ' · $account' : ''}'
        '${bizHint.isNotEmpty ? ' · $bizHint' : ''}';

    await _notifications.showInAppNotification(
      title: title,
      body: body,
      enrichContent: false,
      playSound: settings.vibrate,
      payload: <String, dynamic>{
        'id': event.id.hashCode & 0x7fffffff,
        'title': title,
        'body': body,
        'deep_link': 'hesabix://sms-bank/capture?id=${event.id}',
        'event_key': 'sms_bank_capture',
        'sms_bank_event_id': event.id,
      },
    );
  }

  String _formatAmount(double amount) {
    final s = amount.toStringAsFixed(0);
    final buf = StringBuffer();
    for (var i = 0; i < s.length; i++) {
      final fromEnd = s.length - i;
      buf.write(s[i]);
      if (fromEnd > 1 && fromEnd % 3 == 1) buf.write(',');
    }
    return buf.toString();
  }

  Future<SmsBankEvent?> takePendingEvent(String id) async {
    try {
      final native = await _channel.invokeMethod<dynamic>(
        'takePendingEvent',
        <String, dynamic>{'event_id': id},
      );
      if (native is Map) {
        final event = SmsBankEvent.fromJson(Map<String, dynamic>.from(native));
        await _persistEvent(event);
        return event;
      }
    } catch (_) {}
    return null;
  }

  Future<String?> peekLaunchEventId() async {
    if (_launchEventId != null && _launchEventId!.isNotEmpty) {
      return _launchEventId;
    }
    try {
      final launch = await _channel.invokeMethod<String>('getLaunchEventId');
      if (launch != null && launch.isNotEmpty) {
        _launchEventId = launch;
        return launch;
      }
    } catch (_) {}
    final prefs = await SharedPreferences.getInstance();
    final stored = prefs.getString(_kPrefsLaunchEvent);
    if (stored != null && stored.isNotEmpty) {
      _launchEventId = stored;
      return stored;
    }
    return null;
  }

  Future<void> clearLaunchEventId() async {
    _launchEventId = null;
    try {
      await _channel.invokeMethod('clearLaunchEventId');
    } catch (_) {}
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_kPrefsLaunchEvent);
  }

  Future<String?> consumeLaunchEventId() async {
    final id = await peekLaunchEventId();
    await clearLaunchEventId();
    return id;
  }
}

SmsBankAssistantService createSmsBankAssistantService() => SmsBankAssistantService();
