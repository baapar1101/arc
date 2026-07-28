import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:connectivity_plus/connectivity_plus.dart';

import '../config/app_config.dart';
import 'notifications_ws_client_stub.dart';

export 'notifications_ws_client_stub.dart';

class IoNotificationsWsClient implements NotificationsWsClient {
  WebSocket? _socket;
  void Function(Map<String, dynamic>)? _onMessage;
  String? _apiKey;
  Timer? _reconnectTimer;
  Timer? _pingTimer;
  StreamSubscription<List<ConnectivityResult>>? _connectivitySub;
  bool _manualDisconnect = false;
  int _reconnectAttempt = 0;
  bool _connecting = false;

  void _scheduleReconnect() {
    if (_manualDisconnect) return;
    if (_reconnectTimer?.isActive == true) return;
    final attempt = _reconnectAttempt;
    _reconnectAttempt = math.min(attempt + 1, 8);
    // 2s, 4s, 8s ... capped ~60s with light jitter
    final baseMs = math.min(60000, 2000 * (1 << math.min(attempt, 5)));
    final jitter = math.Random().nextInt(800);
    _reconnectTimer = Timer(Duration(milliseconds: baseMs + jitter), () {
      final key = _apiKey;
      if (key == null || key.isEmpty || _manualDisconnect) return;
      connect(apiKey: key, onMessage: _onMessage);
    });
  }

  void _startPing() {
    _pingTimer?.cancel();
    _pingTimer = Timer.periodic(const Duration(seconds: 25), (_) {
      try {
        _socket?.add(jsonEncode(<String, String>{'type': 'ping'}));
      } catch (_) {
        _socket = null;
        _scheduleReconnect();
      }
    });
  }

  void _ensureConnectivityWatcher() {
    _connectivitySub ??= Connectivity().onConnectivityChanged.listen((results) {
      if (_manualDisconnect) return;
      final online = results.any((r) => r != ConnectivityResult.none);
      if (online && _socket == null && (_apiKey?.isNotEmpty ?? false)) {
        _reconnectAttempt = 0;
        connect(apiKey: _apiKey!, onMessage: _onMessage);
      }
    });
  }

  @override
  void connect({required String apiKey, void Function(Map<String, dynamic>)? onMessage}) async {
    _apiKey = apiKey;
    _onMessage = onMessage;
    _manualDisconnect = false;
    _reconnectTimer?.cancel();
    if (_connecting) return;
    _connecting = true;
    _ensureConnectivityWatcher();
    try {
      await _socket?.close();
    } catch (_) {}
    _socket = null;
    final apiBase = AppConfig.apiBaseUrl;
    final wsBase = apiBase.startsWith('https://')
        ? apiBase.replaceFirst('https://', 'wss://')
        : apiBase.replaceFirst('http://', 'ws://');
    final url = '$wsBase/ws/notifications';
    try {
      _socket = await WebSocket.connect(url);
      _reconnectAttempt = 0;
      _socket!.add(jsonEncode(<String, String>{'type': 'auth', 'api_key': apiKey}));
      _startPing();
      _socket!.listen((dynamic data) {
        try {
          final Map<String, dynamic> msg =
              data is String ? jsonDecode(data) as Map<String, dynamic> : <String, dynamic>{};
          final type = '${msg['type'] ?? ''}';
          if (type == 'pong' || type == 'ping') return;
          if (_onMessage != null) _onMessage!(msg);
        } catch (_) {}
      }, onDone: () {
        _socket = null;
        _pingTimer?.cancel();
        _scheduleReconnect();
      }, onError: (Object _) {
        _socket = null;
        _pingTimer?.cancel();
        _scheduleReconnect();
      });
    } catch (_) {
      _socket = null;
      _pingTimer?.cancel();
      _scheduleReconnect();
    } finally {
      _connecting = false;
    }
  }

  @override
  void disconnect() {
    _manualDisconnect = true;
    _reconnectTimer?.cancel();
    _pingTimer?.cancel();
    unawaited(_connectivitySub?.cancel());
    _connectivitySub = null;
    try {
      _socket?.close();
    } catch (_) {}
    _socket = null;
  }
}

NotificationsWsClient createNotificationsWsClient() => IoNotificationsWsClient();
