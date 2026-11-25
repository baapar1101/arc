import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:hesabix_ui/l10n/app_localizations.dart';
import 'package:hesabix_ui/widgets/barcode/mobile_barcode_scan_screen.dart';
import 'package:hesabix_ui/widgets/barcode/web_barcode_scan_screen.dart';

Future<String?> scanDistributionBarcode(BuildContext context) async {
  if (kIsWeb) {
    return Navigator.of(context).push<String>(
      MaterialPageRoute<String>(
        builder: (_) => const WebBarcodeScanScreen(),
        fullscreenDialog: true,
      ),
    );
  }
  return Navigator.of(context).push<String>(
    MaterialPageRoute<String>(
      builder: (_) => const MobileBarcodeScanScreen(),
      fullscreenDialog: true,
    ),
  );
}

String distributionNoOrderReasonLabel(AppLocalizations t, String code) {
  switch (code) {
    case 'closed':
      return t.distributionReasonClosed;
    case 'no_need':
      return t.distributionReasonNoNeed;
    case 'competitor':
      return t.distributionReasonCompetitor;
    case 'credit':
      return t.distributionReasonCredit;
    case 'no_decision':
      return t.distributionReasonNoDecision;
    default:
      return t.distributionReasonOther;
  }
}

String distributionReturnReasonLabel(AppLocalizations t, String code) {
  switch (code) {
    case 'expired':
      return t.distributionReturnExpired;
    case 'damaged':
      return t.distributionReturnDamaged;
    case 'commercial':
      return t.distributionReturnCommercial;
    case 'wrong_item':
      return t.distributionReturnWrong;
    case 'near_expiry':
      return t.distributionReturnNearExpiry;
    default:
      return t.distributionReasonOther;
  }
}

String distributionFrequencyLabel(AppLocalizations t, String? freq) {
  switch (freq) {
    case 'biweekly':
      return t.distributionFrequencyBiweekly;
    case 'monthly':
      return t.distributionFrequencyMonthly;
    default:
      return t.distributionFrequencyWeekly;
  }
}

String distributionClassLabel(AppLocalizations t, String? cls) {
  switch (cls) {
    case 'A':
      return t.distributionClassA;
    case 'B':
      return t.distributionClassB;
    case 'C':
      return t.distributionClassC;
    default:
      return cls ?? '—';
  }
}

String distributionFailReasonLabel(AppLocalizations t, String code) {
  switch (code) {
    case 'closed':
      return t.distributionReasonClosed;
    case 'refused':
      return t.distributionFailRefused;
    case 'address':
      return t.distributionFailAddress;
    case 'shortage':
      return t.distributionFailShortage;
    default:
      return t.distributionReasonOther;
  }
}

String distributionIsoDate(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

DateTime? distributionParseDt(dynamic s) {
  if (s == null) return null;
  try {
    return DateTime.parse(s.toString());
  } catch (_) {
    return null;
  }
}

const distributionWeekdayLabelsFa = ['دوشنبه', 'سه‌شنبه', 'چهارشنبه', 'پنجشنبه', 'جمعه', 'شنبه', 'یکشنبه'];
const distributionWeekdayLabelsEn = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

String distributionWeekdayLabel(AppLocalizations t, int? wd) {
  if (wd == null) return t.distributionWeekdayAny;
  final labels = t.localeName.startsWith('fa') ? distributionWeekdayLabelsFa : distributionWeekdayLabelsEn;
  if (wd >= 0 && wd < labels.length) return labels[wd];
  return '$wd';
}

/// وضعیت توقف نسبت به ویزیت‌های همان روز: done | current | pending
String distributionPlanStopKind({
  required int? personId,
  required DateTime planDay,
  Map<String, dynamic>? activeVisit,
  List<dynamic> visitItems = const [],
}) {
  if (personId == null) return 'pending';
  final activePid = int.tryParse('${activeVisit?['person_id']}');
  if (activePid != null && activePid == personId) return 'current';
  final today = DateTime(planDay.year, planDay.month, planDay.day);
  for (final raw in visitItems) {
    final v = Map<String, dynamic>.from(raw as Map);
    if (v['status'] != 'completed') continue;
    if (int.tryParse('${v['person_id']}') != personId) continue;
    final started = distributionParseDt(v['started_at']) ?? distributionParseDt(v['ended_at']);
    if (started == null) continue;
    final d = DateTime(started.year, started.month, started.day);
    if (d == today) return 'done';
  }
  return 'pending';
}

const distributionNoOrderCodes = ['closed', 'no_need', 'competitor', 'credit', 'no_decision', 'other'];
const distributionReturnCodes = ['expired', 'damaged', 'commercial', 'wrong_item', 'near_expiry', 'other'];
const distributionFailCodes = ['closed', 'refused', 'address', 'shortage', 'other'];
