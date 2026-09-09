import 'market_context.dart';

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
    this.pricePrecision = 2,
    this.rsi14,
    this.volumeRatio,
    this.atrPercent,
    this.largeTradeFlow,
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
  final int pricePrecision;

  /// 最近 14 根 15 分钟 K 线计算的 RSI，缺少足够数据时为 null。
  final double? rsi14;

  /// 最近 8 根与此前 24 根 15 分钟 K 线的平均成交额比值。
  final double? volumeRatio;

  /// 最近 14 根 15 分钟 K 线的 ATR 占当前价格百分比。
  final double? atrPercent;

  /// 最近聚合成交中相对大额主动买卖的方向代理，不代表链上钱包身份。
  final LargeTradeFlow? largeTradeFlow;
}
