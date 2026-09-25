import 'label_zpl_tcp_stub.dart'
    if (dart.library.io) 'label_zpl_tcp_io.dart' as impl;

/// ارسال خام ZPL به چاپگر شبکه‌ای (TCP). روی وب پشتیبانی نمی‌شود.
Future<void> sendZplOverTcp({
  required String host,
  required int port,
  required String zpl,
}) {
  return impl.sendZplOverTcp(host: host, port: port, zpl: zpl);
}
