export 'softphone_ringtone_stub.dart'
    if (dart.library.html) 'softphone_ringtone_web.dart'
    if (dart.library.io) 'softphone_ringtone_io.dart';

import 'softphone_ringtone_stub.dart'
    if (dart.library.html) 'softphone_ringtone_web.dart'
    if (dart.library.io) 'softphone_ringtone_io.dart';

SoftphoneRingtone createSoftphoneRingtone() => createPlatformSoftphoneRingtone();
