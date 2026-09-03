enum TrendDirection { up, down, flat }

extension TrendDirectionX on TrendDirection {
  String get arrow => switch (this) {
    TrendDirection.up => '↑',
    TrendDirection.down => '↓',
    TrendDirection.flat => '→',
  };
}

class TimeframeTrend {
  const TimeframeTrend({
    required this.period,
    required this.label,
    required this.direction,
  });

  final String period;
  final String label;
  final TrendDirection direction;
}

class PriceLevel {
  const PriceLevel({
    required this.price,
    required this.label,
    this.isCurrent = false,
  });

  final double price;
  final String label;
  final bool isCurrent;
}

class MarketSnapshot {
  const MarketSnapshot({
    required this.symbol,
    required this.name,
    required this.price,
    required this.changePercent,
    required this.state,
    required this.riskLabel,
    required this.riskScore,
    required this.consistency,
    required this.trends,
    required this.levels,
    required this.chartPoints,
    required this.high24h,
    required this.low24h,
    required this.volume24h,
    required this.explanation,
  });

  final String symbol;
  final String name;
  final double price;
  final double changePercent;
  final String state;
  final String riskLabel;
  final int riskScore;
  final int consistency;
  final List<TimeframeTrend> trends;
  final List<PriceLevel> levels;
  final List<double> chartPoints;
  final double high24h;
  final double low24h;
  final String volume24h;
  final String explanation;
}
