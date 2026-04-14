// Conditional export of platform-specific implementations
export 'file_saver_io.dart' if (dart.library.html) 'file_saver_web.dart';


