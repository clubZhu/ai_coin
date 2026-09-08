import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import '../domain/cross_exchange_analysis.dart';
import '../domain/market_snapshot.dart';
import '../domain/position_record.dart';
import 'cross_exchange_repository.dart';

typedef CrossExchangeJsonFetcher = Future<Object?> Function(Uri uri);

class PublicCrossExchangeRepository implements CrossExchangeRepository {
  PublicCrossExchangeRepository({CrossExchangeJsonFetcher? fetcher})
    : _fetcher = fetcher ?? _httpFetcher;

  static const _expectedExchangeCount = 4;
  static const _estimatedRoundTripCostPercent = .14;

  final CrossExchangeJsonFetcher _fetcher;

  static Future<Object?> _httpFetcher(Uri uri) async {
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 8);
    try {
      final request = await client
          .getUrl(uri)
          .timeout(const Duration(seconds: 8));
      request.headers.set(HttpHeaders.userAgentHeader, 'CryptoPilot/1.0');
      request.headers.set(HttpHeaders.acceptHeader, 'application/json');
      final response = await request.close().timeout(
        const Duration(seconds: 8),
      );
      if (response.statusCode != HttpStatus.ok) {
        throw HttpException('行情接口返回 ${response.statusCode}', uri: uri);
      }
      final body = await response.transform(utf8.decoder).join();
      return jsonDecode(body);
    } finally {
      client.close();
    }
  }

  @override
  Future<List<CrossExchangeAnalysis>> fetchAnalyses(
    List<MarketSnapshot> snapshots,
  ) {
    return Future.wait(snapshots.map(_fetchAnalysis));
  }

  Future<CrossExchangeAnalysis> _fetchAnalysis(MarketSnapshot snapshot) async {
    final side = _sideFor(snapshot);
    final quoteFutures = <Future<ExchangeQuote?>>[
      _safeQuote(() => _fetchOkx(snapshot.symbol)),
      _safeQuote(() => _fetchBybit(snapshot.symbol)),
      _safeQuote(() => _fetchCoinbase(snapshot.symbol)),
    ];
    final historyFuture = _safeHistory(snapshot.symbol);
    final externalQuotes = await Future.wait(quoteFutures);
    final candles = await historyFuture;
    final quotes = <ExchangeQuote>[
      ExchangeQuote(
        exchange: 'Binance',
        pair: '${snapshot.symbol}/USDT',
        price: snapshot.price,
        changePercent: snapshot.changePercent,
        receivedAt: DateTime.now(),
      ),
      ...externalQuotes.whereType<ExchangeQuote>(),
    ];

    final consensusPrice = _median(quotes.map((quote) => quote.price).toList());
    final spreadPercent = _spreadPercent(quotes, consensusPrice);
    final agreement = _directionAgreement(quotes, side);
    final atrPercent = _atrPercent(candles);
    final rangePercent = snapshot.price <= 0
        ? 0.0
        : (snapshot.high24h - snapshot.low24h).abs() / snapshot.price * 100;
    final volatilityStop = atrPercent > 0
        ? atrPercent * 1.45
        : snapshot.riskScore * .65;
    final structureStop = rangePercent * .22;
    final stopLossPercent = math
        .max(volatilityStop, structureStop)
        .clamp(.8, 6.0)
        .toDouble();
    final rewardRisk = agreement >= 75 && spreadPercent <= .35 ? 2.2 : 2.0;
    final takeProfitPercent = stopLossPercent * rewardRisk;
    final backtest = _backtest(
      candles,
      side: side,
      stopLossPercent: stopLossPercent,
      takeProfitPercent: takeProfitPercent,
    );

    String? unavailableReason;
    if (quotes.length < 3) {
      unavailableReason = '有效交易所不足 3 家';
    } else if (spreadPercent > 1) {
      unavailableReason = '跨所价差异常，暂不评估';
    } else if (backtest.samples < 80) {
      unavailableReason = '历史样本不足 80 笔';
    }

    double? probability;
    double? probabilityLow;
    double? probabilityHigh;
    if (unavailableReason == null) {
      final adjustment =
          (agreement - 50) * .08 - math.max(0, spreadPercent - .25) * 4;
      probability = (backtest.probability * 100 + adjustment)
          .clamp(5.0, 95.0)
          .toDouble();
      probabilityLow = (backtest.low * 100 + adjustment)
          .clamp(0.0, probability)
          .toDouble();
      probabilityHigh = (backtest.high * 100 + adjustment)
          .clamp(probability, 100.0)
          .toDouble();
    }

    final quoteCoverage = quotes.length / _expectedExchangeCount;
    final spreadQuality = (1 - spreadPercent / 1.2).clamp(0.0, 1.0);
    final sampleQuality = (backtest.samples / 240).clamp(0.0, 1.0);
    final dataQuality =
        (quoteCoverage * 40 +
                spreadQuality * 25 +
                agreement / 100 * 20 +
                sampleQuality * 15)
            .round()
            .clamp(0, 100)
            .toInt();

    return CrossExchangeAnalysis(
      symbol: snapshot.symbol,
      side: side,
      quotes: quotes,
      expectedExchangeCount: _expectedExchangeCount,
      consensusPrice: consensusPrice,
      spreadPercent: spreadPercent,
      directionAgreement: agreement,
      dataQualityScore: dataQuality,
      sampleCount: backtest.samples,
      winProbability: probability,
      probabilityLow: probabilityLow,
      probabilityHigh: probabilityHigh,
      stopLossPercent: stopLossPercent,
      takeProfitPercent: takeProfitPercent,
      unavailableReason: unavailableReason,
    );
  }

  Future<ExchangeQuote?> _safeQuote(
    Future<ExchangeQuote> Function() loader,
  ) async {
    try {
      return await loader();
    } on Object {
      return null;
    }
  }

  Future<List<_Candle>> _safeHistory(String symbol) async {
    try {
      return await _fetchBinanceHistory(symbol);
    } on Object {
      return const [];
    }
  }

  Future<ExchangeQuote> _fetchOkx(String symbol) async {
    final payload = await _fetcher(
      Uri.https('www.okx.com', '/api/v5/market/ticker', {
        'instId': '$symbol-USDT',
      }),
    );
    final ticker = _firstData(payload);
    final price = _number(ticker['last']);
    final open = _number(ticker['open24h']);
    return ExchangeQuote(
      exchange: 'OKX',
      pair: '$symbol/USDT',
      price: price,
      changePercent: open <= 0 ? null : (price - open) / open * 100,
      receivedAt: DateTime.now(),
    );
  }

  Future<ExchangeQuote> _fetchBybit(String symbol) async {
    final payload = await _fetcher(
      Uri.https('api.bybit.com', '/v5/market/tickers', {
        'category': 'spot',
        'symbol': '${symbol}USDT',
      }),
    );
    final root = _map(payload);
    final result = _map(root['result']);
    final rows = _list(result['list']);
    if (rows.isEmpty) throw const FormatException('Bybit 行情为空');
    final ticker = _map(rows.first);
    return ExchangeQuote(
      exchange: 'Bybit',
      pair: '$symbol/USDT',
      price: _number(ticker['lastPrice']),
      changePercent: _signedNumber(ticker['price24hPcnt']) * 100,
      receivedAt: DateTime.now(),
    );
  }

  Future<ExchangeQuote> _fetchCoinbase(String symbol) async {
    final payload = await _fetcher(
      Uri.https('api.exchange.coinbase.com', '/products/$symbol-USD/stats'),
    );
    final stats = _map(payload);
    final price = _number(stats['last']);
    final open = _number(stats['open']);
    return ExchangeQuote(
      exchange: 'Coinbase',
      pair: '$symbol/USD',
      price: price,
      changePercent: open <= 0 ? null : (price - open) / open * 100,
      receivedAt: DateTime.now(),
    );
  }

  Future<List<_Candle>> _fetchBinanceHistory(String symbol) async {
    final payload = await _fetcher(
      Uri.https('data-api.binance.vision', '/api/v3/klines', {
        'symbol': '${symbol}USDT',
        'interval': '15m',
        'limit': '1000',
      }),
    );
    final rows = _list(payload);
    final candles = <_Candle>[];
    for (final raw in rows) {
      if (raw is! List || raw.length < 5) continue;
      final open = double.tryParse('${raw[1]}');
      final high = double.tryParse('${raw[2]}');
      final low = double.tryParse('${raw[3]}');
      final close = double.tryParse('${raw[4]}');
      if (open == null || high == null || low == null || close == null) {
        continue;
      }
      candles.add(_Candle(open: open, high: high, low: low, close: close));
    }
    return candles;
  }

  PositionSide _sideFor(MarketSnapshot snapshot) {
    final up = snapshot.trends
        .where((trend) => trend.direction == TrendDirection.up)
        .length;
    final down = snapshot.trends
        .where((trend) => trend.direction == TrendDirection.down)
        .length;
    return down > up ? PositionSide.short : PositionSide.long;
  }

  int _directionAgreement(List<ExchangeQuote> quotes, PositionSide side) {
    final directional = quotes
        .where((quote) => quote.changePercent != null)
        .toList();
    if (directional.isEmpty) return 50;
    final aligned = directional.where((quote) {
      final change = quote.changePercent!;
      return side == PositionSide.long ? change >= 0 : change <= 0;
    }).length;
    return (aligned * 100 / directional.length).round();
  }

  double _median(List<double> values) {
    if (values.isEmpty) return 0;
    final sorted = [...values]..sort();
    final middle = sorted.length ~/ 2;
    return sorted.length.isOdd
        ? sorted[middle]
        : (sorted[middle - 1] + sorted[middle]) / 2;
  }

  double _spreadPercent(List<ExchangeQuote> quotes, double median) {
    if (quotes.length < 2 || median <= 0) return 0;
    final prices = quotes.map((quote) => quote.price);
    final low = prices.reduce(math.min);
    final high = prices.reduce(math.max);
    return (high - low) / median * 100;
  }

  double _atrPercent(List<_Candle> candles) {
    if (candles.length < 15 || candles.last.close <= 0) return 0;
    final start = candles.length - 14;
    var total = 0.0;
    for (var index = start; index < candles.length; index++) {
      final candle = candles[index];
      final previousClose = candles[index - 1].close;
      total += math.max(
        candle.high - candle.low,
        math.max(
          (candle.high - previousClose).abs(),
          (candle.low - previousClose).abs(),
        ),
      );
    }
    return total / 14 / candles.last.close * 100;
  }

  _BacktestResult _backtest(
    List<_Candle> candles, {
    required PositionSide side,
    required double stopLossPercent,
    required double takeProfitPercent,
  }) {
    if (candles.length < 120) return const _BacktestResult.empty();
    const lookback = 20;
    const horizon = 12;
    var samples = 0;
    var wins = 0;
    for (
      var index = lookback - 1;
      index < candles.length - horizon;
      index += 2
    ) {
      final fast = _averageClose(candles, index - 4, index);
      final slow = _averageClose(candles, index - 19, index);
      if (slow <= 0 || (fast - slow).abs() / slow < .0005) continue;
      final historicalSide = fast > slow
          ? PositionSide.long
          : PositionSide.short;
      if (historicalSide != side) continue;
      samples++;
      final entry = candles[index].close;
      final netStop = math.max(
        .1,
        stopLossPercent - _estimatedRoundTripCostPercent,
      );
      final netTarget = takeProfitPercent + _estimatedRoundTripCostPercent;
      final stopPrice = side == PositionSide.long
          ? entry * (1 - netStop / 100)
          : entry * (1 + netStop / 100);
      final targetPrice = side == PositionSide.long
          ? entry * (1 + netTarget / 100)
          : entry * (1 - netTarget / 100);
      bool? won;
      for (var offset = 1; offset <= horizon; offset++) {
        final candle = candles[index + offset];
        final stopHit = side == PositionSide.long
            ? candle.low <= stopPrice
            : candle.high >= stopPrice;
        final targetHit = side == PositionSide.long
            ? candle.high >= targetPrice
            : candle.low <= targetPrice;
        if (stopHit) {
          won = false;
          break;
        }
        if (targetHit) {
          won = true;
          break;
        }
      }
      if (won == null) {
        final exit = candles[index + horizon].close;
        final grossReturn = (exit - entry) / entry * 100;
        final signedReturn =
            (side == PositionSide.long ? grossReturn : -grossReturn) -
            _estimatedRoundTripCostPercent;
        won = signedReturn > 0;
      }
      if (won == true) wins++;
    }
    if (samples == 0) return const _BacktestResult.empty();
    final smoothed = (wins + 1) / (samples + 2);
    final interval = _wilson(wins, samples);
    return _BacktestResult(
      samples: samples,
      probability: smoothed,
      low: interval.$1,
      high: interval.$2,
    );
  }

  double _averageClose(List<_Candle> candles, int start, int end) {
    var total = 0.0;
    for (var index = start; index <= end; index++) {
      total += candles[index].close;
    }
    return total / (end - start + 1);
  }

  (double, double) _wilson(int wins, int samples) {
    if (samples == 0) return (0, 0);
    const z = 1.96;
    final p = wins / samples;
    final denominator = 1 + z * z / samples;
    final center = (p + z * z / (2 * samples)) / denominator;
    final margin =
        z *
        math.sqrt(p * (1 - p) / samples + z * z / (4 * samples * samples)) /
        denominator;
    return (
      (center - margin).clamp(0.0, 1.0).toDouble(),
      (center + margin).clamp(0.0, 1.0).toDouble(),
    );
  }

  Map<String, dynamic> _firstData(Object? payload) {
    final root = _map(payload);
    final data = _list(root['data']);
    if (data.isEmpty) throw const FormatException('交易所行情为空');
    return _map(data.first);
  }

  Map<String, dynamic> _map(Object? value) {
    if (value is Map<String, dynamic>) return value;
    if (value is Map) return value.map((key, item) => MapEntry('$key', item));
    throw const FormatException('交易所行情格式异常');
  }

  List<dynamic> _list(Object? value) {
    if (value is List) return value;
    throw const FormatException('交易所行情列表格式异常');
  }

  double _number(Object? value) {
    final number = value is num ? value.toDouble() : double.tryParse('$value');
    if (number == null || !number.isFinite || number <= 0) {
      throw const FormatException('交易所行情数值异常');
    }
    return number;
  }

  double _signedNumber(Object? value) {
    final number = value is num ? value.toDouble() : double.tryParse('$value');
    if (number == null || !number.isFinite) {
      throw const FormatException('交易所行情数值异常');
    }
    return number;
  }
}

class _Candle {
  const _Candle({
    required this.open,
    required this.high,
    required this.low,
    required this.close,
  });

  final double open;
  final double high;
  final double low;
  final double close;
}

class _BacktestResult {
  const _BacktestResult({
    required this.samples,
    required this.probability,
    required this.low,
    required this.high,
  });

  const _BacktestResult.empty()
    : samples = 0,
      probability = 0,
      low = 0,
      high = 0;

  final int samples;
  final double probability;
  final double low;
  final double high;
}
