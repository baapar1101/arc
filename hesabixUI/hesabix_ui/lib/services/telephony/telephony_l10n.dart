import 'package:flutter/widgets.dart';

import '../../core/api_client.dart';
import '../../l10n/app_localizations.dart';
import 'softphone_engine.dart';

AppLocalizations telephonyL10n([BuildContext? context]) {
  if (context != null) {
    return AppLocalizations.of(context);
  }
  final loc = ApiClient.currentLocale;
  if (loc != null) return lookupAppLocalizations(loc);
  return lookupAppLocalizations(const Locale('fa'));
}

String telephonyCallStatusLabel(AppLocalizations t, String? status) {
  switch ((status ?? '').toLowerCase()) {
    case 'missed':
      return t.telephonyStatusMissed;
    case 'completed':
      return t.telephonyStatusCompleted;
    case 'answered':
      return t.telephonyStatusAnswered;
    case 'ringing':
      return t.telephonyStatusRinging;
    case 'busy':
      return t.telephonyStatusBusy;
    case 'failed':
      return t.telephonyStatusFailed;
    case 'active':
      return t.telephonyStatusActive;
    default:
      return (status ?? '').isEmpty ? '—' : status!;
  }
}

String telephonyPresenceLabel(AppLocalizations t, String? presence) {
  switch ((presence ?? '').toLowerCase()) {
    case 'ringing':
      return t.telephonyPresenceRinging;
    case 'talking':
    case 'in_call':
      return t.telephonyPresenceTalking;
    case 'offline':
      return t.telephonyPresenceOffline;
    case 'no_extension':
      return t.telephonyPresenceNoExt;
    case 'idle':
      return t.telephonyPresenceIdle;
    default:
      return t.telephonyPresenceUnknown;
  }
}

String telephonyConnectionStateLabel(AppLocalizations t, SoftphoneConnectionState state) {
  switch (state) {
    case SoftphoneConnectionState.idle:
      return t.telephonyConnIdle;
    case SoftphoneConnectionState.connecting:
      return t.telephonyConnConnecting;
    case SoftphoneConnectionState.registered:
      return t.telephonyConnRegistered;
    case SoftphoneConnectionState.ringing:
      return t.telephonyConnRinging;
    case SoftphoneConnectionState.inCall:
      return t.telephonyConnInCall;
    case SoftphoneConnectionState.reconnecting:
      return t.telephonyConnReconnecting;
    case SoftphoneConnectionState.error:
      return t.telephonyConnError;
    case SoftphoneConnectionState.ended:
      return t.telephonyConnEnded;
  }
}

String telephonyScreenPopStatusLabel(AppLocalizations t, String? status) {
  switch ((status ?? '').toLowerCase()) {
    case 'ringing':
      return t.telephonyIncomingCall;
    case 'answered':
    case 'up':
      return t.telephonyInConversation;
    case 'completed':
    case 'hangup':
      return t.telephonyCallEnded;
    case 'missed':
      return t.telephonyCallMissed;
    default:
      return t.telephonyActiveCall;
  }
}

String telephonyCategoryLabel(AppLocalizations t, String? code) {
  switch ((code ?? '').toLowerCase()) {
    case 'sales':
      return t.telephonyCategorySales;
    case 'support':
      return t.telephonyCategorySupport;
    case 'finance':
      return t.telephonyCategoryFinance;
    default:
      return t.telephonyCategoryOther;
  }
}

String telephonyOutcomeLabel(AppLocalizations t, String? code) {
  switch ((code ?? '').toLowerCase()) {
    case 'completed':
      return t.telephonyOutcomeCompleted;
    case 'callback':
      return t.telephonyOutcomeCallback;
    case 'no_answer':
      return t.telephonyOutcomeNoAnswer;
    case 'wrong_number':
      return t.telephonyOutcomeWrongNumber;
    default:
      return t.telephonyCategoryOther;
  }
}

String telephonyRecordingAccessLabel(AppLocalizations t, String? mode) {
  switch ((mode ?? '').trim()) {
    case 'all_operators':
      return t.telephonyRecordingAccessAllOperatorsHint;
    case 'owner_and_managers':
      return t.telephonyRecordingAccessOwnerHint;
    default:
      return t.telephonyRecordingAccessPermissionHint;
  }
}
