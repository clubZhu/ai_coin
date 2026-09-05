import '../domain/market_snapshot.dart';
import 'market_repository.dart';

class MockMarketRepository implements MarketRepository {
  const MockMarketRepository();

  @override
  Future<List<MarketSnapshot>> fetchSnapshots() async => snapshots;

  @override
  Future<List<double>> fetchChartPoints({
    required String symbol,
    required MarketRange range,
  }) async {
    return snapshots
        .firstWhere(
          (snapshot) => snapshot.symbol == symbol,
          orElse: () => snapshots.first,
        )
        .chartPoints;
  }

  List<MarketSnapshot> get snapshots => const [
    MarketSnapshot(
      symbol: 'BTC',
      name: 'Bitcoin',
      price: 77312,
      changePercent: -1.39,
      state: '高位震荡 · 短线偏弱',
      riskLabel: '中等',
      riskScore: 3,
      consistency: 42,
      trends: [
        TimeframeTrend(
          period: '15分钟',
          label: '反弹',
          direction: TrendDirection.up,
        ),
        TimeframeTrend(
          period: '1小时',
          label: '震荡',
          direction: TrendDirection.flat,
        ),
        TimeframeTrend(
          period: '4小时',
          label: '回调',
          direction: TrendDirection.down,
        ),
        TimeframeTrend(period: '日线', label: '偏多', direction: TrendDirection.up),
      ],
      levels: [
        PriceLevel(price: 81500, label: '前高压力'),
        PriceLevel(price: 78400, label: '强压力'),
        PriceLevel(price: 77312, label: '当前价格', isCurrent: true),
        PriceLevel(price: 76200, label: '短线支撑'),
        PriceLevel(price: 75300, label: '4H EMA99'),
      ],
      chartPoints: [
        41,
        43,
        42,
        46,
        45,
        49,
        53,
        52,
        56,
        60,
        58,
        63,
        67,
        65,
        62,
        64,
        59,
        57,
        54,
        50,
        47,
        49,
        46,
        48,
        51,
        50,
        53,
        52,
        55,
      ],
      high24h: 79362,
      low24h: 75980,
      volume24h: r'$38.6B',
      explanation:
          'BTC 从 81,478 高点进入 4H 回调，76,200–76,600 存在明显支撑。短周期正在反弹，但当前不属于明确的单边趋势行情。',
    ),
    MarketSnapshot(
      symbol: 'ETH',
      name: 'Ethereum',
      price: 3824.6,
      changePercent: 0.82,
      state: '区间震荡 · 动能修复',
      riskLabel: '中等',
      riskScore: 3,
      consistency: 58,
      trends: [
        TimeframeTrend(
          period: '15分钟',
          label: '偏多',
          direction: TrendDirection.up,
        ),
        TimeframeTrend(
          period: '1小时',
          label: '反弹',
          direction: TrendDirection.up,
        ),
        TimeframeTrend(
          period: '4小时',
          label: '震荡',
          direction: TrendDirection.flat,
        ),
        TimeframeTrend(period: '日线', label: '偏多', direction: TrendDirection.up),
      ],
      levels: [
        PriceLevel(price: 4080, label: '前高压力'),
        PriceLevel(price: 3920, label: '短线压力'),
        PriceLevel(price: 3824.6, label: '当前价格', isCurrent: true),
        PriceLevel(price: 3740, label: '短线支撑'),
        PriceLevel(price: 3615, label: '4H EMA99'),
      ],
      chartPoints: [
        38,
        37,
        40,
        39,
        43,
        42,
        45,
        48,
        46,
        44,
        47,
        49,
        52,
        51,
        55,
        54,
        58,
        56,
        59,
        61,
        58,
        60,
        62,
        64,
        63,
        66,
        65,
        68,
        70,
      ],
      high24h: 3918,
      low24h: 3712,
      volume24h: r'$21.4B',
      explanation:
          'ETH 短周期动能正在修复，3,740 附近是当前关键支撑。4H 仍处在区间内，站稳 3,920 后趋势一致度才会明显改善。',
    ),
  ];
}
