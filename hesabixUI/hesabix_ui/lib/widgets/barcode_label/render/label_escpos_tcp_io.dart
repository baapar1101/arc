import 'dart:io';
import 'dart:typed_data';

Future<void> sendEscPosOverTcp({
  required String host,
  required int port,
  required List<int> data,
}) async {
  final socket = await Socket.connect(host, port, timeout: const Duration(seconds: 8));
  try {
    socket.add(Uint8List.fromList(data));
    await socket.flush();
  } finally {
    await socket.close();
  }
}
