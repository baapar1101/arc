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

const distributionNoOrderCodes = ['closed', 'no_need', 'competitor', 'credit', 'no_decision', 'other'];
const distributionReturnCodes = ['expired', 'damaged', 'commercial', 'wrong_item', 'near_expiry', 'other'];
const distributionFailCodes = ['closed', 'refused', 'address', 'shortage', 'other'];
