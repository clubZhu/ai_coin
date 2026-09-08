import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import '../domain/coin_recommendation.dart';
import 'coin_recommendation_repository.dart';

typedef RecommendationJsonFetcher = Future<Object?> Function(Uri url);

/// Produces a transparent market shortlist from public Binance spot data.
/// It is deliberately a ranking aid, not an order or a promise of returns.
class BinanceCoinRecommendationRepository
    implements CoinRecommendationRepository {
  BinanceCoinRecommendationRepository({
    RecommendationJsonFetcher? fetcher,
    this.baseUrl = 'https://data-api.binance.vision',
  }) : _fetcher = fetcher ?? _httpFetcher;

  static const _excludedAssets = {
    'USDC',
    'FDUSD',
    'TUSD',
    'USDP',
    'DAI',
    'EUR',
    'EURI',
    'AEUR',
    'TRY',
    'BRL',
    'GBP',
    'AUD',
    'JPY',
    'UAH',
    'ZAR',
  };

  final String baseUrl;
  final RecommendationJsonFetcher _fetcher;

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
      return jsonDecode(await response.transform(utf8.decoder).join());
    } finally {
      client.close();
    }
  }

  @override
  Future<List<CoinRecommendation>> fetchRecommendations({int limit = 6}) async {
    final responses = await Future.wait<Object?>([
      _fetcher(Uri.parse('$baseUrl/api/v3/exchangeInfo')),
      _fetcher(
        Uri.parse('$baseUrl/api/v3/ticker/24hr?symbolStatus=TRADING&type=FULL'),
      ),
    ]);
    final tradableAssets = _tradableAssets(responses[0]);
    final tickers = _tickerRows(responses[1], tradableAssets)
      ..sort((a, b) => b.quoteVolume.compareTo(a.quoteVolume));

    // Analyze only the most liquid candidates to keep the public API load low.
    final shortlist = tickers.take(12);
    final scored = await Future.wait(shortlist.map(_analyzeSafely));
    final recommendations =
        scored
            .whereType<CoinRecommendation>()
            .where((item) => item.score >= 65)
            .toList()
          ..sort((a, b) {
            final scoreOrder = b.score.compareTo(a.score);
            return scoreOrder != 0
                ? scoreOrder
                : b.quoteVolume.compareTo(a.quoteVolume);
          });
    return recommendations.take(math.max(1, limit)).toList(growable: false);
  }

  Set<String> _tradableAssets(Object? payload) {
    if (payload is! Map || payload['symbols'] is! List) {
      throw const FormatException('交易对目录格式异常');
    }
    final assets = <String>{};
    for (final row in payload['symbols'] as List) {
      if (row is! Map ||
          row['quoteAsset'] != 'USDT' ||
          row['status'] != 'TRADING' ||
          row['isSpotTradingAllowed'] == false) {
        continue;
      }
      final asset = row['baseAsset'];
      if (asset is String && _isAllowedAsset(asset)) {
        assets.add(asset.toUpperCase());
      }
    }
    return assets;
  }

  List<_TickerRow> _tickerRows(Object? payload, Set<String> tradableAssets) {
    if (payload is! List) throw const FormatException('24h 行情格式异常');
    final rows = <_TickerRow>[];
    for (final value in payload) {
      if (value is! Map) continue;
      final pair = value['symbol'];
      if (pair is! String || !pair.endsWith('USDT')) continue;
      final asset = pair.substring(0, pair.length - 4).toUpperCase();
      if (!tradableAssets.contains(asset)) continue;
      final price = _toDouble(value['lastPrice']);
      final high = _toDouble(value['highPrice']);
      final low = _toDouble(value['lowPrice']);
      final change = _toDouble(value['priceChangePercent']);
      final volume = _toDouble(value['quoteVolume']);
      if (price <= 0 || high <= low || volume < 2000000) continue;
      rows.add(
        _TickerRow(
          asset: asset,
          price: price,
          high: high,
          low: low,
          changePercent: change,
          quoteVolume: volume,
        ),
      );
    }
    return rows;
  }

  bool _isAllowedAsset(String value) {
    final asset = value.toUpperCase();
    if (_excludedAssets.contains(asset)) return false;
    return !asset.endsWith('UP') &&
        !asset.endsWith('DOWN') &&
        !asset.endsWith('BULL') &&
        !asset.endsWith('BEAR');
  }

  Future<CoinRecommendation?> _analyzeSafely(_TickerRow ticker) async {
    try {
      final pair = '${ticker.asset}USDT';
      final responses = await Future.wait<Object?>([
        _fetcher(_klineUri(pair, '1h', 48)),
        _fetcher(_klineUri(pair, '4h', 42)),
      ]);
      final hourly = _closes(responses[0]);
      final fourHourly = _closes(responses[1]);
      if (hourly.length < 21 || fourHourly.length < 21) return null;

      final hourlyUp = hourly.last >= _sma20(hourly) * 1.001;
      final fourHourlyUp = fourHourly.last >= _sma20(fourHourly) * 1.001;
      final sixHourMomentum =
          (hourly.last - hourly[hourly.length - 7]) /
          hourly[hourly.length - 7] *
          100;
      final volatility = (ticker.high - ticker.low) / ticker.price * 100;

      final liquidityScore =
          (((math.log(ticker.quoteVolume) / math.ln10) - 6) / 4 * 25)
              .clamp(2, 25)
              .toDouble();
      final trendScore = hourlyUp && fourHourlyUp
          ? 30.0
          : hourlyUp || fourHourlyUp
          ? 16.0
          : 2.0;
      final momentumScore = _momentumScore(
        ticker.changePercent,
        sixHourMomentum,
      );
      final volatilityScore = switch (volatility) {
        >= 1.5 && <= 8 => 20.0,
        < 1.5 => 12.0,
        <= 14 => 11.0,
        _ => 2.0,
      };
      final score = math.max(
        0,
        math.min(
          100,
          (liquidityScore + trendScore + momentumScore + volatilityScore)
              .round(),
        ),
      );
      final reasons = <String>[
        if (hourlyUp && fourHourlyUp)
          '1h/4h 趋势同向'
        else if (hourlyUp || fourHourlyUp)
          '单周期趋势转强',
        if (ticker.quoteVolume >= 50000000) '24h 成交活跃',
        if (volatility >= 1.5 && volatility <= 8) '波动相对可控',
        if (ticker.changePercent > 0 && ticker.changePercent <= 10) '短线动量偏强',
      ];
      if (reasons.isEmpty) reasons.add('综合条件进入观察区');

      return CoinRecommendation(
        symbol: ticker.asset,
        price: ticker.price,
        changePercent: ticker.changePercent,
        quoteVolume: ticker.quoteVolume,
        volatilityPercent: volatility,
        score: score,
        level: score >= 78
            ? CoinRecommendationLevel.focus
            : CoinRecommendationLevel.watch,
        reasons: reasons.take(2).toList(growable: false),
      );
    } on Object {
      return null;
    }
  }

  Uri _klineUri(String symbol, String interval, int limit) => Uri.parse(
    '$baseUrl/api/v3/klines?symbol=$symbol&interval=$interval&limit=$limit',
  );

  List<double> _closes(Object? payload) {
    if (payload is! List) return const [];
    return payload
        .whereType<List>()
        .where((row) => row.length > 4)
        .map((row) => _toDouble(row[4]))
        .where((value) => value > 0)
        .toList(growable: false);
  }

  double _sma20(List<double> values) {
    final recent = values.sublist(values.length - 20);
    return recent.reduce((sum, value) => sum + value) / recent.length;
  }

  double _momentumScore(double daily, double sixHour) {
    if (daily >= 0 && daily <= 8 && sixHour >= -0.5 && sixHour <= 5) {
      return 25;
    }
    if (daily > 0 && daily <= 12 && sixHour > 0) return 18;
    if (daily > 12 || sixHour > 7) return 7;
    if (daily >= -2 && sixHour >= -1) return 11;
    return 3;
  }

  double _toDouble(Object? value) => switch (value) {
    num number => number.toDouble(),
    String text => double.tryParse(text) ?? 0,
    _ => 0,
  };
}

class _TickerRow {
  const _TickerRow({
    required this.asset,
    required this.price,
    required this.high,
    required this.low,
    required this.changePercent,
    required this.quoteVolume,
  });

  final String asset;
  final double price;
  final double high;
  final double low;
  final double changePercent;
  final double quoteVolume;
}
