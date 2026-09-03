enum PositionSide { long, short }

enum PositionResult { open, profit, loss }

class PositionRecord {
  const PositionRecord({
    required this.id,
    required this.symbol,
    required this.side,
    required this.entryPrice,
    required this.stopLossPercent,
    required this.takeProfitPercent,
    required this.createdAt,
    this.positionAmount = 100,
    this.leverage = 5,
    this.result = PositionResult.open,
    this.realizedPercent,
    this.closePrice,
  });

  factory PositionRecord.fromJson(Map<String, dynamic> json) {
    return PositionRecord(
      id: json['id'] as String,
      symbol: json['symbol'] as String,
      side: PositionSide.values.firstWhere(
        (value) => value.name == json['side'],
        orElse: () => PositionSide.long,
      ),
      entryPrice: (json['entryPrice'] as num).toDouble(),
      stopLossPercent: (json['stopLossPercent'] as num).toDouble(),
      takeProfitPercent: (json['takeProfitPercent'] as num).toDouble(),
      createdAt: DateTime.parse(json['createdAt'] as String),
      positionAmount:
          (json['positionAmount'] as num?)?.toDouble() ??
          ((json['marginAmount'] as num?)?.toDouble() ?? 20) *
              ((json['leverage'] as num?)?.toInt() ?? 5),
      leverage: (json['leverage'] as num?)?.toInt() ?? 5,
      result: PositionResult.values.firstWhere(
        (value) => value.name == json['result'],
        orElse: () => PositionResult.open,
      ),
      realizedPercent: (json['realizedPercent'] as num?)?.toDouble(),
      closePrice: (json['closePrice'] as num?)?.toDouble(),
    );
  }

  final String id;
  final String symbol;
  final PositionSide side;
  final double entryPrice;
  final double stopLossPercent;
  final double takeProfitPercent;
  final DateTime createdAt;
  final double positionAmount;
  final int leverage;
  final PositionResult result;
  final double? realizedPercent;
  final double? closePrice;

  double get stopLossPrice => side == PositionSide.long
      ? entryPrice * (1 - stopLossPercent / 100)
      : entryPrice * (1 + stopLossPercent / 100);

  double get takeProfitPrice => side == PositionSide.long
      ? entryPrice * (1 + takeProfitPercent / 100)
      : entryPrice * (1 - takeProfitPercent / 100);

  double get positionValue => positionAmount;

  double get estimatedLoss => positionValue * stopLossPercent / 100;

  double get estimatedProfit => positionValue * takeProfitPercent / 100;

  double? get realizedAmount =>
      realizedPercent == null ? null : positionValue * realizedPercent! / 100;

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'symbol': symbol,
      'side': side.name,
      'entryPrice': entryPrice,
      'stopLossPercent': stopLossPercent,
      'takeProfitPercent': takeProfitPercent,
      'createdAt': createdAt.toIso8601String(),
      'positionAmount': positionAmount,
      'leverage': leverage,
      'result': result.name,
      'realizedPercent': realizedPercent,
      'closePrice': closePrice,
    };
  }

  PositionRecord copyWith({
    PositionResult? result,
    double? realizedPercent,
    double? closePrice,
    bool clearClosePrice = false,
    bool clearRealizedPercent = false,
  }) {
    return PositionRecord(
      id: id,
      symbol: symbol,
      side: side,
      entryPrice: entryPrice,
      stopLossPercent: stopLossPercent,
      takeProfitPercent: takeProfitPercent,
      createdAt: createdAt,
      positionAmount: positionAmount,
      leverage: leverage,
      result: result ?? this.result,
      realizedPercent: clearRealizedPercent
          ? null
          : realizedPercent ?? this.realizedPercent,
      closePrice: clearClosePrice ? null : closePrice ?? this.closePrice,
    );
  }
}
