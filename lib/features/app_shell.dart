import 'package:flutter/material.dart';

import '../core/app_theme.dart';
import '../data/mock_market_repository.dart';
import 'ai/ai_page.dart';
import 'home/home_page.dart';
import 'journal/review_page.dart';
import 'market/market_page.dart';
import 'profile/profile_page.dart';
import 'risk/risk_page.dart';

class AppShell extends StatefulWidget {
  const AppShell({super.key});

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  final _repository = const MockMarketRepository();
  int _index = 0;

  void _openRisk() {
    Navigator.of(
      context,
    ).push(MaterialPageRoute<void>(builder: (_) => const RiskPage()));
  }

  void _openReview() {
    Navigator.of(
      context,
    ).push(MaterialPageRoute<void>(builder: (_) => const ReviewPage()));
  }

  @override
  Widget build(BuildContext context) {
    final snapshots = _repository.snapshots;
    final pages = [
      HomePage(
        snapshot: snapshots.first,
        onOpenMarket: () => setState(() => _index = 1),
        onOpenAi: () => setState(() => _index = 2),
        onOpenRisk: _openRisk,
        onOpenReview: _openReview,
      ),
      MarketPage(snapshots: snapshots),
      AiPage(
        snapshots: snapshots,
        onOpenRisk: _openRisk,
        onOpenReview: _openReview,
      ),
      ProfilePage(onOpenReview: _openReview),
    ];

    return Scaffold(
      body: IndexedStack(index: _index, children: pages),
      bottomNavigationBar: _BottomNavigation(
        selectedIndex: _index,
        onSelected: (value) => setState(() => _index = value),
      ),
    );
  }
}

class _BottomNavigation extends StatelessWidget {
  const _BottomNavigation({
    required this.selectedIndex,
    required this.onSelected,
  });

  final int selectedIndex;
  final ValueChanged<int> onSelected;

  @override
  Widget build(BuildContext context) {
    const items = [
      (Icons.home_rounded, '首页'),
      (Icons.candlestick_chart_rounded, '行情'),
      (Icons.auto_awesome_rounded, 'AI'),
      (Icons.person_rounded, '我的'),
    ];

    return DecoratedBox(
      decoration: const BoxDecoration(
        color: AppColors.surface,
        border: Border(top: BorderSide(color: AppColors.line)),
      ),
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: 70,
          child: Row(
            children: List.generate(items.length, (index) {
              final selected = index == selectedIndex;
              final isAi = index == 2;
              return Expanded(
                child: Semantics(
                  button: true,
                  selected: selected,
                  label: items[index].$2,
                  child: InkWell(
                    key: ValueKey('nav-$index'),
                    onTap: () => onSelected(index),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        AnimatedContainer(
                          duration: const Duration(milliseconds: 180),
                          width: isAi ? 43 : 34,
                          height: isAi ? 34 : 28,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: isAi
                                ? (selected
                                      ? AppColors.ink
                                      : AppColors.tealSoft)
                                : (selected
                                      ? AppColors.tealSoft
                                      : Colors.transparent),
                            borderRadius: BorderRadius.circular(13),
                          ),
                          child: Icon(
                            items[index].$1,
                            size: 21,
                            color: isAi && selected
                                ? Colors.white
                                : selected
                                ? AppColors.teal
                                : AppColors.muted,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          items[index].$2,
                          style: TextStyle(
                            color: selected ? AppColors.ink : AppColors.muted,
                            fontSize: 11,
                            fontWeight: selected
                                ? FontWeight.w700
                                : FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            }),
          ),
        ),
      ),
    );
  }
}
