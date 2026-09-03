import 'package:ai_coin/app.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Future<void> launchApp(WidgetTester tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(const CryptoPilotApp());
    await tester.pumpAndSettle();
  }

  testWidgets('首页展示市场状态与核心定位', (tester) async {
    await launchApp(tester);

    expect(find.text('CryptoPilot'), findsOneWidget);
    expect(find.text('AI 市场判断'), findsOneWidget);
    expect(find.text('高位震荡 · 短线偏弱'), findsOneWidget);
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

    final riskEntry = find.text('仓位风险');
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
