import 'dart:async';
import 'dart:convert';
import 'dart:js_interop';
import 'package:web/web.dart' as web;
import '../config/app_config.dart';
import '../core/api_client.dart';
import 'monitoring_ws_client_stub.dart';
export 'monitoring_ws_client_stub.dart';

class MonitoringWebSocketClientWeb implements MonitoringWebSocketClient {
  web.WebSocket? _socket;
  final _controller = StreamController<Map<String, dynamic>>.broadcast();
  Timer? _heartbeatTimer;
  bool _isConnecting = false;

  @override
  Stream<Map<String, dynamic>>? get stream => _controller.stream;

  @override
  bool get isConnected => _socket != null && _socket!.readyState == 1; // WebSocket.OPEN = 1

  @override
  Future<void> connect() async {
    if (_isConnecting || isConnected) return;
    
    _isConnecting = true;
    try {
      // دریافت API key از auth store
      final authStore = ApiClient.getAuthStore();
      if (authStore == null || authStore.apiKey == null) {
        throw Exception('No API key available');
      }

      // ساخت URL WebSocket
      final apiBase = AppConfig.apiBaseUrl;
      final wsBase = apiBase.startsWith('https://')
          ? apiBase.replaceFirst('https://', 'wss://')
          : apiBase.replaceFirst('http://', 'ws://');
      final wsUrl = '$wsBase/api/v1/admin/monitoring/stream?api_key=${authStore.apiKey}';

      _socket = web.WebSocket(wsUrl);
      
      // Handle connection errors silently
      _socket!.onError.listen((web.Event _) {
        _controller.addError(Exception('WebSocket error'));
        _disconnect();
      });
      
      _socket!.onMessage.listen((web.MessageEvent e) {
        try {
          final data = e.data;
          if (data is JSString) {
            final jsonStr = data.toDart;
            final jsonData = jsonDecode(jsonStr) as Map<String, dynamic>;
            _controller.add(jsonData);
          }
        } catch (_) {
          // Ignore message parsing errors
        }
      });
      
      // Handle close events
      _socket!.onClose.listen((web.CloseEvent _) {
        _disconnect();
      });

      // شروع heartbeat
      _startHeartbeat();
    } catch (e) {
      _controller.addError(e);
      _disconnect();
    } finally {
      _isConnecting = false;
    }
  }

  @override
  Future<void> disconnect() async {
    _disconnect();
  }

  void _disconnect() {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = null;
    try {
      _socket?.close();
    } catch (_) {}
    _socket = null;
  }

  void _startHeartbeat() {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      if (isConnected && _socket != null) {
        try {
          _socket!.send('ping'.toJS);
        } catch (e) {
          _disconnect();
        }
      }
    });
  }
}

MonitoringWebSocketClient createMonitoringWebSocketClient() => MonitoringWebSocketClientWeb();

