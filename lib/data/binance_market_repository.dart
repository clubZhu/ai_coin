import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import '../domain/market_context.dart';
import '../domain/market_snapshot.dart';
import '../domain/trading_assets.dart';
import 'market_repository.dart';

typedef JsonFetcher = Future<Object?> Function(Uri url);

/// 从币安公共行情接口（免 API Key）拉取 24h 行情与多周期 K 线，
/// 趋势、支撑压力等分析字段由 K 线数据在本地推导。
class BinanceMarketRepository implements MarketRepository {
  BinanceMarketRepository({
    JsonFetcher? fetcher,
    this.baseUrl = 'https://data-api.binance.vision',
    this.symbols = TradingAssets.symbols,
    this.pricePrecisions = const {},
  }) : _fetcher = fetcher ?? _httpFetcher;

  static const _trendConfigs = [
    (period: '15分钟', interval: '15m', limit: 96, threshold: 0.12),
    (period: '1小时', interval: '1h', limit: 60, threshold: 0.35),
    (period: '4小时', interval: '4h', limit: 60, threshold: 0.9),
    (period: '日线', interval: '1d', limit: 30, threshold: 2.0),
  ];

  final String baseUrl;
  final List<String> symbols;
  final Map<String, int> pricePrecisions;
  final JsonFetcher _fetcher;

