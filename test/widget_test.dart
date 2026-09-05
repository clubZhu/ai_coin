import 'dart:async';

import 'package:ai_coin/app.dart';
import 'package:ai_coin/data/binance_market_repository.dart';
import 'package:ai_coin/data/live_price_service.dart';
import 'package:ai_coin/data/market_repository.dart';
import 'package:ai_coin/data/mock_market_repository.dart';
import 'package:ai_coin/data/position_repository.dart';
import 'package:ai_coin/domain/market_snapshot.dart';
import 'package:ai_coin/domain/position_record.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _TestLivePriceService implements LivePriceService {
  final Map<String, StreamController<double>> _controllers = {};

  @override
  Stream<double> watchPrice(String symbol) {
    return _controllers
        .putIfAbsent(
          symbol,
          () => StreamController<double>.broadcast(sync: true),
        )
        .stream;
  }

  void emit(String symbol, double price) {
    _controllers
        .putIfAbsent(
          symbol,
          () => StreamController<double>.broadcast(sync: true),
        )
        .add(price);
  }
}

class _TestMarketRepository implements MarketRepository {
  _TestMarketRepository({this.failFirst = false});

  final bool failFirst;
  int calls = 0;
  final List<MarketRange> chartRanges = [];

  @override
  Future<List<MarketSnapshot>> fetchSnapshots() async {
    calls++;
    if (failFirst && calls == 1) {
      throw const FormatException('网络请求失败');
    }
    return [
      _testSnapshot(symbol: 'BTC', price: 80000, changePercent: 1.24),
      _testSnapshot(symbol: 'ETH', price: 4000, changePercent: -0.5),
    ];
  }

  @override
  Future<List<double>> fetchChartPoints({
    required String symbol,
    required MarketRange range,
  }) async {
    chartRanges.add(range);
    return [10, 14, 12, 18, 16, 22, 25, 23, 27, 30];
  }
}

MarketSnapshot _testSnapshot({
  required String symbol,
  required double price,
  required double changePercent,
}) {
  return MarketSnapshot(
    symbol: symbol,
    name: symbol == 'BTC' ? 'Bitcoin' : 'Ethereum',
    price: price,
    changePercent: changePercent,
    state: '多数周期同向 · 偏多',
    riskLabel: '中等',
    riskScore: 3,
    consistency: 60,
    trends: [
      TimeframeTrend(period: '15分钟', label: '反弹', direction: TrendDirection.up),
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
      PriceLevel(price: price * 1.05, label: '24h 高点'),
      PriceLevel(price: price, label: '当前价格', isCurrent: true),
      PriceLevel(price: price * 0.95, label: '24h 低点'),
    ],
    chartPoints: [10, 12, 11, 14, 13, 16, 18, 17, 20, 22],
    high24h: price * 1.02,
    low24h: price * 0.98,
    volume24h: r'$26.5B',
    explanation: '测试行情说明。',
  );
}

