/// با `dart.library.io` پیاده‌سازی واقعی؛ روی وب صرفاً No-op.
export 'crm_operator_voice_api.dart';
export 'crm_operator_voice_stub.dart'
    if (dart.library.io) 'crm_operator_voice_io.dart';