  static Future<Object?> _httpFetcher(Uri url) async {
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 10);
    try {
      final request = await client
          .getUrl(url)
          .timeout(const Duration(seconds: 10));
      final response = await request.close().timeout(
        const Duration(seconds: 10),
      );
      if (response.statusCode != HttpStatus.ok) {
        throw HttpException('币安接口返回 ${response.statusCode}', uri: url);
      }
      final body = await response.transform(utf8.decoder).join();
      return jsonDecode(body);
    } finally {
      client.close();
    }
  }

  @override
  Future<List<MarketSnapshot>> fetchSnapshots() async {
    return Future.wait(symbols.map(_fetchSnapshot));
  }

  @override
  Future<List<double>> fetchChartPoints({
    required String symbol,
    required MarketRange range,
  }) async {
    final payload = await _fetcher(
      _uri('/api/v3/klines', {
        'symbol': '${symbol.toUpperCase()}USDT',
        'interval': range.interval,
        'limit': '${range.limit}',
      }),
    );
    return _closes(payload);
  }

  Future<MarketSnapshot> _fetchSnapshot(String symbol) async {
    final pair = '${symbol.toUpperCase()}USDT';
    final responses = await Future.wait<Object?>([
      _fetcher(_uri('/api/v3/ticker/24hr', {'symbol': pair})),
      _optionalFetch(
        _uri('/api/v3/aggTrades', {'symbol': pair, 'limit': '1000'}),
      ),
      for (final config in _trendConfigs)
        _fetcher(
          _uri('/api/v3/klines', {
            'symbol': pair,
            'interval': config.interval,
            'limit': '${config.limit}',
          }),
        ),
    ]);

    final ticker = _asMap(responses.first);
    final largeTradeFlow = _largeTradeFlow(responses[1]);
    final candleGroups = responses.skip(2).map(_candles).toList();
    final trendCloses = candleGroups
        .map((candles) => candles.map((candle) => candle.close).toList())
        .toList();
    final trends = <TimeframeTrend>[
      for (var index = 0; index < _trendConfigs.length; index++)
        _trend(
          _trendConfigs[index].period,
          trendCloses[index],
          _trendConfigs[index].threshold,
        ),
    ];

    final price = _toDouble(ticker['lastPrice']);
    final pricePrecision =
        pricePrecisions[symbol.toUpperCase()] ??
        _decimalPlaces('${ticker['lastPrice']}');
    final changePercent = _toDouble(ticker['priceChangePercent']);
    final high24h = _toDouble(ticker['highPrice']);
    final low24h = _toDouble(ticker['lowPrice']);
    final quoteVolume = _toDouble(ticker['quoteVolume']);
    final shortCandles = candleGroups.first;
    final rsi14 = _rsi14(shortCandles);
    final volumeRatio = _volumeRatio(shortCandles);
    final atrPercent = _atrPercent(shortCandles);

    final dominant = _dominantDirection(trends);
    final consistency = _consistency(trends, dominant);
    final rangePercent = price > 0 ? (high24h - low24h) / price * 100 : 0.0;
    final riskScore = switch (rangePercent) {
      < 2 => 1,
      < 4 => 2,
      < 7 => 3,
      < 12 => 4,
      _ => 5,
    };
    final riskLabel = switch (riskScore) {
      <= 2 => '低',
      3 => '中等',
      _ => '高',
    };

    return MarketSnapshot(
      symbol: symbol,
      name: TradingAssets.names[symbol] ?? symbol,
      price: price,
      changePercent: changePercent,
      state: _state(consistency, dominant),
      riskLabel: riskLabel,
      riskScore: riskScore,
      consistency: consistency,
      trends: trends,
      levels: [
        PriceLevel(price: high24h, label: '24h 高点'),
        PriceLevel(price: price, label: '当前价格', isCurrent: true),
        PriceLevel(price: low24h, label: '24h 低点'),
      ],
      chartPoints: trendCloses.first,
      high24h: high24h,
      low24h: low24h,
      volume24h: _formatVolume(quoteVolume),
      explanation:
          '$symbol 报价 \$${_formatPrice(price, pricePrecision)}，24h${changePercent >= 0 ? '上涨' : '下跌'} '
          '${changePercent.abs().toStringAsFixed(2)}%，运行区间 '
          '\$${_formatPrice(low24h, pricePrecision)} – \$${_formatPrice(high24h, pricePrecision)}。'
          '短线${trends.first.label}、日线${trends.last.label}，'
          '多周期一致度 $consistency%，24h 波动属$riskLabel水平。',
      pricePrecision: pricePrecision,
      rsi14: rsi14,
      volumeRatio: volumeRatio,
      atrPercent: atrPercent,
      largeTradeFlow: largeTradeFlow,
    );
  }

  Future<Object?> _optionalFetch(Uri uri) async {
    try {
      return await _fetcher(uri);
    } on Object {
      return null;
    }
  }

  Uri _uri(String path, Map<String, String> query) =>
      Uri.parse(baseUrl + path).replace(queryParameters: query);

  TimeframeTrend _trend(String period, List<double> closes, double threshold) {
    if (closes.length < 21) {
      return TimeframeTrend(
        period: period,
        label: '震荡',
        direction: TrendDirection.flat,
      );
    }
    final fast = _ema(closes, 9);
    final slow = _ema(closes, 21);
    final recent = closes[closes.length - 5];
    final spread = slow == 0 ? 0.0 : (fast - slow) / slow * 100;
    final recentChange = recent == 0
        ? 0.0
        : (closes.last - recent) / recent * 100;
    final strength = spread * .7 + recentChange * .3;
    final direction = strength > threshold
        ? TrendDirection.up
        : strength < -threshold
        ? TrendDirection.down
        : TrendDirection.flat;
    final label = switch (direction) {
      TrendDirection.up => strength > threshold * 3 ? '上涨' : '反弹',
      TrendDirection.down => strength < -threshold * 3 ? '下跌' : '回调',
      TrendDirection.flat => '震荡',
    };
    return TimeframeTrend(period: period, label: label, direction: direction);
  }

  double _ema(List<double> values, int period) {
    final multiplier = 2 / (period + 1);
    var value = values.first;
    for (final next in values.skip(1)) {
      value = (next - value) * multiplier + value;
    }
    return value;
  }

  TrendDirection _dominantDirection(List<TimeframeTrend> trends) {
    final counts = {
      for (final direction in TrendDirection.values) direction: 0,
    };
    for (final trend in trends) {
      counts[trend.direction] = counts[trend.direction]! + 1;
    }
    return counts.entries
        .reduce((best, entry) => entry.value > best.value ? entry : best)
        .key;
  }

  int _consistency(List<TimeframeTrend> trends, TrendDirection dominant) {
    final count = trends.where((trend) => trend.direction == dominant).length;
    return (count * 100 / trends.length).round();
  }

  String _state(int consistency, TrendDirection dominant) {
    final word = switch (dominant) {
      TrendDirection.up => '偏多',
      TrendDirection.down => '偏空',
      TrendDirection.flat => '震荡',
    };
    if (consistency >= 75) return '多周期共振 · $word';
    if (consistency >= 50) return '多数周期同向 · $word';
    return '多空分歧 · 区间震荡';
  }

  String _formatVolume(double quoteVolume) {
    if (quoteVolume >= 1e9) {
      return '\$${(quoteVolume / 1e9).toStringAsFixed(1)}B';
    }
    if (quoteVolume >= 1e6) {
      return '\$${(quoteVolume / 1e6).toStringAsFixed(1)}M';
    }
    if (quoteVolume >= 1e3) {
      return '\$${(quoteVolume / 1e3).toStringAsFixed(1)}K';
    }
    return '\$${quoteVolume.toStringAsFixed(0)}';
  }

  String _formatPrice(double value, int precision) {
    final fixed = value.toStringAsFixed(precision.clamp(0, 12).toInt());
    final digits = fixed.split('.').first;
    final buffer = StringBuffer();
    for (var index = 0; index < digits.length; index++) {
      if (index > 0 && (digits.length - index) % 3 == 0) buffer.write(',');
      buffer.write(digits[index]);
    }
    final fraction = fixed.split('.').last;
    if (fixed.contains('.')) buffer.write('.$fraction');
    return buffer.toString();
  }

  int _decimalPlaces(String value) {
    if (!value.contains('.')) return 0;
    return value
        .split('.')
        .last
        .replaceFirst(RegExp(r'0+$'), '')
        .length
        .clamp(0, 12)
        .toInt();
  }

  Map<String, dynamic> _asMap(Object? payload) {
    if (payload is Map<String, dynamic>) return payload;
    throw const FormatException('币安行情数据格式异常');
  }

  List<double> _closes(Object? payload) {
    return _candles(payload).map((candle) => candle.close).toList();
  }

  List<_Candle> _candles(Object? payload) {
    if (payload is! List) throw const FormatException('币安 K 线数据格式异常');
    final candles = <_Candle>[];
    for (final row in payload) {
      if (row is! List || row.length < 8) continue;
      final high = double.tryParse('${row[2]}');
      final low = double.tryParse('${row[3]}');
      final close = double.tryParse('${row[4]}');
      final quoteVolume = double.tryParse('${row[7]}');
      if (high == null || low == null || close == null || quoteVolume == null) {
        continue;
      }
      candles.add(
        _Candle(high: high, low: low, close: close, quoteVolume: quoteVolume),
      );
    }
    if (candles.isEmpty) throw const FormatException('币安 K 线数据为空');
    return candles;
  }

  double? _rsi14(List<_Candle> candles) {
    if (candles.length < 15) return null;
    var averageGain = 0.0;
    var averageLoss = 0.0;
    for (var index = 1; index <= 14; index++) {
      final change = candles[index].close - candles[index - 1].close;
      if (change >= 0) {
        averageGain += change;
      } else {
        averageLoss -= change;
      }
    }
    averageGain /= 14;
    averageLoss /= 14;
    for (var index = 15; index < candles.length; index++) {
      final change = candles[index].close - candles[index - 1].close;
      final gain = math.max(change, 0);
      final loss = math.max(-change, 0);
      averageGain = (averageGain * 13 + gain) / 14;
      averageLoss = (averageLoss * 13 + loss) / 14;
    }
    if (averageLoss == 0) return 100;
    if (averageGain == 0) return 0;
    final relativeStrength = averageGain / averageLoss;
    return 100 - 100 / (1 + relativeStrength);
  }

  double? _volumeRatio(List<_Candle> candles) {
    if (candles.length < 32) return null;
    final recent = candles.sublist(candles.length - 8);
    final baseline = candles.sublist(candles.length - 32, candles.length - 8);
    final recentAverage =
        recent.fold<double>(0, (sum, candle) => sum + candle.quoteVolume) /
        recent.length;
    final baselineAverage =
        baseline.fold<double>(0, (sum, candle) => sum + candle.quoteVolume) /
        baseline.length;
    if (baselineAverage <= 0) return null;
    return (recentAverage / baselineAverage).clamp(0, 9).toDouble();
  }

  double? _atrPercent(List<_Candle> candles) {
    if (candles.length < 15 || candles.last.close <= 0) return null;
    var atr = 0.0;
    for (var index = 1; index <= 14; index++) {
      final candle = candles[index];
      final previousClose = candles[index - 1].close;
      atr += math.max(
        candle.high - candle.low,
        math.max(
          (candle.high - previousClose).abs(),
          (candle.low - previousClose).abs(),
        ),
      );
    }
    atr /= 14;
    for (var index = 15; index < candles.length; index++) {
      final candle = candles[index];
      final previousClose = candles[index - 1].close;
      final trueRange = math.max(
        candle.high - candle.low,
        math.max(
          (candle.high - previousClose).abs(),
          (candle.low - previousClose).abs(),
        ),
      );
      atr = (atr * 13 + trueRange) / 14;
    }
    return atr / candles.last.close * 100;
  }

  LargeTradeFlow? _largeTradeFlow(Object? payload) {
    if (payload is! List) return null;
    final trades = <_AggregateTrade>[];
    for (final raw in payload) {
      if (raw is! Map) continue;
      final price = double.tryParse('${raw['p']}');
      final quantity = double.tryParse('${raw['q']}');
      final time = int.tryParse('${raw['T']}');
      final buyerIsMaker = raw['m'];
      if (price == null ||
          quantity == null ||
          time == null ||
          buyerIsMaker is! bool ||
          price <= 0 ||
          quantity <= 0) {
        continue;
      }
      trades.add(
        _AggregateTrade(
          notional: price * quantity,
          takerBuy: !buyerIsMaker,
          time: time,
        ),
      );
    }
    if (trades.length < 20) return null;

    final notionals = trades.map((trade) => trade.notional).toList()..sort();
    final thresholdIndex = (notionals.length * .9)
        .floor()
        .clamp(0, notionals.length - 1)
        .toInt();
    final threshold = notionals[thresholdIndex];
    final largeTrades = trades
        .where((trade) => trade.notional >= threshold)
        .toList();
    if (largeTrades.isEmpty) return null;

    final totalNotional = trades.fold<double>(
      0,
      (sum, trade) => sum + trade.notional,
    );
    var largeBuy = 0.0;
    var largeSell = 0.0;
    for (final trade in largeTrades) {
      if (trade.takerBuy) {
        largeBuy += trade.notional;
      } else {
        largeSell += trade.notional;
      }
    }
    final largeTotal = largeBuy + largeSell;
    if (largeTotal <= 0 || totalNotional <= 0) return null;
    final earliest = trades.map((trade) => trade.time).reduce(math.min);
    final latest = trades.map((trade) => trade.time).reduce(math.max);
    final windowMinutes = math.max(0, latest - earliest) / 60000;
    final sampleCoverage = math.min(trades.length / 500, 1.0);
    final timeCoverage = math.min(windowMinutes / 5, 1.0);
    final largeCoverage = math.min(largeTrades.length / 60, 1.0);
    final confidence =
        (20 + sampleCoverage * 40 + timeCoverage * 20 + largeCoverage * 20)
            .round()
            .clamp(0, 95)
            .toInt();
    return LargeTradeFlow(
      netFlowPercent: (largeBuy - largeSell) / largeTotal * 100,
      largeTradeSharePercent: largeTotal / totalNotional * 100,
      sampleCount: trades.length,
      windowMinutes: windowMinutes,
      confidence: confidence,
    );
  }

  double _toDouble(Object? value) {
    final parsed = value is num ? value.toDouble() : double.tryParse('$value');
    if (parsed == null) throw const FormatException('币安行情数值解析失败');
    return parsed;
  }
}

class _Candle {
  const _Candle({
    required this.high,
    required this.low,
    required this.close,
    required this.quoteVolume,
  });

  final double high;
  final double low;
  final double close;
  final double quoteVolume;
}

class _AggregateTrade {
  const _AggregateTrade({
    required this.notional,
    required this.takerBuy,
    required this.time,
  });

  final double notional;
  final bool takerBuy;
  final int time;
}
