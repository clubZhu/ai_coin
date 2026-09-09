import 'position_record.dart';

class ExchangeQuote {
  const ExchangeQuote({
    required this.exchange,
    required this.pair,
    required this.price,
    required this.changePercent,
    required this.receivedAt,
  });

  final String exchange;
  final String pair;
  final double price;
  final double? changePercent;
  final DateTime receivedAt;
}

class CrossExchangeAnalysis {
  const CrossExchangeAnalysis({
    required this.symbol,
    required this.side,
    required this.quotes,
    required this.expectedExchangeCount,
    required this.consensusPrice,
    required this.spreadPercent,
    required this.directionAgreement,
    required this.dataQualityScore,
    required this.sampleCount,
    required this.winProbability,
    required this.probabilityLow,
    required this.probabilityHigh,
    required this.stopLossPercent,
    required this.takeProfitPercent,
    required this.unavailableReason,
    this.pricePrecision = 2,
  });

  final String symbol;
  final PositionSide side;
  final List<ExchangeQuote> quotes;
  final int expectedExchangeCount;
  final double consensusPrice;
  final double spreadPercent;
  final int directionAgreement;
  final int dataQualityScore;
  final int sampleCount;
  final double? winProbability;
  final double? probabilityLow;
  final double? probabilityHigh;
  final double stopLossPercent;
  final double takeProfitPercent;
  final String? unavailableReason;
  final int pricePrecision;

  int get validExchangeCount => quotes.length;

  bool get hasReliableProbability =>
      winProbability != null &&
      probabilityLow != null &&
      probabilityHigh != null;

  double get rewardRiskRatio => takeProfitPercent / stopLossPercent;

  double get stopLossPrice => side == PositionSide.long
      ? consensusPrice * (1 - stopLossPercent / 100)
      : consensusPrice * (1 + stopLossPercent / 100);

  double get takeProfitPrice => side == PositionSide.long
      ? consensusPrice * (1 + takeProfitPercent / 100)
      : consensusPrice * (1 - takeProfitPercent / 100);
}
