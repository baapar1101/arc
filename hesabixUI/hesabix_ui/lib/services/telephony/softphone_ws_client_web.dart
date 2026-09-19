import 'dart:async';
import 'dart:convert';
import 'dart:js_interop';
import 'dart:typed_data';

import 'package:web/web.dart' as web;

import '../../config/app_config.dart';
import 'softphone_ws_client_stub.dart';

export 'softphone_ws_client_stub.dart';

class WebSoftphoneWsClient implements SoftphoneWsClient {
  web.WebSocket? _ws;
  bool _connected = false;
  void Function(Map<String, dynamic>)? _onJson;
  void Function(List<int>, String)? _onPcm;
  final List<StreamSubscription<dynamic>> _subs = [];

  @override
  bool get isConnected => _connected && _ws != null;

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
  }) {
    _onJson = onJson;
    _onPcm = onPcm;
    for (final s in _subs) {
      s.cancel();
    }
    _subs.clear();
    try {
      _ws?.close();
    } catch (_) {}
    _connected = false;

    try {
      final apiBase = AppConfig.apiBaseUrl.replaceAll(RegExp(r'/+$'), '');
      final wsBase = apiBase.startsWith('https://')
          ? apiBase.replaceFirst('https://', 'wss://')
          : apiBase.replaceFirst('http://', 'ws://');
      final url = '$wsBase/ws/telephony/softphone';
      final ws = web.WebSocket(url);
      ws.binaryType = 'arraybuffer';
      _ws = ws;
      _subs.add(ws.onOpen.listen((_) {
        ws.send(jsonEncode({
          'type': 'auth',
          'api_key': apiKey,
          'business_id': businessId,
          'session_id': sessionId,
          'media_ticket': mediaTicket,
        }).toJS);
      }));
      _subs.add(ws.onMessage.listen((web.MessageEvent e) {
        final data = e.data;
        if (data is JSString) {
          try {
            final msg = jsonDecode(data.toDart) as Map<String, dynamic>;
            if ('${msg['type']}' == 'auth_ok') _connected = true;
            _onJson?.call(msg);
          } catch (_) {}
          return;
        }
        // باینری: تلاش برای خواندن ArrayBuffer
        try {
          final ab = data as JSArrayBuffer;
          final bytes = ab.toDart.asUint8List();
          _handleBinary(bytes);
        } catch (_) {}
      }));
      _subs.add(ws.onClose.listen((_) {
        _connected = false;
        _ws = null;
        onDone?.call();
      }));
      _subs.add(ws.onError.listen((_) {
        onError?.call(StateError('softphone ws error'));
      }));
    } catch (e) {
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
      _ws?.send(jsonEncode(msg).toJS);
    } catch (_) {}
  }

  @override
  void sendPcm(String sessionId, List<int> pcm) {
    final sid = utf8.encode(sessionId.padRight(36).substring(0, 36));
    final out = BytesBuilder();
    out.add([0x48, 0x53, 0x58, 0x4D, 1, 0]);
    out.add([(pcm.length >> 8) & 0xFF, pcm.length & 0xFF]);
    out.add(sid);
    out.add(pcm);
    try {
      final bytes = Uint8List.fromList(out.toBytes());
      _ws?.send(bytes.buffer.toJS);
    } catch (_) {}
  }

  @override
  void disconnect() {
    _connected = false;
    for (final s in _subs) {
      s.cancel();
    }
    _subs.clear();
    try {
      _ws?.close();
    } catch (_) {}
    _ws = null;
  }
}

SoftphoneWsClient createSoftphoneWsClient() => WebSoftphoneWsClient();