void main() {
  Future<void> launchApp(
    WidgetTester tester, {
    LivePriceService? livePriceService,
    MarketRepository? marketRepository,
    PositionRepository? positionRepository,
  }) async {
    final service = livePriceService ?? _TestLivePriceService();
    SharedPreferences.setMockInitialValues({});
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      CryptoPilotApp(
        marketRepository: marketRepository ?? const MockMarketRepository(),
        livePriceService: service,
        positionRepository: positionRepository,
      ),
    );
    if (livePriceService == null) {
      (service as _TestLivePriceService).emit('BTC', 77312);
    }
    await tester.pumpAndSettle();
  }

  test('开仓记录可以在本机存储中往返读取', () async {
    SharedPreferences.setMockInitialValues({});
    final repository = LocalPositionRepository();
    final record = PositionRecord(
      id: 'record-1',
      symbol: 'BTC',
      side: PositionSide.long,
      entryPrice: 77312,
      stopLossPercent: 2,
      takeProfitPercent: 10,
      createdAt: DateTime(2026, 9, 3, 10, 30),
      positionAmount: 200,
      leverage: 10,
      result: PositionResult.profit,
      realizedPercent: 8.5,
      closePrice: 84000,
    );

    await repository.save([record]);
    final loaded = await repository.load();

    expect(loaded, hasLength(1));
    expect(loaded.single.symbol, 'BTC');
    expect(loaded.single.result, PositionResult.profit);
    expect(loaded.single.realizedPercent, 8.5);
    expect(loaded.single.closePrice, 84000);
    expect(loaded.single.positionAmount, 200);
    expect(loaded.single.leverage, 10);
    expect(loaded.single.positionValue, 200);
  });

  testWidgets('首页展示开仓计算工具和默认目标价格', (tester) async {
    await launchApp(tester);

    expect(find.text('开仓'), findsOneWidget);
    expect(find.text('开仓记录'), findsOneWidget);
    expect(find.text(r'-$2.00'), findsOneWidget);
    expect(find.text(r'+$10.00'), findsOneWidget);
    expect(find.text('价格 75,766 USDT'), findsOneWidget);
    expect(find.text('价格 85,043 USDT'), findsOneWidget);
  });

  testWidgets('开仓数量按已加杠杆的实际数量计算盈亏', (tester) async {
    await launchApp(tester);

    await tester.enterText(
      find.byKey(const ValueKey('position-amount-input')),
      '200',
    );
    await tester.tap(find.byKey(const ValueKey('leverage-selector')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('10X').last);
    await tester.pumpAndSettle();

    expect(find.text('10X'), findsOneWidget);
    expect(find.text(r'-$4.00'), findsOneWidget);
    expect(find.text(r'+$20.00'), findsOneWidget);
  });

  testWidgets('可以切换币种并跟随币安实时价格', (tester) async {
    final livePrices = _TestLivePriceService();
    await launchApp(tester, livePriceService: livePrices);

    var priceField = tester.widget<TextField>(
      find.byKey(const ValueKey('entry-price-input')),
    );
    expect(priceField.controller?.text, isEmpty);
    expect(find.text('市价 --'), findsOneWidget);
    expect(find.text('价格 --'), findsNWidgets(2));

    livePrices.emit('BTC', 80000);
    await tester.pump();
    priceField = tester.widget<TextField>(
      find.byKey(const ValueKey('entry-price-input')),
    );
    expect(priceField.controller?.text, '80,000');
    expect(find.text('实时 80,000'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('coin-selector')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('ETH/USDT'));
    await tester.pumpAndSettle();
    livePrices.emit('ETH', 4000);
    await tester.pump();

    priceField = tester.widget<TextField>(
      find.byKey(const ValueKey('entry-price-input')),
    );
    expect(priceField.controller?.text, '4,000');
    expect(find.text('价格 3,920 USDT'), findsOneWidget);
    expect(find.text('价格 4,400 USDT'), findsOneWidget);

    await tester.enterText(
      find.byKey(const ValueKey('entry-price-input')),
      '4100',
    );
    livePrices.emit('ETH', 4200);
    await tester.pump();
    priceField = tester.widget<TextField>(
      find.byKey(const ValueKey('entry-price-input')),
    );
    expect(priceField.controller?.text, '4,100');

    await tester.tap(find.byKey(const ValueKey('use-market-price')));
    await tester.pump();
    priceField = tester.widget<TextField>(
      find.byKey(const ValueKey('entry-price-input')),
    );
    expect(priceField.controller?.text, '4,200');
  });

  testWidgets('止损止盈比例可以动态调整', (tester) async {
    await launchApp(tester);

    final increaseLoss = find.byKey(const ValueKey('止损-increase'));
    await tester.scrollUntilVisible(
      increaseLoss,
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(increaseLoss);
    await tester.pumpAndSettle();

    expect(find.text('2.5%'), findsOneWidget);
    expect(find.text('价格 75,379 USDT'), findsOneWidget);
  });

  testWidgets('首页开仓记录入口可以进入记录页', (tester) async {
    await launchApp(tester);

    final entry = find.byKey(const ValueKey('open-records-entry'));
    await tester.tap(entry);
    await tester.pumpAndSettle();

    expect(find.text('开仓记录'), findsOneWidget);
    expect(find.text('共 0 笔'), findsOneWidget);
    expect(find.text('暂无开仓记录'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.arrow_back_ios_new_rounded));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('entry-price-input')), findsOneWidget);
  });

  testWidgets('可以新增开仓记录并在记录页编辑盈利结果', (tester) async {
    await launchApp(tester);

    final addButton = find.byKey(const ValueKey('add-position-record'));
    await tester.scrollUntilVisible(
      addButton,
      350,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.drag(find.byType(Scrollable).first, const Offset(0, -130));
    await tester.pumpAndSettle();
    await tester.tap(addButton);
    await tester.pumpAndSettle();

    final entry = find.byKey(const ValueKey('open-records-entry'));
    await tester.drag(find.byType(Scrollable).first, const Offset(0, 600));
    await tester.pumpAndSettle();
    await tester.tap(entry);
    await tester.pumpAndSettle();

    expect(find.text('共 1 笔'), findsOneWidget);
    expect(find.text('暂无开仓记录'), findsNothing);
    final editButton = find.text('记录盈亏结果');
    await tester.scrollUntilVisible(
      editButton,
      350,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(editButton);
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('result-profit')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('close-price-input')),
      '84000',
    );
    await tester.enterText(
      find.byKey(const ValueKey('result-percent-input')),
      '8.5',
    );
    await tester.tap(find.byKey(const ValueKey('save-record-result')));
    await tester.pumpAndSettle();

    expect(find.text('盈利'), findsOneWidget);
    expect(find.textContaining('+8.5%'), findsOneWidget);
    expect(find.text(r'$84,000'), findsOneWidget);
  });

  testWidgets('底部导航可以切换行情与 AI 页面', (tester) async {
    await launchApp(tester);

    await tester.tap(find.byKey(const ValueKey('nav-1')));
    await tester.pumpAndSettle();
    expect(find.text('BTC / ETH 市场快照'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('nav-2')));
    await tester.pumpAndSettle();
    expect(find.text('Trading Copilot'), findsOneWidget);
    expect(find.text('分析风险，不替你下注'), findsOneWidget);
  });

  testWidgets('AI 助手会返回结构化追问结果', (tester) async {
    await launchApp(tester);
    await tester.tap(find.byKey(const ValueKey('nav-2')));
    await tester.pumpAndSettle();

    final input = find.byKey(const ValueKey('ai-input'));
    await tester.scrollUntilVisible(input, 500);
    await tester.enterText(input, 'BTC 支撑在哪里？');
    await tester.tap(find.byKey(const ValueKey('ai-send')));
    await tester.pumpAndSettle();

    expect(find.text('关键支撑判断'), findsOneWidget);
    expect(find.text(r'$76,200'), findsWidgets);
  });

  test('Binance 行情接口会解析行情并推导多周期趋势', () async {
    Future<Object?> fetcher(Uri url) async {
      if (url.path.contains('ticker/24hr')) {
        return {
          'symbol': 'BTCUSDT',
          'lastPrice': '80000.00',
          'priceChangePercent': '-1.25',
          'highPrice': '81000.00',
          'lowPrice': '79000.00',
          'quoteVolume': '26500000000',
        };
      }
      return [
        for (var index = 0; index < 30; index++)
          [0, '1', '2', '0.5', '${100 + index}', '10', 0, '0'],
      ];
    }

    final repository = BinanceMarketRepository(fetcher: fetcher);
    final snapshots = await repository.fetchSnapshots();

    final btc = snapshots.first;
    expect(btc.price, 80000);
    expect(btc.changePercent, -1.25);
    expect(btc.high24h, 81000);
    expect(btc.low24h, 79000);
    expect(btc.volume24h, r'$26.5B');
    expect(btc.trends, hasLength(4));
    expect(btc.trends.first.direction, TrendDirection.up);
    expect(btc.consistency, 100);
    expect(
      btc.levels.any((level) => level.isCurrent && level.price == 80000),
      isTrue,
    );

    final chart = await repository.fetchChartPoints(
      symbol: 'BTC',
      range: MarketRange.fourHours,
    );
    expect(chart.last, 129);
  });

  testWidgets('行情页展示接口行情并跟随实时价格', (tester) async {
    final repository = _TestMarketRepository();
    final livePrices = _TestLivePriceService();
    await launchApp(
      tester,
      livePriceService: livePrices,
      marketRepository: repository,
    );

    await tester.tap(find.byKey(const ValueKey('nav-1')));
    await tester.pumpAndSettle();

    expect(find.text('BTC / ETH 市场快照'), findsOneWidget);
    expect(find.text(r'$80,000'), findsOneWidget);
    expect(find.text('+1.24%  24h'), findsOneWidget);
    expect(find.text(r'$26.5B'), findsOneWidget);

    livePrices.emit('BTC', 81000);
    await tester.pump();
    expect(find.text(r'$81,000'), findsOneWidget);
    expect(find.text('实时'), findsOneWidget);
  });

  testWidgets('行情页切换周期能够重新拉取K线', (tester) async {
    final repository = _TestMarketRepository();
    await launchApp(tester, marketRepository: repository);

    await tester.tap(find.byKey(const ValueKey('nav-1')));
    await tester.pumpAndSettle();
    expect(repository.chartRanges, isEmpty);

    await tester.tap(find.byKey(const ValueKey('range-4H')));
    await tester.pumpAndSettle();

    expect(repository.chartRanges, contains(MarketRange.fourHours));
  });

  testWidgets('行情页加载失败时可以重试', (tester) async {
    final repository = _TestMarketRepository(failFirst: true);
    await launchApp(tester, marketRepository: repository);

    await tester.tap(find.byKey(const ValueKey('nav-1')));
    await tester.pumpAndSettle();
    expect(find.text('行情加载失败'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('retry-market')));
    await tester.pumpAndSettle();

    expect(find.text('BTC / ETH 市场快照'), findsOneWidget);
    expect(find.text(r'$80,000'), findsOneWidget);
  });

  testWidgets('开仓记录按实时价格计算浮动盈亏', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final repository = LocalPositionRepository();

    final livePrices = _TestLivePriceService();
    await launchApp(
      tester,
      livePriceService: livePrices,
      positionRepository: repository,
    );

    // 启动后写入（launchApp 内会重置 mock 存储，预置需在其之后）。
    await repository.save([
      PositionRecord(
        id: 'record-live',
        symbol: 'BTC',
        side: PositionSide.long,
        entryPrice: 80000,
        stopLossPercent: 2,
        takeProfitPercent: 10,
        createdAt: DateTime(2026, 9, 3, 10, 30),
        positionAmount: 200,
        leverage: 5,
      ),
    ]);

    final entry = find.byKey(const ValueKey('open-records-entry'));
    await tester.tap(entry);
    await tester.pumpAndSettle();

    expect(find.text('浮动盈亏'), findsOneWidget);

    livePrices.emit('BTC', 82400);
    await tester.pump();

    expect(find.text(r'+$6.00'), findsNWidgets(2));
    expect(find.text(r'$82,400'), findsOneWidget);
    expect(find.textContaining('+3.0%'), findsOneWidget);

    livePrices.emit('BTC', 77600);
    await tester.pump();

    expect(find.text(r'-$6.00'), findsNWidgets(2));
    expect(find.text(r'$77,600'), findsOneWidget);
    expect(find.textContaining('-3.0%'), findsOneWidget);
  });

  testWidgets('仓位风险体检会计算默认高风险仓位', (tester) async {
    await launchApp(tester);
    await tester.tap(find.byKey(const ValueKey('nav-2')));
    await tester.pumpAndSettle();

    final riskEntry = find.text('仓位体检');
    await tester.scrollUntilVisible(riskEntry, 500);
    await tester.drag(find.byType(Scrollable).first, const Offset(0, -180));
    await tester.pumpAndSettle();
    await tester.tap(riskEntry);
    await tester.pumpAndSettle();
    expect(find.text('仓位风险体检'), findsOneWidget);

    final analyze = find.byKey(const ValueKey('analyze-risk'));
    await tester.scrollUntilVisible(
      analyze,
      400,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(analyze);
    await tester.pumpAndSettle();

    expect(find.text('95'), findsOneWidget);
    expect(find.text('极高风险'), findsOneWidget);
  });
}
