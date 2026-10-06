import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import 'crypto_transport_service.dart';

final api = ApiClient();

class ApiClient extends ChangeNotifier {
  WebSocketChannel? _channel;
  CryptoTransportService _crypto = CryptoTransportService();

  bool _isConnected = false;
  bool get isConnected => _isConnected;

  late String host;
  late int port;

  Completer<Map<String, dynamic>>? _pendingCompleter;

  Timer? _connectionTimeoutTimer;

  int _connectionGeneration = 0;

  bool _handshakeCompleted = false;

  static const Duration handshakeTimeout = Duration(seconds: 10);
  static const Duration requestTimeout = Duration(seconds: 10);

  static const int maxWebSocketMessageBytes = 1 * 1024 * 1024; // 1 MiB

  Future<void> connect() async {
    disconnect();

    final int generation = ++_connectionGeneration;

    _crypto = CryptoTransportService();
    _handshakeCompleted = false;

    final completer = Completer<void>();

    try {
      final expectedCertPem = await rootBundle.loadString('assets/server_cert.pem');

      final uri = _buildWebSocketUri();

      final channel = WebSocketChannel.connect(uri);
      _channel = channel;

      _connectionTimeoutTimer = Timer(handshakeTimeout, () {
        if (generation != _connectionGeneration) {
          return;
        }

        if (!completer.isCompleted && !_handshakeCompleted) {
          completer.completeError(
            TimeoutException(
              'WebSocket handshake timed out',
              handshakeTimeout,
            ),
          );

          disconnect();
        }
      });

      channel.stream.listen(
        (message) async {
          if (generation != _connectionGeneration) {
            return;
          }

          try {
            final messageString = _messageToString(message);

            if (_messageSizeInBytes(messageString) > maxWebSocketMessageBytes) {
              throw Exception('WebSocket message exceeds maximum allowed size');
            }

            if (!_handshakeCompleted) {
              await _crypto.processHandshakeResponse(
                messageString,
                expectedCertPem,
              );

              if (generation != _connectionGeneration) {
                return;
              }

              _handshakeCompleted = true;
              _isConnected = true;

              _connectionTimeoutTimer?.cancel();
              _connectionTimeoutTimer = null;

              notifyListeners();

              if (!completer.isCompleted) {
                completer.complete();
              }

              return;
            }

            final data = jsonDecode(messageString);

            if (data is! Map<String, dynamic>) {
              throw Exception('Invalid WebSocket response envelope');
            }

            final payload = data['payload'];

            if (payload is! String || payload.isEmpty) {
              throw Exception('Invalid encrypted response payload');
            }

            final respPayload = await _crypto.decryptEnvelope(payload);

            if (generation != _connectionGeneration) {
              return;
            }

            final pending = _pendingCompleter;

            if (pending != null && !pending.isCompleted) {
              pending.complete(respPayload);
            }

            _pendingCompleter = null;
          } catch (e) {
            if (generation != _connectionGeneration) {
              return;
            }

            if (!_handshakeCompleted) {
              _isConnected = false;
              notifyListeners();

              _connectionTimeoutTimer?.cancel();
              _connectionTimeoutTimer = null;

              if (!completer.isCompleted) {
                completer.completeError(e);
              }

              _closeCurrentChannel();
              return;
            }

            final pending = _pendingCompleter;

            if (pending != null && !pending.isCompleted) {
              pending.completeError(e);
            }

            _pendingCompleter = null;
          }
        },
        onError: (Object err) {
          if (generation != _connectionGeneration) {
            return;
          }

          _handleConnectionFailure(
            err,
            completer,
          );
        },
        onDone: () {
          if (generation != _connectionGeneration) {
            return;
          }

          _connectionTimeoutTimer?.cancel();
          _connectionTimeoutTimer = null;

          _isConnected = false;
          _handshakeCompleted = false;

          notifyListeners();

          if (!completer.isCompleted) {
            completer.completeError(Exception('WebSocket connection closed'));
          }

          final pending = _pendingCompleter;

          if (pending != null && !pending.isCompleted) {
            pending.completeError(Exception('WebSocket connection closed'));
          }

          _pendingCompleter = null;
        },
        cancelOnError: false,
      );

      final handshakeStr = await _crypto.createHandshakePayload();

      if (generation != _connectionGeneration) {
        return completer.future;
      }

      if (_messageSizeInBytes(handshakeStr) > maxWebSocketMessageBytes) {
        throw Exception('Handshake message exceeds maximum allowed size');
      }

      channel.sink.add(handshakeStr);
    } catch (e) {
      if (generation == _connectionGeneration) {
        _isConnected = false;
        _handshakeCompleted = false;

        _connectionTimeoutTimer?.cancel();
        _connectionTimeoutTimer = null;

        notifyListeners();

        _closeCurrentChannel();
      }

      if (!completer.isCompleted) {
        completer.completeError(e);
      }
    }

    return completer.future;
  }

