export 'bytes_export_impl_stub.dart'
    if (dart.library.js_interop) 'bytes_export_impl_web.dart'
    if (dart.library.io) 'bytes_export_impl_io.dart';
