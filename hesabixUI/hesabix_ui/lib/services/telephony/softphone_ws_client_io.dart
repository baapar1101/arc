import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import '../../config/app_config.dart';
import 'softphone_ws_client_stub.dart';

export 'softphone_ws_client_stub.dart';

class IoSoftphoneWsClient implements SoftphoneWsClient {
  WebSocket? _socket;
  bool _connected = false;
  void Function(Map<String, dynamic>)? _onJson;
  void Function(List<int>, String)? _onPcm;

  @override
  bool get isConnected => _connected && _socket != null;

  @override
  void connect({
    required String apiKey,
    required int businessId,
    required String sessionId,
    required String mediaTicket,
    void Function(Map<String, dynamic> msg)? onJson,
    void Function(List<int> pcm, String sessionId)? onPcm,
    void Function(Object error)? onError,
    void Function()? onDone,
  }) async {
    _onJson = onJson;
    _onPcm = onPcm;
    try {
      await _socket?.close();
    } catch (_) {}
    _socket = null;
    _connected = false;
    final apiBase = AppConfig.apiBaseUrl.replaceAll(RegExp(r'/+$'), '');
    final wsBase = apiBase.startsWith('https://')
        ? apiBase.replaceFirst('https://', 'wss://')
        : apiBase.replaceFirst('http://', 'ws://');
    final url = '$wsBase/ws/telephony/softphone';
    try {
      _socket = await WebSocket.connect(url);
      _socket!.add(jsonEncode({
        'type': 'auth',
        'api_key': apiKey,
        'business_id': businessId,
        'session_id': sessionId,
        'media_ticket': mediaTicket,
      }));
      _socket!.listen((dynamic data) {
        if (data is List<int>) {
          _handleBinary(Uint8List.fromList(data));
          return;
        }
        if (data is String) {
          try {
            final msg = jsonDecode(data) as Map<String, dynamic>;
            final type = '${msg['type'] ?? ''}';
            if (type == 'auth_ok') _connected = true;
            _onJson?.call(msg);
          } catch (_) {}
        }
      }, onDone: () {
        _connected = false;
        _socket = null;
        onDone?.call();
      }, onError: (Object e) {
        _connected = false;
        onError?.call(e);
      });
    } catch (e) {
      _connected = false;
      onError?.call(e);
    }
  }

  void _handleBinary(Uint8List blob) {
    if (blob.length < 44) return;
    if (blob[0] != 0x48 || blob[1] != 0x53 || blob[2] != 0x58 || blob[3] != 0x4D) return;
    final pcmLen = (blob[6] << 8) | blob[7];
    final sid = String.fromCharCodes(blob.sublist(8, 44)).trim();
    final end = 44 + pcmLen;
    if (blob.length < end) return;
    _onPcm?.call(blob.sublist(44, end), sid);
  }

  @override
  void sendJson(Map<String, dynamic> msg) {
    try {
      _socket?.add(jsonEncode(msg));
    } catch (_) {}
  }

  @override
  void sendPcm(String sessionId, List<int> pcm) {
    final sid = utf8.encode(sessionId.padRight(36).substring(0, 36));
    final header = BytesBuilder();
    header.add([0x48, 0x53, 0x58, 0x4D, 1, 0]);
    header.add([(pcm.length >> 8) & 0xFF, pcm.length & 0xFF]);
    header.add(sid);
    header.add(pcm);
    try {
      _socket?.add(header.toBytes());
    } catch (_) {}
  }

  @override
  void disconnect() {
    _connected = false;
    try {
      _socket?.close();
    } catch (_) {}
    _socket = null;
  }
}

SoftphoneWsClient createSoftphoneWsClient() => IoSoftphoneWsClient();