  Uri _buildWebSocketUri() {
    final scheme = _isSecureWebSocket() ? 'wss' : 'ws';

    if (port == 0) {
      return Uri.parse(
        '$scheme://$host/ws',
      );
    }

    return Uri.parse(
      '$scheme://$host:$port/ws',
    );
  }

  bool _isSecureWebSocket() {
    if (kIsWeb) {
      final currentUri = Uri.base;

      if (currentUri.scheme == 'https') {
        return true;
      }
    }

    return false;
  }

  void _handleConnectionFailure(
    Object error,
    Completer<void> connectCompleter,
  ) {
    _isConnected = false;
    _handshakeCompleted = false;

    _connectionTimeoutTimer?.cancel();
    _connectionTimeoutTimer = null;

    notifyListeners();

    if (!connectCompleter.isCompleted) {
      connectCompleter.completeError(error);
    }

    final pending = _pendingCompleter;

    if (pending != null && !pending.isCompleted) {
      pending.completeError(error);
    }

    _pendingCompleter = null;

    _closeCurrentChannel();
  }

  String _messageToString(dynamic message) {
    if (message is String) {
      return message;
    }

    if (message is List<int>) {
      return utf8.decode(message);
    }

    throw Exception(
      'Unsupported WebSocket message type',
    );
  }

  int _messageSizeInBytes(String message) {
    return utf8.encode(message).length;
  }

  Future<Map<String, dynamic>> sendCommand(
    Map<String, dynamic> req,
  ) async {
    if (!_isConnected || !_handshakeCompleted) {
      await connect();
    }

    if (!_isConnected || !_handshakeCompleted || _channel == null) {
      throw Exception('WebSocket is not connected');
    }

    if (_pendingCompleter != null) {
      throw Exception('Another operation is already in progress');
    }

    final encryptedStr =
        await _crypto.encryptPayload(req);

    if (_messageSizeInBytes(encryptedStr) > maxWebSocketMessageBytes) {
      throw Exception('Request exceeds maximum WebSocket message size');
    }

    final completer = Completer<Map<String, dynamic>>();

    _pendingCompleter = completer;

    try {
      _channel!.sink.add(encryptedStr);

      return await completer.future.timeout(
        requestTimeout,
        onTimeout: () {
          if (identical(_pendingCompleter, completer)) {
            _pendingCompleter = null;
          }

          throw TimeoutException('Server timeout', requestTimeout);
        },
      );
    } catch (e) {
      if (identical(_pendingCompleter, completer)) {
        _pendingCompleter = null;
      }

      rethrow;
    }
  }

  Future<void> logout() async {
    if (!_isConnected || !_handshakeCompleted) {
      _clearCryptoState();
      return;
    }

    try {
      await sendCommand({
        'action': 'Logout',
      });
    } catch (_) {
    } finally {
      disconnect();
    }
  }

  void disconnect() {
    _connectionGeneration++;

    _connectionTimeoutTimer?.cancel();
    _connectionTimeoutTimer = null;

    final pending = _pendingCompleter;

    if (pending != null && !pending.isCompleted) {
      pending.completeError(
        Exception('WebSocket disconnected'),
      );
    }

    _pendingCompleter = null;

    _handshakeCompleted = false;
    _isConnected = false;

    _closeCurrentChannel();

    _clearCryptoState();

    notifyListeners();
  }

  void _closeCurrentChannel() {
    final channel = _channel;
    _channel = null;

    if (channel != null) {
      try {
        channel.sink.close();
      } catch (_) {
      }
    }
  }

  void _clearCryptoState() {
    _crypto.dispose();
    _crypto = CryptoTransportService();
  }

  static bool isReleaseWeb() {
    return kIsWeb && kReleaseMode;
  }

  static Future<void> saveSettings(
    String host,
    int port,
  ) async {
    if (isReleaseWeb()) {
      return;
    }

    final SharedPreferences prefs =
        await SharedPreferences.getInstance();

    await prefs.setString('host', host);
    await prefs.setInt('port', port);
  }

  static Future<Map<String, dynamic>> loadSettings() async {
    if (isReleaseWeb()) {
      final Uri currentUri = Uri.base;

      return {
        'host': currentUri.host,
        'port': currentUri.port,
      };
    }

    final SharedPreferences prefs =
        await SharedPreferences.getInstance();

    final String host = prefs.getString('host') ?? '192.168.1.10';

    final int port = prefs.getInt('port') ?? 8080;

    return {
      'host': host,
      'port': port,
    };
  }

  @override
  void dispose() {
    disconnect();
    super.dispose();
  }
}
