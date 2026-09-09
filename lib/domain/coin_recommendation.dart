enum CoinRecommendationLevel { focus, watch }

class CoinRecommendation {
  const CoinRecommendation({
    required this.symbol,
    required this.price,
    required this.changePercent,
    required this.quoteVolume,
    required this.volatilityPercent,
    required this.score,
    required this.level,
    required this.reasons,
    required this.pricePrecision,
  });

  final String symbol;
  final double price;
  final double changePercent;
  final double quoteVolume;
  final double volatilityPercent;
  final int score;
  final CoinRecommendationLevel level;
  final List<String> reasons;
  final int pricePrecision;

  String get levelLabel => switch (level) {
    CoinRecommendationLevel.focus => '重点关注',
    CoinRecommendationLevel.watch => '可以观察',
  };
}
