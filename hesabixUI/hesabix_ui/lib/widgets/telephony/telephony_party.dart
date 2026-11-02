/// نمایش نام شخص/سرنخ در کنار شماره تماس.
String telephonyPeerNumber(Map<String, dynamic> call) {
  final dir = '${call['direction'] ?? ''}';
  final inbound = dir == 'inbound';
  final raw = inbound
      ? (call['from_number_normalized'] ?? call['from_number_raw'] ?? call['from'] ?? call['peer_number'])
      : (call['to_number_normalized'] ?? call['to_number_raw'] ?? call['peer_number'] ?? call['from']);
  final s = '$raw'.trim();
  if (s.isEmpty || s == 'null') return '';
  return s;
}

String? telephonyPartyName(Map<String, dynamic> call) {
  if (call['ambiguous'] == true) return null;
  for (final key in ['party_name', 'person_name', 'lead_name']) {
    final v = '${call[key] ?? ''}'.trim();
    if (v.isNotEmpty && v != 'null') return v;
  }
  final person = call['person'];
  if (person is Map) {
    final v = '${person['name'] ?? ''}'.trim();
    if (v.isNotEmpty && v != 'null') return v;
  }
  final lead = call['lead'];
  if (lead is Map) {
    final v = '${lead['name'] ?? ''}'.trim();
    if (v.isNotEmpty && v != 'null') return v;
  }
  return null;
}

String telephonyPartyTitle(Map<String, dynamic> call, {required String unknownLabel, String? ambiguousLabel}) {
  if (call['ambiguous'] == true) {
    final label = (ambiguousLabel ?? '').trim();
    if (label.isNotEmpty) return label;
  }
  final name = telephonyPartyName(call);
  if (name != null && name.isNotEmpty) return name;
  final peer = telephonyPeerNumber(call);
  return peer.isEmpty ? unknownLabel : peer;
}

String? telephonyPartySubtitle(Map<String, dynamic> call) {
  final name = telephonyPartyName(call);
  final peer = telephonyPeerNumber(call);
  if (name != null && name.isNotEmpty && peer.isNotEmpty && peer != name) return peer;
  if (call['ambiguous'] == true && peer.isNotEmpty) return peer;
  return null;
}
