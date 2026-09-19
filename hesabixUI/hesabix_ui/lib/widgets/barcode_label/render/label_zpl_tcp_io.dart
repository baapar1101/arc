import 'dart:convert';
import 'dart:io';

Future<void> sendZplOverTcp({
  required String host,
  required int port,
  required String zpl,
}) async {
  final socket = await Socket.connect(host, port, timeout: const Duration(seconds: 8));
  try {
    socket.add(utf8.encode(zpl));
    await socket.flush();
  } finally {
    await socket.close();
  }
}
