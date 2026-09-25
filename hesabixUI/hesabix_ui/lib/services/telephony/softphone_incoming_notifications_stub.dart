/// No-op softphone incoming call notifications (web / desktop).
const String softphoneActionAnswer = 'softphone_answer';
const String softphoneActionDecline = 'softphone_decline';

class SoftphoneIncomingNotifications {
  Future<void> initialize({
    void Function(Map<String, dynamic> action)? onAction,
  }) async {}

  Future<void> showIncomingCall({
    required String caller,
    required String extension,
    int? callId,
    String? sessionId,
  }) async {}

  Future<void> cancelIncomingCall() async {}

  Future<Map<String, dynamic>?> consumePendingAction() async => null;
}

SoftphoneIncomingNotifications createSoftphoneIncomingNotifications() =>
    SoftphoneIncomingNotifications();

bool get supportsSoftphoneIncomingNotifications => false;
