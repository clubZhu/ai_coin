import '../domain/market_snapshot.dart';

enum MarketRange {
  hour('1H', interval: '1m', limit: 60),
  fourHours('4H', interval: '5m', limit: 48),
  day('1D', interval: '15m', limit: 96),
  week('1W', interval: '1h', limit: 168),
  month('1M', interval: '4h', limit: 180);

  const MarketRange(this.label, {required this.interval, required this.limit});

  final String label;
  final String interval;
  final int limit;
}

abstract interface class MarketRepository {
  Future<List<MarketSnapshot>> fetchSnapshots();

  Future<List<double>> fetchChartPoints({
    required String symbol,
    required MarketRange range,
  });
}
