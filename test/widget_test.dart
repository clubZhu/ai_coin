import 'package:ai_coin/app.dart';
import 'package:ai_coin/data/position_repository.dart';
import 'package:ai_coin/domain/position_record.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  Future<void> launchApp(WidgetTester tester) async {
    SharedPreferences.setMockInitialValues({});
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(const CryptoPilotApp());
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
  });

  testWidgets('首页展示开仓计算工具和默认目标价格', (tester) async {
    await launchApp(tester);

    expect(find.text('CryptoPilot'), findsOneWidget);
    expect(find.text('开仓计划'), findsOneWidget);
    expect(find.text('先算清止损与止盈价格，再确认开仓。'), findsOneWidget);
    expect(find.text(r'$75,766'), findsOneWidget);
    expect(find.text(r'$85,043'), findsOneWidget);
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
    expect(find.text(r'$75,379'), findsOneWidget);
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

    expect(find.text('1 笔'), findsOneWidget);
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
    expect(find.text('+8.5%'), findsOneWidget);
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
