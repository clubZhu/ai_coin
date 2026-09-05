import 'dart:convert';
import 'dart:io';

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
  }) : _fetcher = fetcher ?? _httpFetcher;

  static const _trendConfigs = [
    (period: '15分钟', interval: '15m', limit: 96, threshold: 0.12),
    (period: '1小时', interval: '1h', limit: 60, threshold: 0.35),
    (period: '4小时', interval: '4h', limit: 60, threshold: 0.9),
    (period: '日线', interval: '1d', limit: 30, threshold: 2.0),
  ];

  final String baseUrl;
  final List<String> symbols;
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
    final trendCloses = responses.skip(1).map(_closes).toList();
    final trends = <TimeframeTrend>[
      for (var index = 0; index < _trendConfigs.length; index++)
        _trend(
          _trendConfigs[index].period,
          trendCloses[index],
          _trendConfigs[index].threshold,
        ),
    ];

    final price = _toDouble(ticker['lastPrice']);
    final changePercent = _toDouble(ticker['priceChangePercent']);
    final high24h = _toDouble(ticker['highPrice']);
    final low24h = _toDouble(ticker['lowPrice']);
    final quoteVolume = _toDouble(ticker['quoteVolume']);

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
          '$symbol 报价 \$${_formatPrice(price)}，24h${changePercent >= 0 ? '上涨' : '下跌'} '
          '${changePercent.abs().toStringAsFixed(2)}%，运行区间 '
          '\$${_formatPrice(low24h)} – \$${_formatPrice(high24h)}。'
          '短线${trends.first.label}、日线${trends.last.label}，'
          '多周期一致度 $consistency%，24h 波动属$riskLabel水平。',
    );
  }

  Uri _uri(String path, Map<String, String> query) =>
      Uri.parse(baseUrl + path).replace(queryParameters: query);

  TimeframeTrend _trend(String period, List<double> closes, double threshold) {
    if (closes.length < 10) {
      return TimeframeTrend(
        period: period,
        label: '震荡',
        direction: TrendDirection.flat,
      );
    }
    final baseline = _sma(closes.sublist(closes.length - 9));
    final change = (closes.last - baseline) / baseline * 100;
    final direction = change > threshold
        ? TrendDirection.up
        : change < -threshold
        ? TrendDirection.down
        : TrendDirection.flat;
    final label = switch (direction) {
      TrendDirection.up => change > threshold * 3 ? '上涨' : '反弹',
      TrendDirection.down => change < -threshold * 3 ? '下跌' : '回调',
      TrendDirection.flat => '震荡',
    };
    return TimeframeTrend(period: period, label: label, direction: direction);
  }

  double _sma(List<double> values) =>
      values.reduce((total, value) => total + value) / values.length;

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

  String _formatPrice(double value) {
    final fixed = value >= 1000
        ? value.toStringAsFixed(0)
        : value.toStringAsFixed(2);
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

  Map<String, dynamic> _asMap(Object? payload) {
    if (payload is Map<String, dynamic>) return payload;
    throw const FormatException('币安行情数据格式异常');
  }

  List<double> _closes(Object? payload) {
    if (payload is! List) throw const FormatException('币安 K 线数据格式异常');
    final closes = <double>[];
    for (final row in payload) {
      if (row is! List || row.length < 5) continue;
      final close = double.tryParse('${row[4]}');
      if (close != null) closes.add(close);
    }
    if (closes.isEmpty) throw const FormatException('币安 K 线数据为空');
    return closes;
  }

  double _toDouble(Object? value) {
    final parsed = value is num ? value.toDouble() : double.tryParse('$value');
    if (parsed == null) throw const FormatException('币安行情数值解析失败');
    return parsed;
  }
}
