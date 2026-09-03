import 'dart:async';

import 'package:ai_coin/app.dart';
import 'package:ai_coin/data/live_price_service.dart';
import 'package:ai_coin/data/position_repository.dart';
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

void main() {
  Future<void> launchApp(
    WidgetTester tester, {
    LivePriceService? livePriceService,
  }) async {
    final service = livePriceService ?? _TestLivePriceService();
    SharedPreferences.setMockInitialValues({});
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(CryptoPilotApp(livePriceService: service));
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

    expect(
      find.text('开仓'),
      findsOneWidget,
      reason: tester.allWidgets
          .whereType<Text>()
          .map((widget) => widget.data)
          .whereType<String>()
          .join(' | '),
    );
    expect(find.text('仓位计算器'), findsOneWidget);
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

  testWidgets('可以新增开仓记录并编辑盈利结果', (tester) async {
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
