import 'dart:async';
import 'dart:convert';
import 'dart:io';

abstract interface class LivePriceService {
  Stream<double> watchPrice(String symbol);
}

class BinanceLivePriceService implements LivePriceService {
  const BinanceLivePriceService();

  @override
  Stream<double> watchPrice(String symbol) {
    return _BinancePriceConnection(symbol).stream;
  }
}

class _BinancePriceConnection {
  _BinancePriceConnection(String symbol)
    : _symbol = symbol.toLowerCase(),
      _controller = StreamController<double>() {
    _controller
      ..onListen = _connect
      ..onCancel = _dispose;
  }

  final String _symbol;
  final StreamController<double> _controller;

  WebSocket? _socket;
  StreamSubscription<dynamic>? _socketSubscription;
  Timer? _reconnectTimer;
  bool _connecting = false;
  bool _closed = false;
  int _retrySeconds = 1;

  Stream<double> get stream => _controller.stream;

  Future<void> _connect() async {
    if (_closed || _connecting) return;
    _connecting = true;
    try {
      final socket = await WebSocket.connect(
        'wss://data-stream.binance.vision/ws/${_symbol}usdt@miniTicker',
      ).timeout(const Duration(seconds: 10));
      if (_closed) {
        await socket.close();
        return;
      }

      socket.pingInterval = const Duration(seconds: 20);
      _socket = socket;
      _retrySeconds = 1;
      _connecting = false;
      _socketSubscription = socket.listen(
        _handleMessage,
        onError: (Object error) => _handleDisconnect(error),
        onDone: _handleDisconnect,
        cancelOnError: true,
      );
    } on Object catch (error) {
      _connecting = false;
      if (!_closed) {
        _controller.addError(error);
        _scheduleReconnect();
      }
    }
  }

  void _handleMessage(dynamic message) {
    if (_closed || message is! String) return;
    try {
      final decoded = jsonDecode(message);
      if (decoded is! Map<String, dynamic>) return;
      final payload = decoded['data'] is Map<String, dynamic>
          ? decoded['data'] as Map<String, dynamic>
          : decoded;
      final price = double.tryParse(payload['c']?.toString() ?? '');
      if (price != null && price > 0 && !_controller.isClosed) {
        _controller.add(price);
      }
    } on FormatException {
      // Ignore malformed frames and keep the market stream alive.
    }
  }

  void _handleDisconnect([Object? error]) {
    if (_closed) return;
    _connecting = false;
    _socketSubscription = null;
    _socket = null;
    if (error != null && !_controller.isClosed) {
      _controller.addError(error);
    }
    _scheduleReconnect();
  }

  void _scheduleReconnect() {
    if (_closed || _reconnectTimer?.isActive == true) return;
    final delay = Duration(seconds: _retrySeconds);
    _retrySeconds = (_retrySeconds * 2).clamp(1, 15).toInt();
    _reconnectTimer = Timer(delay, _connect);
  }

  Future<void> _dispose() async {
    _closed = true;
    _reconnectTimer?.cancel();
    await _socketSubscription?.cancel();
    await _socket?.close();
    _socketSubscription = null;
    _socket = null;
  }
}
