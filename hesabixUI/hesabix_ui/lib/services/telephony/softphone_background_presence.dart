// Helpers for Softphone background presence (Android FGS heartbeat + Windows tray).

enum WindowsCloseDecision { hideToTray, confirmExit }

WindowsCloseDecision windowsCloseDecision({required bool softphoneWantsPresence}) {
  return softphoneWantsPresence ? WindowsCloseDecision.hideToTray : WindowsCloseDecision.confirmExit;
}

bool isSoftphoneSessionGoneCode(String? code) {
  return code == 'SOFTPHONE_SESSION_ENDED' || code == 'SOFTPHONE_NO_SESSION';
}

bool isSoftphoneSessionGoneStatus(int statusCode) {
  return statusCode == 404 || statusCode == 409 || statusCode == 410;
}

bool isSoftphoneSessionGone({required int statusCode, Map<String, dynamic>? body}) {
  if (isSoftphoneSessionGoneStatus(statusCode)) return true;
  final error = body?['error'];
  if (error is Map) {
    return isSoftphoneSessionGoneCode('${error['code'] ?? ''}');
  }
  return false;
}

Map<String, dynamic>? unwrapSoftphoneApiData(Object? body) {
  if (body is! Map) return null;
  final map = Map<String, dynamic>.from(body);
  final data = map['data'];
  if (data is Map) return Map<String, dynamic>.from(data);
  if (map.containsKey('session_id') || map.containsKey('session') || map.containsKey('media_ticket')) {
    return map;
  }
  return map['success'] == true ? <String, dynamic>{} : map;
}

String? extractSoftphoneSessionId(Map<String, dynamic> data) {
  final session = data['session'];
  if (session is Map) {
    final sid = '${session['session_id'] ?? ''}'.trim();
    if (sid.isNotEmpty) return sid;
  }
  final sid = '${data['session_id'] ?? ''}'.trim();
  return sid.isEmpty ? null : sid;
}

String? extractSoftphoneMediaTicket(Map<String, dynamic> data) {
  final ticket = '${data['media_ticket'] ?? ''}'.trim();
  return ticket.isEmpty ? null : ticket;
}
