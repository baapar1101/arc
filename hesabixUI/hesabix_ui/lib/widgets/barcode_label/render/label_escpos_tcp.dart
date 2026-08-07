import 'label_escpos_tcp_stub.dart'
    if (dart.library.io) 'label_escpos_tcp_io.dart' as impl;

Future<void> sendEscPosOverTcp({
  required String host,
  required int port,
  required List<int> data,
}) {
  return impl.sendEscPosOverTcp(host: host, port: port, data: data);
}
