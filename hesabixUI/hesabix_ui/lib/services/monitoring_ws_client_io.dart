import 'dart:async';
import 'dart:convert';
import 'dart:io';
import '../config/app_config.dart';
import '../core/api_client.dart';
import 'monitoring_ws_client_stub.dart';
export 'monitoring_ws_client_stub.dart';

class MonitoringWebSocketClientIO implements MonitoringWebSocketClient {
  WebSocket? _socket;
  final _controller = StreamController<Map<String, dynamic>>.broadcast();
  Timer? _heartbeatTimer;
  bool _isConnecting = false;

  @override
  Stream<Map<String, dynamic>>? get stream => _controller.stream;

  @override
  bool get isConnected => _socket != null && _socket!.readyState == WebSocket.open;

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
      final wsUrl = '$wsBase/api/v1/admin/monitoring/stream';

      _socket = await WebSocket.connect(wsUrl);
      _socket!.add(jsonEncode(<String, String>{'type': 'auth', 'api_key': authStore.apiKey!}));
      _socket!.listen(
        (data) {
          try {
            final jsonData = jsonDecode(data as String) as Map<String, dynamic>;
            _controller.add(jsonData);
          } catch (e) {
            // خطا در parse کردن JSON
            print('Error parsing WebSocket message: $e');
          }
        },
        onError: (error) {
          _controller.addError(error);
          _disconnect();
        },
        onDone: () {
          _disconnect();
        },
        cancelOnError: true,
      );

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
    _socket?.close();
    _socket = null;
  }

  void _startHeartbeat() {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      if (isConnected) {
        try {
          _socket!.add('ping');
        } catch (e) {
          _disconnect();
        }
      }
    });
  }
}

MonitoringWebSocketClient createMonitoringWebSocketClient() => MonitoringWebSocketClientIO();

