class LargeTradeFlow {
  const LargeTradeFlow({
    required this.netFlowPercent,
    required this.largeTradeSharePercent,
    required this.sampleCount,
    required this.windowMinutes,
    required this.confidence,
  });

  /// 大额主动买入额与卖出额的净差，占大额成交总额百分比，范围 -100～100。
  final double netFlowPercent;

  /// 大额成交占本次聚合成交样本总成交额的比例。
  final double largeTradeSharePercent;
  final int sampleCount;
  final double windowMinutes;
  final int confidence;

  String get directionLabel {
    if (netFlowPercent >= 12) return '净流入';
    if (netFlowPercent <= -12) return '净流出';
    return '均衡';
  }
}

class PolicyImpact {
  const PolicyImpact({
    required this.directionScore,
    required this.eventRiskScore,
    required this.confidence,
    required this.relevantItemCount,
    required this.availableSourceCount,
    required this.expectedSourceCount,
    required this.headline,
    required this.updatedAt,
    required this.unavailableReason,
  });

  /// 正值偏宽松/支持，负值偏收紧/限制，范围 -100～100。
  final int directionScore;

  /// 近期政策事件带来的不确定性，范围 0～100。
  final int eventRiskScore;
  final int confidence;
  final int relevantItemCount;
  final int availableSourceCount;
  final int expectedSourceCount;
  final String? headline;
  final DateTime? updatedAt;
  final String? unavailableReason;

  bool get isAvailable => availableSourceCount > 0;

  String get directionLabel {
    if (!isAvailable) return '数据不足';
    if (directionScore >= 18) return '偏利好';
    if (directionScore <= -18) return '偏利空';
    return '中性';
  }

  String get riskLabel {
    if (!isAvailable) return '未知';
    if (eventRiskScore >= 65) return '高影响';
    if (eventRiskScore >= 35) return '需关注';
    return '平稳';
  }
}
